CREATE TEMP FUNCTION map_payment(method STRING, provider STRING) AS ((
 WITH n AS (SELECT UPPER(NULLIF(TRIM(method),'')) m, UPPER(NULLIF(TRIM(provider),'')) p),
 b AS (SELECT *, CASE p WHEN 'KASIKORN' THEN 'KBANK' WHEN 'KBANK' THEN 'KBANK' WHEN 'KRUNGSRI' THEN 'BAY' WHEN 'BAY' THEN 'BAY' WHEN 'KRUNGTHAI' THEN 'KTB' WHEN 'KTB' THEN 'KTB' WHEN 'BANGKOK_BANK' THEN 'BBL' WHEN 'BBL' THEN 'BBL' WHEN 'SCB' THEN 'SCB' WHEN 'UOB' THEN 'UOB' WHEN 'TMB' THEN 'TMB' WHEN 'TTB' THEN 'TTB' END bank FROM n)
 SELECT AS STRUCT
 CASE m WHEN 'EDC' THEN 'EDC EDC' WHEN 'BANK_TRANSFER' THEN 'TRF Transfer' WHEN 'CASH' THEN 'TRF Transfer' WHEN 'DIRECT_PAYMENT' THEN 'DPM จ่ายตรงกับบริษัทประกัน' WHEN 'ONLINECARD' THEN 'OMC Omise Credit Card' WHEN 'QR_CODE' THEN 'OME Omise QR Prompt Pay' WHEN 'ALL' THEN IF(p='ALL','RCL-CMI-channel',NULL) ELSE method END sap_payment_method,
 CASE
 WHEN m='ALL' AND p='ALL' THEN 'RCL-CMI-channel'
 WHEN m='EDC' THEN CONCAT('RCB-EDC',IF(bank IS NULL,'',CONCAT('-',bank)))
 WHEN m='BANK_TRANSFER' THEN CONCAT('RCB-Transfer',IF(bank IS NULL,'',CONCAT('-',bank)))
 WHEN m='CASH' AND p='SERVICE_PROVIDER_UNSPECIFIED' THEN 'RCB-Transfer-อื่นๆ'
 WHEN m='CASH' THEN CONCAT('RCB-Transfer',IF(bank IS NULL,'',CONCAT('-',bank)))
 WHEN m='DIRECT_PAYMENT' THEN 'RCB-DIRECT PAYMENT'
 WHEN m='ONLINECARD' THEN CONCAT('RCB-Omise Credit Card',IF(p IN ('OMISE','RCB'),'-BAY',IF(bank IS NULL,'',CONCAT('-',bank))))
 WHEN m='QR_CODE' THEN CONCAT('RCB-Omise QR Prompt Pay',IF(p IN ('OMISE','RCB','RABBIT_LENDING'),'-BAY',IF(bank IS NULL,'',CONCAT('-',bank))))
 ELSE NULL END sap_payment_channel,
 bank identified_bank
 FROM b
));
WITH sap AS (
SELECT CompanyDB,DocEntry,U_OrderID,U_OrderItem,U_InvoiceNo,U_Period,TransactionStatus,PaymentMethod,PaymentChannel,PaymentDate,U_ActualReceived,UpdateDate,
 COUNT(*) OVER(PARTITION BY CompanyDB,DocEntry) sap_key_rows
FROM `pacific-plating-282708.sap_integration_v2.SAP_LIVE_FULL`
), charges AS (
SELECT c.id,c.transaction_id,c.third_party_id,c.payment_method,c.service_provider,c.amount,c.payment_date,c.delete_time,t.payment_option,o.human_id order_id,i.human_id order_item
FROM `pacific-plating-282708.careos.carepay_charges` c
JOIN `pacific-plating-282708.careos.carepay_transactions` t ON t.id=c.transaction_id
JOIN `pacific-plating-282708.careos.careos_orders` o ON o.payment=CONCAT('transactions/',t.id)
JOIN `pacific-plating-282708.careos.careos_order_items` i ON i.order_id=o.id
WHERE c.status='SUCCESSFUL'
), matched AS (
 SELECT s.*,ARRAY(SELECT AS STRUCT c.id,c.payment_method,c.service_provider,c.amount,c.payment_date,c.delete_time,c.payment_option
 FROM charges c WHERE c.order_item=s.U_OrderItem AND c.order_id=s.U_OrderID AND NULLIF(c.third_party_id,'')=NULLIF(s.U_InvoiceNo,'') GROUP BY c.id,c.payment_method,c.service_provider,c.amount,c.payment_date,c.delete_time,c.payment_option) source_matches
 FROM sap s
), resolved AS (
 SELECT *,ARRAY_LENGTH(source_matches) source_match_count,source_matches[SAFE_OFFSET(0)] c FROM matched
), mapped AS (
 SELECT *,map_payment(c.payment_method,c.service_provider) proposed FROM resolved
)
SELECT CURRENT_TIMESTAMP() checked_at_utc,CompanyDB,DocEntry,U_OrderID OrderID,U_OrderItem OrderItem,U_InvoiceNo InvoiceNo,U_Period Period,TransactionStatus,PaymentDate SAP_PaymentDate,U_ActualReceived SAP_ActualReceived,UpdateDate SAP_UpdateDate,sap_key_rows,PaymentMethod SAP_PaymentMethod,PaymentChannel SAP_PaymentChannel,source_match_count,c.id ChargeID,c.payment_method Source_Method,c.service_provider Source_Provider,c.payment_option Source_PaymentOption,c.amount/100 Source_ChargeAmount,c.payment_date Source_PaymentDate,c.delete_time Source_DeleteTime,
IF(source_match_count=1,proposed.sap_payment_method,NULL) Proposed_PaymentMethod,IF(source_match_count=1,proposed.sap_payment_channel,NULL) Proposed_PaymentChannel,
CASE WHEN sap_key_rows!=1 THEN 'REVIEW_DUPLICATE_SAP_KEY' WHEN source_match_count=0 THEN 'REVIEW_NO_EXACT_CHARGE' WHEN source_match_count!=1 THEN 'REVIEW_AMBIGUOUS_CHARGE' WHEN c.delete_time IS NOT NULL THEN 'REVIEW_DELETED_SOURCE' WHEN PaymentChannel IN ('RCB-CreditShell','RCL-CMI-channel') OR STARTS_WITH(PaymentChannel,'RCL-') THEN 'REVIEW_SPECIAL_FLOW' WHEN TransactionStatus NOT IN ('Paid','paid') THEN 'REVIEW_REVERSAL_OR_STATUS' WHEN proposed.sap_payment_channel IS NULL THEN 'REVIEW_UNKNOWN_METHOD' WHEN PaymentMethod IS DISTINCT FROM proposed.sap_payment_method OR PaymentChannel IS DISTINCT FROM proposed.sap_payment_channel THEN 'PROPOSED_CORRECTION' ELSE 'MATCH' END Review_Reason
FROM mapped
WHERE REGEXP_CONTAINS(IFNULL(PaymentChannel,''),r'(?i)EDC') OR c.payment_method='EDC' OR (source_match_count=1 AND (PaymentMethod IS DISTINCT FROM proposed.sap_payment_method OR PaymentChannel IS DISTINCT FROM proposed.sap_payment_channel))
ORDER BY CompanyDB,DocEntry;

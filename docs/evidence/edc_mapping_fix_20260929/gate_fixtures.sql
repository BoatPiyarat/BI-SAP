CREATE TEMP FUNCTION map_payment(method STRING, provider STRING) AS ((
 WITH n AS (SELECT UPPER(NULLIF(TRIM(method),'')) m, UPPER(NULLIF(TRIM(provider),'')) p),
 b AS (SELECT *, CASE p WHEN 'KASIKORN' THEN 'KBANK' WHEN 'KBANK' THEN 'KBANK' WHEN 'KRUNGSRI' THEN 'BAY' WHEN 'BAY' THEN 'BAY' WHEN 'KRUNGTHAI' THEN 'KTB' WHEN 'KTB' THEN 'KTB' WHEN 'BANGKOK_BANK' THEN 'BBL' WHEN 'BBL' THEN 'BBL' WHEN 'SCB' THEN 'SCB' WHEN 'UOB' THEN 'UOB' WHEN 'TMB' THEN 'TMB' WHEN 'TTB' THEN 'TTB' END bank FROM n)
 SELECT AS STRUCT
 CASE m WHEN 'EDC' THEN 'EDC EDC' WHEN 'BANK_TRANSFER' THEN 'TRF Transfer' WHEN 'CASH' THEN 'TRF Transfer' WHEN 'DIRECT_PAYMENT' THEN 'DPM จ่ายตรงกับบริษัทประกัน' WHEN 'ONLINECARD' THEN 'OMC Omise Credit Card' WHEN 'QR_CODE' THEN 'OME Omise QR Prompt Pay' WHEN 'ALL' THEN IF(p='ALL','RCL-CMI-channel',NULL) ELSE method END sap_payment_method,
 CASE
 WHEN m='ALL' THEN IF(p='ALL','RCL-CMI-channel',NULL)
 WHEN m='EDC' THEN CONCAT('RCB-EDC',IF(bank IS NULL,'',CONCAT('-',bank)))
 WHEN m='BANK_TRANSFER' THEN CONCAT('RCB-Transfer',IF(bank IS NULL,'',CONCAT('-',bank)))
 WHEN m='CASH' AND p='SERVICE_PROVIDER_UNSPECIFIED' THEN 'RCB-Transfer-อื่นๆ'
 WHEN m='CASH' THEN CONCAT('RCB-Transfer',IF(bank IS NULL,'',CONCAT('-',bank)))
 WHEN m='DIRECT_PAYMENT' THEN 'RCB-DIRECT PAYMENT'
 WHEN m='ONLINECARD' THEN CONCAT('RCB-Omise Credit Card',IF(p IN ('OMISE','RCB'),'-BAY',IF(bank IS NULL,'',CONCAT('-',bank))))
 WHEN m='QR_CODE' THEN CONCAT('RCB-Omise QR Prompt Pay',IF(p IN ('OMISE','RCB','RABBIT_LENDING'),'-BAY',IF(bank IS NULL,'',CONCAT('-',bank))))
 ELSE IF(m IS NULL OR m='PAYMENT_METHOD_UNSPECIFIED',NULL,CONCAT('RCB-',m,IF(bank IS NULL,'',CONCAT('-',bank)))) END sap_payment_channel,
 bank identified_bank
 FROM b
));
WITH cases AS (
SELECT 'missing_onetime_known' id,0 matches,'ONETIME' flow,FALSE credit,'EDC' method,'SCB' provider,FALSE expected_hold UNION ALL
SELECT 'missing_onetime_unknown_bank',0,'ONETIME',FALSE,'EDC',NULL,FALSE UNION ALL
SELECT 'ambiguous_mapping',2,'ONETIME',FALSE,'EDC','SCB',TRUE UNION ALL
SELECT 'null_flow',0,NULL,FALSE,'EDC','SCB',TRUE UNION ALL
SELECT 'null_credit_flag',0,'ONETIME',NULL,'EDC','SCB',TRUE UNION ALL
SELECT 'rcl_no_mapping',0,'RCL',FALSE,'EDC','SCB',TRUE UNION ALL
SELECT 'creditshell_no_mapping',0,'ONETIME',TRUE,'EDC','SCB',TRUE UNION ALL
SELECT 'unmapped_method',0,'ONETIME',FALSE,'CHEQUE','SCB',FALSE UNION ALL
SELECT 'missing_method',0,'ONETIME',FALSE,NULL,'SCB',TRUE UNION ALL
SELECT 'approved_mapping',1,'ONETIME',FALSE,'EDC','SCB',FALSE
), checks AS (SELECT *,matches>1 OR (matches=0 AND NOT COALESCE((flow='ONETIME' AND credit=FALSE AND map_payment(method,provider).sap_payment_channel IS NOT NULL),FALSE)) actual_hold FROM cases)
SELECT *,actual_hold IS NOT DISTINCT FROM expected_hold passed FROM checks;

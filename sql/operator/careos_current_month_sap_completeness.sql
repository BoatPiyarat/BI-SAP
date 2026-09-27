-- READ ONLY: temporary tables only. No deployment, export, SAP write or scheduler change.
-- Paid grain: charge_id x linked order_item, retaining ambiguous allocations rather than hiding them.
-- Cancellation grain: item x SAP DocEntry; historical conflicting document states are REVIEW, not confirmed missing.
-- Scope: canonical SAP_LIVE_FULL visibility (excludes B2B and dedups DocEntry across companies).
-- Month uses Asia/Bangkok; CURRENT MONTH is month-to-date at as_of, never a completed future month.
-- payment_date is preferred; update_time fallback is explicit. Cancellation date is item.cancel_time.
-- SAP_LIVE_FULL is a mirror, not an import acknowledgement. Identity matching is not GL reconciliation.
DECLARE month_start DATE DEFAULT DATE_TRUNC(CURRENT_DATE('Asia/Bangkok'), MONTH);
DECLARE month_end DATE DEFAULT DATE_ADD(month_start, INTERVAL 1 MONTH);
DECLARE as_of TIMESTAMP DEFAULT CURRENT_TIMESTAMP();
DECLARE only_exceptions BOOL DEFAULT TRUE;
DECLARE include_undated_cancellations BOOL DEFAULT TRUE;

CREATE TEMP TABLE charges AS
SELECT b.*,
  ROW_NUMBER() OVER(PARTITION BY transaction_id,installment_number,service_provider ORDER BY create_time,id) AS period_charge_rank,
  ROW_NUMBER() OVER(PARTITION BY transaction_id ORDER BY create_time,id) AS transaction_charge_rank,
  COUNTIF(service_provider <> 'RABBIT_LENDING') OVER(PARTITION BY transaction_id ORDER BY create_time,id ROWS UNBOUNDED PRECEDING) AS rcb_charge_rank,
  COUNTIF(service_provider NOT IN ('ICOLLECTION','RABBIT_LENDING')) OVER(PARTITION BY transaction_id ORDER BY COALESCE(payment_date,update_time,create_time),create_time,id ROWS UNBOUNDED PRECEDING) AS health_change_charge_rank,
  COUNT(*) OVER(PARTITION BY transaction_id,installment_number,third_party_id) AS invoice_source_count
FROM (
  SELECT id,transaction_id,third_party_id,installment_number,amount,currency_code,status,
    service_provider,payment_method,create_time,update_time,payment_date,delete_time,
    COUNT(*) OVER(PARTITION BY id) AS source_id_rows
  FROM `pacific-plating-282708.careos.carepay_charges`
  QUALIFY ROW_NUMBER() OVER(PARTITION BY id ORDER BY update_time DESC,version DESC)=1
) b WHERE status='SUCCESSFUL';

CREATE TEMP TABLE month_charges AS
SELECT *, COALESCE(payment_date,update_time) AS paid_at,
  DATE(COALESCE(payment_date,update_time),'Asia/Bangkok') AS paid_date,
  IF(payment_date IS NULL,'UPDATE_TIME_FALLBACK','PAYMENT_DATE') AS paid_date_source
FROM charges
WHERE DATE(COALESCE(payment_date,update_time),'Asia/Bangkok')>=month_start
  AND DATE(COALESCE(payment_date,update_time),'Asia/Bangkok')<month_end
  AND COALESCE(payment_date,update_time)<=as_of;

CREATE TEMP TABLE snapshots AS
SELECT transaction_id,id,number_of_installment,is_current
FROM `pacific-plating-282708.careos.carepay_transaction_snapshots`
QUALIFY ROW_NUMBER() OVER(PARTITION BY transaction_id ORDER BY is_current DESC,update_time DESC,id)=1;

CREATE TEMP TABLE dimensions AS
SELECT o.id AS order_pk,o.human_id AS order_id,oi.id AS item_pk,oi.human_id AS order_item,
  REGEXP_REPLACE(o.payment,r'^transactions/','') AS transaction_id,
  COALESCE(oi.product,o.product) AS product,oi.motor_item_type,
  CASE WHEN COALESCE(oi.product,o.product)='products/car-insurance' THEN 'Motor'
    WHEN COALESCE(oi.product,o.product) IS NULL THEN 'Unknown' ELSE 'NonMotor' END AS business_type,
  oi.cancel_time,COALESCE(oi.is_cancelled,FALSE) OR oi.cancel_time IS NOT NULL AS is_cancelled,
  oi.delete_time AS item_deleted_at,oi.submission_status,oi.approval_status,
  oi.gross_premium,oi.net_premium,oi.create_time AS item_created_at,
  o.create_time AS order_created_at,o.delete_time AS order_deleted_at,
  l.status AS lead_status,t.payment_option,t.installments,t.status AS transaction_status,
  ss.number_of_installment AS snapshot_periods,ss.id AS snapshot_id,
  EXISTS(SELECT 1 FROM `pacific-plating-282708.careos.cancelled_change_orders` x WHERE x.current_human_id=o.human_id) AS is_change_order_new,
  EXISTS(SELECT 1 FROM `pacific-plating-282708.careos.cancelled_change_orders` x WHERE x.old_human_id=o.human_id) AS is_change_order_old,
  COUNT(oi.id) OVER(PARTITION BY o.id) AS order_item_count,
  COUNTIF(oi.motor_item_type='MOTOR_TYPE_COMPULSORY') OVER(PARTITION BY o.id) AS compulsory_item_count
FROM `pacific-plating-282708.careos.careos_orders` o
LEFT JOIN `pacific-plating-282708.careos.careos_order_items` oi ON oi.order_id=o.id
LEFT JOIN `pacific-plating-282708.careos.careos_leads` l ON CONCAT('leads/',l.id)=o.lead
LEFT JOIN `pacific-plating-282708.careos.carepay_transactions` t ON CONCAT('transactions/',t.id)=o.payment
LEFT JOIN snapshots ss ON ss.transaction_id=t.id;

-- Preserve every DocEntry exposed by the canonical view; never collapse item/period.
CREATE TEMP TABLE sap AS
SELECT DocEntry,U_OrderID AS order_id,U_OrderItem AS order_item,U_Period AS period,
  NULLIF(NULLIF(TRIM(U_InvoiceNo),''),'NULL') AS invoice_no,
  LOWER(TRIM(TransactionStatus)) AS sap_status,TransactionStatus AS sap_status_original,
  ROUND(U_ActualReceived,2) AS actual_received,ExpectedReceived AS expected_received,
  TotalPeriods AS total_periods,PaymentChannel AS payment_channel,
  SAFE.PARSE_DATE('%d%m%Y',PaymentDate) AS paid_date,UpdateDate AS sap_update_at
FROM `pacific-plating-282708.sap_integration_v2.SAP_LIVE_FULL`;

CREATE TEMP TABLE sap_period AS
SELECT order_item,period,COUNT(*) AS sap_period_rows,
  COUNTIF(sap_status='paid') AS sap_period_paid_rows,
  COUNTIF(STARTS_WITH(sap_status,'cancelled')) AS sap_period_cancelled_rows,
  STRING_AGG(IF(STARTS_WITH(sap_status,'cancelled'),CAST(DocEntry AS STRING),NULL),',') AS period_cancelled_docentries,
  STRING_AGG(DISTINCT sap_status,',' ORDER BY sap_status) AS sap_period_statuses
FROM sap GROUP BY order_item,period;
CREATE TEMP TABLE sap_items AS
SELECT order_item,COUNT(*) AS sap_item_rows,COUNT(DISTINCT period) AS sap_distinct_periods,
 MAX(total_periods) AS sap_total_periods,COUNTIF(NOT COALESCE(STARTS_WITH(sap_status,'cancelled'),FALSE)) AS sap_uncancelled_rows
FROM sap GROUP BY order_item;

CREATE TEMP TABLE sap_receipt_status AS
SELECT order_item,period,invoice_no,COUNT(*) AS receipt_doc_count,
 COUNTIF(STARTS_WITH(sap_status,'cancelled')) AS cancelled_receipt_doc_count,
 STRING_AGG(IF(STARTS_WITH(sap_status,'cancelled'),CAST(DocEntry AS STRING),NULL),',') AS cancelled_docentries
FROM sap GROUP BY order_item,period,invoice_no;

CREATE TEMP TABLE paid_link_base AS
SELECT c.*,d.* EXCEPT(transaction_id),
  COALESCE(d.payment_option,t.payment_option) AS resolved_payment_option,
  CASE WHEN c.service_provider='RABBIT_LENDING' OR COALESCE(d.payment_option,t.payment_option)='RABBIT_CARE_INSTALLMENT' THEN 'RCL'
    WHEN COALESCE(d.payment_option,t.payment_option) IS NULL AND c.service_provider IS NULL THEN 'Unknown' ELSE 'RCB' END AS flow,
  CASE WHEN COALESCE(d.payment_option,t.payment_option) IS NULL THEN 'UNKNOWN'
    WHEN COALESCE(d.payment_option,t.payment_option)='RABBIT_CARE_INSTALLMENT' THEN 'INSTALLMENT'
    WHEN COALESCE(d.payment_option,t.payment_option)='CREDIT_CARD_INSTALLMENT' THEN 'BANK_INSTALLMENT' ELSE 'ONETIME' END AS payment_mode,
  -- A compulsory first-charge allocation is real; subsequent voluntary periods must not
  -- manufacture compulsory receipts. Keep excluded links visible, with no cash duplication.
  CASE WHEN d.motor_item_type='MOTOR_TYPE_COMPULSORY' AND COALESCE(d.payment_option,t.payment_option)='RABBIT_CARE_INSTALLMENT'
    AND (c.installment_number!=1 OR c.period_charge_rank!=1) THEN 'NOT_APPLICABLE_COMPULSORY_LATER_CHARGE'
    WHEN d.motor_item_type='MOTOR_TYPE_COMPULSORY' AND COALESCE(d.payment_option,t.payment_option) IS DISTINCT FROM 'RABBIT_CARE_INSTALLMENT'
      AND c.service_provider <> 'RABBIT_LENDING' AND c.rcb_charge_rank>1 THEN 'NOT_APPLICABLE_COMPULSORY_LATER_CHARGE'
    ELSE 'RECEIPT_LINK' END AS allocation_scope
FROM month_charges c
LEFT JOIN dimensions d ON d.transaction_id=c.transaction_id
LEFT JOIN `pacific-plating-282708.careos.carepay_transactions` t ON t.id=c.transaction_id;

CREATE TEMP TABLE paid_links AS
SELECT p.*,ARRAY(
 SELECT DISTINCT inv FROM UNNEST([
   NULLIF(NULLIF(TRIM(p.third_party_id),''),'NULL'),
   IF(p.flow='RCL' AND p.business_type='Motor' AND p.installment_number=1 AND p.third_party_id IS NOT NULL,CONCAT('2_',p.third_party_id),NULL),
   IF(p.third_party_id IS NULL AND p.flow='RCB' AND p.business_type='Motor',CONCAT(CAST(p.rcb_charge_rank AS STRING),'_',p.order_item),NULL),
   IF(p.third_party_id IS NULL AND p.flow='RCL',IF(p.business_type='Motor' AND p.installment_number=1,CONCAT('2_',p.order_item),p.order_item),NULL),
   IF(p.third_party_id IS NULL AND p.product='products/travel-insurance',p.order_item,NULL),
   IF(p.third_party_id IS NULL AND p.flow='RCB' AND p.product='products/health-insurance' AND NOT COALESCE(p.is_change_order_new,FALSE),
      CONCAT(CASE p.payment_method WHEN 'DIRECT_PAYMENT' THEN 'dpm_' WHEN 'BANK_TRANSFER' THEN 'trf_' WHEN 'CASH' THEN 'cash_' WHEN 'EDC' THEN 'edc_' ELSE '' END,p.order_item),NULL),
   IF(NULLIF(p.third_party_id,'') IS NULL AND p.flow='RCB' AND p.product='products/health-insurance' AND p.is_change_order_new,
      CONCAT(CASE p.payment_method WHEN 'DIRECT_PAYMENT' THEN 'dpm_' WHEN 'BANK_TRANSFER' THEN 'trf_' WHEN 'CASH' THEN 'cash_' WHEN 'EDC' THEN 'edc_' ELSE CONCAT(LOWER(COALESCE(p.payment_method,'payment')),'_') END,CAST(p.health_change_charge_rank AS STRING),'_',p.order_item),NULL)
 ]) inv WHERE inv IS NOT NULL AND TRIM(inv)!='' AND UPPER(TRIM(inv))!='NULL'
) AS candidate_invoice_nos
FROM paid_link_base p;

CREATE TEMP TABLE paid_match AS
SELECT p.id AS charge_id,p.item_pk,
  COUNT(s.DocEntry) AS matched_sap_rows,
  COUNTIF(s.sap_status='paid' OR STARTS_WITH(s.sap_status,'cancelled')) AS terminal_matches,
  STRING_AGG(DISTINCT s.sap_status,',' ORDER BY s.sap_status) AS matched_statuses,
  STRING_AGG(DISTINCT s.invoice_no,',' ORDER BY s.invoice_no) AS matched_invoices,
  STRING_AGG(DISTINCT CAST(s.DocEntry AS STRING),',') AS matched_docentries,
  SUM(s.actual_received) AS sap_matched_actual,
  MAX(s.sap_update_at) AS sap_update_at,
  MAX(s.paid_date) AS sap_paid_date,
  COUNTIF(s.invoice_no=p.third_party_id) AS exact_invoice_matches
FROM paid_links p
LEFT JOIN sap s ON s.order_item=p.order_item AND s.period=p.installment_number
 AND s.invoice_no IN UNNEST(p.candidate_invoice_nos)
GROUP BY p.id,p.item_pk;

CREATE TEMP TABLE paid_results AS
SELECT 'PAID' AS event_type,'CURRENT_MONTH' AS date_scope,
 p.order_id,p.order_item,p.item_pk,p.transaction_id,p.id AS charge_id,
 p.installment_number AS installment_period,COALESCE(p.business_type,'Unknown') AS business_type,p.product,p.motor_item_type,
 p.flow,p.payment_mode,p.resolved_payment_option AS payment_option,
 COALESCE(p.snapshot_periods,p.installments) AS careos_total_installments,
 p.paid_date,p.paid_at,p.paid_date_source,p.payment_date AS raw_payment_at,p.update_time AS charge_updated_at,
 DATE(p.cancel_time,'Asia/Bangkok') AS cancellation_date,p.cancel_time AS cancelled_at,
 ROUND(p.amount/100,2) AS charge_amount_thb,
 IF(p.order_item_count=1 AND p.allocation_scope='RECEIPT_LINK',ROUND(p.amount/100,2),NULL) AS comparable_item_amount_thb,
 p.third_party_id AS raw_invoice_no,TO_JSON_STRING(p.candidate_invoice_nos) AS candidate_invoice_nos,p.payment_method,p.service_provider,
 p.period_charge_rank,p.transaction_charge_rank,p.order_item_count,p.compulsory_item_count,
 p.allocation_scope,p.is_cancelled,p.is_change_order_new,p.is_change_order_old,
 p.lead_status,p.submission_status,p.approval_status,p.snapshot_periods,
 COALESCE(si.sap_item_rows,0) AS sap_item_rows,COALESCE(sp.sap_period_rows,0) AS sap_period_rows,
 COALESCE(sp.sap_period_paid_rows,0) AS sap_period_paid_rows,
 sp.sap_period_statuses,m.matched_sap_rows,m.terminal_matches,m.matched_statuses,m.matched_invoices,m.matched_docentries,
 m.sap_matched_actual,m.sap_update_at,m.sap_paid_date,
 CASE
  WHEN p.allocation_scope!='RECEIPT_LINK' THEN p.allocation_scope
  WHEN p.source_id_rows>1 OR p.invoice_source_count>1 THEN 'AMBIGUOUS_SOURCE_RECEIPT_IDENTITY'
  WHEN p.order_id IS NULL THEN 'NO_CAREOS_ORDER'
  WHEN p.order_item IS NULL THEN 'NO_CAREOS_ORDER_ITEM'
  WHEN m.matched_sap_rows>1 THEN 'MULTIPLE_SAP_RECEIPT_MATCHES'
  WHEN m.terminal_matches=1 AND NULLIF(p.third_party_id,'') IS NULL THEN 'FALLBACK_INVOICE_REVIEW'
  WHEN m.terminal_matches=1 AND p.order_item_count=1 AND ABS(COALESCE(m.sap_matched_actual,0)-p.amount/100)>0.011 THEN 'SAP_AMOUNT_DIFF_ALLOCATION_REVIEW'
  WHEN m.terminal_matches=1 THEN 'MATCHED_SAP_RECEIPT_IDENTITY'
  WHEN NULLIF(TRIM(p.third_party_id),'') IS NULL OR UPPER(TRIM(p.third_party_id))='NULL' THEN 'MISSING_SOURCE_INVOICE'
  WHEN p.is_change_order_new THEN 'CHANGE_ORDER_NEW_FLOW_REVIEW'
  WHEN p.flow='RCL' AND p.business_type='Motor' AND p.motor_item_type IS DISTINCT FROM 'MOTOR_TYPE_COMPULSORY'
    AND p.resolved_payment_option='RABBIT_CARE_INSTALLMENT' AND p.service_provider='RABBIT_LENDING'
    AND p.period_charge_rank>1 AND COALESCE(sp.sap_period_paid_rows,0)>0 THEN 'ADDITIONAL_CHARGE_PAID_PERIOD_GATE'
  WHEN p.is_cancelled THEN 'CANCELLED_ITEM_RECEIPT_NOT_FOUND'
  WHEN p.lead_status IS DISTINCT FROM 'LEAD_STATUS_PURCHASED' THEN 'SOURCE_LEAD_NOT_PURCHASED_REVIEW'
  WHEN p.snapshot_periods IS NULL THEN 'SOURCE_SNAPSHOT_MISSING_REVIEW'
  WHEN m.matched_sap_rows>0 THEN 'SAP_RECEIPT_NONTERMINAL'
  WHEN COALESCE(si.sap_item_rows,0)=0 THEN 'SAP_ITEM_NOT_FOUND'
  WHEN COALESCE(sp.sap_period_rows,0)=0 THEN 'SAP_PERIOD_NOT_FOUND'
  WHEN COALESCE(sp.sap_period_paid_rows,0)>0 THEN 'SAP_PAID_DIFFERENT_INVOICE'
  ELSE 'SAP_PERIOD_PENDING_RECEIPT_MISSING'
 END AS reason_code,
 CAST(NULL AS INT64) AS cancellation_docentry,CAST(NULL AS STRING) AS counterpart_cancelled_docentries
FROM paid_links p
LEFT JOIN paid_match m ON m.charge_id=p.id AND m.item_pk IS NOT DISTINCT FROM p.item_pk
LEFT JOIN sap_period sp ON sp.order_item=p.order_item AND sp.period=p.installment_number
LEFT JOIN sap_items si ON si.order_item=p.order_item;

CREATE TEMP TABLE transaction_paid AS
SELECT transaction_id,COUNT(*) AS successful_charge_count,MAX(COALESCE(payment_date,update_time)) AS last_paid_at,
 STRING_AGG(DISTINCT service_provider,',') AS providers,SUM(amount)/100 AS lifetime_charge_amount_thb
FROM charges GROUP BY transaction_id;

CREATE TEMP TABLE cancel_results AS
SELECT 'CANCELLATION' AS event_type,
 IF(d.cancel_time IS NULL,'UNDATED_NOT_ASSIGNED_TO_MONTH','CURRENT_MONTH') AS date_scope,
 d.order_id,d.order_item,d.item_pk,d.transaction_id,CAST(NULL AS STRING) AS charge_id,
 s.period AS installment_period,d.business_type,d.product,d.motor_item_type,
 IF(d.payment_option='RABBIT_CARE_INSTALLMENT' OR REGEXP_CONTAINS(COALESCE(tp.providers,''),r'(^|,)RABBIT_LENDING(,|$)'),'RCL','RCB') AS flow,
 CASE WHEN d.payment_option='RABBIT_CARE_INSTALLMENT' THEN 'INSTALLMENT'
 WHEN d.payment_option='CREDIT_CARD_INSTALLMENT' THEN 'BANK_INSTALLMENT' ELSE 'ONETIME' END AS payment_mode,
 d.payment_option,COALESCE(d.snapshot_periods,d.installments) AS careos_total_installments,
 s.paid_date,tp.last_paid_at AS paid_at,'SAP_PAYMENT_DATE_FOR_CANCELLED_DOCUMENT' AS paid_date_source,
 CAST(NULL AS TIMESTAMP) AS raw_payment_at,CAST(NULL AS TIMESTAMP) AS charge_updated_at,
 DATE(d.cancel_time,'Asia/Bangkok') AS cancellation_date,d.cancel_time AS cancelled_at,
 CAST(NULL AS FLOAT64) AS charge_amount_thb,
 CAST(NULL AS FLOAT64) AS comparable_item_amount_thb,
 s.invoice_no AS raw_invoice_no,TO_JSON_STRING([s.invoice_no]) AS candidate_invoice_nos,CAST(NULL AS STRING) AS payment_method,tp.providers AS service_provider,
 CAST(NULL AS INT64) AS period_charge_rank,CAST(NULL AS INT64) AS transaction_charge_rank,
 d.order_item_count,d.compulsory_item_count,'CANCEL_SAP_DOCUMENT' AS allocation_scope,
 d.is_cancelled,d.is_change_order_new,d.is_change_order_old,d.lead_status,d.submission_status,d.approval_status,d.snapshot_periods,
 COALESCE(si.sap_item_rows,0) AS sap_item_rows,COALESCE(sp.sap_period_rows,0) AS sap_period_rows,
 COALESCE(sp.sap_period_paid_rows,0) AS sap_period_paid_rows,sp.sap_period_statuses,
 IF(s.DocEntry IS NULL,0,1) AS matched_sap_rows,IF(STARTS_WITH(s.sap_status,'cancelled'),1,0) AS terminal_matches,
 s.sap_status AS matched_statuses,s.invoice_no AS matched_invoices,CAST(s.DocEntry AS STRING) AS matched_docentries,
 s.actual_received AS sap_matched_actual,s.sap_update_at,s.paid_date AS sap_paid_date,
 CASE WHEN d.cancel_time IS NULL THEN 'CANCEL_DATE_MISSING'
 WHEN s.DocEntry IS NULL AND COALESCE(tp.successful_charge_count,0)=0 THEN 'CANCEL_NO_SAP_NO_SUCCESSFUL_PAYMENT'
 WHEN s.DocEntry IS NULL THEN 'CANCEL_CREATE_MISSING_IN_SAP'
 WHEN STARTS_WITH(s.sap_status,'cancelled') THEN 'MATCHED_SAP_CANCELLATION'
 WHEN s.invoice_no IS NOT NULL AND rs.cancelled_receipt_doc_count>0 THEN 'CANCEL_DOCUMENT_STATUS_CONFLICT'
 WHEN s.invoice_no IS NULL AND s.sap_status='pending' AND sp.sap_period_cancelled_rows>0 THEN 'CANCEL_PENDING_DOC_WITH_TERMINAL_PERIOD'
 WHEN si.sap_uncancelled_rows<si.sap_item_rows THEN 'CANCEL_PARTIALLY_APPLIED'
 WHEN sp.sap_period_rows>1 THEN 'CANCEL_MULTIPLE_ROWS_SAME_PERIOD'
 WHEN d.is_change_order_old THEN 'CANCEL_CHANGE_ORDER_NOT_APPLIED'
 ELSE 'CANCEL_STATUS_NOT_APPLIED' END AS reason_code,
 s.DocEntry AS cancellation_docentry,IF(s.invoice_no IS NULL,sp.period_cancelled_docentries,rs.cancelled_docentries) AS counterpart_cancelled_docentries
FROM dimensions d
LEFT JOIN transaction_paid tp ON tp.transaction_id=d.transaction_id
LEFT JOIN sap s ON s.order_item=d.order_item
LEFT JOIN sap_items si ON si.order_item=d.order_item
LEFT JOIN sap_period sp ON sp.order_item=d.order_item AND sp.period=s.period
LEFT JOIN sap_receipt_status rs ON rs.order_item=s.order_item AND rs.period=s.period AND rs.invoice_no IS NOT DISTINCT FROM s.invoice_no
WHERE d.is_cancelled AND d.item_pk IS NOT NULL
 AND ((DATE(d.cancel_time,'Asia/Bangkok')>=month_start AND DATE(d.cancel_time,'Asia/Bangkok')<month_end AND d.cancel_time<=as_of)
 OR (include_undated_cancellations AND d.cancel_time IS NULL));

CREATE TEMP TABLE audit_result AS
SELECT *,reason_code NOT IN ('MATCHED_SAP_RECEIPT_IDENTITY','MATCHED_SAP_CANCELLATION','NOT_APPLICABLE_COMPULSORY_LATER_CHARGE','CANCEL_NO_SAP_NO_SUCCESSFUL_PAYMENT') AS needs_review,
 CASE WHEN reason_code IN ('MATCHED_SAP_RECEIPT_IDENTITY','MATCHED_SAP_CANCELLATION') THEN 'MATCHED'
 WHEN reason_code IN ('NOT_APPLICABLE_COMPULSORY_LATER_CHARGE','CANCEL_NO_SAP_NO_SUCCESSFUL_PAYMENT') THEN 'NOT_APPLICABLE'
 WHEN reason_code IN ('AMBIGUOUS_SOURCE_RECEIPT_IDENTITY','MULTIPLE_SAP_RECEIPT_MATCHES','FALLBACK_INVOICE_REVIEW','SAP_AMOUNT_DIFF_ALLOCATION_REVIEW','MISSING_SOURCE_INVOICE','CANCEL_DATE_MISSING','CANCEL_DOCUMENT_STATUS_CONFLICT','CANCEL_PENDING_DOC_WITH_TERMINAL_PERIOD') THEN 'REVIEW'
 ELSE 'MISSING_TERMINAL_SAP_EVIDENCE' END AS reconciliation_status,
 IF(event_type='PAID' AND order_item_count>1,'MULTI_ITEM_ALLOCATION_NOT_RECONCILED',IF(event_type='PAID','SINGLE_ITEM_RAW_CHARGE_COMPARISON','DOCUMENT_STATE_ONLY')) AS amount_check_scope,
 IF(reason_code IN ('ADDITIONAL_CHARGE_PAID_PERIOD_GATE','SOURCE_LEAD_NOT_PURCHASED_REVIEW','SOURCE_SNAPSHOT_MISSING_REVIEW','CANCEL_MULTIPLE_ROWS_SAME_PERIOD','CHANGE_ORDER_NEW_FLOW_REVIEW'),'ROUTING_CAUSE_CANDIDATE','OBSERVED_DATA_STATE') AS cause_confidence,
 month_start AS audit_month_start,month_end AS audit_month_end_exclusive,as_of AS audit_as_of
FROM (SELECT * FROM paid_results UNION ALL SELECT * FROM cancel_results);

ASSERT (SELECT COUNT(DISTINCT charge_id) FROM paid_results)=(SELECT COUNT(*) FROM month_charges)
 AS 'Charge population lost during item linking';
ASSERT NOT EXISTS(SELECT 1 FROM paid_results GROUP BY charge_id,item_pk HAVING COUNT(*)>1)
 AS 'Duplicate charge-item audit rows';
ASSERT NOT EXISTS(SELECT 1 FROM cancel_results GROUP BY item_pk,cancellation_docentry HAVING COUNT(*)>1)
 AS 'Duplicate cancellation document audit rows';

-- Result 1: row/item summary; charge sums are deliberately NOT summed across item links.
SELECT event_type,date_scope,flow,business_type,payment_mode,reason_code,needs_review,reconciliation_status,
 COUNT(*) AS audit_rows,COUNT(DISTINCT order_id) AS orders,COUNT(DISTINCT order_item) AS order_items,
 COUNT(DISTINCT charge_id) AS distinct_charges
FROM audit_result GROUP BY event_type,date_scope,flow,business_type,payment_mode,reason_code,needs_review,reconciliation_status
ORDER BY event_type,needs_review DESC,audit_rows DESC;
-- Result 2: money counted ONCE per charge, irrespective of linked items.
SELECT COUNT(*) AS successful_month_charges,ROUND(SUM(amount)/100,2) AS successful_month_charge_thb,
 COUNTIF(paid_date_source='UPDATE_TIME_FALLBACK') AS fallback_paid_date_charges,
 COUNTIF(EXISTS(SELECT 1 FROM paid_results r WHERE r.charge_id=c.id AND r.reason_code NOT IN('MATCHED_SAP_RECEIPT_IDENTITY','NOT_APPLICABLE_COMPULSORY_LATER_CHARGE'))) AS charges_needing_review,
 ROUND(SUM(IF(EXISTS(SELECT 1 FROM paid_results r WHERE r.charge_id=c.id AND r.reason_code NOT IN('MATCHED_SAP_RECEIPT_IDENTITY','NOT_APPLICABLE_COMPULSORY_LATER_CHARGE')),amount,0))/100,2) AS review_charge_thb_not_missing_gl_amount,
 month_start AS month_start,month_end AS month_end_exclusive,as_of AS checked_at,
 (SELECT MAX(sap_update_at) FROM sap) AS latest_sap_business_update_at
FROM month_charges c;
-- Result 3: requested actionable detail. Set only_exceptions=FALSE to return matched rows too.
SELECT * FROM audit_result WHERE NOT only_exceptions OR needs_review
ORDER BY event_type,reason_code,order_id,order_item,installment_period,charge_id,cancellation_docentry;

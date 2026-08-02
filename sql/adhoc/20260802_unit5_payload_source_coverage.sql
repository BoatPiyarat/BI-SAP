-- SOURCE ONLY / Class A diagnostic. No persistent object, export, or GCS write.
-- Verifies that every Unit 5 target row has exactly one contract-source variant before the
-- 56-column builder is written. Run only through scripts/bq_safe_query.sh.

DECLARE p_pipeline_run_id STRING DEFAULT 'V3NIGHTLY-2026-08-02T09:02:26-b36e1712';

CREATE TEMP TABLE _event AS
SELECT e.*,
  IF(EXISTS (SELECT 1 FROM `pacific-plating-282708.sap_integration_v3.sap_mirror_doc` m
      WHERE m.U_OrderItem=e.order_item),'NEWPAYMENT','CREATE') file_role
FROM `pacific-plating-282708.sap_integration_v3.v3_unit2_event_shadow` e
WHERE e.pipeline_run_id=p_pipeline_run_id AND e.outcome='READY_CREATE_OR_PAYMENT'
  AND NOT EXISTS (SELECT 1
    FROM `pacific-plating-282708.sap_integration_v3.v3_unit3_mapping_hold` h
    WHERE h.pipeline_run_id=e.pipeline_run_id AND h.order_item=e.order_item
      AND h.period=e.period AND h.charge_id=e.charge_id);

CREATE TEMP TABLE _target AS
WITH create_rows AS (
  SELECT s.order_item,s.order_id,s.period,s.flow,s.expected_status,
    'CREATE' file_role,e.charge_id,e.invoice_no,
    IFNULL(ROW_NUMBER() OVER(PARTITION BY s.order_item,s.period
      ORDER BY e.charge_time,e.charge_id),1) event_rank
  FROM `pacific-plating-282708.sap_integration_v3.v3_unit2_schedule_shadow` s
  LEFT JOIN _event e ON e.file_role='CREATE' AND e.order_item=s.order_item AND e.period=s.period
  WHERE s.pipeline_run_id=p_pipeline_run_id
    AND EXISTS (SELECT 1 FROM _event x WHERE x.file_role='CREATE' AND x.order_item=s.order_item)
)
SELECT * FROM create_rows
UNION ALL
SELECT order_item,order_id,period,flow,'Paid','NEWPAYMENT',charge_id,invoice_no,1
FROM _event WHERE file_role='NEWPAYMENT';

CREATE TEMP TABLE _source_key AS
SELECT source_name,OrderItem,SAFE_CAST(Period AS INT64) period,
  NULLIF(TRIM(CAST(InvoiceNo AS STRING)),'') invoice_no,
  LOWER(TRIM(CAST(TransactionStatus AS STRING))) transaction_status,
  COUNT(*) physical_rows
FROM (
  SELECT 'V3_ONETIME' source_name,OrderItem,Period,InvoiceNo,TransactionStatus
  FROM `pacific-plating-282708.sap_integration_v3.vw_onetime_payload_source`
  WHERE EXISTS (SELECT 1 FROM _target t WHERE t.order_item=OrderItem)
  UNION ALL
  SELECT 'LEGACY_RCL',OrderItem,Period,InvoiceNo,TransactionStatus
  FROM `pacific-plating-282708.sap_data_engineer.sap_dashboard_carepay_installment`
  WHERE EXISTS (SELECT 1 FROM _target t WHERE t.order_item=OrderItem)
)
GROUP BY source_name,OrderItem,period,invoice_no,transaction_status;

CREATE TEMP TABLE _coverage AS
SELECT t.*,
  COUNTIF(s.OrderItem IS NOT NULL) source_variants,
  SUM(IFNULL(s.physical_rows,0)) source_physical_rows,
  STRING_AGG(DISTINCT s.source_name,',' ORDER BY s.source_name) source_names,
  (SELECT COUNT(*) FROM _source_key k
    WHERE k.OrderItem=t.order_item AND k.period=t.period) same_key_variants
FROM _target t
LEFT JOIN _source_key s ON s.OrderItem=t.order_item AND s.period=t.period
  AND ((t.invoice_no IS NOT NULL AND s.invoice_no=t.invoice_no)
    OR (t.invoice_no IS NULL AND s.invoice_no IS NULL AND s.transaction_status='pending'))
GROUP BY t.order_item,t.order_id,t.period,t.flow,t.expected_status,t.file_role,t.charge_id,
  t.invoice_no,t.event_rank;

SELECT file_role,flow,expected_status,
  CASE WHEN source_variants=0 AND same_key_variants=0 THEN 'MISSING_KEY'
       WHEN source_variants=0 AND same_key_variants=1 THEN 'INVOICE_MISMATCH_UNIQUE_SOURCE'
       WHEN source_variants=0 THEN 'INVOICE_MISMATCH_AMBIGUOUS_SOURCE'
       WHEN source_variants=1 THEN 'EXACT_SOURCE'
       ELSE 'AMBIGUOUS_SOURCE' END coverage,
  COUNT(*) records,COUNT(DISTINCT order_item) order_items,
  SUM(source_physical_rows) source_physical_rows
FROM _coverage
GROUP BY file_role,flow,expected_status,coverage
ORDER BY file_role,flow,expected_status,coverage;

-- Regression control for the Scenario 3 splitter correlation rejected by BigQuery.
-- Read-only apart from temporary tables; set the sealed run ID before execution.
DECLARE p_pipeline_run_id STRING DEFAULT 'V3NIGHTLY-2026-08-26T13:23:38-e830fff2';

CREATE TEMP TABLE _event AS
SELECT e.pipeline_run_id,e.order_item,e.period,e.charge_id,
  ARRAY_AGG(e.invoice_no IGNORE NULLS ORDER BY e.invoice_no LIMIT 1)[SAFE_OFFSET(0)] invoice_no
FROM `pacific-plating-282708.sap_integration_v3.v3_unit2_event_shadow` e
WHERE e.pipeline_run_id=p_pipeline_run_id AND e.outcome='READY_CREATE_OR_PAYMENT' AND e.flow='RCL'
  AND EXISTS (SELECT 1 FROM `pacific-plating-282708.sap_integration_v3.sap_mirror_doc` m
    WHERE m.U_OrderItem=e.order_item)
GROUP BY e.pipeline_run_id,e.order_item,e.period,e.charge_id;

CREATE TEMP TABLE _identity AS
SELECT pipeline_run_id,order_item,period,charge_id,invoice_no,
  COUNT(*) identity_rows,
  ARRAY_AGG(payload_hash IGNORE NULLS ORDER BY payload_hash LIMIT 1)[SAFE_OFFSET(0)] identity_payload_hash
FROM `pacific-plating-282708.sap_integration_v3.v3_unit5_payload_identity`
WHERE pipeline_run_id=p_pipeline_run_id AND file_role='NEWPAYMENT'
GROUP BY pipeline_run_id,order_item,period,charge_id,invoice_no;

CREATE TEMP TABLE _shape AS
SELECT e.*,COALESCE(i.identity_rows,0) identity_rows,
  (SELECT COUNT(*) FROM `pacific-plating-282708.sap_integration_v3.v3_unit5_newpayment_run_snapshot` p
    WHERE p.pipeline_run_id=e.pipeline_run_id AND p.OrderItem=e.order_item
      AND SAFE_CAST(p.Period AS INT64)=e.period AND p.InvoiceNo=e.invoice_no) target_payload_rows,
  (SELECT COUNT(*) FROM `pacific-plating-282708.sap_integration_v3.v3_unit5_newpayment_run_snapshot` p
    WHERE p.pipeline_run_id=e.pipeline_run_id AND p.OrderItem=e.order_item
      AND SAFE_CAST(p.Period AS INT64)=e.period AND p.InvoiceNo=e.invoice_no
      AND TO_HEX(SHA256(TO_JSON_STRING((SELECT AS STRUCT p.* EXCEPT(pipeline_run_id,snapshotted_at)))))
        =i.identity_payload_hash) hash_match_rows
FROM _event e
LEFT JOIN _identity i ON i.pipeline_run_id=e.pipeline_run_id AND i.order_item=e.order_item
  AND i.period=e.period AND i.charge_id=e.charge_id AND i.invoice_no=e.invoice_no;

ASSERT (SELECT COUNT(*) FROM _shape)=(SELECT COUNT(*) FROM _event)
  AS 'Scenario 3 correlation rewrite lost or multiplied event identities';
ASSERT (SELECT COUNTIF(hash_match_rows>target_payload_rows) FROM _shape)=0
  AS 'Scenario 3 hash matches cannot exceed target payload rows';
ASSERT (SELECT AS STRUCT COUNT(*) event_identities,COUNTIF(identity_rows>0) matched_identity_rows,
    COUNTIF(target_payload_rows>0) matched_payload_rows,COUNTIF(hash_match_rows=1) exact_hash_rows
  FROM _shape)=STRUCT(367 AS event_identities,4 AS matched_identity_rows,
    1 AS matched_payload_rows,1 AS exact_hash_rows)
  AS 'Scenario 3 sealed-run identity/hash expectations changed';

SELECT COUNT(*) event_identities,COUNTIF(identity_rows>0) matched_identity_rows,
  COUNTIF(target_payload_rows>0) matched_payload_rows,COUNTIF(hash_match_rows=1) exact_hash_rows
FROM _shape;

-- Read-only diagnosis of the latest failed V3 workflow execution.
DECLARE p_pipeline_run_id STRING DEFAULT 'V3NIGHTLY-2026-08-03T11:24:27-437934f3';

SELECT
  (SELECT COUNT(*) FROM `pacific-plating-282708.sap_integration_v3.v3_unit5_payload_identity`
    WHERE pipeline_run_id=p_pipeline_run_id AND file_role='NEWPAYMENT') AS identity_rows,
  (SELECT COUNT(*) FROM `pacific-plating-282708.sap_integration_v3.v3_unit5_balance_hold`
    WHERE pipeline_run_id=p_pipeline_run_id) AS held_identity_rows,
  (SELECT COUNT(DISTINCT order_item)
    FROM `pacific-plating-282708.sap_integration_v3.v3_unit5_balance_hold`
    WHERE pipeline_run_id=p_pipeline_run_id) AS held_items,
  (SELECT COUNT(*)
    FROM `pacific-plating-282708.sap_integration_v3.v3_unit5_newpayment_delivery_ready` d
    WHERE ABS(SAFE_CAST(d.ActualReceived AS NUMERIC)-SAFE_CAST(d.ExpectedReceived AS NUMERIC))>10
      AND EXISTS (
        SELECT 1
        FROM `pacific-plating-282708.sap_integration_v3.v3_unit5_payload_identity` i
        WHERE i.pipeline_run_id=p_pipeline_run_id AND i.file_role='NEWPAYMENT'
          AND i.order_item=d.OrderItem AND i.period=SAFE_CAST(d.Period AS INT64)
          AND i.invoice_no=d.InvoiceNo)) AS remaining_target_mismatches,
  (SELECT COUNT(*)
    FROM `pacific-plating-282708.sap_integration_v3.v3_unit5_newpayment_delivery_ready`)
    AS current_delivery_ready_rows;

SELECT d.OrderItem,d.Period,d.InvoiceNo,d.ExpectedReceived,d.ActualReceived,
  EXISTS (
    SELECT 1 FROM `pacific-plating-282708.sap_integration_v3.v3_unit5_balance_hold` h
    WHERE h.pipeline_run_id=p_pipeline_run_id AND h.order_item=d.OrderItem) AS item_has_hold
FROM `pacific-plating-282708.sap_integration_v3.v3_unit5_newpayment_delivery_ready` d
WHERE ABS(SAFE_CAST(d.ActualReceived AS NUMERIC)-SAFE_CAST(d.ExpectedReceived AS NUMERIC))>10
  AND EXISTS (
    SELECT 1
    FROM `pacific-plating-282708.sap_integration_v3.v3_unit5_payload_identity` i
    WHERE i.pipeline_run_id=p_pipeline_run_id AND i.file_role='NEWPAYMENT'
      AND i.order_item=d.OrderItem AND i.period=SAFE_CAST(d.Period AS INT64)
      AND i.invoice_no=d.InvoiceNo)
ORDER BY d.OrderItem,d.Period
LIMIT 100;

WITH latest AS (
  SELECT pipeline_run_id,MAX(built_at) AS built_at
  FROM `pacific-plating-282708.sap_integration_v3.v3_unit5_payload_identity`
  WHERE file_role='NEWPAYMENT'
  GROUP BY pipeline_run_id
  ORDER BY built_at DESC
  LIMIT 1
)
SELECT l.pipeline_run_id,l.built_at,
  COUNT(DISTINCT TO_JSON_STRING(STRUCT(i.order_item,i.period,i.charge_id,i.payload_hash)))
    AS identity_rows,
  COUNT(DISTINCT IF(h.order_item IS NOT NULL,
    TO_JSON_STRING(STRUCT(i.order_item,i.period,i.charge_id,i.payload_hash)),NULL)) AS held_identities,
  COUNT(DISTINCT IF(d.OrderItem IS NOT NULL,
    TO_JSON_STRING(STRUCT(i.order_item,i.period,i.charge_id,i.payload_hash)),NULL))
    AS delivery_matched_identities,
  COUNTIF(d.OrderItem IS NOT NULL
    AND ABS(SAFE_CAST(d.ActualReceived AS NUMERIC)-SAFE_CAST(d.ExpectedReceived AS NUMERIC))>10)
    AS remaining_target_mismatches
FROM latest l
JOIN `pacific-plating-282708.sap_integration_v3.v3_unit5_payload_identity` i
  ON i.pipeline_run_id=l.pipeline_run_id AND i.file_role='NEWPAYMENT'
LEFT JOIN `pacific-plating-282708.sap_integration_v3.v3_unit5_balance_hold` h
  ON h.pipeline_run_id=i.pipeline_run_id AND h.order_item=i.order_item
 AND h.period=i.period AND h.charge_id=i.charge_id
LEFT JOIN `pacific-plating-282708.sap_integration_v3.v3_unit5_newpayment_delivery_ready` d
  ON d.OrderItem=i.order_item AND SAFE_CAST(d.Period AS INT64)=i.period
 AND d.InvoiceNo=i.invoice_no
GROUP BY l.pipeline_run_id,l.built_at;

SELECT routine_name,last_altered
FROM `pacific-plating-282708.sap_integration_v3.INFORMATION_SCHEMA.ROUTINES`
WHERE routine_name IN ('sp_build_v3_newpayment_delivery_ready','sp_run_v3_units2_5')
ORDER BY routine_name;

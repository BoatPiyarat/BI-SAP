-- Read-only evidence for fresh V3 CREATE candidates that do not bind exactly to their payload source.
-- The query compares the immutable charge identity at every transformation boundary.
DECLARE target_run_id STRING DEFAULT 'V3NIGHTLY-2026-08-25T14:32:37-0ce16d45';

CREATE TEMP TABLE classified AS
WITH create_event AS (
  SELECT e.order_item, e.period, e.charge_id, e.flow, e.invoice_no AS event_invoice_no
  FROM `pacific-plating-282708.sap_integration_v3.v3_unit2_event_shadow` e
  WHERE e.pipeline_run_id = target_run_id
    AND e.outcome = 'READY_CREATE_OR_PAYMENT'
    AND NOT EXISTS (
      SELECT 1
      FROM `pacific-plating-282708.sap_integration_v3.sap_mirror_doc` m
      WHERE m.U_OrderItem = e.order_item
    )
    AND NOT EXISTS (
      SELECT 1
      FROM `pacific-plating-282708.sap_integration_v3.v3_unit3_mapping_hold` h
      WHERE h.pipeline_run_id = e.pipeline_run_id
        AND h.order_item = e.order_item
        AND h.period = e.period
        AND h.charge_id = e.charge_id
    )
),
identity_boundary AS (
  SELECT
    e.*,
    c.third_party_id AS raw_third_party_id,
    s.third_party_id AS staged_third_party_id,
    CASE
      WHEN e.flow = 'ONETIME' THEN o.InvoiceNo
      ELSE r.InvoiceNo
    END AS source_invoice_no
  FROM create_event e
  JOIN `pacific-plating-282708.careos.carepay_charges` c
    ON c.id = e.charge_id
  JOIN `pacific-plating-282708.sap_integration_v3.stg_payment_events` s
    ON s.charge_id = e.charge_id
  LEFT JOIN `pacific-plating-282708.sap_integration_v3.vw_onetime_payload_source` o
    ON e.flow = 'ONETIME'
    AND o.OrderItem = e.order_item
    AND SAFE_CAST(o.Period AS INT64) = e.period
  LEFT JOIN `pacific-plating-282708.sap_data_engineer.sap_dashboard_carepay_installment` r
    ON e.flow = 'RCL'
    AND r.OrderItem = e.order_item
    AND SAFE_CAST(r.Period AS INT64) = e.period
)
SELECT *,
    CASE
      WHEN raw_third_party_id IS NULL THEN 'RAW_NULL'
      WHEN staged_third_party_id != raw_third_party_id THEN 'STAGE_CHANGED_RAW'
      WHEN event_invoice_no != staged_third_party_id THEN 'EVENT_CHANGED_STAGE'
      WHEN source_invoice_no = event_invoice_no THEN 'EXACT'
      WHEN source_invoice_no = CONCAT('1_', event_invoice_no) THEN 'SOURCE_1_PREFIX'
      WHEN source_invoice_no = CONCAT('2_', event_invoice_no) THEN 'SOURCE_2_PREFIX'
      WHEN STARTS_WITH(IFNULL(source_invoice_no, ''), CONCAT(event_invoice_no, '_'))
        THEN 'SOURCE_EVENT_PREFIX'
      WHEN source_invoice_no IS NULL THEN 'SOURCE_NULL'
      ELSE 'OTHER_MISMATCH'
    END AS identity_shape
FROM identity_boundary;

SELECT
  flow,
  identity_shape,
  COUNT(*) AS joined_rows,
  COUNT(DISTINCT charge_id) AS event_count,
  COUNTIF(raw_third_party_id IS NULL) AS raw_null_count
FROM classified
GROUP BY flow, identity_shape
ORDER BY flow, identity_shape;

SELECT
  flow,
  identity_shape,
  order_item,
  period,
  charge_id,
  raw_third_party_id,
  staged_third_party_id,
  event_invoice_no,
  source_invoice_no
FROM classified
WHERE identity_shape != 'EXACT'
QUALIFY ROW_NUMBER() OVER (PARTITION BY flow, identity_shape ORDER BY order_item, period) <= 10
ORDER BY flow, identity_shape, order_item, period;

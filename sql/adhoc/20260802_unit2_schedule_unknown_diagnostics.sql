-- Read-only diagnostic for Unit 2 schedule-grain UNKNOWN rows.
-- Run with standard dry-run, 20 GiB cap, and asia-southeast1 location.
DECLARE target_run_id STRING DEFAULT 'V3NIGHTLY-2026-08-02T09:02:26-b36e1712';

SELECT
  s.flow,
  s.expected_status,
  s.sap_status,
  s.expected_invoice_no IS NULL AS expected_invoice_is_null,
  s.sap_invoice_no IS NULL AS sap_invoice_is_null,
  d.is_cancelled_effective,
  COUNT(*) AS records,
  COUNT(DISTINCT s.order_id) AS orders
FROM `pacific-plating-282708.sap_integration_v3.v3_unit2_schedule_shadow` s
LEFT JOIN `pacific-plating-282708.sap_integration_v3.stg_order_dim` d
  USING (order_item, order_id)
WHERE s.pipeline_run_id = target_run_id
  AND s.outcome = 'HELD_CLASSIFICATION_UNKNOWN'
GROUP BY 1,2,3,4,5,6
ORDER BY records DESC, flow, expected_status, sap_status;

SELECT
  COUNT(*) AS records,
  COUNT(DISTINCT FORMAT('%s|%d', s.order_item, s.period)) AS keys,
  COUNTIF(e.order_item IS NULL) AS absent_from_expected_state,
  COUNTIF(x.order_item IS NULL) AS absent_from_exclusion_register,
  COUNTIF(v.order_item IS NULL) AS absent_from_validation_register
FROM `pacific-plating-282708.sap_integration_v3.v3_unit2_schedule_shadow` s
LEFT JOIN `pacific-plating-282708.sap_integration_v3.expected_state` e
  ON e.order_item=s.order_item AND e.period=s.period
LEFT JOIN (
  SELECT DISTINCT order_item, period
  FROM `pacific-plating-282708.sap_integration_v3.sap_excluded_records`
) x ON x.order_item=s.order_item AND x.period=s.period
LEFT JOIN (
  SELECT DISTINCT order_item, period
  FROM `pacific-plating-282708.sap_integration_v3.sap_validation_error`
) v ON v.order_item=s.order_item AND v.period=s.period
WHERE s.pipeline_run_id = target_run_id
  AND s.outcome = 'HELD_CLASSIFICATION_UNKNOWN';

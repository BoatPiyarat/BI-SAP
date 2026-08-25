DECLARE target_run_id STRING DEFAULT 'V3NIGHTLY-2026-08-25T11:17:18-ca7ee9e7';

SELECT
  'run_log' AS evidence,
  step AS key,
  status AS value,
  rows_out AS count_value,
  ended_at AS observed_at,
  error_message AS detail
FROM `pacific-plating-282708.sap_integration_v3.pipeline_run_log`
WHERE run_id = target_run_id

UNION ALL

SELECT
  'unit_row_count',
  unit_name,
  'ROWS',
  row_count,
  CURRENT_TIMESTAMP(),
  NULL
FROM (
  SELECT 'unit2_event_shadow' AS unit_name, COUNT(*) AS row_count
  FROM `pacific-plating-282708.sap_integration_v3.v3_unit2_event_shadow`
  WHERE pipeline_run_id = target_run_id
  UNION ALL
  SELECT 'unit5_payload_identity', COUNT(*)
  FROM `pacific-plating-282708.sap_integration_v3.v3_unit5_payload_identity`
  WHERE pipeline_run_id = target_run_id
  UNION ALL
  SELECT 'unit5_balance_hold', COUNT(*)
  FROM `pacific-plating-282708.sap_integration_v3.v3_unit5_balance_hold`
  WHERE pipeline_run_id = target_run_id
)

UNION ALL

SELECT
  'conflicting_archive',
  a.export_run_id,
  a.delivery_status,
  COUNT(*),
  MAX(a.exported_at),
  CONCAT('file=', ANY_VALUE(a.file_name), '; archive=', ANY_VALUE(a.archive_uri),
         '; production=', COALESCE(ANY_VALUE(a.gcs_uri), 'NULL'))
FROM `pacific-plating-282708.sap_integration_v3.v3_unit5_payload_identity` i
JOIN `pacific-plating-282708.sap_integration_v3.export_archive` a
  ON a.order_item = i.order_item
 AND a.period = i.period
 AND a.charge_id = i.charge_id
WHERE i.pipeline_run_id = target_run_id
  AND i.file_role = 'NEWPAYMENT'
  AND a.delivery_status IN (
    'PREPARED_ARCHIVE', 'ARCHIVED_PENDING_OBJECT_METADATA',
    'ARCHIVED_PENDING_DELIVERY', 'DELIVERED', 'PICKED_UP', 'ACKNOWLEDGED')
GROUP BY a.export_run_id, a.delivery_status
ORDER BY evidence, observed_at, key;

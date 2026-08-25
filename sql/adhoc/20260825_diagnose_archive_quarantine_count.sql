SELECT export_run_id,delivery_status,COUNT(*) AS ledger_rows,
  COUNT(DISTINCT TO_JSON_STRING(STRUCT(order_item,period,charge_id))) AS distinct_identities,
  COUNT(DISTINCT order_item) AS distinct_items,
  COUNT(DISTINCT archive_uri) AS archive_uri_count,
  COUNTIF(gcs_uri IS NOT NULL OR object_generation IS NOT NULL OR file_sha256 IS NOT NULL
    OR sap_log_id IS NOT NULL OR sap_result_status IS NOT NULL OR acknowledged_at IS NOT NULL)
    AS rows_with_delivery_or_sap_evidence,
  MIN(exported_at) AS first_exported_at,MAX(exported_at) AS last_exported_at
FROM `pacific-plating-282708.sap_integration_v3.export_archive`
WHERE export_run_id='V3DAILY-20260824-113215-68dfc784'
GROUP BY export_run_id,delivery_status;

SELECT
  (SELECT COUNT(*) FROM `pacific-plating-282708.sap_integration_v3.export_file_manifest`
    WHERE export_run_id='V3DAILY-20260824-113215-68dfc784') AS file_manifests,
  (SELECT COUNT(*) FROM `pacific-plating-282708.sap_integration_v3.sap_delivery_manifest_v3`
    WHERE export_run_id='V3DAILY-20260824-113215-68dfc784') AS sap_manifests,
  (SELECT COUNT(*) FROM `pacific-plating-282708.sap_integration_v3.v3_archive_quarantine_log`
    WHERE export_run_id='V3DAILY-20260824-113215-68dfc784') AS quarantine_logs;

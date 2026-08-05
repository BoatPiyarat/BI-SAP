-- Read-only check of the production-object basename versus SAP's reported filename for LogID 21183.

DECLARE p_export_run_id STRING DEFAULT 'V3DAILY-20260803-113257-55042e7c';
DECLARE p_log_id STRING DEFAULT '21183';
DECLARE p_email_file_name STRING DEFAULT
  'RCB_MOTOR_INSURANCE_RCB_06_V3_DAILY_NEWPAYMENT_20260803_V3DAILY-20260803-113257-55042e7c_000000000000.csv';

WITH evidence AS (
  SELECT
    'sap_delivery_manifest_v3' AS evidence_source,
    export_run_id,
    sap_file_name AS recorded_file_name,
    REGEXP_EXTRACT(production_uri, r'([^/]+)$') AS production_basename,
    production_uri,
    CAST(data_row_count AS STRING) AS row_count,
    delivery_status AS status
  FROM `pacific-plating-282708.sap_integration_v3.sap_delivery_manifest_v3`
  WHERE DATE(recorded_at) BETWEEN DATE '2026-08-03' AND DATE '2026-08-06'
    AND export_run_id = p_export_run_id

  UNION ALL

  SELECT
    'export_file_manifest',
    export_run_id,
    NULL,
    REGEXP_EXTRACT(production_uri, r'([^/]+)$'),
    production_uri,
    CAST(data_row_count AS STRING),
    delivery_status
  FROM `pacific-plating-282708.sap_integration_v3.export_file_manifest`
  WHERE DATE(recorded_at) BETWEEN DATE '2026-08-03' AND DATE '2026-08-06'
    AND export_run_id = p_export_run_id

  UNION ALL

  SELECT
    'export_archive',
    export_run_id,
    ANY_VALUE(file_name),
    REGEXP_EXTRACT(ANY_VALUE(gcs_uri), r'([^/]+)$'),
    ANY_VALUE(gcs_uri),
    CAST(COUNT(*) AS STRING),
    ANY_VALUE(delivery_status)
  FROM `pacific-plating-282708.sap_integration_v3.export_archive`
  WHERE DATE(exported_at) BETWEEN DATE '2026-08-03' AND DATE '2026-08-06'
    AND export_run_id = p_export_run_id
  GROUP BY export_run_id

  UNION ALL

  SELECT
    'sap_import_result_header_v3',
    NULL,
    file_name,
    NULL,
    NULL,
    NULL,
    status
  FROM `pacific-plating-282708.sap_integration_v3.sap_import_result_header_v3`
  WHERE DATE(ingested_at) BETWEEN DATE '2026-08-03' AND DATE '2026-08-06'
    AND log_id = p_log_id
)
SELECT
  evidence_source,
  export_run_id,
  recorded_file_name,
  production_basename,
  production_uri,
  row_count,
  status,
  recorded_file_name = p_email_file_name AS recorded_name_matches_email,
  production_basename = p_email_file_name AS production_basename_matches_email
FROM evidence
ORDER BY evidence_source;

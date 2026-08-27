-- Read-only proof that prerequisite definition/schema deployments did not perform runtime work.
SELECT
  (SELECT COUNT(*)
    FROM `pacific-plating-282708.sap_integration_v3.v3_unit2_magnitude_config`
    WHERE effective_start <= CURRENT_TIMESTAMP()
      AND (effective_end IS NULL OR effective_end > CURRENT_TIMESTAMP())) AS active_config_count,
  (SELECT COUNT(*)
    FROM `pacific-plating-282708.sap_integration_v3.v3_unit2_magnitude_run`
    WHERE config_id LIKE 'BOOTSTRAP-%') AS bootstrap_run_count,
  (SELECT COUNT(*)
    FROM `pacific-plating-282708.sap_integration_v3.v3_daily_completeness_run`)
    AS completeness_run_count,
  (SELECT COUNT(*)
    FROM `pacific-plating-282708.sap_integration_v3.v3_daily_completeness_metric`)
    AS completeness_metric_count,
  (SELECT COUNT(*)
    FROM `pacific-plating-282708.sap_integration_v3.v3_daily_completeness_evidence`)
    AS completeness_evidence_count,
  (SELECT COUNT(*)
    FROM `pacific-plating-282708.sap_integration_v3.INFORMATION_SCHEMA.COLUMNS`
    WHERE table_name = 'sap_delivery_manifest_v3'
      AND column_name = 'production_file_name') AS production_file_name_column_count;

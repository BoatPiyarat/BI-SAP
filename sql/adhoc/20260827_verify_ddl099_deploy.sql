-- Read-only post-deploy verification for DDL 099. No bootstrap CALL is made.
SELECT
  (SELECT COUNT(*)
    FROM `pacific-plating-282708.sap_integration_v3.INFORMATION_SCHEMA.ROUTINES`
    WHERE routine_name = 'sp_bootstrap_v3_unit2_magnitude') AS routine_count,
  (SELECT TO_HEX(SHA256(routine_definition))
    FROM `pacific-plating-282708.sap_integration_v3.INFORMATION_SCHEMA.ROUTINES`
    WHERE routine_name = 'sp_bootstrap_v3_unit2_magnitude') AS live_definition_sha256,
  (SELECT COUNT(*)
    FROM `pacific-plating-282708.sap_integration_v3.v3_unit2_magnitude_config`
    WHERE effective_start <= CURRENT_TIMESTAMP()
      AND (effective_end IS NULL OR effective_end > CURRENT_TIMESTAMP())) AS active_config_count,
  (SELECT COUNT(*)
    FROM `pacific-plating-282708.sap_integration_v3.v3_unit2_magnitude_run`
    WHERE config_id LIKE 'BOOTSTRAP-%') AS bootstrap_run_count;

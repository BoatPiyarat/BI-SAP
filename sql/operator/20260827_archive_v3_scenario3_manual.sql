-- MUTATING HUMAN FALLBACK. Archives one exact approved Scenario 3 run to the restricted
-- sap-interface-archive prefix only. It does not write gs://interface-file/**.
-- Deploy reviewed DDL 100 first and replace every sentinel before execution.

DECLARE target_pipeline_run_id STRING DEFAULT 'REPLACE_WITH_APPROVED_PIPELINE_RUN_ID';
DECLARE target_export_run_id STRING DEFAULT 'REPLACE_WITH_V3SCENARIO3_YYYYMMDD_HHMMSS_TOKEN';
DECLARE requested_by STRING DEFAULT 'REPLACE_WITH_OPERATOR_IDENTITY';

ASSERT target_pipeline_run_id != 'REPLACE_WITH_APPROVED_PIPELINE_RUN_ID'
  AS 'Set the exact approved Scenario 3 pipeline run';
ASSERT target_export_run_id != 'REPLACE_WITH_V3SCENARIO3_YYYYMMDD_HHMMSS_TOKEN'
  AS 'Set an exact V3SCENARIO3-YYYYMMDD-HHMMSS-xxxxxxxx export token';
ASSERT requested_by != 'REPLACE_WITH_OPERATOR_IDENTITY'
  AS 'Set the accountable operator identity';

CALL `pacific-plating-282708.sap_integration_v3.sp_export_v3_scenario3_archive`(
  target_pipeline_run_id, target_export_run_id, requested_by);

SELECT *
FROM `pacific-plating-282708.sap_integration_v3.v3_flow_export_claim`
WHERE export_run_id = target_export_run_id;

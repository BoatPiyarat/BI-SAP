-- MUTATING EVIDENCE ADAPTER. Run only after DDL 100 + DDL 101 are deployed and the exact
-- Scenario 1 manual-delivery marker has already succeeded. This does not write or copy GCS.

DECLARE target_pipeline_run_id STRING DEFAULT 'REPLACE_WITH_APPROVED_PIPELINE_RUN_ID';
DECLARE target_export_run_id STRING DEFAULT 'REPLACE_WITH_EXACT_EXPORT_RUN_ID';
DECLARE registered_by STRING DEFAULT 'REPLACE_WITH_OPERATOR_IDENTITY';

ASSERT target_pipeline_run_id != 'REPLACE_WITH_APPROVED_PIPELINE_RUN_ID'
  AND target_export_run_id != 'REPLACE_WITH_EXACT_EXPORT_RUN_ID'
  AND registered_by != 'REPLACE_WITH_OPERATOR_IDENTITY'
  AS 'Replace all Scenario 1 lifecycle registration sentinels';

CALL `pacific-plating-282708.sap_integration_v3.sp_register_v3_scenario1_lifecycle`(
  target_pipeline_run_id, target_export_run_id, registered_by);

SELECT *
FROM `pacific-plating-282708.sap_integration_v3.vw_v3_flow_export_lifecycle`
WHERE export_run_id = target_export_run_id;

-- READ ONLY. Exact production preflight for approved Unit 2 pilot UNIT2-PILOT-20260827-V1.
-- Run only through scripts/bq_safe_query.sh immediately before the one-time bootstrap CALL.

DECLARE v_baseline_run_id STRING DEFAULT 'V3NIGHTLY-2026-08-25T22:21:31-manual';
DECLARE v_config_id STRING DEFAULT 'UNIT2-PILOT-20260827-V1';

DECLARE v_active_config_count INT64;
DECLARE v_config_id_count INT64;
DECLARE v_archive_success_count INT64;
DECLARE v_summary_count INT64;
DECLARE v_magnitude_run_count INT64;
DECLARE v_distribution_count INT64;
DECLARE v_result_count INT64;

SET v_active_config_count = (SELECT COUNT(*)
  FROM `pacific-plating-282708.sap_integration_v3.v3_unit2_magnitude_config`
  WHERE effective_start <= CURRENT_TIMESTAMP()
    AND (effective_end IS NULL OR effective_end > CURRENT_TIMESTAMP()));
SET v_config_id_count = (SELECT COUNT(*)
  FROM `pacific-plating-282708.sap_integration_v3.v3_unit2_magnitude_config`
  WHERE config_id = v_config_id);
SET v_archive_success_count = (SELECT COUNT(*)
  FROM `pacific-plating-282708.sap_integration_v3.pipeline_run_log`
  WHERE run_id = v_baseline_run_id
    AND step = 'UNITS_2_5_ARCHIVE'
    AND status = 'SUCCESS');
SET v_summary_count = (SELECT COUNT(*)
  FROM `pacific-plating-282708.sap_integration_v3.v3_unit2_summary`
  WHERE pipeline_run_id = v_baseline_run_id);
SET v_magnitude_run_count = (SELECT COUNT(*)
  FROM `pacific-plating-282708.sap_integration_v3.v3_unit2_magnitude_run`
  WHERE pipeline_run_id = v_baseline_run_id);
SET v_distribution_count = (SELECT COUNT(*)
  FROM `pacific-plating-282708.sap_integration_v3.v3_unit2_distribution`
  WHERE pipeline_run_id = v_baseline_run_id);
SET v_result_count = (SELECT COUNT(*)
  FROM `pacific-plating-282708.sap_integration_v3.v3_unit2_magnitude_result`
  WHERE pipeline_run_id = v_baseline_run_id);

ASSERT v_active_config_count = 0 AS 'STOP: an active Unit 2 magnitude configuration exists';
ASSERT v_config_id_count = 0 AS 'STOP: approved config_id already exists';
ASSERT v_archive_success_count = 1 AS 'STOP: baseline must have exactly one successful archive row';
ASSERT v_summary_count > 0 AS 'STOP: baseline Unit 2 summary is missing';
ASSERT v_magnitude_run_count = 0 AS 'STOP: baseline magnitude run already exists';
ASSERT v_distribution_count = 0 AS 'STOP: baseline distribution already exists';
ASSERT v_result_count = 0 AS 'STOP: baseline magnitude results already exist';

SELECT
  v_baseline_run_id AS baseline_run_id,
  v_config_id AS config_id,
  v_active_config_count AS active_config_count,
  v_config_id_count AS config_id_count,
  v_archive_success_count AS archive_success_count,
  v_summary_count AS summary_count,
  v_magnitude_run_count AS magnitude_run_count,
  v_distribution_count AS distribution_count,
  v_result_count AS result_count,
  'PASS' AS preflight_status;

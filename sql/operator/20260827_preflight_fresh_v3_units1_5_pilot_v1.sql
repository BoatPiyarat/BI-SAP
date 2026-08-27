-- READ ONLY. Exact BigQuery gate for one fresh V3 Units 1-5 workflow execution.
-- Workflow delivery remains false, but the execution does read SAP, use the bronze/load path,
-- build V3 tables, and may write a restricted rcb-bronze-zone archive when Unit 5 has ready rows.

DECLARE v_checked_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP();
DECLARE v_config_id STRING DEFAULT 'UNIT2-PILOT-20260827-V1';
DECLARE v_baseline_run_id STRING DEFAULT 'V3NIGHTLY-2026-08-25T22:21:31-manual';

ASSERT (SELECT COUNT(*)
  FROM `pacific-plating-282708.sap_integration_v3.v3_unit2_magnitude_config`
  WHERE effective_start <= v_checked_at
    AND effective_end > TIMESTAMP_ADD(v_checked_at, INTERVAL 2 HOUR)) = 1
  AS 'STOP: exactly one active Unit 2 configuration with two hours remaining is required';
ASSERT (SELECT COUNT(*)
  FROM `pacific-plating-282708.sap_integration_v3.v3_unit2_magnitude_config`
  WHERE config_id = v_config_id
    AND effective_start <= v_checked_at
    AND effective_end > TIMESTAMP_ADD(v_checked_at, INTERVAL 2 HOUR)
    AND effective_start = TIMESTAMP '2026-08-27 14:51:46+00'
    AND effective_end = TIMESTAMP '2026-08-31 17:00:00+00'
    AND records_absolute = 25 AND records_percentage = 0.05
    AND orders_absolute = 10 AND orders_percentage = 0.05
    AND amount_satang_absolute = 500000 AND amount_percentage = 0.05
    AND approval_reference = 'Boat-chat-20260827-UNIT2-PILOT-20260827-V1'
    AND approved_by = 'Boat'
    AND approved_at = TIMESTAMP '2026-08-27 14:51:46+00') = 1
  AS 'STOP: active Unit 2 configuration does not equal Boat-approved pilot V1';
ASSERT (SELECT COUNT(*)
  FROM `pacific-plating-282708.sap_integration_v3.v3_unit2_magnitude_run`
  WHERE pipeline_run_id = v_baseline_run_id
    AND baseline_run_id = v_baseline_run_id
    AND config_id = v_config_id
    AND compared_cells = 39
    AND breached_cells = 0
    AND status = 'PASS') = 1
  AS 'STOP: exact reviewed Unit 2 bootstrap PASS is missing';
ASSERT (SELECT COUNT(*)
  FROM `pacific-plating-282708.sap_integration_v3.pipeline_run_log`
  WHERE run_id = v_baseline_run_id
    AND step = 'UNITS_2_5_ARCHIVE'
    AND status = 'SUCCESS') = 1
  AS 'STOP: bootstrap baseline does not have exactly one successful archive step';

SELECT
  v_checked_at AS checked_at,
  v_config_id AS config_id,
  v_baseline_run_id AS baseline_run_id,
  'PASS' AS preflight_status,
  'Production interface delivery remains disabled; bronze extract/load/archive writes remain possible'
    AS execution_boundary;

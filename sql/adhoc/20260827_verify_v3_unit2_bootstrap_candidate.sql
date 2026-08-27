-- Read-only verification of the proposed first Unit 2 magnitude baseline.
DECLARE v_baseline_run_id STRING DEFAULT 'V3NIGHTLY-2026-08-25T22:21:31-manual';

ASSERT (SELECT COUNT(*)
  FROM `pacific-plating-282708.sap_integration_v3.pipeline_run_log`
  WHERE run_id = v_baseline_run_id
    AND step = 'UNITS_2_5_ARCHIVE'
    AND status = 'SUCCESS') = 1
  AS 'baseline must have exactly one successful Units 2-5 archive row';

ASSERT (SELECT COUNT(*)
  FROM `pacific-plating-282708.sap_integration_v3.v3_unit2_summary`
  WHERE pipeline_run_id = v_baseline_run_id) > 0
  AS 'baseline Unit 2 summary is absent';

ASSERT (SELECT COUNT(*)
  FROM `pacific-plating-282708.sap_integration_v3.v3_unit2_distribution`
  WHERE pipeline_run_id = v_baseline_run_id) = 0
  AS 'baseline already has distribution evidence';

ASSERT (SELECT COUNT(*)
  FROM `pacific-plating-282708.sap_integration_v3.v3_unit2_magnitude_run`
  WHERE pipeline_run_id = v_baseline_run_id) = 0
  AS 'baseline already has a magnitude result';

ASSERT (SELECT COUNT(*)
  FROM `pacific-plating-282708.sap_integration_v3.v3_unit2_magnitude_config`
  WHERE effective_start <= CURRENT_TIMESTAMP()
    AND (effective_end IS NULL OR effective_end > CURRENT_TIMESTAMP())) = 0
  AS 'an active magnitude configuration already exists';

SELECT v_baseline_run_id AS baseline_run_id,
  (SELECT COUNT(*)
    FROM `pacific-plating-282708.sap_integration_v3.v3_unit2_summary`
    WHERE pipeline_run_id = v_baseline_run_id) AS unit2_summary_rows,
  (SELECT COUNT(*)
    FROM `pacific-plating-282708.sap_integration_v3.v3_unit2_event_shadow`
    WHERE pipeline_run_id = v_baseline_run_id) AS event_rows,
  (SELECT COUNT(*)
    FROM `pacific-plating-282708.sap_integration_v3.v3_unit2_schedule_shadow`
    WHERE pipeline_run_id = v_baseline_run_id) AS schedule_rows,
  0 AS active_config_count,
  0 AS existing_distribution_rows,
  0 AS existing_magnitude_run_rows;

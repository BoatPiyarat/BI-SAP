-- SOURCE ONLY / Class A.
-- Dashboard evidence for the extract/orchestrator cadence. BigQuery cannot read Cloud Scheduler
-- or Cloud Logging directly, and the legacy sap_extract_control table is confirmed empty/dead.
-- This view therefore uses durable pipeline_run_log rows written by the V3 workflow.
--
-- Important boundary: pipeline_run_log does not record whether a workflow execution was started
-- by Cloud Scheduler or manually. `execution_health` detects a missing/failed orchestrated run,
-- while `scheduler_trigger_status` remains UNVERIFIED_TRIGGER until trigger provenance is added.
-- A manual workflow execution can otherwise mask a missed scheduler trigger.

CREATE OR REPLACE VIEW
  `pacific-plating-282708.sap_integration_v3.vw_dash_extract_scheduler_health` AS
WITH orchestrator_runs AS (
  SELECT
    run_id,
    MIN(IF(step = 'UNIT1_START', started_at, NULL)) AS run_started_at,
    MAX(IF(step = 'EXTRACT_DONE' AND status = 'SUCCESS', ended_at, NULL)) AS extract_done_at,
    MAX(IF(step = 'HEALTHY_ZERO' AND status = 'SUCCESS', ended_at, NULL)) AS healthy_zero_at,
    MAX(IF(step = 'LOAD_COMMITMENT' AND status = 'SUCCESS', ended_at, NULL)) AS load_committed_at,
    MAX(IF(step = 'UNIT1_COMPLETE' AND status = 'SUCCESS', ended_at, NULL)) AS unit1_completed_at,
    COUNTIF(status = 'FAILED') AS failed_steps,
    ARRAY_AGG(
      IF(status = 'FAILED', STRUCT(step, error_message, ended_at), NULL)
      IGNORE NULLS ORDER BY ended_at DESC LIMIT 1
    )[SAFE_OFFSET(0)] AS latest_failure
  FROM `pacific-plating-282708.sap_integration_v3.pipeline_run_log`
  WHERE scope = 'NIGHTLY:orchestrator'
  GROUP BY run_id
),
latest AS (
  SELECT *
  FROM orchestrator_runs
  WHERE run_started_at IS NOT NULL
  QUALIFY ROW_NUMBER() OVER (ORDER BY run_started_at DESC, run_id DESC) = 1
)
SELECT
  run_id AS latest_run_id,
  run_started_at AS latest_run_started_at,
  TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), run_started_at, HOUR) AS hours_since_latest_run,
  extract_done_at,
  healthy_zero_at,
  load_committed_at,
  unit1_completed_at,
  failed_steps,
  latest_failure.step AS latest_failed_step,
  latest_failure.error_message AS latest_error_message,
  CASE
    WHEN run_id IS NULL THEN 'NO_EVIDENCE'
    WHEN TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), run_started_at, HOUR) > 26 THEN 'STALE'
    WHEN failed_steps > 0 OR unit1_completed_at IS NULL THEN 'FAILED_OR_INCOMPLETE'
    WHEN healthy_zero_at IS NOT NULL OR load_committed_at IS NOT NULL THEN 'FRESH'
    ELSE 'EVIDENCE_INCOMPLETE'
  END AS execution_health,
  'UNVERIFIED_TRIGGER' AS scheduler_trigger_status,
  'pipeline_run_log:NIGHTLY:orchestrator' AS evidence_source,
  CURRENT_TIMESTAMP() AS checked_at
FROM (SELECT 1) anchor
LEFT JOIN latest ON TRUE;

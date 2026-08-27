-- Read-only human fallback for a claimed or activated common Scheduler cutover.
-- This query does not call Cloud Scheduler. It reports the exact durable restoration target.
-- Replace the sentinel only with the approved cutover_id recorded by DDL 102.

DECLARE v_cutover_id STRING DEFAULT 'REPLACE_WITH_APPROVED_CUTOVER_ID';

ASSERT v_cutover_id!='REPLACE_WITH_APPROVED_CUTOVER_ID'
  AS 'Set the exact approved common Scheduler cutover_id';
ASSERT (SELECT COUNT(*)
  FROM `pacific-plating-282708.sap_integration_v3.v3_common_scheduler_cutover_ledger`
  WHERE cutover_id=v_cutover_id AND cutover_state IN ('CLAIMED','ACTIVATED'))=1
  AS 'Fallback requires exactly one live CLAIMED or ACTIVATED cutover';

SELECT
  cutover_id,
  cutover_state,
  workflow_revision,
  JSON_VALUE(legacy_prestate,'$.name') AS legacy_scheduler_name,
  JSON_VALUE(legacy_prestate,'$.state') AS restore_legacy_state,
  JSON_VALUE(legacy_prestate,'$.schedule') AS restore_legacy_schedule,
  JSON_VALUE(legacy_prestate,'$.timeZone') AS restore_legacy_time_zone,
  JSON_VALUE(v3_prestate,'$.name') AS v3_scheduler_name,
  'PAUSED' AS required_v3_safe_state,
  JSON_VALUE(v3_prestate,'$.schedule') AS v3_schedule,
  JSON_VALUE(v3_prestate,'$.timeZone') AS v3_time_zone,
  legacy_config_hash,
  v3_config_hash,
  pre_inventory_evidence_id,
  claimed_by,
  claimed_at,
  verification_reference,
  CASE cutover_state
    WHEN 'CLAIMED' THEN 'After exact restoration, close as ABORTED'
    WHEN 'ACTIVATED' THEN 'After exact restoration, close as ROLLED_BACK'
  END AS required_ledger_transition
FROM `pacific-plating-282708.sap_integration_v3.v3_common_scheduler_cutover_ledger`
WHERE cutover_id=v_cutover_id;

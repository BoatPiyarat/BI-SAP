-- CLASS A / EMERGENCY ROLLBACK — DO NOT RUN WITHOUT EXPLICIT BOAT APPROVAL.
-- Exact rollback for sql/adhoc/20260824_correct_august_period_cutoff_1600.sql only.

DECLARE v_period_start DATE DEFAULT DATE '2026-08-01';
DECLARE v_new_cutoff TIMESTAMP DEFAULT TIMESTAMP '2026-09-01 09:00:00+00';
DECLARE v_old_cutoff TIMESTAMP DEFAULT TIMESTAMP '2026-09-01 07:00:00+00';

ASSERT CURRENT_TIMESTAMP() < v_old_cutoff
  AS 'Rollback must execute before the original cutoff';
ASSERT (SELECT COUNT(*) FROM `pacific-plating-282708.sap_integration_v3.sap_period_state`
  WHERE period_start=v_period_start AND status='OPEN'
    AND closing_at=v_new_cutoff AND state_version=3)=1
  AS 'Rollback period-state precondition failed';
ASSERT (SELECT COUNT(*) FROM `pacific-plating-282708.sap_integration_v3.sap_period_lock`
  WHERE period='2026-08' AND open_period_start=v_period_start AND lock_datetime=v_new_cutoff
    AND locked_by IS NULL AND locked_at IS NULL)=1
  AS 'Rollback period-lock precondition failed';

BEGIN TRANSACTION;

UPDATE `pacific-plating-282708.sap_integration_v3.sap_period_state`
SET closing_at=v_old_cutoff,
    state_version=state_version+1,
    updated_at=CURRENT_TIMESTAMP()
WHERE period_start=v_period_start
  AND status='OPEN'
  AND closing_at=v_new_cutoff
  AND state_version=3;
ASSERT @@row_count=1 AS 'Expected exactly one August period-state row to roll back';

UPDATE `pacific-plating-282708.sap_integration_v3.sap_period_lock`
SET lock_datetime=v_old_cutoff
WHERE period='2026-08'
  AND open_period_start=v_period_start
  AND lock_datetime=v_new_cutoff
  AND locked_by IS NULL
  AND locked_at IS NULL;
ASSERT @@row_count=1 AS 'Expected exactly one August period-lock row to roll back';

COMMIT TRANSACTION;

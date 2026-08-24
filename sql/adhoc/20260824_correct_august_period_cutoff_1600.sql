-- CLASS A / PRODUCTION DML — DO NOT RUN WITHOUT REVIEW PASS + BOAT DEPLOY APPROVAL.
-- Purpose: correct the live August 2026 accounting-period cutoff from 14:00 to 16:00 ICT.
-- Human source: Mo Pawinee Tantheeraphonchai relaying Boat Piyarat Toomsap at
-- 2026-08-24 13:51 ICT: closing period 1-Sep-26 16:00.
-- Durable confirmation:
-- https://docs.google.com/spreadsheets/d/1K_LLlIfPgJWnKRJfJ1e4ZMkdf8M7_u2addZGbdwHo_Q/edit
--
-- Live pre-state captured through scripts/bq_safe_query.sh at 2026-08-24 17:55 ICT
-- (query timestamp 2026-08-24 10:55:00 UTC; 239 bytes):
--   sap_period_state 2026-08: OPEN, closing_at 2026-09-01 07:00:00 UTC, state_version 2
--   sap_period_state 2026-09: PLANNED
--   sap_period_lock  2026-08: lock_datetime 2026-09-01 07:00:00 UTC
--   sap_period_cutoff_calendar: NOT DEPLOYED
--
-- Rollback: use sql/adhoc/20260824_rollback_august_period_cutoff_1400.sql only if this exact
-- transaction succeeds and a separately approved rollback is required. Both files are atomic.

DECLARE v_period_start DATE DEFAULT DATE '2026-08-01';
DECLARE v_next_period_start DATE DEFAULT DATE '2026-09-01';
DECLARE v_old_cutoff TIMESTAMP DEFAULT TIMESTAMP '2026-09-01 07:00:00+00';
DECLARE v_new_cutoff TIMESTAMP DEFAULT TIMESTAMP '2026-09-01 09:00:00+00';

ASSERT CURRENT_TIMESTAMP() < v_old_cutoff
  AS 'Correction must execute before the previously registered cutoff';
ASSERT (SELECT COUNT(*) FROM `pacific-plating-282708.sap_integration_v3.sap_period_state`
  WHERE period_start=v_period_start AND period_id='2026-08' AND period_end=v_next_period_start
    AND status='OPEN' AND closing_at=v_old_cutoff AND state_version=2)=1
  AS 'August OPEN period pre-state differs from reviewed evidence';
ASSERT (SELECT COUNT(*) FROM `pacific-plating-282708.sap_integration_v3.sap_period_state`
  WHERE period_start=v_next_period_start AND period_id='2026-09'
    AND status='PLANNED' AND closing_at IS NULL)=1
  AS 'Adjacent September PLANNED period pre-state differs from reviewed evidence';
ASSERT (SELECT COUNT(*) FROM `pacific-plating-282708.sap_integration_v3.sap_period_lock`
  WHERE period='2026-08' AND open_period_start=v_period_start AND lock_datetime=v_old_cutoff
    AND locked_by IS NULL AND locked_at IS NULL)=1
  AS 'August legacy period-lock pre-state differs from reviewed evidence';

BEGIN TRANSACTION;

UPDATE `pacific-plating-282708.sap_integration_v3.sap_period_state`
SET closing_at=v_new_cutoff,
    state_version=state_version+1,
    updated_at=CURRENT_TIMESTAMP()
WHERE period_start=v_period_start
  AND status='OPEN'
  AND closing_at=v_old_cutoff
  AND state_version=2;
ASSERT @@row_count=1 AS 'Expected exactly one August period-state row to update';

UPDATE `pacific-plating-282708.sap_integration_v3.sap_period_lock`
SET lock_datetime=v_new_cutoff
WHERE period='2026-08'
  AND open_period_start=v_period_start
  AND lock_datetime=v_old_cutoff
  AND locked_by IS NULL
  AND locked_at IS NULL;
ASSERT @@row_count=1 AS 'Expected exactly one August period-lock row to update';

ASSERT (SELECT COUNT(*) FROM `pacific-plating-282708.sap_integration_v3.sap_period_state`
  WHERE period_start=v_period_start AND status='OPEN'
    AND closing_at=v_new_cutoff AND state_version=3)=1
  AS 'August period-state post-condition failed';
ASSERT (SELECT COUNT(*) FROM `pacific-plating-282708.sap_integration_v3.sap_period_lock`
  WHERE period='2026-08' AND open_period_start=v_period_start AND lock_datetime=v_new_cutoff
    AND locked_by IS NULL AND locked_at IS NULL)=1
  AS 'August period-lock post-condition failed';

COMMIT TRANSACTION;

SELECT
  period_id,
  period_start,
  period_end,
  status,
  closing_at,
  state_version,
  updated_at
FROM `pacific-plating-282708.sap_integration_v3.sap_period_state`
WHERE period_start IN (v_period_start,v_next_period_start)
ORDER BY period_start;


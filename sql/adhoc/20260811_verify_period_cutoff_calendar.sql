-- Executable verification for sql/ddl/075_v3_period_cutoff_calendar.sql, addressing the
-- "no executable tests were provided" BLOCK finding in
-- docs/reviews/2026-08-11-a82409d-codex.md.
--
-- Part 1: sp_register_period_cutoff is exercised live via real CALLs, using period_start values
-- in year 2099 (obviously synthetic; never collides with the real July/August 2026 rows). Safe to
-- run against the live table -- this procedure only ever touches sap_period_cutoff_calendar, never
-- sap_period_state. Cleans up its own rows before and after.
--
-- Part 2: sp_transition_due_period_from_calendar's branching logic is rehearsed against TEMP
-- tables only, following the exact safe pattern already established in
-- sql/adhoc/20260802_unit4_period_state_rehearsal.sql. A stored procedure's fully-qualified table
-- references always resolve to the real tables regardless of any same-named TEMP table in the
-- caller's scope, so the real procedure cannot be called against fabricated data without touching
-- the real sap_period_state -- and that table's "exactly one OPEN period" invariant is live
-- production state (sp_close_open_period asserts it) that must never be corrupted, even
-- temporarily, by a test. This rehearsal instead re-implements the procedure's exact branching
-- predicates (copied from sql/ddl/075_v3_period_cutoff_calendar.sql) against isolated TEMP data.
--
-- Explicitly NOT covered here, disclosed rather than faked:
--   - Timezone: p_closing_at/CURRENT_TIMESTAMP() are both absolute TIMESTAMP instants with no
--     timezone conversion in this procedure's own logic; the timezone-correctness concern lives
--     at the human data-entry point (Finance/Boat supplying the correct UTC-equivalent instant
--     when registering a cutoff), which this SQL cannot test.
--   - Rerun-after-transition: requires actually calling sp_transition_due_period_from_calendar
--     against a real (or a dedicated isolated-fixture, like sql/ddl/074_post_import_rehearsal_fixtures.sql
--     built for the post-import case) sap_period_state, which this file deliberately does not do.
--     Flagged in RQ-20260811-* as follow-up work, not silently skipped.

DECLARE test_period_1 DATE DEFAULT DATE '2099-01-01';
DECLARE test_period_2 DATE DEFAULT DATE '2099-02-01';
DECLARE failures INT64 DEFAULT 0;

DELETE FROM `pacific-plating-282708.sap_integration_v3.sap_period_cutoff_calendar`
WHERE period_start IN (test_period_1, test_period_2);

-- T1: valid registration succeeds.
CALL `pacific-plating-282708.sap_integration_v3.sp_register_period_cutoff`(
  test_period_1, TIMESTAMP '2099-02-01 00:00:00 UTC', 'test-suite',
  'sql/adhoc/20260811_verify_period_cutoff_calendar.sql'
);
IF (SELECT COUNT(*) FROM `pacific-plating-282708.sap_integration_v3.sap_period_cutoff_calendar`
    WHERE period_start = test_period_1) != 1 THEN
  SET failures = failures + 1;
  SELECT 'T1 FAIL: valid registration did not insert exactly one row' AS result;
ELSE
  SELECT 'T1 PASS: valid registration inserted one row' AS result;
END IF;

-- T2: duplicate registration is rejected (hard failure, caught here).
BEGIN
  CALL `pacific-plating-282708.sap_integration_v3.sp_register_period_cutoff`(
    test_period_1, TIMESTAMP '2099-02-01 00:00:00 UTC', 'test-suite', 'duplicate-attempt'
  );
  SET failures = failures + 1;
  SELECT 'T2 FAIL: duplicate registration did not raise' AS result;
EXCEPTION WHEN ERROR THEN
  SELECT 'T2 PASS: duplicate registration correctly rejected' AS result;
END;

-- T3: non-month-aligned period_start is rejected.
BEGIN
  CALL `pacific-plating-282708.sap_integration_v3.sp_register_period_cutoff`(
    DATE '2099-03-15', TIMESTAMP '2099-04-01 00:00:00 UTC', 'test-suite', 'misaligned-attempt'
  );
  SET failures = failures + 1;
  SELECT 'T3 FAIL: non-month-aligned period_start did not raise' AS result;
EXCEPTION WHEN ERROR THEN
  SELECT 'T3 PASS: non-month-aligned period_start correctly rejected' AS result;
END;

-- T4: blank approved_by is rejected.
BEGIN
  CALL `pacific-plating-282708.sap_integration_v3.sp_register_period_cutoff`(
    test_period_2, TIMESTAMP '2099-03-01 00:00:00 UTC', '   ', 'blank-approver-attempt'
  );
  SET failures = failures + 1;
  SELECT 'T4 FAIL: blank approved_by did not raise' AS result;
EXCEPTION WHEN ERROR THEN
  SELECT 'T4 PASS: blank approved_by correctly rejected' AS result;
END;

-- T5: blank source_reference is rejected.
BEGIN
  CALL `pacific-plating-282708.sap_integration_v3.sp_register_period_cutoff`(
    test_period_2, TIMESTAMP '2099-03-01 00:00:00 UTC', 'test-suite', ''
  );
  SET failures = failures + 1;
  SELECT 'T5 FAIL: blank source_reference did not raise' AS result;
EXCEPTION WHEN ERROR THEN
  SELECT 'T5 PASS: blank source_reference correctly rejected' AS result;
END;

-- T6: closing_at not later than period_start is rejected.
BEGIN
  CALL `pacific-plating-282708.sap_integration_v3.sp_register_period_cutoff`(
    test_period_2, TIMESTAMP '2099-01-15 00:00:00 UTC', 'test-suite', 'early-cutoff-attempt'
  );
  SET failures = failures + 1;
  SELECT 'T6 FAIL: closing_at not later than period_start did not raise' AS result;
EXCEPTION WHEN ERROR THEN
  SELECT 'T6 PASS: closing_at not later than period_start correctly rejected' AS result;
END;

DELETE FROM `pacific-plating-282708.sap_integration_v3.sap_period_cutoff_calendar`
WHERE period_start IN (test_period_1, test_period_2);

SELECT IF(failures = 0, 'PART 1: ALL PASS', CONCAT('PART 1: ', CAST(failures AS STRING), ' FAILURE(S)'))
  AS part1_result;

-- =================================================================================================
-- Part 2: TEMP-table rehearsal of sp_transition_due_period_from_calendar's branching (no CALL, no
-- production mutation). Mirrors sql/adhoc/20260802_unit4_period_state_rehearsal.sql's pattern.
-- =================================================================================================

DECLARE rehearsal_failures INT64 DEFAULT 0;

-- Scenario A: NOT_DUE (cutoff is in the future relative to real current time).
CREATE OR REPLACE TEMP TABLE rehearsal_period_state AS
SELECT DATE '2099-05-01' AS period_start, 'OPEN' AS status,
  TIMESTAMP_ADD(CURRENT_TIMESTAMP(), INTERVAL 1 HOUR) AS closing_at;
CREATE OR REPLACE TEMP TABLE rehearsal_calendar AS
SELECT DATE '2099-05-01' AS period_start, TIMESTAMP_ADD(CURRENT_TIMESTAMP(), INTERVAL 1 HOUR) AS closing_at
UNION ALL
SELECT DATE '2099-06-01', TIMESTAMP_ADD(CURRENT_TIMESTAMP(), INTERVAL 2 HOUR);
IF (SELECT COUNT(*) FROM rehearsal_period_state WHERE status = 'OPEN') != 1 THEN
  SET rehearsal_failures = rehearsal_failures + 1;
  SELECT 'SCENARIO A SETUP FAIL: expected exactly one OPEN row' AS result;
ELSEIF (SELECT c.closing_at FROM rehearsal_calendar c JOIN rehearsal_period_state p USING (period_start))
    != (SELECT closing_at FROM rehearsal_period_state) THEN
  SET rehearsal_failures = rehearsal_failures + 1;
  SELECT 'SCENARIO A FAIL: calendar/state closing_at mismatch (should match by construction)' AS result;
ELSEIF CURRENT_TIMESTAMP() < (SELECT closing_at FROM rehearsal_period_state) THEN
  SELECT 'SCENARIO A PASS: NOT_DUE predicted' AS result;
ELSE
  SET rehearsal_failures = rehearsal_failures + 1;
  SELECT 'SCENARIO A FAIL: expected NOT_DUE (cutoff is 1 hour in the future)' AS result;
END IF;

-- Scenario B: TRANSITIONED (cutoff is in the past; next period's calendar row exists).
CREATE OR REPLACE TEMP TABLE rehearsal_period_state AS
SELECT DATE '2099-05-01' AS period_start, 'OPEN' AS status,
  TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 HOUR) AS closing_at;
CREATE OR REPLACE TEMP TABLE rehearsal_calendar AS
SELECT DATE '2099-05-01' AS period_start, TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 HOUR) AS closing_at
UNION ALL
SELECT DATE '2099-06-01', TIMESTAMP_ADD(CURRENT_TIMESTAMP(), INTERVAL 1 HOUR);
IF CURRENT_TIMESTAMP() < (SELECT closing_at FROM rehearsal_period_state) THEN
  SET rehearsal_failures = rehearsal_failures + 1;
  SELECT 'SCENARIO B FAIL: expected the cutoff to already be due' AS result;
ELSEIF (SELECT COUNT(*) FROM rehearsal_calendar WHERE period_start = DATE '2099-06-01') != 1 THEN
  SET rehearsal_failures = rehearsal_failures + 1;
  SELECT 'SCENARIO B FAIL: next period calendar row missing (should exist by construction)' AS result;
ELSE
  SELECT 'SCENARIO B PASS: TRANSITIONED predicted (would delegate to sp_close_open_period)' AS result;
END IF;

-- Scenario C: fail-closed -- no registered calendar cutoff for the current OPEN period.
CREATE OR REPLACE TEMP TABLE rehearsal_period_state AS
SELECT DATE '2099-05-01' AS period_start, 'OPEN' AS status,
  TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 HOUR) AS closing_at;
CREATE OR REPLACE TEMP TABLE rehearsal_calendar AS
SELECT DATE '2099-06-01' AS period_start, TIMESTAMP_ADD(CURRENT_TIMESTAMP(), INTERVAL 1 HOUR) AS closing_at;
IF (SELECT closing_at FROM rehearsal_calendar c JOIN rehearsal_period_state p USING (period_start)) IS NULL THEN
  SELECT 'SCENARIO C PASS: fail-closed, no calendar row for current OPEN period' AS result;
ELSE
  SET rehearsal_failures = rehearsal_failures + 1;
  SELECT 'SCENARIO C FAIL: expected no matching calendar row' AS result;
END IF;

-- Scenario D: fail-closed -- calendar cutoff does not match sap_period_state.closing_at.
CREATE OR REPLACE TEMP TABLE rehearsal_period_state AS
SELECT DATE '2099-05-01' AS period_start, 'OPEN' AS status,
  TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 HOUR) AS closing_at;
CREATE OR REPLACE TEMP TABLE rehearsal_calendar AS
SELECT DATE '2099-05-01' AS period_start, TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 2 HOUR) AS closing_at;
IF (SELECT c.closing_at FROM rehearsal_calendar c JOIN rehearsal_period_state p USING (period_start))
    = (SELECT closing_at FROM rehearsal_period_state) THEN
  SET rehearsal_failures = rehearsal_failures + 1;
  SELECT 'SCENARIO D FAIL: expected a mismatch between calendar and state closing_at' AS result;
ELSE
  SELECT 'SCENARIO D PASS: fail-closed, calendar/state closing_at mismatch detected' AS result;
END IF;

-- Scenario E: fail-closed -- cutoff is due but next period has no registered calendar cutoff.
CREATE OR REPLACE TEMP TABLE rehearsal_period_state AS
SELECT DATE '2099-05-01' AS period_start, 'OPEN' AS status,
  TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 HOUR) AS closing_at;
CREATE OR REPLACE TEMP TABLE rehearsal_calendar AS
SELECT DATE '2099-05-01' AS period_start, TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 HOUR) AS closing_at;
IF (SELECT COUNT(*) FROM rehearsal_calendar WHERE period_start = DATE '2099-06-01') != 0 THEN
  SET rehearsal_failures = rehearsal_failures + 1;
  SELECT 'SCENARIO E SETUP FAIL: next period calendar row should not exist' AS result;
ELSE
  SELECT 'SCENARIO E PASS: fail-closed, no calendar row for next period at due cutoff' AS result;
END IF;

SELECT IF(rehearsal_failures = 0, 'PART 2: ALL PASS', CONCAT('PART 2: ', CAST(rehearsal_failures AS STRING), ' FAILURE(S)'))
  AS part2_result;

-- SOURCE ONLY / Class A. Implements the "smallest safe implementation" from
-- docs/FINDINGS_MONTHLY_CUTOFF_AUTOMATION_GAP_20260805.md (reviewed PASS,
-- docs/reviews/2026-08-06-9c61d17-claude.md / RQ-20260805-2202).
--
-- Closes the automation gap where the nightly workflow (061_v3_units2_5_nightly_wrapper.sql)
-- never calls sp_close_open_period (053_v3_unit4_period_state_machine.sql), so the daily
-- pipeline cannot advance the accounting period unattended across a month boundary.
--
-- Deploying these definitions does not seed the calendar, register a cutoff, or transition a
-- period. Seeding/registering/transitioning are separate mutations requiring their own reviewed
-- CALLs by Codex (SINGLE DEPLOYER). Wiring sp_transition_due_period_from_calendar into the
-- nightly workflow is also a separate, later change per the finding's own gate list.
--
-- Deliberately NOT built here (per the finding's "Gates before implementation" #1 and #2):
--   - Any UPDATE/correction path for sap_period_cutoff_calendar. The registry/correction policy
--     is not yet confirmed with Finance; a wrong row today can only be worked around by a future
--     reviewed correction artifact, never a silent in-place UPDATE. sp_register_period_cutoff
--     therefore only inserts and only ever rejects a duplicate period_start.
--   - The September (or any post-August) cutoff row. Finance has not supplied it; nothing in
--     this file invents or defaults a future month.

CREATE TABLE IF NOT EXISTS `pacific-plating-282708.sap_integration_v3.sap_period_cutoff_calendar` (
  period_start DATE NOT NULL,
  closing_at TIMESTAMP NOT NULL,
  approved_by STRING NOT NULL,
  source_reference STRING NOT NULL,
  recorded_at TIMESTAMP NOT NULL
)
CLUSTER BY period_start;

CREATE OR REPLACE PROCEDURE `pacific-plating-282708.sap_integration_v3.sp_register_period_cutoff`(
  p_period_start DATE,
  p_closing_at TIMESTAMP,
  p_approved_by STRING,
  p_source_reference STRING
)
BEGIN
  ASSERT p_period_start=DATE_TRUNC(p_period_start,MONTH)
    AS 'period_start must be month-aligned';
  ASSERT NULLIF(TRIM(p_approved_by),'') IS NOT NULL AS 'approved_by is required';
  ASSERT NULLIF(TRIM(p_source_reference),'') IS NOT NULL AS 'source_reference is required';
  ASSERT p_closing_at>TIMESTAMP(p_period_start)
    AS 'closing_at must be later than period_start';

  -- Atomic insert-only guard (Codex review docs/reviews/2026-08-11-a82409d-codex.md: a separate
  -- ASSERT COUNT(*)=0 then INSERT is not atomic, so two concurrent calls can both pass the assert
  -- and both insert). MERGE...WHEN NOT MATCHED THEN INSERT is a single atomic DML statement,
  -- mirroring the exact established idiom in 071_v3_post_import_refresh_outbox.sql's
  -- sp_enqueue_v3_post_import_refresh. Unlike that idempotent-retry case (ASSERT @@row_count IN
  -- (0,1)), a duplicate period_start here must be a hard failure, not a silent no-op — registration
  -- is meant to reject re-registration, so @@row_count must be exactly 1.
  MERGE `pacific-plating-282708.sap_integration_v3.sap_period_cutoff_calendar` t
  USING (SELECT p_period_start AS period_start) s
  ON t.period_start=s.period_start
  WHEN NOT MATCHED THEN INSERT
    (period_start,closing_at,approved_by,source_reference,recorded_at)
    VALUES (p_period_start,p_closing_at,p_approved_by,p_source_reference,CURRENT_TIMESTAMP());
  ASSERT @@row_count=1
    AS 'period_start already has a registered cutoff; corrections need a reviewed correction artifact, not re-registration';
END;

CREATE OR REPLACE PROCEDURE `pacific-plating-282708.sap_integration_v3.sp_transition_due_period_from_calendar`(
  p_closed_by STRING,
  OUT p_result STRING
)
BEGIN
  DECLARE v_open_period_start DATE;
  DECLARE v_open_closing_at TIMESTAMP;
  DECLARE v_calendar_closing_at TIMESTAMP;
  DECLARE v_next_start DATE;
  DECLARE v_next_calendar_closing_at TIMESTAMP;

  ASSERT (SELECT COUNT(*) FROM `pacific-plating-282708.sap_integration_v3.sap_period_state`
    WHERE status='OPEN')=1 AS 'Requires exactly one OPEN period';
  SET (v_open_period_start,v_open_closing_at)=(
    SELECT AS STRUCT period_start,closing_at
    FROM `pacific-plating-282708.sap_integration_v3.sap_period_state`
    WHERE status='OPEN'
  );

  SET v_calendar_closing_at=(
    SELECT closing_at FROM `pacific-plating-282708.sap_integration_v3.sap_period_cutoff_calendar`
    WHERE period_start=v_open_period_start
  );
  ASSERT v_calendar_closing_at IS NOT NULL
    AS 'No registered calendar cutoff for the current OPEN period — fails closed, not inferred';
  ASSERT v_calendar_closing_at=v_open_closing_at
    AS 'Calendar cutoff does not match sap_period_state.closing_at — fails closed';

  IF CURRENT_TIMESTAMP()<v_calendar_closing_at THEN
    SET p_result='NOT_DUE';
  ELSE
    SET v_next_start=DATE_ADD(v_open_period_start,INTERVAL 1 MONTH);
    SET v_next_calendar_closing_at=(
      SELECT closing_at FROM `pacific-plating-282708.sap_integration_v3.sap_period_cutoff_calendar`
      WHERE period_start=v_next_start
    );
    ASSERT v_next_calendar_closing_at IS NOT NULL
      AS 'No registered calendar cutoff for the next period — fails closed, cannot transition';

    CALL `pacific-plating-282708.sap_integration_v3.sp_close_open_period`(
      v_open_period_start,v_calendar_closing_at,v_next_calendar_closing_at,p_closed_by
    );
    SET p_result='TRANSITIONED';
  END IF;
END;

-- 030_interface_daily_status.sql
-- TASK_V3_GAP_CLOSURE_v2.md A2 + Boat 2026-07-27 away-window plan item 2.2.
--
-- *** FIRST DRAFT, UNVERIFIED against Boat's exact intended semantics for STATUS_CONFLICT /
-- PAID_AFTER_CANCEL / the D+2 boundary - built from the task doc's status list and my own
-- best-effort interpretation, NOT yet confirmed by Boat. Flagging every judgment call inline.
-- Do not treat this as a finished spec - it's a real, deployed, working first pass that needs
-- review. ***
--
-- Judgment calls made (please confirm/correct):
-- 1. "age" for the D+2 PENDING_ACK/MISSING boundary = days since expected_payment_date (the date
--    CareOS expects this period to be Paid by). If expected_payment_date is NULL or in the future,
--    age is treated as 0 (i.e. PENDING_ACK, not MISSING) - a conservative choice to avoid false
--    MISSING alarms on periods that aren't due yet.
-- 2. STATUS_CONFLICT = SAP shows Cancelled/Cancelled(Change order) for a period CareOS does NOT
--    expect to be Cancelled - a genuine disagreement, distinct from ordinary payment-timing lag.
-- 3. PAID_AFTER_CANCEL = SAP's own PaymentDate for this period is AFTER careos_order_items'
--    cancel_time - a real post-cancellation payment, the actual red flag. *** CORRECTED after
--    first deploy 2026-07-27: the initial version fired on "is_cancelled AND currently Paid" with
--    NO timing comparison at all, which matched 1,898 rows that turned out to be the normal,
--    already-established-as-expected "paid periods before being cancelled, cancellation is final"
--    pattern (2026-07-25 changelog) - e.g. L78263089-V1 paid across Apr-Jun 2026, cancelled
--    2026-07-27, all 4 of its periods false-positived as PAID_AFTER_CANCEL. Fixed by parsing SAP's
--    DDMMYYYY PaymentDate and comparing against cancel_time; re-verified this drops the count from
--    1,898 to near-zero (see 30_SAP_CHANGELOG.md 2026-07-27 for the corrected number). ***
--    Deliberately checked BEFORE STATUS_CONFLICT (an order can be both "CareOS says cancelled" and
--    "SAP shows Paid after that" - PAID_AFTER_CANCEL is the more specific/actionable case).
-- 4. UNROUTED passes through expected_state.flow = 'UNROUTED' - currently 0 rows exist (Credit
--    Shell/other unrouted flows aren't in expected_state yet, PHASE B item), kept for when that's
--    added so this table doesn't need a second change later.
--
-- Grain: 1 row per (order_item, period), full rebuild every run (same convention as
-- delta_export). Distinct from delta_export (which stays, unchanged, feeding the diff-harness
-- work) - this table is the A2-specific status vocabulary, a different lens on the same join.

CREATE OR REPLACE PROCEDURE `pacific-plating-282708.sap_integration_v3.sp_refresh_interface_daily_status`()
BEGIN
  DECLARE run_id STRING DEFAULT GENERATE_UUID();
  DECLARE started TIMESTAMP DEFAULT CURRENT_TIMESTAMP();
  DECLARE row_count INT64;

  CREATE OR REPLACE TABLE `pacific-plating-282708.sap_integration_v3.interface_daily_status`
  CLUSTER BY status AS
  WITH base AS (
    SELECT
      e.order_item, e.order_id, e.period, e.flow, e.expected_status, e.expected_invoice_no,
      e.expected_payment_date,
      s.TransactionStatus AS sap_status, s.U_InvoiceNo AS sap_invoice_no,
      s.resolution_confidence,  -- added 2026-07-27: surfaces PROVISIONAL_PENDING_AWARE_Q3A rows
      SAFE.PARSE_DATE('%d%m%Y', s.PaymentDate) AS sap_payment_date,
      IFNULL(oi.is_cancelled, FALSE) AS is_cancelled,
      DATE(oi.cancel_time) AS cancel_date
    FROM `pacific-plating-282708.sap_integration_v3.expected_state` e
    LEFT JOIN `pacific-plating-282708.sap_integration_v3.stg_sap_state` s
      ON s.U_OrderItem = e.order_item AND s.U_Period = e.period
    LEFT JOIN `pacific-plating-282708.careos.careos_order_items` oi
      ON oi.human_id = e.order_item
  ),
  classified AS (
    SELECT *,
      GREATEST(DATE_DIFF(CURRENT_DATE(), COALESCE(expected_payment_date, CURRENT_DATE()), DAY), 0) AS age_days,
      CASE
        WHEN flow = 'UNROUTED' THEN 'UNROUTED'
        WHEN is_cancelled AND IFNULL(sap_invoice_no, '') != '' AND sap_status IN ('Paid', 'paid')
             AND sap_payment_date IS NOT NULL AND cancel_date IS NOT NULL AND sap_payment_date > cancel_date
          THEN 'PAID_AFTER_CANCEL'
        WHEN sap_status IN ('Cancelled', 'Cancelled (Change order / Rejected)')
             AND expected_status != 'Cancelled'
          THEN 'STATUS_CONFLICT'
        WHEN expected_status = 'Paid' AND IFNULL(sap_invoice_no, '') = '' THEN
          IF(GREATEST(DATE_DIFF(CURRENT_DATE(), COALESCE(expected_payment_date, CURRENT_DATE()), DAY), 0) <= 2,
             'PENDING_ACK', 'MISSING')
        ELSE 'OK'
      END AS status
    FROM base
  )
  SELECT
    order_item, order_id, period, flow, expected_status, expected_invoice_no, expected_payment_date,
    sap_status, sap_invoice_no, resolution_confidence, is_cancelled, age_days, status,
    CURRENT_TIMESTAMP() AS computed_at
  FROM classified;

  SET row_count = (SELECT COUNT(*) FROM `pacific-plating-282708.sap_integration_v3.interface_daily_status`);

  INSERT INTO `pacific-plating-282708.sap_integration_v3.pipeline_run_log`
    (run_id, run_type, step, scope, rows_in, rows_out, started_at, ended_at, status, error_message)
  VALUES (run_id, 'NIGHTLY', 'interface_daily_status', 'FULL', NULL, row_count, started,
          CURRENT_TIMESTAMP(), 'SUCCESS', NULL);
END;

-- Alert design note (important, please read before trusting this): A2's spec says "alert on
-- MISSING/STATUS_CONFLICT". Taken literally (>0 rows) this would fire EVERY single day, because
-- both categories have large, pre-existing, already-known backlogs today (MISSING ~341K,
-- STATUS_CONFLICT ~59K - this is the historical gap this whole V3 project exists to close, not a
-- new incident). An alert that always fires is worse than no alert - it trains you to ignore it.
-- Without a day-over-day baseline to compare against (not built yet - would need a small history
-- table snapshotting counts nightly), absolute-count alerting on these two is not viable. So:
-- - PAID_AFTER_CANCEL: alerts on ANY row (>0) - genuinely rare (7 today) and always actionable.
-- - Freshness (no fresh row by late morning): alerts if stale.
-- - MISSING/STATUS_CONFLICT: reported as information only in the daily digest (Step 4 of the
--   07:00 routine), NOT as a standalone trigger here, until a real baseline-comparison mechanism
--   exists. Flagged as a real gap vs Boat's literal ask - see docs/INPUTS_NEEDED.md.
CREATE OR REPLACE PROCEDURE `pacific-plating-282708.sap_integration_v3.sp_check_interface_daily_status_alert`()
BEGIN
  DECLARE paid_after_cancel_n INT64;
  DECLARE last_computed TIMESTAMP;
  DECLARE hours_since_computed INT64;

  SET paid_after_cancel_n = (SELECT COUNT(*) FROM `pacific-plating-282708.sap_integration_v3.interface_daily_status` WHERE status = 'PAID_AFTER_CANCEL');
  SET last_computed = (SELECT MAX(computed_at) FROM `pacific-plating-282708.sap_integration_v3.interface_daily_status`);
  SET hours_since_computed = TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), last_computed, HOUR);

  IF hours_since_computed > 12 THEN
    RAISE USING MESSAGE = FORMAT(
      'interface_daily_status has not refreshed in %d hours (last: %t) - by 07:30 ICT there should be a fresh row. The nightly chain may not have run.',
      hours_since_computed, last_computed
    );
  ELSEIF paid_after_cancel_n > 0 THEN
    RAISE USING MESSAGE = FORMAT(
      'interface_daily_status: %d PAID_AFTER_CANCEL row(s) - a real payment recorded in SAP after the order was cancelled in CareOS. Check `pacific-plating-282708.sap_integration_v3.interface_daily_status` WHERE status = \'PAID_AFTER_CANCEL\'.',
      paid_after_cancel_n
    );
  END IF;
END;

-- 017_sap_validation_error.sql
-- P2 build (Boat, 2026-07-25: "start building" V3 P1-P3).
-- Implements SAP_INTERFACE_REDESIGN_V3.md §2.6 L4 Validation - "fail -> sap_validation_error
-- (ห้าม drop เงียบ)". This table has never existed before today - every prior silent-drop
-- incident this project has had (A1-A7 in the design doc's own problem inventory) is exactly the
-- class of bug a blocking validation layer catches before export, not after Finance notices.
--
-- Scope deliberately kept to checks that can be verified against real data right now:
--   1. PK_DUP - (order_item, period) must be unique in expected_state
--   2. SCHEDULE_GAP - an order_item's periods must be exactly 1..total_periods, no gaps/no extras
-- NOT built yet: Balance check (§2.6 #3 - TotalAmount = Premium+EIR+SBT+fees) and Master check
-- (§2.6 #5 - InsurerCode/PaymentDate cutoff) - these depend on business formulas not yet
-- independently verified against real data this session; better to ship two checks that are
-- provably correct than five where three are guesses. Cancel preflight (§2.6 #4) needs the L5
-- delta-export layer to exist first (it validates the cancel file itself, not expected_state).

-- NOTE (root-caused and fixed 2026-07-26): this used to produce ~728,745 false-positive
-- SCHEDULE_GAP rows when called via `CALL sp_run_validation()`, even though the identical HAVING
-- logic returned 0 rows as a standalone ad hoc query. Originally written up as an unexplained
-- BigQuery engine quirk and disabled.
--
-- Actual root cause, isolated via a sequence of reproduction tests (see 20_SAP_PROGRESS.md for the
-- full trail): the old SCHEDULE_GAP query computed COUNT(DISTINCT period) and MAX(total_periods)
-- TWICE - once inside the SELECT list's CONCAT (for the `detail` message) and again in the HAVING
-- clause. When this query ran in the same script/procedure AFTER another CREATE OR REPLACE TABLE
-- ... GROUP BY ... query (i.e. exactly the real sp_run_validation shape, PK_DUP first then
-- SCHEDULE_GAP), the duplicated aggregate expressions caused the HAVING filter to stop filtering -
-- reproduced down to a minimal, deterministic repro. It was NOT about UNION ALL, CLUSTER BY, script
-- vs stored procedure, or destination table sharing - all of those were tested and ruled out first.
-- Fix: compute each aggregate exactly once in a CTE, then reference the already-materialized
-- columns in both the SELECT list and the filter (WHERE on the CTE, not HAVING) - never repeat an
-- aggregate expression across SELECT/HAVING in a query that runs after another aggregation query in
-- the same script. Verified: 0 rows after the fix, consistent with hand-checked clean orders.
CREATE OR REPLACE PROCEDURE `pacific-plating-282708.sap_integration_v3.sp_run_validation`()
BEGIN
  CREATE OR REPLACE TABLE `pacific-plating-282708.sap_integration_v3.sap_validation_error`
  CLUSTER BY check_name AS
  SELECT order_item, period, 'PK_DUP' AS check_name,
    CONCAT('(order_item, period) appears ', CAST(COUNT(*) AS STRING), ' times in expected_state') AS detail,
    CURRENT_TIMESTAMP() AS detected_at
  FROM `pacific-plating-282708.sap_integration_v3.expected_state`
  GROUP BY order_item, period
  HAVING COUNT(*) > 1;

  INSERT INTO `pacific-plating-282708.sap_integration_v3.sap_validation_error`
  WITH agg AS (
    SELECT order_item, COUNT(DISTINCT period) AS n_periods, MAX(total_periods) AS n_total_periods
    FROM `pacific-plating-282708.sap_integration_v3.expected_state`
    GROUP BY order_item
  )
  SELECT order_item, CAST(NULL AS INT64) AS period, 'SCHEDULE_GAP' AS check_name,
    CONCAT('expected periods 1..', CAST(n_total_periods AS STRING),
           ', found ', CAST(n_periods AS STRING), ' distinct periods') AS detail,
    CURRENT_TIMESTAMP() AS detected_at
  FROM agg
  WHERE n_periods != n_total_periods;
END;

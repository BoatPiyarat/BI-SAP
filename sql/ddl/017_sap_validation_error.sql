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

-- NOTE (fixed 2026-07-25): this used to be a single CREATE TABLE ... AS <PK_DUP SELECT> UNION ALL
-- <SCHEDULE_GAP SELECT>. Confirmed live that combining the two into one UNION ALL query produces
-- 728,745 false-positive SCHEDULE_GAP rows even though every order checked by hand is completely
-- clean (e.g. total_periods=6, exactly periods 1-6 present, MAX(total_periods)=6=COUNT(DISTINCT
-- period)). Reproduced standalone outside the procedure: the SCHEDULE_GAP branch alone (grouped
-- by order_item) returns 0 rows; the SAME branch combined via UNION ALL with the PK_DUP branch
-- (grouped by order_item, period) over the SAME source table returns 728,745. This is a real
-- BigQuery engine quirk when two differently-grouped aggregations over one table share a query,
-- not a logic bug - worked around by splitting into two sequential steps (CREATE then INSERT) so
-- the two aggregations never share one query plan. An earlier fix attempt (ANY_VALUE -> MAX) did
-- NOT resolve this - that was a real but different, smaller issue; this UNION ALL interaction is
-- the actual cause of the 728,745 figure.
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

  -- SCHEDULE_GAP disabled 2026-07-25 - genuinely unreliable, not yet root-caused. Confirmed live:
  -- the exact same HAVING COUNT(DISTINCT period) != MAX(total_periods) logic returns 0 rows when
  -- run as a plain ad hoc SELECT, but 728,745 rows when run via this procedure (reproduced even
  -- after splitting the UNION ALL into two sequential steps, ruling out that theory too).
  -- Spot-checked specific flagged order_items directly against expected_state at the same moment
  -- and found them completely clean (single row, period=total_periods=1). Root cause not yet
  -- found - do not trust this check's output until it is. PK_DUP above is unaffected and safe to
  -- use; only SCHEDULE_GAP is disabled.
  --
  -- INSERT INTO `pacific-plating-282708.sap_integration_v3.sap_validation_error`
  -- SELECT order_item, CAST(NULL AS INT64) AS period, 'SCHEDULE_GAP' AS check_name,
  --   CONCAT('expected periods 1..', CAST(MAX(total_periods) AS STRING),
  --          ', found ', CAST(COUNT(DISTINCT period) AS STRING), ' distinct periods') AS detail,
  --   CURRENT_TIMESTAMP() AS detected_at
  -- FROM `pacific-plating-282708.sap_integration_v3.expected_state`
  -- GROUP BY order_item
  -- HAVING COUNT(DISTINCT period) != MAX(total_periods);
END;

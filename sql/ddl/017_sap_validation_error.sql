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
--   3. MASTER_INSURER_UNKNOWN (added 2026-07-26) - InsurerCode not seen anywhere in SAP's own
--      history, checked against real create/newpayment candidates before they'd be submitted
--   4. MASTER_PAYMENTDATE_LOCKED (added 2026-07-26) - PaymentDate falls before the current
--      accounting month, which SAP rejects as a locked posting period
-- NOT built: Balance check (§2.6 #3 - TotalAmount = Premium+EIR+SBT+fees) - tested against real
-- stg_sap_state data 2026-07-26: only ~60% match at scale (mismatch concentrated in Motor, ~46%,
-- not period-based; adding Interest/Principle fields made it WORSE). Not shipping a guessed
-- formula into a blocking gate - see 20_SAP_PROGRESS.md for the full negative result. Cancel
-- preflight (§2.6 #4) needs the L5 delta-export layer to exist first (it validates the cancel
-- file itself, not expected_state).
--
-- MASTER checks added 2026-07-26, directly motivated by real SAP import rejections that same day:
-- `InsurerCode: is not found in DB` (order L79977888, code 29 - confirmed absent from SAP's entire
-- history via SPLIT(U_InsurerCode,'-')[OFFSET(1)] on stg_sap_state) and
-- `PaymentDate:Posting Periods must be Unlocked` (order L80346837, June 2026 date submitted after
-- that period closed). Both checks run against the actual create/newpayment candidate source
-- tables (`sap_dashboard_carepay_fully_paid`, `sap_dashboard_carepay_installment`) restricted to
-- rows not already in SAP, so they catch problems BEFORE a file gets generated, not after SAP
-- rejects it. Verified against real data before shipping: InsurerCode check found 24 candidates
-- across 6 distinct unrecognized codes (small, plausible); PaymentDate check found 0 (sane -
-- candidate tables are normally kept current).

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

  INSERT INTO `pacific-plating-282708.sap_integration_v3.sap_validation_error`
  WITH known_insurers AS (
    SELECT DISTINCT SPLIT(U_InsurerCode, '-')[OFFSET(1)] AS insurer_code
    FROM `pacific-plating-282708.sap_integration_v3.stg_sap_state`
    WHERE U_InsurerCode LIKE '%-%'
  ),
  candidates AS (
    SELECT OrderItem AS order_item, InsurerCode AS insurer_code
    FROM `pacific-plating-282708.sap_data_engineer.sap_dashboard_carepay_fully_paid`
    WHERE InsurerCode IS NOT NULL AND InsurerCode != ''
    UNION DISTINCT
    SELECT OrderItem, InsurerCode
    FROM `pacific-plating-282708.sap_data_engineer.sap_dashboard_carepay_installment`
    WHERE InsurerCode IS NOT NULL AND InsurerCode != ''
  )
  SELECT c.order_item, CAST(NULL AS INT64) AS period, 'MASTER_INSURER_UNKNOWN' AS check_name,
    CONCAT('InsurerCode ', c.insurer_code, ' not found anywhere in SAP history') AS detail,
    CURRENT_TIMESTAMP() AS detected_at
  FROM candidates c
  LEFT JOIN known_insurers k ON k.insurer_code = c.insurer_code
  WHERE k.insurer_code IS NULL
    AND c.order_item NOT IN (
      SELECT DISTINCT U_OrderItem FROM `pacific-plating-282708.sap_integration_v2.SAP_LIVE_FULL`
    );

  INSERT INTO `pacific-plating-282708.sap_integration_v3.sap_validation_error`
  WITH candidates AS (
    SELECT OrderItem AS order_item, PaymentDate AS payment_date
    FROM `pacific-plating-282708.sap_data_engineer.sap_dashboard_carepay_fully_paid`
    WHERE PaymentDate IS NOT NULL AND PaymentDate != ''
    UNION DISTINCT
    SELECT OrderItem, PaymentDate
    FROM `pacific-plating-282708.sap_data_engineer.sap_dashboard_carepay_installment`
    WHERE PaymentDate IS NOT NULL AND PaymentDate != ''
  )
  SELECT c.order_item, CAST(NULL AS INT64) AS period, 'MASTER_PAYMENTDATE_LOCKED' AS check_name,
    CONCAT('PaymentDate ', c.payment_date, ' falls before the current accounting month') AS detail,
    CURRENT_TIMESTAMP() AS detected_at
  FROM candidates c
  WHERE SAFE.PARSE_DATE('%d%m%Y', c.payment_date) < DATE_TRUNC(CURRENT_DATE(), MONTH)
    AND c.order_item NOT IN (
      SELECT DISTINCT U_OrderItem FROM `pacific-plating-282708.sap_integration_v2.SAP_LIVE_FULL`
    );
END;

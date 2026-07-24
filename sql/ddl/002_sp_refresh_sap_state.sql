-- 002_sp_refresh_sap_state.sql
-- P0: stg_sap_state as the single deduped SAP-state source, one row per
-- (U_OrderItem, U_Period), Cancelled > Paid > Pending priority.
--
-- REVISED 2026-07-24 after checking real BigQuery state (previous version of this
-- file assumed `sap_integration_v2.raw_sap_live`, per the original design docs -
-- that table does NOT exist. Boat confirmed: sap_integration_v2.SAP_LIVE_FULL is
-- the real, current SAP source; build from that instead.
--
-- Why this table is still needed even though SAP_LIVE_FULL already dedups:
-- SAP_LIVE_FULL (see sql/production/SAP_LIVE_FULL.sql) already unions
-- SAP_LIVE/SAP_LIVE_2024/2025/2026 and dedups by DocEntry (ROW_NUMBER by
-- BatchRunDate DESC). But DocEntry-level dedup does NOT collapse multiple SAP
-- documents for the same (U_OrderItem, U_Period) - e.g. a Pending schedule doc
-- and a later Paid/Cancelled doc for the same period both have distinct
-- DocEntry values and both survive. Confirmed live on 2026-07-24:
--   328,071 (U_OrderItem, U_Period) keys have >1 row in SAP_LIVE_FULL today,
--   accounting for 687,700 of 1,649,468 total rows (~42%).
--   Example: L73340138-V1 period 2 has both a Paid row (DocEntry 750141,
--   BatchRunDate 11032024) and a Cancelled row (DocEntry 1005571, BatchRunDate
--   10072024) with the same InvoiceNo - exactly the "multiple docs per period"
--   scenario SAP_CANCEL_IMPORT_SPEC_INFERRED_v0.9.md Q3a describes.
-- TransactionStatus values confirmed live: 'Paid' (1,087,891), 'Pending'
-- (432,840), 'Cancelled' (90,489), 'Cancelled (Change order / Rejected)' (38,248).
-- No NULLs found in U_OrderItem/U_Period.
--
-- Column shape: SELECT r.* (every SAP_LIVE_FULL column preserved verbatim) -
-- see 20_SAP_PROGRESS.md for why this was chosen over DATA_PREP_DESIGN's
-- renamed-subset version.
--
-- "Repoint consumers to stg_sap_state": narrower than the design docs assumed -
-- most production queries (sap_dashboard_carepay_installment, the RCL 04 credit
-- shell) don't read SAP_LIVE_FULL at all. Only sap_dashboard_carepay_fully_paid's
-- `sap_batchrun` CTE and the RCL 04 credit shell's `sap_cancelled` CTE touch it
-- (both narrow, single-purpose lookups) - see NEXT in 20_SAP_PROGRESS.md.
--
-- Idempotent: full rebuild every run. run_scope kept for calling-convention
-- parity with the other sp_refresh_* procs; ignored here (source is small/fast).

CREATE OR REPLACE PROCEDURE `pacific-plating-282708.sap_integration_v3.sp_refresh_sap_state`(run_scope STRING)
BEGIN
  DECLARE run_id STRING DEFAULT GENERATE_UUID();
  DECLARE started TIMESTAMP DEFAULT CURRENT_TIMESTAMP();
  DECLARE row_count INT64;

  CREATE OR REPLACE TABLE `pacific-plating-282708.sap_integration_v3.stg_sap_state`
  CLUSTER BY U_OrderItem AS
  SELECT * EXCEPT(rn) FROM (
    SELECT
      r.*,
      ROW_NUMBER() OVER (
        PARTITION BY U_OrderItem, U_Period
        ORDER BY
          CASE WHEN TransactionStatus IN ('Cancelled', 'Cancelled (Change order / Rejected)') THEN 0
               WHEN TransactionStatus IN ('Paid', 'paid') THEN 1
               ELSE 2 END,
          CASE WHEN IFNULL(U_InvoiceNo, '') != '' THEN 0 ELSE 1 END,
          PARSE_TIMESTAMP('%d%m%Y', BatchRunDate) DESC
      ) AS rn
    FROM `pacific-plating-282708.sap_integration_v2.SAP_LIVE_FULL` r
  )
  WHERE rn = 1;

  SET row_count = (SELECT COUNT(*) FROM `pacific-plating-282708.sap_integration_v3.stg_sap_state`);

  INSERT INTO `pacific-plating-282708.sap_integration_v3.pipeline_run_log`
    (run_id, run_type, step, scope, rows_in, rows_out, started_at, ended_at, status, error_message)
  VALUES (
    run_id,
    IF(STARTS_WITH(run_scope, 'ADHOC:'), 'ADHOC', 'NIGHTLY'),
    'sap_state',
    run_scope,
    NULL,
    row_count,
    started,
    CURRENT_TIMESTAMP(),
    'SUCCESS',
    NULL
  );
END;

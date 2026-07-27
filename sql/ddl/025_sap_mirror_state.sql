-- 025_sap_mirror_state.sql
-- STEP 3 of TASK_CLEAN_SAP_MIRROR.md — sap_mirror_state: one row per
-- (U_OrderItem, U_Period), built on top of sap_mirror_doc (024).
--
-- *** PROVISIONAL — every row this produces is provisional pending Aware's
-- *** answer to Q3a (docs/design/SAP_CANCEL_IMPORT_SPEC_INFERRED_v0.9.md):
-- *** "When a period has MULTIPLE documents in SAP, which document's
-- *** InvoiceNo/status is authoritative?" This is the same open question
-- *** already blocking the cancel-batch-21 fix (20_SAP_PROGRESS.md IN-FLIGHT
-- *** #1). Per Boat 2026-07-26: build the picking rule as ONE isolated point
-- *** now (below), tag every row so downstream consumers know it's provisional,
-- *** and revisit the ORDER BY the moment Aware answers.
--
-- Picking rule reused verbatim from stg_sap_state (sql/ddl/002_sp_refresh_sap_state.sql,
-- already validated live): Cancelled > Paid > Pending, non-empty InvoiceNo
-- wins ties, latest BatchRunDate wins remaining ties. The only structural
-- difference here: source is sap_mirror_doc (full-fidelity, no B2B filter)
-- instead of SAP_LIVE_FULL, and two confirmed placeholder/junk U_OrderItem
-- values are excluded before ranking (see below).
--
-- Junk filter (from FINDINGS_SAP_MIRROR_20260726.md duplicate-document
-- forensics, confirmed live 2026-07-26): U_OrderItem = 'Invoice' (496 rows,
-- all period=1, mixed Paid/Cancelled, BatchRunDate range 02042024-29042024)
-- and U_OrderItem = 'SaleOrder' (45 rows, all period=1, all Paid, NULL
-- BatchRunDate) are SAP object-type labels that leaked into the OrderItem
-- column, not real orders. Excluded here, not in sap_mirror_doc, because
-- sap_mirror_doc's whole purpose is "nothing dropped" — this is the state
-- layer's job. If more such values turn up, add them to the one list below.
--
-- `docs_considered` / `resolution_confidence` columns let any consumer see
-- which rows involved a real pick among multiple documents (ambiguous,
-- PROVISIONAL) vs had only one candidate (UNAMBIGUOUS, not affected by Q3a
-- either way) — confirmed live 2026-07-26: 31% of (OrderItem, Period) keys
-- have 2+ candidate documents.
--
-- Idempotent: full rebuild every run, matches sp_refresh_sap_state.sql
-- convention. run_scope kept for calling-convention parity.

CREATE OR REPLACE PROCEDURE `pacific-plating-282708.sap_integration_v3.sp_refresh_sap_mirror_state`(run_scope STRING)
BEGIN
  DECLARE run_id STRING DEFAULT GENERATE_UUID();
  DECLARE started TIMESTAMP DEFAULT CURRENT_TIMESTAMP();
  DECLARE row_count INT64;
  DECLARE provisional_count INT64;

  CREATE OR REPLACE TABLE `pacific-plating-282708.sap_integration_v3.sap_mirror_state`
  CLUSTER BY U_OrderItem AS
  WITH candidates AS (
    -- Known non-business placeholder values only — add here if more turn up.
    SELECT *
    FROM `pacific-plating-282708.sap_integration_v3.sap_mirror_doc`
    WHERE U_OrderItem NOT IN ('Invoice', 'SaleOrder')
  ),
  ranked AS (
    SELECT
      c.*,
      COUNT(*) OVER (PARTITION BY U_OrderItem, U_Period) AS docs_considered,
      -- ============================================================
      -- *** THE PICKING RULE — the one place this logic lives. ***
      -- PROVISIONAL pending Aware Q3a — change only this ORDER BY when
      -- Aware answers which document is authoritative for a multi-doc period.
      -- ============================================================
      ROW_NUMBER() OVER (
        PARTITION BY U_OrderItem, U_Period
        ORDER BY
          CASE WHEN TransactionStatus IN ('Cancelled', 'Cancelled (Change order / Rejected)') THEN 0
               WHEN TransactionStatus IN ('Paid', 'paid') THEN 1
               ELSE 2 END,
          CASE WHEN IFNULL(U_InvoiceNo, '') != '' THEN 0 ELSE 1 END,
          SAFE.PARSE_TIMESTAMP('%d%m%Y', BatchRunDate) DESC,
          DocEntry DESC  -- final deterministic tiebreak, added 2026-07-27: same-day
                         -- same-status multi-invoice periods (e.g. two real "additional
                         -- payment" charges both Paid same BatchRunDate) were resolving
                         -- non-deterministically without this — see 30_SAP_CHANGELOG.md
                         -- 2026-07-27. Highest DocEntry = most recently created document.
      ) AS rn
      -- ============================================================
    FROM candidates c
  )
  SELECT
    * EXCEPT(rn),
    IF(docs_considered > 1, 'PROVISIONAL_PENDING_AWARE_Q3A', 'UNAMBIGUOUS') AS resolution_confidence
  FROM ranked
  WHERE rn = 1;

  SET row_count = (SELECT COUNT(*) FROM `pacific-plating-282708.sap_integration_v3.sap_mirror_state`);
  SET provisional_count = (
    SELECT COUNT(*) FROM `pacific-plating-282708.sap_integration_v3.sap_mirror_state`
    WHERE resolution_confidence = 'PROVISIONAL_PENDING_AWARE_Q3A'
  );

  INSERT INTO `pacific-plating-282708.sap_integration_v3.pipeline_run_log`
    (run_id, run_type, step, scope, rows_in, rows_out, started_at, ended_at, status, error_message)
  VALUES (
    run_id,
    IF(STARTS_WITH(run_scope, 'ADHOC:'), 'ADHOC', 'NIGHTLY'),
    'sap_mirror_state',
    run_scope,
    NULL,
    row_count,
    started,
    CURRENT_TIMESTAMP(),
    'SUCCESS',
    CONCAT(CAST(provisional_count AS STRING), ' of ', CAST(row_count AS STRING),
           ' rows PROVISIONAL_PENDING_AWARE_Q3A (2+ candidate documents)')
  );
END;

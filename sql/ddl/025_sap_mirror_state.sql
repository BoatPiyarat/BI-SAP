-- 025_sap_mirror_state.sql
-- STEP 3 of TASK_CLEAN_SAP_MIRROR.md — sap_mirror_state: one row per
-- (U_OrderItem, U_Period), built on top of sap_mirror_doc (024).
--
-- RULE-03 confirmed by Boat/Aware 2026-07-31: preserve status and non-empty
-- InvoiceNo priority, then resolve remaining multi-document ties by native
-- UpdateDate/UpdateTime recency. BatchRunDate is not a valid recency signal
-- because RULE-02 makes it constant within the open period.
--
-- Picking rule reused verbatim from stg_sap_state (sql/ddl/002_sp_refresh_sap_state.sql,
-- already validated live): Cancelled > Paid > Pending, non-empty InvoiceNo
-- wins ties, latest UpdateDate/UpdateTime wins remaining ties. The only structural
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
-- which rows were resolved among multiple documents by confirmed recency versus rows with one
-- candidate (`UNAMBIGUOUS`). Confirmed live 2026-07-26: 31% of (OrderItem, Period) keys had 2+
-- candidate documents.
--
-- Idempotent: full rebuild every run, matches sp_refresh_sap_state.sql
-- convention. run_scope kept for calling-convention parity.

CREATE OR REPLACE PROCEDURE `pacific-plating-282708.sap_integration_v3.sp_refresh_sap_mirror_state`(run_scope STRING)
BEGIN
  DECLARE run_id STRING DEFAULT GENERATE_UUID();
  DECLARE started TIMESTAMP DEFAULT CURRENT_TIMESTAMP();
  DECLARE row_count INT64;
  DECLARE multi_doc_count INT64;

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
      -- RULE-03: retain priority layers 1-2; recency is layer 3.
      -- ============================================================
      ROW_NUMBER() OVER (
        PARTITION BY U_OrderItem, U_Period
        ORDER BY
          CASE WHEN TransactionStatus IN ('Cancelled', 'Cancelled (Change order / Rejected)') THEN 0
               WHEN TransactionStatus IN ('Paid', 'paid') THEN 1
               ELSE 2 END,
          CASE WHEN IFNULL(U_InvoiceNo, '') != '' THEN 0 ELSE 1 END,
          UpdateDate DESC,
          UpdateTime DESC,
          DocEntry DESC
      ) AS rn
      -- ============================================================
    FROM candidates c
  )
  SELECT
    * EXCEPT(rn),
    IF(docs_considered > 1, 'MULTI_DOC_RESOLVED_BY_RECENCY', 'UNAMBIGUOUS') AS resolution_confidence
  FROM ranked
  WHERE rn = 1;

  SET row_count = (SELECT COUNT(*) FROM `pacific-plating-282708.sap_integration_v3.sap_mirror_state`);
  SET multi_doc_count = (
    SELECT COUNT(*) FROM `pacific-plating-282708.sap_integration_v3.sap_mirror_state`
    WHERE resolution_confidence = 'MULTI_DOC_RESOLVED_BY_RECENCY'
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
    CONCAT(CAST(multi_doc_count AS STRING), ' of ', CAST(row_count AS STRING),
           ' rows MULTI_DOC_RESOLVED_BY_RECENCY (2+ candidate documents)')
  );
END;

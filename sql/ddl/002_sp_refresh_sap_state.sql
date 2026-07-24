-- 002_sp_refresh_sap_state.sql
-- P0 (AGENTS.md / 20_SAP_PROGRESS.md): stg_sap_state from raw_sap_live ONLY.
-- Design ref: SAP_INTERFACE_REDESIGN_V3.md §2.1 (S1), SAP_DATA_PREP_DESIGN_v3.md §5 (S4)
--
-- ~~ DESIGN CONFLICT FLAGGED, RESOLVED BELOW — please confirm ~~
-- REDESIGN_V3 §2.1 defines stg_sap_state as `SELECT r.* ...` (all raw_sap_live columns,
-- native SAP names preserved: U_OrderItem, U_Period, TransactionStatus, U_InvoiceNo, ...).
-- SAP_DATA_PREP_DESIGN_v3.md §5 instead enumerates a renamed subset (order_id, order_item,
-- period, sap_status, sap_invoice_no, ...) with "...(ทุก column ที่ cancel ต้อง mirror)..."
-- left as a placeholder — i.e. it's incomplete without the 56-column Data Dictionary.
--
-- This file follows REDESIGN_V3 (SELECT r.*): every raw_sap_live column is preserved
-- verbatim, nothing renamed, nothing can be silently dropped. That's the safer choice
-- given the hard rule "InvoiceNo is immutable... mirror stored values exactly" — a
-- hand-picked column list risks omitting one of the "must mirror on cancel" fields
-- before the Data Dictionary has been checked against this table's real schema (not
-- verified this session — see PROGRESS note). If downstream procs (sp_validate,
-- sp_export_delta, cancel-gen) are later written expecting the DATA_PREP_DESIGN aliases
-- (order_item, period, sap_status, sap_invoice_no), add a thin second view with those
-- aliases on top of this table rather than reshaping this one.
--
-- Idempotent: full rebuild every run (source table is small/fast per Stage Map "[full, เร็ว]").
-- run_scope param kept only for calling-convention parity with the other sp_refresh_*
-- procs (order_dim/payment_events/schedule), which ARE incremental; this one ignores it.

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
        PARTITION BY U_OrderItem, SAFE_CAST(U_Period AS INT64)
        ORDER BY
          CASE WHEN TransactionStatus IN ('Cancelled', 'Cancelled (Change order / Rejected)') THEN 0
               WHEN TransactionStatus IN ('Paid', 'paid') THEN 1
               ELSE 2 END,
          CASE WHEN IFNULL(U_InvoiceNo, '') != '' THEN 0 ELSE 1 END
      ) AS rn
    FROM `pacific-plating-282708.sap_integration_v2.raw_sap_live` r
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

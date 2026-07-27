-- 026_collapse_stg_sap_state_to_view.sql
-- Per Boat 2026-07-27 (TASK_V3_GAP_CLOSURE_v2 PHASE A / A4): "ยุบ 2 นิยามให้เหลือหนึ่ง — เปลี่ยน
-- stg_sap_state เป็น view ทับ sap_mirror_state (picking rule ที่เดียว, consumer ไม่ต้องแก้)" —
-- there were two independently-computed "1 row per (OrderItem, Period)" picking rules
-- (002_sp_refresh_sap_state.sql building stg_sap_state directly from SAP_LIVE_FULL, and
-- 025_sap_mirror_state.sql building sap_mirror_state from sap_mirror_doc). Same logic, kept in
-- two places — exactly the kind of duplication that drifts apart over time. Collapsed to one:
-- sap_mirror_state's picking rule is now the only one that runs; stg_sap_state becomes a plain
-- view over it, preserving its original 57-column contract so no consumer needs to change.
--
-- *** Two real bugs were found and fixed (024/025/002) while verifying this collapse is safe —
-- see 30_SAP_CHANGELOG.md 2026-07-27 for full detail: ***
-- 1. sap_mirror_doc's per-DocEntry dedup ordered by the DDMMYYYY STRING BatchRunDate instead of
--    parsing it to a date first, sorting lexicographically instead of chronologically (e.g.
--    "31032026" > "16062026" as a string) — silently kept stale rows for 44,781 (OrderItem,Period)
--    keys. Fixed in 024 (SAF.PARSE_DATE before ORDER BY).
-- 2. Both picking rules lacked a final deterministic tiebreak for same-day, same-status,
--    multi-invoice periods (e.g. two real "additional payment" charges both Paid the same
--    BatchRunDate) — 1,859 keys picked arbitrarily differently between the two implementations.
--    Fixed in 002 and 025 (added `DocEntry DESC` as the last ORDER BY key).
-- After both fixes, stg_sap_state (old table logic) and sap_mirror_state (junk-excluded) matched
-- on every single (OrderItem, Period) key except the 2 known 'Invoice'/'SaleOrder' placeholder
-- keys sap_mirror_state deliberately excludes — confirmed live 2026-07-27, re-verified below.
--
-- Verification done before this migration ran (per Boat's ask - row count + 5 spot-check orders):
--   expected_state / delta_export baseline captured against the still-table stg_sap_state:
--   1,462,333 rows each (1:1), sap_validation_error 24 rows. 5 sampled real order_items
--   (L79510892-V1, L78199908-V1, L78322469-V1, L77764180-V1, L78250933-V1) captured in full from
--   delta_export before this change. Re-run and re-compared AFTER the view swap (see
--   30_SAP_CHANGELOG.md 2026-07-27) — 0 unexplained diffs.
--
-- Column contract preserved: sap_mirror_state has 2 extra columns (docs_considered,
-- resolution_confidence) beyond the original stg_sap_state 57. The view excludes both so any
-- existing `SELECT *` consumer sees an identical schema to before. Anything that wants the
-- provisional-pick flag should read sap_mirror_state directly, not stg_sap_state.
--
-- sp_refresh_sap_state (002) is NOT deleted (history/reference), but is no longer called by the
-- nightly chain below — calling it now would fail anyway (CREATE OR REPLACE TABLE against a name
-- that is now a VIEW errors in BigQuery). The nightly chain now refreshes sap_mirror_doc +
-- sap_mirror_state instead, in the same slot sp_refresh_sap_state used to occupy.

-- Step 1: one-time schema migration — replace the stg_sap_state TABLE with a VIEW.
DROP TABLE IF EXISTS `pacific-plating-282708.sap_integration_v3.stg_sap_state`;

CREATE VIEW `pacific-plating-282708.sap_integration_v3.stg_sap_state` AS
SELECT * EXCEPT(docs_considered, resolution_confidence)
FROM `pacific-plating-282708.sap_integration_v3.sap_mirror_state`;

-- Step 2: repoint the nightly chain (was 020_extend_nightly_refresh_with_p2_p3.sql) to refresh
-- sap_mirror_doc + sap_mirror_state instead of the now-retired sp_refresh_sap_state.
CREATE OR REPLACE PROCEDURE `pacific-plating-282708.sap_integration_v3.sp_nightly_state_and_recon_refresh`()
BEGIN
  CALL `pacific-plating-282708.sap_integration_v3.sp_refresh_stg_order_dim`();
  CALL `pacific-plating-282708.sap_integration_v3.sp_refresh_stg_payment_events`();
  CALL `pacific-plating-282708.sap_integration_v3.sp_refresh_stg_schedule`();
  CALL `pacific-plating-282708.sap_integration_v3.sp_refresh_sap_mirror_doc`('NIGHTLY:scheduled');
  CALL `pacific-plating-282708.sap_integration_v3.sp_refresh_sap_mirror_state`('NIGHTLY:scheduled');
  CALL `pacific-plating-282708.sap_integration_v3.sp_recon_all_charges`();
  CALL `pacific-plating-282708.sap_integration_v3.sp_refresh_expected_state`();
  CALL `pacific-plating-282708.sap_integration_v3.sp_run_validation`();
  CALL `pacific-plating-282708.sap_integration_v3.sp_refresh_delta_export`();
END;

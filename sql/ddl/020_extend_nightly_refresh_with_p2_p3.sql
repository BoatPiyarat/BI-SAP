-- 020_extend_nightly_refresh_with_p2_p3.sql
-- Wires the P2 engine (expected_state, sap_validation_error) and P3 delta_export into the
-- existing nightly chain (sp_nightly_state_and_recon_refresh, 21:00 ICT, already scheduled - see
-- 008/014). Boat, 2026-07-26: "continue on the building daily process, delta export daily, put
-- everything in the bucket" - this is the first half (the refresh chain); the bucket/export part
-- is a separate, deliberately-not-yet-built step (see 20_SAP_PROGRESS.md - delta_export still only
-- writes a diagnostic table, not an interface file).
--
-- Order matters: expected_state depends on stg_schedule + stg_payment_events (P1, already
-- refreshed earlier in this same chain); delta_export depends on expected_state AND stg_sap_state
-- (also already refreshed earlier in this chain, by sp_refresh_sap_state). sp_run_validation reads
-- expected_state only, so it can run right after sp_refresh_expected_state, before delta_export -
-- validation errors should be visible even if delta_export computation were to fail downstream.

CREATE OR REPLACE PROCEDURE `pacific-plating-282708.sap_integration_v3.sp_nightly_state_and_recon_refresh`()
BEGIN
  CALL `pacific-plating-282708.sap_integration_v3.sp_refresh_stg_order_dim`();
  CALL `pacific-plating-282708.sap_integration_v3.sp_refresh_stg_payment_events`();
  CALL `pacific-plating-282708.sap_integration_v3.sp_refresh_stg_schedule`();
  CALL `pacific-plating-282708.sap_integration_v3.sp_refresh_sap_state`('NIGHTLY:scheduled');
  CALL `pacific-plating-282708.sap_integration_v3.sp_recon_all_charges`();
  CALL `pacific-plating-282708.sap_integration_v3.sp_refresh_expected_state`();
  CALL `pacific-plating-282708.sap_integration_v3.sp_run_validation`();
  CALL `pacific-plating-282708.sap_integration_v3.sp_refresh_delta_export`();
END;

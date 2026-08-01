-- 047_repoint_nightly_mirror_to_incremental.sql
-- Chain 3 cutover: replace the nightly full sap_mirror_doc rebuild (024) with the
-- reviewed incremental MERGE procedure (043). All downstream calls and their order
-- remain unchanged.
--
-- Preconditions (hard gates):
--   1. RQ-20260801-1637-043-deterministic-gate-evidence = PASS.
--   2. RQ-20260801-1640-chain2-rule03-evidence = PASS.
--   3. Boat explicitly authorizes the production repoint.
--
-- Rollback: run the rollback definition at the end of this file. It restores only
-- the 024 call and leaves the scheduler, tables, watermark, and downstream steps intact.

CREATE OR REPLACE PROCEDURE `pacific-plating-282708.sap_integration_v3.sp_nightly_state_and_recon_refresh`()
BEGIN
  CALL `pacific-plating-282708.sap_integration_v3.sp_refresh_stg_order_dim`();
  CALL `pacific-plating-282708.sap_integration_v3.sp_refresh_stg_payment_events`();
  CALL `pacific-plating-282708.sap_integration_v3.sp_refresh_stg_schedule`();
  CALL `pacific-plating-282708.sap_integration_v3.sp_refresh_sap_mirror_doc_incremental`('NIGHTLY:scheduled');
  CALL `pacific-plating-282708.sap_integration_v3.sp_refresh_sap_mirror_state`('NIGHTLY:scheduled');
  CALL `pacific-plating-282708.sap_integration_v3.sp_recon_all_charges`();
  CALL `pacific-plating-282708.sap_integration_v3.sp_refresh_expected_state`();
  CALL `pacific-plating-282708.sap_integration_v3.sp_run_validation`();
  CALL `pacific-plating-282708.sap_integration_v3.sp_refresh_delta_export`();
  CALL `pacific-plating-282708.sap_integration_v3.sp_refresh_interface_daily_status`();
END;

-- ============================================================================
-- ROLLBACK — execute this block only if the incremental nightly call fails.
-- ============================================================================
/*
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
  CALL `pacific-plating-282708.sap_integration_v3.sp_refresh_interface_daily_status`();
END;
*/

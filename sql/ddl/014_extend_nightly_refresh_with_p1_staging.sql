-- 014_extend_nightly_refresh_with_p1_staging.sql
-- P1 build (Boat, 2026-07-25: "start building" V3 P1-P3).
-- Extends the existing sp_nightly_state_and_recon_refresh (008, already scheduled daily 21:00 ICT
-- with failure email - see 004/008) to also refresh the three new P1 staging tables. Matches
-- decision #5 from SAP_INTERFACE_REDESIGN_V3.md §5: "Ownership + schedule ของ chain ใหม่ (เสนอ:
-- ต่อท้าย extract 20:30 ทั้งเส้น)" - append the whole new chain, don't stand up a second schedule.
--
-- No new bq mk --transfer_config needed - the existing scheduled query calls this procedure by
-- name, so extending the procedure body is enough; the schedule itself (every day 21:00 ICT)
-- already exists (008).
--
-- Order: the three P1 staging refreshes first (mutually independent - each reads straight from
-- careos.* source tables, none currently depend on each other or on stg_sap_state), then the
-- existing SAP-state + recon refresh unchanged.

CREATE OR REPLACE PROCEDURE `pacific-plating-282708.sap_integration_v3.sp_nightly_state_and_recon_refresh`()
BEGIN
  CALL `pacific-plating-282708.sap_integration_v3.sp_refresh_stg_order_dim`();
  CALL `pacific-plating-282708.sap_integration_v3.sp_refresh_stg_payment_events`();
  CALL `pacific-plating-282708.sap_integration_v3.sp_refresh_stg_schedule`();
  CALL `pacific-plating-282708.sap_integration_v3.sp_refresh_sap_state`('NIGHTLY:scheduled');
  CALL `pacific-plating-282708.sap_integration_v3.sp_recon_all_charges`();
END;

-- 008_schedule_state_recon_refresh.sql
-- Boat's goal #2: "make the job cover all transaction (recon) - auto." Found live 2026-07-25:
-- stg_sap_state (built 002, one-time manual run 2026-07-24) was NEVER on a schedule - no
-- transfer config anywhere calls sp_refresh_sap_state or sp_recon_all_charges. That staleness
-- was directly responsible for part of the MISSING_FROM_SAP inflation (584 periods that were
-- already Paid+invoiced in real SAP_LIVE_FULL still showed Pending/no-invoice in the month-old
-- stg_sap_state snapshot). Wiring this into a daily schedule closes that gap permanently and
-- keeps the dashboard views (006) showing current reality instead of a frozen day-one snapshot.

CREATE OR REPLACE PROCEDURE `pacific-plating-282708.sap_integration_v3.sp_nightly_state_and_recon_refresh`()
BEGIN
  CALL `pacific-plating-282708.sap_integration_v3.sp_refresh_sap_state`('NIGHTLY:scheduled');
  CALL `pacific-plating-282708.sap_integration_v3.sp_recon_all_charges`();
END;

-- ============================================================================
-- Scheduling (same BQDTS pattern as 004_dead_mans_switch.sql - no --target_dataset,
-- since a plain CALL script has no destination table):
--
-- bq mk --transfer_config --project_id=pacific-plating-282708 \
--   --data_source=scheduled_query --display_name="sap_state_and_recon_refresh" \
--   --schedule="every day 21:00" --location=asia-southeast1 \
--   --params='{"query":"CALL `pacific-plating-282708.sap_integration_v3.sp_nightly_state_and_recon_refresh`();"}'
--
-- 21:00 ICT (14:00 UTC) - after the daytime extract/CF chain has had all day to run, and
-- before the 22:00 ICT dead-man's-switch check, so the freshness + completeness pictures
-- move together. Both procedures are fast BigQuery-only jobs (SAP_LIVE_FULL -> stg_sap_state
-- dedup, then careos vs stg_sap_state recon) - seconds, not minutes.
-- ============================================================================

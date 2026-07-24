-- 004_dead_mans_switch.sql
-- P0 follow-up (2026-07-24): the scheduler incident (3 nights of silent failure) would have
-- been caught on night one by this check. SAP_DASHBOARD_DESIGN_v1.md Page 1/4 proposed this
-- against `interface_daily_status` / `pipeline_run_log` (not built yet, P4). This version uses
-- the real signal available today instead of waiting: `SAP_LIVE.U_BatchRunDate`, since we traced
-- this session that SAP_LIVE is the genuine, direct-from-SAP-DB freshness signal (see
-- 20_SAP_PROGRESS.md "REAL ARCHITECTURE DISCOVERED").
--
-- Threshold: 26 hours. The real pipeline should load at least once daily; 26h gives a couple
-- hours of slack past a full day before calling it stale (matches the "<26 min" / ">30 min"
-- language in SAP_DASHBOARD_DESIGN_v1.md Page 4, which reads like a units typo for hours given
-- this is a once-daily batch, not a streaming pipeline).

CREATE OR REPLACE VIEW `pacific-plating-282708.sap_integration_v3.vw_dead_mans_switch` AS
-- WHERE U_BatchRunDate <= CURRENT_TIMESTAMP() excludes ~5 known anomalous rows dated
-- 2026-08-15 (future) found 2026-07-24 (unusual OrderID prefixes RR/RF/RC, not the usual
-- Lxxxxxxx) - without this, MAX() picks up the bogus future date and the switch never
-- trips even if the real pipeline stops loading. See 20_SAP_PROGRESS.md for that finding.
SELECT
  MAX(U_BatchRunDate) AS last_load_ts,
  TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), MAX(U_BatchRunDate), HOUR) AS hours_since_last_load,
  IF(TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), MAX(U_BatchRunDate), HOUR) > 26, 'STALE', 'FRESH') AS status
FROM `pacific-plating-282708.sap_integration_v2.SAP_LIVE`
WHERE U_BatchRunDate <= CURRENT_TIMESTAMP();

-- Scheduled check: fails loudly (RAISE) when stale, so BigQuery's own scheduled-query
-- failure-email notification (enabled at schedule-creation time, no new infra/credentials
-- needed) fires. This script is what the scheduled query in 005 actually runs.
CREATE OR REPLACE PROCEDURE `pacific-plating-282708.sap_integration_v3.sp_check_dead_mans_switch`()
BEGIN
  DECLARE hours_stale INT64;
  DECLARE last_ts TIMESTAMP;

  SET (hours_stale, last_ts) = (
    SELECT AS STRUCT hours_since_last_load, last_load_ts
    FROM `pacific-plating-282708.sap_integration_v3.vw_dead_mans_switch`
  );

  IF hours_stale > 26 THEN
    RAISE USING MESSAGE = FORMAT(
      'SAP dead-man\'s-switch: SAP_LIVE has not received a fresh load in %d hours (last load: %t). sap-extract-schedule may be down again - check gcloud scheduler jobs describe sap-extract-schedule.',
      hours_stale, last_ts
    );
  END IF;
END;

-- ============================================================================
-- Scheduling this check (done manually this session, recorded here for anyone
-- who needs to recreate/modify it - bq CLI does not expose email_preferences
-- as a mk/update flag, so the last step needs a direct API PATCH):
--
-- bq mk --transfer_config --project_id=pacific-plating-282708 \
--   --data_source=scheduled_query --display_name="sap_dead_mans_switch" \
--   --schedule="every day 15:00" --location=asia-southeast1 \
--   --params='{"query":"CALL `pacific-plating-282708.sap_integration_v3.sp_check_dead_mans_switch`();"}'
-- (deliberately no --target_dataset - a plain CALL has no destination table;
-- BQDTS rejects the config with "Dataset specified in the query ('') is not
-- consistent with Destination dataset" if one is set)
--
-- TOKEN=$(gcloud auth print-access-token)
-- curl -X PATCH "https://bigquerydatatransfer.googleapis.com/v1/<transfer_config_name>?updateMask=emailPreferences" \
--   -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
--   -d '{"emailPreferences": {"enableFailureEmail": true}}'
--
-- Live as of 2026-07-24: transfer config
-- projects/919786098205/locations/asia-southeast1/transferConfigs/6a647519-0000-218f-a688-582429d00cdc
-- Runs daily 15:00 UTC (22:00 ICT). Tested manually (bq mk --transfer_run)
-- end-to-end: SUCCEEDED while fresh; FAILED with the RAISE message when
-- forced to fail (see below).
--
-- Recipients (2026-07-24): Boat asked for piyaratt@rabbit.co.th and
-- rc_bi@rabbit.co.th specifically. BQDTS's native emailPreferences only
-- supports ONE recipient (the config owner - currently data@rabbit.co.th,
-- since that's the account that created it), no multi-recipient field exists
-- in the API. Left that native email on as a redundant third notification,
-- and added a proper multi-recipient path via Cloud Monitoring instead:
--
--   1. Log-based metric `sap_dead_mans_switch_failure` - counts ERROR-severity
--      log entries scoped to this transfer config:
--        gcloud logging metrics create sap_dead_mans_switch_failure \
--          --log-filter='resource.type="bigquery_dts_config" AND
--            resource.labels.config_id="6a647519-0000-218f-a688-582429d00cdc"
--            AND severity="ERROR"'
--   2. Two email notification channels (gcloud beta monitoring channels create)
--      for piyaratt@rabbit.co.th and rc_bi@rabbit.co.th
--   3. Alert policy "SAP dead-man's-switch failure" (projects/pacific-plating-282708/
--      alertPolicies/2008919338975126785) - fires when the metric > 0,
--      notifies both channels
--
-- Verified end-to-end 2026-07-24: temporarily replaced the procedure body with
-- an unconditional RAISE, triggered the scheduled query, confirmed via direct
-- Cloud Monitoring API query that the metric ingested the failure (value=1 in
-- the exact 1-minute window the error occurred), then immediately reverted the
-- procedure to its real logic and reconfirmed it passes cleanly. Could not
-- personally confirm the email landed in either inbox - ask Boat to confirm.
-- ============================================================================

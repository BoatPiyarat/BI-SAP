-- 027_missed_extract_alert_message.sql
-- Boat, 2026-07-27 ("away 26-30 July" plan, item 1.2 MISSED-EXTRACT ALERT): a short, directly
-- actionable message for the extract-staleness alert, since Boat will be reading and acting on
-- this from a phone every morning while away.
--
-- The detection logic already exists and has been live since 2026-07-24
-- (004_dead_mans_switch.sql: sp_check_dead_mans_switch, RAISEs if SAP_LIVE hasn't loaded in >26h,
-- scheduled via BQDTS `sap_dead_mans_switch` at 15:00 UTC / 22:00 ICT with enableFailureEmail=true)
-- - this file does NOT change the detection, only the RAISE message, so no duplicate alert is
-- created for the same condition. Delivery channel: BQDTS's own failure-email mechanism (Boat
-- chose email over Slack for this 4-day window - no Slack webhook exists in this project).
--
-- NOTE on delivery recipient (flagged, not fixed): BQDTS failure emails go to the transfer
-- config's owner identity, historically data@rabbit.co.th per 20_SAP_PROGRESS.md 2026-07-24 -
-- UNVERIFIED whether that reaches piyaratt@rabbit.co.th directly or needs forwarding. Logged in
-- docs/INPUTS_NEEDED.md.

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
      'extract ไม่ได้รันคืนที่ %t (%d ชม.แล้ว) — กด EXECUTE ที่ https://console.cloud.google.com/run/jobs/details/asia-southeast1/sap-extract-job/executions?project=pacific-plating-282708',
      last_ts, hours_stale
    );
  END IF;
END;

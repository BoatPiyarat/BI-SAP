DECLARE run_id STRING DEFAULT 'V3NIGHTLY-2026-08-02T09:02:26-b36e1712';
SELECT 'UNIT3' section, TO_JSON_STRING(t) detail FROM (
  SELECT ready_events,held_events,releasable_events
  FROM `pacific-plating-282708.sap_integration_v3.v3_unit3_run_summary`
  WHERE pipeline_run_id=run_id) t
UNION ALL SELECT 'NOTIFICATION',TO_JSON_STRING(t) FROM (
  SELECT unknown_rows,mapping_hold_rows,notification_rows
  FROM `pacific-plating-282708.sap_integration_v3.v3_notification_run_summary`
  WHERE pipeline_run_id=run_id) t
UNION ALL SELECT 'GATE',TO_JSON_STRING(t) FROM (
  SELECT gate_code,blocker_count
  FROM `pacific-plating-282708.sap_integration_v3.v3_automation_gate_result`
  WHERE pipeline_run_id=run_id) t
UNION ALL SELECT 'HOLD',TO_JSON_STRING(t) FROM (
  SELECT hold_code,COUNT(*) records
  FROM `pacific-plating-282708.sap_integration_v3.v3_unit3_mapping_hold`
  WHERE pipeline_run_id=run_id GROUP BY hold_code) t;

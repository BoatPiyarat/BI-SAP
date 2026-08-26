-- Read-only reconciliation for the hold-only Scenario 1 EDC classifier.
SELECT
  summary.pipeline_run_id,
  summary.event_count,
  summary.classified_count,
  summary.acknowledged_count,
  summary.kbank_structurally_ready_count,
  summary.unapproved_bank_or_method_count,
  summary.interface_row_count,
  summary.gate_status,
  ARRAY_AGG(STRUCT(holds.hold_code, holds.row_count) ORDER BY holds.hold_code) AS hold_distribution
FROM `pacific-plating-282708.sap_integration_v3.v3_edc_onetime_event_summary` AS summary
LEFT JOIN (
  SELECT pipeline_run_id, hold_code, COUNT(*) AS row_count
  FROM `pacific-plating-282708.sap_integration_v3.v3_edc_onetime_event_hold`
  WHERE pipeline_run_id = 'V3NIGHTLY-2026-08-26T13:23:38-e830fff2'
  GROUP BY pipeline_run_id, hold_code
) AS holds USING (pipeline_run_id)
WHERE summary.pipeline_run_id = 'V3NIGHTLY-2026-08-26T13:23:38-e830fff2'
GROUP BY ALL;

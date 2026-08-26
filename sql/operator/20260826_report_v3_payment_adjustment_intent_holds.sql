-- Read-only reconciliation for the additional-payment/correction intent classifier.
SELECT
  summary.pipeline_run_id,
  summary.candidate_payload_count,
  summary.classified_payload_count,
  summary.additional_payment_marker_count,
  summary.correction_marker_count,
  summary.interface_row_count,
  summary.gate_status,
  ARRAY_AGG(IF(holds.hold_code IS NULL, NULL,
    STRUCT(holds.hold_code, holds.payload_count)) IGNORE NULLS ORDER BY holds.hold_code)
    AS hold_distribution
FROM `pacific-plating-282708.sap_integration_v3.v3_payment_adjustment_intent_summary` AS summary
LEFT JOIN (
  SELECT pipeline_run_id, hold_code, COUNT(*) AS payload_count
  FROM `pacific-plating-282708.sap_integration_v3.v3_payment_adjustment_intent_hold`
  WHERE pipeline_run_id = 'V3NIGHTLY-2026-08-26T13:23:38-e830fff2'
  GROUP BY pipeline_run_id, hold_code
) AS holds USING (pipeline_run_id)
WHERE summary.pipeline_run_id = 'V3NIGHTLY-2026-08-26T13:23:38-e830fff2'
GROUP BY ALL;

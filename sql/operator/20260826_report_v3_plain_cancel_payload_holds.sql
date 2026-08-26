-- Read-only reconciliation for the hold-only plain-cancellation preparation.
SELECT
  summary.ownership_run_id,
  summary.input_item_count,
  summary.classified_item_count,
  summary.payload_row_count,
  summary.structurally_ready_held_item_count,
  summary.interface_row_count,
  summary.gate_status,
  ARRAY_AGG(STRUCT(holds.hold_code, holds.item_count, holds.payload_rows)
    ORDER BY holds.hold_code) AS hold_distribution
FROM `pacific-plating-282708.sap_integration_v3.v3_plain_cancel_payload_summary` AS summary
LEFT JOIN (
  SELECT ownership_run_id, hold_code, COUNT(*) AS item_count,
    SUM(payload_row_count) AS payload_rows
  FROM `pacific-plating-282708.sap_integration_v3.v3_plain_cancel_payload_hold`
  WHERE ownership_run_id = 'V3NIGHTLY-2026-08-26T13:23:38-e830fff2-CANCEL-HOLD'
  GROUP BY ownership_run_id, hold_code
) AS holds USING (ownership_run_id)
WHERE summary.ownership_run_id = 'V3NIGHTLY-2026-08-26T13:23:38-e830fff2-CANCEL-HOLD'
GROUP BY ALL;

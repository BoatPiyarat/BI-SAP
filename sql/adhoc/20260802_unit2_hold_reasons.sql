-- Read-only Unit 2 hold/unknown breakdown. Dry-run before execution.
SELECT 'PAYMENT_EVENT' population_grain, outcome, outcome_reason,
  COUNT(*) records, COUNT(DISTINCT order_id) distinct_orders, SUM(charge_amount) amount
FROM `pacific-plating-282708.sap_integration_v3.v3_unit2_event_shadow`
WHERE pipeline_run_id='V3NIGHTLY-2026-08-02T09:02:26-b36e1712'
  AND outcome IN ('HELD_VALIDATION','HELD_CLASSIFICATION_UNKNOWN')
GROUP BY outcome,outcome_reason
UNION ALL
SELECT 'SCHEDULE',outcome,outcome_reason,COUNT(*),COUNT(DISTINCT order_id),CAST(NULL AS INT64)
FROM `pacific-plating-282708.sap_integration_v3.v3_unit2_schedule_shadow`
WHERE pipeline_run_id='V3NIGHTLY-2026-08-02T09:02:26-b36e1712'
  AND outcome IN ('HELD_VALIDATION','HELD_CLASSIFICATION_UNKNOWN')
GROUP BY outcome,outcome_reason
ORDER BY population_grain,outcome,records DESC;

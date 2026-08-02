-- Read-only result for the approved Unit 2 shadow run. Dry-run before execution.
SELECT population_grain, outcome, records, distinct_orders, amount, computed_at
FROM `pacific-plating-282708.sap_integration_v3.v3_unit2_summary`
WHERE pipeline_run_id='V3NIGHTLY-2026-08-02T09:02:26-b36e1712'
ORDER BY population_grain, outcome;

DECLARE v_run_id STRING DEFAULT 'V3NIGHTLY-2026-08-27T00:17:51-manual-fresh-sap';

SELECT 'active_magnitude_config' AS check_name, COUNT(*) AS row_count
FROM `pacific-plating-282708.sap_integration_v3.v3_unit2_magnitude_config`
WHERE effective_start<=CURRENT_TIMESTAMP()
  AND (effective_end IS NULL OR effective_end>CURRENT_TIMESTAMP())
UNION ALL
SELECT 'unit2_summary',COUNT(*)
FROM `pacific-plating-282708.sap_integration_v3.v3_unit2_summary`
WHERE pipeline_run_id=v_run_id
UNION ALL
SELECT 'unit3_summary',COUNT(*)
FROM `pacific-plating-282708.sap_integration_v3.v3_unit3_run_summary`
WHERE pipeline_run_id=v_run_id
UNION ALL
SELECT 'scenario1_manifest',COUNT(*)
FROM `pacific-plating-282708.sap_integration_v3.v3_onetime_create_build_manifest`
WHERE pipeline_run_id=v_run_id
UNION ALL
SELECT 'scenario1_activation_snapshot',COUNT(*)
FROM `pacific-plating-282708.sap_integration_v3.v3_onetime_create_activation_summary`
WHERE pipeline_run_id=v_run_id;

SELECT population_grain,outcome,COUNT(*) AS summary_rows,SUM(records) AS records,
  SUM(distinct_orders) AS distinct_orders,SUM(amount) AS amount_satang
FROM `pacific-plating-282708.sap_integration_v3.v3_unit2_summary`
WHERE pipeline_run_id=v_run_id
GROUP BY population_grain,outcome
ORDER BY population_grain,outcome;

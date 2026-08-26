-- Read-only bootstrap evidence for the first approved Unit 2 magnitude configuration.
-- This reports observed deltas only; it does not recommend or seed production thresholds.
DECLARE v_current_run_id STRING DEFAULT
  'V3NIGHTLY-2026-08-27T00:17:51-manual-fresh-sap';
DECLARE v_baseline_run_id STRING;

SET v_baseline_run_id = (
  SELECT run_id
  FROM `pacific-plating-282708.sap_integration_v3.pipeline_run_log`
  WHERE run_id != v_current_run_id
    AND step = 'UNITS_2_5_ARCHIVE'
    AND status = 'SUCCESS'
  GROUP BY run_id
  HAVING COUNT(*) = 1
  ORDER BY MAX(ended_at) DESC,run_id DESC
  LIMIT 1
);

ASSERT v_baseline_run_id IS NOT NULL
  AS 'No prior successful Units 2-5 run exists for bootstrap comparison';
ASSERT (SELECT COUNT(*)
  FROM `pacific-plating-282708.sap_integration_v3.v3_unit2_summary`
  WHERE pipeline_run_id=v_current_run_id)>0
  AS 'Fresh current Unit 2 summary is missing';
ASSERT (SELECT COUNT(*)
  FROM `pacific-plating-282708.sap_integration_v3.v3_unit2_summary`
  WHERE pipeline_run_id=v_baseline_run_id)>0
  AS 'Selected successful baseline has no Unit 2 summary';

CREATE TEMP TABLE distribution AS
WITH event_cells AS (
  SELECT pipeline_run_id,'PAYMENT_EVENT' AS population_grain,outcome,
    COALESCE(flow,'UNKNOWN') AS flow,
    IF(flow='ONETIME','RCB','RCL') AS business_unit,
    COALESCE(s.expected_status,'UNKNOWN') AS expected_status,
    COUNT(*) AS records,COUNT(DISTINCT e.order_id) AS distinct_orders,
    SUM(e.charge_amount) AS amount_satang
  FROM `pacific-plating-282708.sap_integration_v3.v3_unit2_event_shadow` e
  LEFT JOIN `pacific-plating-282708.sap_integration_v3.v3_unit2_schedule_shadow` s
    USING(pipeline_run_id,order_item,order_id,period)
  WHERE pipeline_run_id IN (v_current_run_id,v_baseline_run_id)
  GROUP BY 1,2,3,4,5,6
),schedule_cells AS (
  SELECT pipeline_run_id,'SCHEDULE' AS population_grain,outcome,
    COALESCE(flow,'UNKNOWN') AS flow,
    IF(flow='ONETIME','RCB','RCL') AS business_unit,
    COALESCE(expected_status,'UNKNOWN') AS expected_status,
    COUNT(*) AS records,COUNT(DISTINCT order_id) AS distinct_orders,
    CAST(NULL AS INT64) AS amount_satang
  FROM `pacific-plating-282708.sap_integration_v3.v3_unit2_schedule_shadow`
  WHERE pipeline_run_id IN (v_current_run_id,v_baseline_run_id)
  GROUP BY 1,2,3,4,5,6
)
SELECT * FROM event_cells UNION ALL SELECT * FROM schedule_cells;

ASSERT (SELECT SUM(records) FROM distribution
  WHERE pipeline_run_id=v_current_run_id AND population_grain='PAYMENT_EVENT')
  =(SELECT COUNT(*)
    FROM `pacific-plating-282708.sap_integration_v3.v3_unit2_event_shadow`
    WHERE pipeline_run_id=v_current_run_id)
  AS 'Current event distribution does not conserve';
ASSERT (SELECT SUM(records) FROM distribution
  WHERE pipeline_run_id=v_baseline_run_id AND population_grain='PAYMENT_EVENT')
  =(SELECT COUNT(*)
    FROM `pacific-plating-282708.sap_integration_v3.v3_unit2_event_shadow`
    WHERE pipeline_run_id=v_baseline_run_id)
  AS 'Baseline event distribution does not conserve';
ASSERT (SELECT SUM(records) FROM distribution
  WHERE pipeline_run_id=v_current_run_id AND population_grain='SCHEDULE')
  =(SELECT COUNT(*)
    FROM `pacific-plating-282708.sap_integration_v3.v3_unit2_schedule_shadow`
    WHERE pipeline_run_id=v_current_run_id)
  AS 'Current schedule distribution does not conserve';
ASSERT (SELECT SUM(records) FROM distribution
  WHERE pipeline_run_id=v_baseline_run_id AND population_grain='SCHEDULE')
  =(SELECT COUNT(*)
    FROM `pacific-plating-282708.sap_integration_v3.v3_unit2_schedule_shadow`
    WHERE pipeline_run_id=v_baseline_run_id)
  AS 'Baseline schedule distribution does not conserve';

WITH current_cells AS (
  SELECT * FROM distribution WHERE pipeline_run_id=v_current_run_id
),baseline_cells AS (
  SELECT * FROM distribution WHERE pipeline_run_id=v_baseline_run_id
)
SELECT v_current_run_id AS current_run_id,v_baseline_run_id AS baseline_run_id,
  COALESCE(c.population_grain,b.population_grain) AS population_grain,
  COALESCE(c.outcome,b.outcome) AS outcome,COALESCE(c.flow,b.flow) AS flow,
  COALESCE(c.business_unit,b.business_unit) AS business_unit,
  COALESCE(c.expected_status,b.expected_status) AS expected_status,
  IFNULL(c.records,0) AS current_records,IFNULL(b.records,0) AS baseline_records,
  IFNULL(c.records,0)-IFNULL(b.records,0) AS records_delta,
  SAFE_DIVIDE(ABS(IFNULL(c.records,0)-IFNULL(b.records,0)),ABS(b.records))
    AS records_delta_ratio,
  IFNULL(c.distinct_orders,0) AS current_orders,
  IFNULL(b.distinct_orders,0) AS baseline_orders,
  IFNULL(c.distinct_orders,0)-IFNULL(b.distinct_orders,0) AS orders_delta,
  SAFE_DIVIDE(ABS(IFNULL(c.distinct_orders,0)-IFNULL(b.distinct_orders,0)),
    ABS(b.distinct_orders)) AS orders_delta_ratio,
  c.amount_satang AS current_amount_satang,b.amount_satang AS baseline_amount_satang,
  IFNULL(c.amount_satang,0)-IFNULL(b.amount_satang,0) AS amount_delta_satang,
  SAFE_DIVIDE(ABS(IFNULL(c.amount_satang,0)-IFNULL(b.amount_satang,0)),
    ABS(b.amount_satang)) AS amount_delta_ratio
FROM current_cells c FULL OUTER JOIN baseline_cells b
USING(population_grain,outcome,flow,business_unit,expected_status)
ORDER BY population_grain,outcome,flow,business_unit,expected_status;

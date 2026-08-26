-- SOURCE ONLY / Class A. No configuration seed in this file.
-- A missing approved config or prior successful baseline blocks before Unit 3.

CREATE TABLE IF NOT EXISTS `pacific-plating-282708.sap_integration_v3.v3_unit2_magnitude_config` (
  config_id STRING NOT NULL,
  effective_start TIMESTAMP NOT NULL,
  effective_end TIMESTAMP,
  records_absolute INT64 NOT NULL,
  records_percentage NUMERIC NOT NULL,
  orders_absolute INT64 NOT NULL,
  orders_percentage NUMERIC NOT NULL,
  amount_satang_absolute INT64 NOT NULL,
  amount_percentage NUMERIC NOT NULL,
  approval_reference STRING NOT NULL,
  approved_by STRING NOT NULL,
  approved_at TIMESTAMP NOT NULL,
  created_at TIMESTAMP NOT NULL
)
CLUSTER BY effective_start;

CREATE TABLE IF NOT EXISTS `pacific-plating-282708.sap_integration_v3.v3_unit2_distribution` (
  pipeline_run_id STRING NOT NULL,
  population_grain STRING NOT NULL,
  outcome STRING NOT NULL,
  flow STRING NOT NULL,
  business_unit STRING NOT NULL,
  expected_status STRING NOT NULL,
  records INT64 NOT NULL,
  distinct_orders INT64 NOT NULL,
  amount_satang INT64,
  computed_at TIMESTAMP NOT NULL
)
PARTITION BY DATE(computed_at)
CLUSTER BY pipeline_run_id, population_grain, outcome, flow;

CREATE TABLE IF NOT EXISTS `pacific-plating-282708.sap_integration_v3.v3_unit2_magnitude_result` (
  pipeline_run_id STRING NOT NULL,
  baseline_run_id STRING NOT NULL,
  config_id STRING NOT NULL,
  population_grain STRING NOT NULL,
  outcome STRING NOT NULL,
  flow STRING NOT NULL,
  business_unit STRING NOT NULL,
  expected_status STRING NOT NULL,
  current_records INT64 NOT NULL,
  baseline_records INT64 NOT NULL,
  current_orders INT64 NOT NULL,
  baseline_orders INT64 NOT NULL,
  current_amount_satang INT64,
  baseline_amount_satang INT64,
  breach_reasons ARRAY<STRING>,
  evaluated_at TIMESTAMP NOT NULL
)
PARTITION BY DATE(evaluated_at)
CLUSTER BY pipeline_run_id, population_grain, outcome, flow;

CREATE TABLE IF NOT EXISTS `pacific-plating-282708.sap_integration_v3.v3_unit2_magnitude_run` (
  pipeline_run_id STRING NOT NULL,
  baseline_run_id STRING NOT NULL,
  config_id STRING NOT NULL,
  compared_cells INT64 NOT NULL,
  breached_cells INT64 NOT NULL,
  status STRING NOT NULL,
  evaluated_at TIMESTAMP NOT NULL
)
PARTITION BY DATE(evaluated_at)
CLUSTER BY pipeline_run_id, status;

CREATE OR REPLACE PROCEDURE
  `pacific-plating-282708.sap_integration_v3.sp_evaluate_v3_unit2_magnitude`(
    p_pipeline_run_id STRING
  )
BEGIN
  DECLARE v_config_id STRING;
  DECLARE v_baseline_run_id STRING;
  DECLARE v_breached_cells INT64;

  ASSERT NULLIF(TRIM(p_pipeline_run_id), '') IS NOT NULL
    AS 'Magnitude gate requires pipeline_run_id';
  ASSERT (SELECT COUNT(*)
    FROM `pacific-plating-282708.sap_integration_v3.v3_unit2_summary`
    WHERE pipeline_run_id = p_pipeline_run_id) > 0
    AS 'Magnitude gate requires current Unit 2 output';
  ASSERT (SELECT COUNT(*)
    FROM `pacific-plating-282708.sap_integration_v3.v3_unit2_magnitude_config`
    WHERE effective_start <= CURRENT_TIMESTAMP()
      AND (effective_end IS NULL OR effective_end > CURRENT_TIMESTAMP())) = 1
    AS 'Magnitude gate requires exactly one active approved configuration';

  SET v_config_id = (
    SELECT config_id
    FROM `pacific-plating-282708.sap_integration_v3.v3_unit2_magnitude_config`
    WHERE effective_start <= CURRENT_TIMESTAMP()
      AND (effective_end IS NULL OR effective_end > CURRENT_TIMESTAMP())
  );
  SET v_baseline_run_id = (
    SELECT r.pipeline_run_id
    FROM `pacific-plating-282708.sap_integration_v3.v3_unit2_magnitude_run` r
    WHERE r.pipeline_run_id != p_pipeline_run_id
      AND r.status = 'PASS'
      AND EXISTS (
        SELECT 1
        FROM `pacific-plating-282708.sap_integration_v3.pipeline_run_log` l
        WHERE l.run_id = r.pipeline_run_id
          AND l.step = 'UNITS_2_5_ARCHIVE'
          AND l.status = 'SUCCESS'
      )
    ORDER BY r.evaluated_at DESC, r.pipeline_run_id DESC
    LIMIT 1
  );
  ASSERT v_baseline_run_id IS NOT NULL
    AS 'Magnitude gate has no prior successful baseline; bootstrap requires reviewed approval';

  DELETE FROM `pacific-plating-282708.sap_integration_v3.v3_unit2_distribution`
  WHERE pipeline_run_id = p_pipeline_run_id;

  INSERT INTO `pacific-plating-282708.sap_integration_v3.v3_unit2_distribution`
  WITH event_cells AS (
    SELECT
      e.pipeline_run_id, 'PAYMENT_EVENT' AS population_grain, e.outcome,
      COALESCE(e.flow, 'UNKNOWN') AS flow,
      IF(e.flow = 'ONETIME', 'RCB', 'RCL') AS business_unit,
      COALESCE(s.expected_status, 'UNKNOWN') AS expected_status,
      COUNT(*) AS records, COUNT(DISTINCT e.order_id) AS distinct_orders,
      SUM(e.charge_amount) AS amount_satang
    FROM `pacific-plating-282708.sap_integration_v3.v3_unit2_event_shadow` e
    LEFT JOIN `pacific-plating-282708.sap_integration_v3.v3_unit2_schedule_shadow` s
      USING (pipeline_run_id, order_item, order_id, period)
    WHERE e.pipeline_run_id = p_pipeline_run_id
    GROUP BY 1,2,3,4,5,6
  ),
  schedule_cells AS (
    SELECT
      pipeline_run_id, 'SCHEDULE' AS population_grain, outcome,
      COALESCE(flow, 'UNKNOWN') AS flow,
      IF(flow = 'ONETIME', 'RCB', 'RCL') AS business_unit,
      COALESCE(expected_status, 'UNKNOWN') AS expected_status,
      COUNT(*) AS records, COUNT(DISTINCT order_id) AS distinct_orders,
      CAST(NULL AS INT64) AS amount_satang
    FROM `pacific-plating-282708.sap_integration_v3.v3_unit2_schedule_shadow`
    WHERE pipeline_run_id = p_pipeline_run_id
    GROUP BY 1,2,3,4,5,6
  )
  SELECT *, CURRENT_TIMESTAMP() FROM event_cells
  UNION ALL
  SELECT *, CURRENT_TIMESTAMP() FROM schedule_cells;

  ASSERT (SELECT SUM(records)
    FROM `pacific-plating-282708.sap_integration_v3.v3_unit2_distribution`
    WHERE pipeline_run_id = p_pipeline_run_id AND population_grain = 'PAYMENT_EVENT')
    = (SELECT COUNT(*)
      FROM `pacific-plating-282708.sap_integration_v3.v3_unit2_event_shadow`
      WHERE pipeline_run_id = p_pipeline_run_id)
    AS 'Magnitude event records do not conserve';
  ASSERT (SELECT SUM(amount_satang)
    FROM `pacific-plating-282708.sap_integration_v3.v3_unit2_distribution`
    WHERE pipeline_run_id = p_pipeline_run_id AND population_grain = 'PAYMENT_EVENT')
    = (SELECT SUM(charge_amount)
      FROM `pacific-plating-282708.sap_integration_v3.v3_unit2_event_shadow`
      WHERE pipeline_run_id = p_pipeline_run_id)
    AS 'Magnitude event amount does not conserve';
  ASSERT (SELECT SUM(records)
    FROM `pacific-plating-282708.sap_integration_v3.v3_unit2_distribution`
    WHERE pipeline_run_id = p_pipeline_run_id AND population_grain = 'SCHEDULE')
    = (SELECT COUNT(*)
      FROM `pacific-plating-282708.sap_integration_v3.v3_unit2_schedule_shadow`
      WHERE pipeline_run_id = p_pipeline_run_id)
    AS 'Magnitude schedule records do not conserve';

  DELETE FROM `pacific-plating-282708.sap_integration_v3.v3_unit2_magnitude_result`
  WHERE pipeline_run_id = p_pipeline_run_id;

  INSERT INTO `pacific-plating-282708.sap_integration_v3.v3_unit2_magnitude_result`
  WITH cfg AS (
    SELECT *
    FROM `pacific-plating-282708.sap_integration_v3.v3_unit2_magnitude_config`
    WHERE config_id = v_config_id
  ),
  cells AS (
    SELECT
      COALESCE(c.population_grain, b.population_grain) population_grain,
      COALESCE(c.outcome, b.outcome) outcome,
      COALESCE(c.flow, b.flow) flow,
      COALESCE(c.business_unit, b.business_unit) business_unit,
      COALESCE(c.expected_status, b.expected_status) expected_status,
      IFNULL(c.records, 0) current_records, IFNULL(b.records, 0) baseline_records,
      IFNULL(c.distinct_orders, 0) current_orders,
      IFNULL(b.distinct_orders, 0) baseline_orders,
      c.amount_satang current_amount_satang, b.amount_satang baseline_amount_satang
    FROM (SELECT *
      FROM `pacific-plating-282708.sap_integration_v3.v3_unit2_distribution`
      WHERE pipeline_run_id = p_pipeline_run_id) c
    FULL OUTER JOIN (SELECT *
      FROM `pacific-plating-282708.sap_integration_v3.v3_unit2_distribution`
      WHERE pipeline_run_id = v_baseline_run_id) b
    USING (population_grain, outcome, flow, business_unit, expected_status)
  )
  SELECT
    p_pipeline_run_id, v_baseline_run_id, config_id,
    population_grain, outcome, flow, business_unit, expected_status,
    current_records, baseline_records, current_orders, baseline_orders,
    current_amount_satang, baseline_amount_satang,
    ARRAY_CONCAT(
      IF(ABS(current_records - baseline_records) > records_absolute
        AND (baseline_records = 0 OR SAFE_DIVIDE(
          ABS(current_records - baseline_records), ABS(baseline_records)
        ) > records_percentage), ['RECORDS'], []),
      IF(ABS(current_orders - baseline_orders) > orders_absolute
        AND (baseline_orders = 0 OR SAFE_DIVIDE(
          ABS(current_orders - baseline_orders), ABS(baseline_orders)
        ) > orders_percentage), ['ORDERS'], []),
      IF(current_amount_satang IS NOT NULL OR baseline_amount_satang IS NOT NULL,
        IF(ABS(IFNULL(current_amount_satang, 0) - IFNULL(baseline_amount_satang, 0))
            > amount_satang_absolute
          AND (IFNULL(baseline_amount_satang, 0) = 0 OR SAFE_DIVIDE(
            ABS(IFNULL(current_amount_satang, 0) - IFNULL(baseline_amount_satang, 0)),
            ABS(baseline_amount_satang)
          ) > amount_percentage), ['AMOUNT'], []),
        [])
    ) breach_reasons,
    CURRENT_TIMESTAMP()
  FROM cells CROSS JOIN cfg;

  SET v_breached_cells = (SELECT COUNTIF(ARRAY_LENGTH(breach_reasons) > 0)
    FROM `pacific-plating-282708.sap_integration_v3.v3_unit2_magnitude_result`
    WHERE pipeline_run_id = p_pipeline_run_id);

  DELETE FROM `pacific-plating-282708.sap_integration_v3.v3_unit2_magnitude_run`
  WHERE pipeline_run_id = p_pipeline_run_id;
  INSERT INTO `pacific-plating-282708.sap_integration_v3.v3_unit2_magnitude_run`
  SELECT p_pipeline_run_id, v_baseline_run_id, v_config_id, COUNT(*), v_breached_cells,
    IF(v_breached_cells = 0, 'PASS', 'HELD_MAGNITUDE_REVIEW'), CURRENT_TIMESTAMP()
  FROM `pacific-plating-282708.sap_integration_v3.v3_unit2_magnitude_result`
  WHERE pipeline_run_id = p_pipeline_run_id;

  ASSERT v_breached_cells = 0
    AS 'HELD_MAGNITUDE_REVIEW; inspect v3_unit2_magnitude_result before Unit 3';
END;

-- SOURCE ONLY / Class A.
-- One-time bootstrap for the Unit 2 magnitude gate's otherwise circular first baseline.
-- This file creates a procedure only. It does not seed a configuration, call the procedure,
-- activate a workflow/Scheduler job, export an interface file, or write GCS.

CREATE OR REPLACE PROCEDURE
  `pacific-plating-282708.sap_integration_v3.sp_bootstrap_v3_unit2_magnitude`(
    p_baseline_run_id STRING,
    p_config_id STRING,
    p_effective_start TIMESTAMP,
    p_effective_end TIMESTAMP,
    p_records_absolute INT64,
    p_records_percentage NUMERIC,
    p_orders_absolute INT64,
    p_orders_percentage NUMERIC,
    p_amount_satang_absolute INT64,
    p_amount_percentage NUMERIC,
    p_approval_reference STRING,
    p_approved_by STRING,
    p_approved_at TIMESTAMP
  )
BEGIN
  DECLARE v_recorded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP();

  ASSERT NULLIF(TRIM(p_baseline_run_id), '') IS NOT NULL
    AND NULLIF(TRIM(p_config_id), '') IS NOT NULL
    AS 'Bootstrap requires exact baseline run and config IDs';
  ASSERT NULLIF(TRIM(p_approval_reference), '') IS NOT NULL
    AND NULLIF(TRIM(p_approved_by), '') IS NOT NULL
    AND p_approved_at IS NOT NULL
    AND p_approved_at <= v_recorded_at
    AS 'Bootstrap requires explicit approval provenance';
  ASSERT p_effective_start <= v_recorded_at
    AND (p_effective_end IS NULL OR p_effective_end > v_recorded_at)
    AS 'Bootstrap configuration must be active when registered';
  ASSERT p_records_absolute >= 0
    AND p_orders_absolute >= 0
    AND p_amount_satang_absolute >= 0
    AND p_records_percentage BETWEEN 0 AND 1
    AND p_orders_percentage BETWEEN 0 AND 1
    AND p_amount_percentage BETWEEN 0 AND 1
    AS 'Magnitude thresholds must be non-negative and percentages must be within [0,1]';
  ASSERT (SELECT COUNT(*)
    FROM `pacific-plating-282708.sap_integration_v3.v3_unit2_magnitude_config`
    WHERE effective_start <= v_recorded_at
      AND (effective_end IS NULL OR effective_end > v_recorded_at)) = 0
    AS 'Bootstrap requires zero active magnitude configurations';
  ASSERT (SELECT COUNT(*)
    FROM `pacific-plating-282708.sap_integration_v3.v3_unit2_magnitude_config`
    WHERE config_id = p_config_id) = 0
    AS 'config_id already exists';
  ASSERT (SELECT COUNT(*)
    FROM `pacific-plating-282708.sap_integration_v3.pipeline_run_log`
    WHERE run_id = p_baseline_run_id
      AND step = 'UNITS_2_5_ARCHIVE'
      AND status = 'SUCCESS') = 1
    AS 'Bootstrap baseline must have exactly one successful Units 2-5 archive row';
  ASSERT (SELECT COUNT(*)
    FROM `pacific-plating-282708.sap_integration_v3.v3_unit2_summary`
    WHERE pipeline_run_id = p_baseline_run_id) > 0
    AS 'Bootstrap baseline has no Unit 2 summary';
  ASSERT (SELECT COUNT(*)
    FROM `pacific-plating-282708.sap_integration_v3.v3_unit2_magnitude_run`
    WHERE pipeline_run_id = p_baseline_run_id) = 0
    AS 'Bootstrap baseline already has a magnitude result';
  ASSERT (SELECT COUNT(*)
    FROM `pacific-plating-282708.sap_integration_v3.v3_unit2_distribution`
    WHERE pipeline_run_id = p_baseline_run_id) = 0
    AS 'Bootstrap refuses to replace existing baseline distribution evidence';

  CREATE TEMP TABLE _distribution AS
  WITH event_cells AS (
    SELECT
      e.pipeline_run_id,
      'PAYMENT_EVENT' AS population_grain,
      e.outcome,
      COALESCE(e.flow, 'UNKNOWN') AS flow,
      IF(e.flow = 'ONETIME', 'RCB', 'RCL') AS business_unit,
      COALESCE(s.expected_status, 'UNKNOWN') AS expected_status,
      COUNT(*) AS records,
      COUNT(DISTINCT e.order_id) AS distinct_orders,
      SUM(e.charge_amount) AS amount_satang
    FROM `pacific-plating-282708.sap_integration_v3.v3_unit2_event_shadow` e
    LEFT JOIN `pacific-plating-282708.sap_integration_v3.v3_unit2_schedule_shadow` s
      USING (pipeline_run_id, order_item, order_id, period)
    WHERE e.pipeline_run_id = p_baseline_run_id
    GROUP BY 1,2,3,4,5,6
  ),
  schedule_cells AS (
    SELECT
      pipeline_run_id,
      'SCHEDULE' AS population_grain,
      outcome,
      COALESCE(flow, 'UNKNOWN') AS flow,
      IF(flow = 'ONETIME', 'RCB', 'RCL') AS business_unit,
      COALESCE(expected_status, 'UNKNOWN') AS expected_status,
      COUNT(*) AS records,
      COUNT(DISTINCT order_id) AS distinct_orders,
      CAST(NULL AS INT64) AS amount_satang
    FROM `pacific-plating-282708.sap_integration_v3.v3_unit2_schedule_shadow`
    WHERE pipeline_run_id = p_baseline_run_id
    GROUP BY 1,2,3,4,5,6
  )
  SELECT * FROM event_cells
  UNION ALL
  SELECT * FROM schedule_cells;

  ASSERT (SELECT COUNT(*) FROM _distribution) > 0
    AS 'Bootstrap baseline distribution is empty';
  ASSERT (SELECT SUM(records) FROM _distribution
    WHERE population_grain = 'PAYMENT_EVENT')
    = (SELECT COUNT(*)
      FROM `pacific-plating-282708.sap_integration_v3.v3_unit2_event_shadow`
      WHERE pipeline_run_id = p_baseline_run_id)
    AS 'Bootstrap event distribution does not conserve';
  ASSERT (SELECT SUM(amount_satang) FROM _distribution
    WHERE population_grain = 'PAYMENT_EVENT')
    = (SELECT SUM(charge_amount)
      FROM `pacific-plating-282708.sap_integration_v3.v3_unit2_event_shadow`
      WHERE pipeline_run_id = p_baseline_run_id)
    AS 'Bootstrap event amount does not conserve';
  ASSERT (SELECT SUM(records) FROM _distribution
    WHERE population_grain = 'SCHEDULE')
    = (SELECT COUNT(*)
      FROM `pacific-plating-282708.sap_integration_v3.v3_unit2_schedule_shadow`
      WHERE pipeline_run_id = p_baseline_run_id)
    AS 'Bootstrap schedule distribution does not conserve';

  BEGIN TRANSACTION;

  INSERT INTO `pacific-plating-282708.sap_integration_v3.v3_unit2_magnitude_config`
    (config_id, effective_start, effective_end, records_absolute, records_percentage,
      orders_absolute, orders_percentage, amount_satang_absolute, amount_percentage,
      approval_reference, approved_by, approved_at, created_at)
  VALUES
    (p_config_id, p_effective_start, p_effective_end, p_records_absolute,
      p_records_percentage, p_orders_absolute, p_orders_percentage,
      p_amount_satang_absolute, p_amount_percentage, p_approval_reference,
      p_approved_by, p_approved_at, v_recorded_at);
  ASSERT @@row_count = 1 AS 'Magnitude configuration insert failed';

  INSERT INTO `pacific-plating-282708.sap_integration_v3.v3_unit2_distribution`
    (pipeline_run_id, population_grain, outcome, flow, business_unit, expected_status,
      records, distinct_orders, amount_satang, computed_at)
  SELECT *, v_recorded_at FROM _distribution;
  ASSERT @@row_count = (SELECT COUNT(*) FROM _distribution)
    AS 'Bootstrap distribution insert did not conserve cells';

  INSERT INTO `pacific-plating-282708.sap_integration_v3.v3_unit2_magnitude_result`
    (pipeline_run_id, baseline_run_id, config_id, population_grain, outcome, flow,
      business_unit, expected_status, current_records, baseline_records, current_orders,
      baseline_orders, current_amount_satang, baseline_amount_satang, breach_reasons,
      evaluated_at)
  SELECT
    p_baseline_run_id,
    p_baseline_run_id,
    p_config_id,
    population_grain,
    outcome,
    flow,
    business_unit,
    expected_status,
    records,
    records,
    distinct_orders,
    distinct_orders,
    amount_satang,
    amount_satang,
    CAST([] AS ARRAY<STRING>),
    v_recorded_at
  FROM _distribution;
  ASSERT @@row_count = (SELECT COUNT(*) FROM _distribution)
    AS 'Bootstrap self-baseline result did not conserve cells';

  INSERT INTO `pacific-plating-282708.sap_integration_v3.v3_unit2_magnitude_run`
    (pipeline_run_id, baseline_run_id, config_id, compared_cells, breached_cells,
      status, evaluated_at)
  SELECT p_baseline_run_id, p_baseline_run_id, p_config_id, COUNT(*), 0, 'PASS', v_recorded_at
  FROM _distribution;
  ASSERT @@row_count = 1 AS 'Bootstrap magnitude PASS insert failed';

  COMMIT TRANSACTION;
END;

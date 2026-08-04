-- SOURCE ONLY / Class A.
-- Replacement for the obsolete hardcoded ">60 total / baseline ~22-24" regression heuristic.
-- Source intentionally contains no threshold seed. A scheduled transfer-config revision and
-- end-to-end human delivery test remain separate production gates.

CREATE TABLE IF NOT EXISTS
  `pacific-plating-282708.sap_integration_v3.validation_error_daily_history` (
    snapshot_date DATE NOT NULL,
    snapshot_id STRING NOT NULL,
    source_detected_at TIMESTAMP,
    check_name STRING NOT NULL,
    record_count INT64 NOT NULL,
    order_count INT64 NOT NULL,
    recorded_at TIMESTAMP NOT NULL
  )
PARTITION BY snapshot_date
CLUSTER BY check_name, snapshot_id;

CREATE TABLE IF NOT EXISTS
  `pacific-plating-282708.sap_integration_v3.validation_regression_alert_config` (
    check_name STRING NOT NULL,
    max_record_increase INT64 NOT NULL,
    max_order_increase INT64 NOT NULL,
    effective_from DATE NOT NULL,
    effective_to DATE,
    approved_by STRING NOT NULL,
    approved_at TIMESTAMP NOT NULL
  )
CLUSTER BY check_name, effective_from
OPTIONS(description = 'Human-approved per-rule validation regression thresholds; no source seed');

CREATE OR REPLACE PROCEDURE
  `pacific-plating-282708.sap_integration_v3.sp_snapshot_validation_errors`(
    p_snapshot_date DATE,
    p_snapshot_id STRING
  )
BEGIN
  DECLARE v_source_rows INT64;
  DECLARE v_snapshot_rows INT64;
  DECLARE v_source_detected_at TIMESTAMP;

  ASSERT p_snapshot_date IS NOT NULL AS 'snapshot_date is required';
  ASSERT p_snapshot_date <= CURRENT_DATE('Asia/Bangkok')
    AS 'future validation snapshots are prohibited';
  ASSERT NULLIF(TRIM(p_snapshot_id), '') IS NOT NULL AS 'snapshot_id is required';
  ASSERT (SELECT COUNT(*)
    FROM `pacific-plating-282708.sap_integration_v3.validation_error_daily_history`
    WHERE snapshot_date = p_snapshot_date) = 0
    AS 'daily validation snapshot already exists; refusing overwrite/replay';

  SET v_source_rows = (SELECT COUNT(*)
    FROM `pacific-plating-282708.sap_integration_v3.sap_validation_error`);
  SET v_source_detected_at = (SELECT MAX(detected_at)
    FROM `pacific-plating-282708.sap_integration_v3.sap_validation_error`);

  INSERT INTO `pacific-plating-282708.sap_integration_v3.validation_error_daily_history`
    (snapshot_date, snapshot_id, source_detected_at, check_name,
     record_count, order_count, recorded_at)
  SELECT p_snapshot_date, p_snapshot_id, v_source_detected_at, check_name,
    COUNT(*), COUNT(DISTINCT order_item), CURRENT_TIMESTAMP()
  FROM `pacific-plating-282708.sap_integration_v3.sap_validation_error`
  GROUP BY check_name;

  SET v_snapshot_rows = (SELECT IFNULL(SUM(record_count), 0)
    FROM `pacific-plating-282708.sap_integration_v3.validation_error_daily_history`
    WHERE snapshot_date = p_snapshot_date);
  ASSERT v_snapshot_rows = v_source_rows
    AS 'validation snapshot record conservation failed';
END;

CREATE OR REPLACE PROCEDURE
  `pacific-plating-282708.sap_integration_v3.sp_check_validation_regression_v2`(
    p_snapshot_date DATE
  )
BEGIN
  DECLARE v_previous_date DATE;
  DECLARE v_breaches ARRAY<STRING>;

  ASSERT p_snapshot_date IS NOT NULL AS 'snapshot_date is required';
  ASSERT (SELECT COUNT(*)
    FROM `pacific-plating-282708.sap_integration_v3.validation_error_daily_history`
    WHERE snapshot_date = p_snapshot_date) > 0
    AS 'current validation snapshot is missing or empty';
  SET v_previous_date = (SELECT MAX(snapshot_date)
    FROM `pacific-plating-282708.sap_integration_v3.validation_error_daily_history`
    WHERE snapshot_date < p_snapshot_date);
  ASSERT v_previous_date IS NOT NULL
    AS 'prior validation snapshot is missing; cannot evaluate regression';

  ASSERT NOT EXISTS (
    SELECT 1
    FROM `pacific-plating-282708.sap_integration_v3.validation_error_daily_history` h
    WHERE h.snapshot_date = p_snapshot_date
      AND NOT EXISTS (
        SELECT 1
        FROM `pacific-plating-282708.sap_integration_v3.validation_regression_alert_config` c
        WHERE c.check_name = h.check_name
          AND c.effective_from <= p_snapshot_date
          AND (c.effective_to IS NULL OR p_snapshot_date < c.effective_to)
      )
  ) AS 'every current validation check requires active approved threshold configuration';
  ASSERT NOT EXISTS (
    SELECT check_name
    FROM `pacific-plating-282708.sap_integration_v3.validation_regression_alert_config`
    WHERE effective_from <= p_snapshot_date
      AND (effective_to IS NULL OR p_snapshot_date < effective_to)
    GROUP BY check_name
    HAVING COUNT(*) > 1
  ) AS 'overlapping active validation threshold configuration';

  SET v_breaches = ARRAY(
    WITH current_counts AS (
      SELECT check_name, record_count, order_count
      FROM `pacific-plating-282708.sap_integration_v3.validation_error_daily_history`
      WHERE snapshot_date = p_snapshot_date
    ),
    previous_counts AS (
      SELECT check_name, record_count, order_count
      FROM `pacific-plating-282708.sap_integration_v3.validation_error_daily_history`
      WHERE snapshot_date = v_previous_date
    ),
    active_config AS (
      SELECT check_name, max_record_increase, max_order_increase
      FROM `pacific-plating-282708.sap_integration_v3.validation_regression_alert_config`
      WHERE effective_from <= p_snapshot_date
        AND (effective_to IS NULL OR p_snapshot_date < effective_to)
    )
    SELECT FORMAT(
      '%s records delta=%d (current=%d prior=%d); orders delta=%d (current=%d prior=%d)',
      c.check_name, c.record_count - IFNULL(p.record_count, 0),
      c.record_count, IFNULL(p.record_count, 0),
      c.order_count - IFNULL(p.order_count, 0), c.order_count, IFNULL(p.order_count, 0)
    )
    FROM current_counts c
    LEFT JOIN previous_counts p USING (check_name)
    JOIN active_config cfg USING (check_name)
    WHERE c.record_count - IFNULL(p.record_count, 0) > cfg.max_record_increase
       OR c.order_count - IFNULL(p.order_count, 0) > cfg.max_order_increase
    ORDER BY c.check_name
  );

  IF ARRAY_LENGTH(v_breaches) > 0 THEN
    RAISE USING MESSAGE = CONCAT(
      'validation regression exceeded approved day-over-day threshold: ',
      ARRAY_TO_STRING(v_breaches, ' | ')
    );
  END IF;
END;

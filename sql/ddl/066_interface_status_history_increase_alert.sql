-- SOURCE ONLY / Class A.
-- Day-over-day MISSING/STATUS_CONFLICT history and increase alert.
-- No threshold seed is included: Boat must approve X before this checker can run.
-- Existing absolute backlogs are never treated as a new incident by themselves.

CREATE TABLE IF NOT EXISTS
  `pacific-plating-282708.sap_integration_v3.interface_status_daily_history` (
    snapshot_date DATE NOT NULL,
    snapshot_id STRING NOT NULL,
    source_computed_at TIMESTAMP NOT NULL,
    status STRING NOT NULL,
    record_count INT64 NOT NULL,
    order_count INT64 NOT NULL,
    recorded_at TIMESTAMP NOT NULL
  )
PARTITION BY snapshot_date
CLUSTER BY status, snapshot_id
OPTIONS(description = 'Immutable daily interface-status counts; logical key (snapshot_date,status)');

CREATE TABLE IF NOT EXISTS
  `pacific-plating-282708.sap_integration_v3.interface_status_alert_config` (
    status STRING NOT NULL,
    max_record_increase INT64 NOT NULL,
    max_order_increase INT64 NOT NULL,
    effective_from DATE NOT NULL,
    effective_to DATE,
    approved_by STRING NOT NULL,
    approved_at TIMESTAMP NOT NULL
  )
CLUSTER BY status, effective_from
OPTIONS(description = 'Human-approved day-over-day increase thresholds; source intentionally has no seed');

CREATE OR REPLACE PROCEDURE
  `pacific-plating-282708.sap_integration_v3.sp_snapshot_interface_daily_status`(
    p_snapshot_date DATE,
    p_snapshot_id STRING
  )
BEGIN
  DECLARE v_source_computed_at TIMESTAMP;
  DECLARE v_source_rows INT64;
  DECLARE v_snapshot_rows INT64;

  ASSERT p_snapshot_date IS NOT NULL AS 'snapshot_date is required';
  ASSERT p_snapshot_date <= CURRENT_DATE('Asia/Bangkok')
    AS 'future interface-status snapshots are prohibited';
  ASSERT NULLIF(TRIM(p_snapshot_id), '') IS NOT NULL AS 'snapshot_id is required';
  ASSERT (SELECT COUNT(DISTINCT computed_at)
    FROM `pacific-plating-282708.sap_integration_v3.interface_daily_status`) = 1
    AS 'interface_daily_status must contain exactly one refresh timestamp';

  SET v_source_computed_at = (
    SELECT MAX(computed_at)
    FROM `pacific-plating-282708.sap_integration_v3.interface_daily_status`
  );
  SET v_source_rows = (
    SELECT COUNT(*)
    FROM `pacific-plating-282708.sap_integration_v3.interface_daily_status`
  );

  ASSERT DATE(v_source_computed_at, 'Asia/Bangkok') = p_snapshot_date
    AS 'snapshot date does not match the source refresh date';
  ASSERT (SELECT COUNT(*)
    FROM `pacific-plating-282708.sap_integration_v3.interface_status_daily_history`
    WHERE snapshot_date = p_snapshot_date) = 0
    AS 'daily snapshot already exists; refusing overwrite/replay';

  INSERT INTO `pacific-plating-282708.sap_integration_v3.interface_status_daily_history`
    (snapshot_date, snapshot_id, source_computed_at, status, record_count, order_count, recorded_at)
  SELECT
    p_snapshot_date,
    p_snapshot_id,
    v_source_computed_at,
    status,
    COUNT(*),
    COUNT(DISTINCT order_item),
    CURRENT_TIMESTAMP()
  FROM `pacific-plating-282708.sap_integration_v3.interface_daily_status`
  GROUP BY status;

  SET v_snapshot_rows = (
    SELECT SUM(record_count)
    FROM `pacific-plating-282708.sap_integration_v3.interface_status_daily_history`
    WHERE snapshot_date = p_snapshot_date
  );
  ASSERT v_snapshot_rows = v_source_rows
    AS 'interface-status snapshot record conservation failed';
END;

CREATE OR REPLACE PROCEDURE
  `pacific-plating-282708.sap_integration_v3.sp_check_interface_status_increase_alert`(
    p_snapshot_date DATE
  )
BEGIN
  DECLARE v_previous_date DATE;
  DECLARE v_breaches ARRAY<STRING>;

  ASSERT p_snapshot_date IS NOT NULL AS 'snapshot_date is required';
  ASSERT (SELECT COUNT(*)
    FROM `pacific-plating-282708.sap_integration_v3.interface_status_daily_history`
    WHERE snapshot_date = p_snapshot_date) > 0 AS 'current daily snapshot is missing';

  SET v_previous_date = (
    SELECT MAX(snapshot_date)
    FROM `pacific-plating-282708.sap_integration_v3.interface_status_daily_history`
    WHERE snapshot_date < p_snapshot_date
  );
  ASSERT v_previous_date IS NOT NULL AS 'prior daily snapshot is missing; cannot compute increase';

  ASSERT (SELECT COUNT(*)
    FROM `pacific-plating-282708.sap_integration_v3.interface_status_alert_config`
    WHERE status IN ('MISSING', 'STATUS_CONFLICT')
      AND effective_from <= p_snapshot_date
      AND (effective_to IS NULL OR p_snapshot_date < effective_to)) = 2
    AS 'exactly one active approved threshold is required for each monitored status';
  ASSERT (SELECT COUNT(DISTINCT status)
    FROM `pacific-plating-282708.sap_integration_v3.interface_status_alert_config`
    WHERE status IN ('MISSING', 'STATUS_CONFLICT')
      AND effective_from <= p_snapshot_date
      AND (effective_to IS NULL OR p_snapshot_date < effective_to)) = 2
    AS 'active alert threshold configuration is duplicated or incomplete';

  SET v_breaches = ARRAY(
    WITH monitored AS (
      SELECT status FROM UNNEST(['MISSING', 'STATUS_CONFLICT']) status
    ),
    current_counts AS (
      SELECT status, record_count, order_count
      FROM `pacific-plating-282708.sap_integration_v3.interface_status_daily_history`
      WHERE snapshot_date = p_snapshot_date
    ),
    previous_counts AS (
      SELECT status, record_count, order_count
      FROM `pacific-plating-282708.sap_integration_v3.interface_status_daily_history`
      WHERE snapshot_date = v_previous_date
    ),
    active_config AS (
      SELECT status, max_record_increase, max_order_increase
      FROM `pacific-plating-282708.sap_integration_v3.interface_status_alert_config`
      WHERE status IN ('MISSING', 'STATUS_CONFLICT')
        AND effective_from <= p_snapshot_date
        AND (effective_to IS NULL OR p_snapshot_date < effective_to)
    )
    SELECT FORMAT(
      '%s records %+d (current %d, prior %d); orders %+d (current %d, prior %d)',
      m.status,
      IFNULL(c.record_count, 0) - IFNULL(p.record_count, 0),
      IFNULL(c.record_count, 0), IFNULL(p.record_count, 0),
      IFNULL(c.order_count, 0) - IFNULL(p.order_count, 0),
      IFNULL(c.order_count, 0), IFNULL(p.order_count, 0)
    )
    FROM monitored m
    LEFT JOIN current_counts c USING (status)
    LEFT JOIN previous_counts p USING (status)
    JOIN active_config cfg USING (status)
    WHERE IFNULL(c.record_count, 0) - IFNULL(p.record_count, 0) > cfg.max_record_increase
       OR IFNULL(c.order_count, 0) - IFNULL(p.order_count, 0) > cfg.max_order_increase
    ORDER BY m.status
  );

  IF ARRAY_LENGTH(v_breaches) > 0 THEN
    RAISE USING MESSAGE = CONCAT(
      'interface_daily_status day-over-day increase exceeded approved threshold: ',
      ARRAY_TO_STRING(v_breaches, ' | ')
    );
  END IF;
END;

-- SOURCE ONLY / Class A.
-- Immutable normalized Unit 6 completeness snapshot. This procedure sends no alert and does not
-- infer human delivery. READY_TO_ALERT is a data/evidence state; alert_delivery_status starts
-- PENDING and must be updated only by a separately reviewed human-channel delivery integration.

CREATE TABLE IF NOT EXISTS
  `pacific-plating-282708.sap_integration_v3.v3_daily_completeness_run` (
    pipeline_run_id STRING NOT NULL,
    snapshot_status STRING NOT NULL,
    alert_delivery_status STRING NOT NULL,
    unit1_complete_count INT64 NOT NULL,
    units2_5_complete_count INT64 NOT NULL,
    magnitude_status STRING NOT NULL,
    gate_blocker_count INT64 NOT NULL,
    notification_rows INT64 NOT NULL,
    export_run_count INT64 NOT NULL,
    manifest_count INT64 NOT NULL,
    created_at TIMESTAMP NOT NULL
  )
PARTITION BY DATE(created_at)
CLUSTER BY pipeline_run_id, snapshot_status;

CREATE TABLE IF NOT EXISTS
  `pacific-plating-282708.sap_integration_v3.v3_daily_completeness_metric` (
    pipeline_run_id STRING NOT NULL,
    metric_group STRING NOT NULL,
    population_grain STRING NOT NULL,
    metric_code STRING NOT NULL,
    records INT64 NOT NULL,
    orders INT64,
    amount_satang INT64,
    created_at TIMESTAMP NOT NULL
  )
PARTITION BY DATE(created_at)
CLUSTER BY pipeline_run_id, metric_group, metric_code;

CREATE TABLE IF NOT EXISTS
  `pacific-plating-282708.sap_integration_v3.v3_daily_completeness_evidence` (
    pipeline_run_id STRING NOT NULL,
    evidence_type STRING NOT NULL,
    evidence_key STRING NOT NULL,
    evidence_status STRING NOT NULL,
    evidence_detail STRING,
    recorded_at TIMESTAMP NOT NULL
  )
PARTITION BY DATE(recorded_at)
CLUSTER BY pipeline_run_id, evidence_type, evidence_status;

CREATE OR REPLACE PROCEDURE
  `pacific-plating-282708.sap_integration_v3.sp_build_v3_daily_completeness_snapshot`(
    p_pipeline_run_id STRING
  )
BEGIN
  DECLARE v_unit1 INT64;
  DECLARE v_units2_5 INT64;
  DECLARE v_magnitude_status STRING;
  DECLARE v_gate_blockers INT64;
  DECLARE v_notification_rows INT64;
  DECLARE v_export_runs INT64;
  DECLARE v_manifests INT64;

  ASSERT NULLIF(TRIM(p_pipeline_run_id), '') IS NOT NULL AS 'pipeline_run_id is required';
  ASSERT (SELECT COUNT(*)
    FROM `pacific-plating-282708.sap_integration_v3.v3_daily_completeness_run`
    WHERE pipeline_run_id = p_pipeline_run_id) = 0
    AS 'completeness snapshot already exists; immutable replay refused';
  ASSERT (SELECT COUNT(*)
    FROM `pacific-plating-282708.sap_integration_v3.v3_unit2_summary`
    WHERE pipeline_run_id = p_pipeline_run_id) > 0 AS 'Unit 2 summary is required';
  ASSERT (SELECT COUNT(*)
    FROM `pacific-plating-282708.sap_integration_v3.v3_unit2_magnitude_run`
    WHERE pipeline_run_id = p_pipeline_run_id) = 1 AS 'exactly one magnitude result is required';
  ASSERT (SELECT COUNT(*)
    FROM `pacific-plating-282708.sap_integration_v3.v3_notification_run_summary`
    WHERE pipeline_run_id = p_pipeline_run_id) = 1 AS 'exactly one notification summary is required';

  SET v_unit1 = (SELECT COUNTIF(step = 'UNIT1_COMPLETE' AND status = 'SUCCESS')
    FROM `pacific-plating-282708.sap_integration_v3.pipeline_run_log`
    WHERE run_id = p_pipeline_run_id);
  SET v_units2_5 = (SELECT COUNTIF(step = 'UNITS_2_5_ARCHIVE' AND status = 'SUCCESS')
    FROM `pacific-plating-282708.sap_integration_v3.pipeline_run_log`
    WHERE run_id = p_pipeline_run_id);
  SET v_magnitude_status = (SELECT status
    FROM `pacific-plating-282708.sap_integration_v3.v3_unit2_magnitude_run`
    WHERE pipeline_run_id = p_pipeline_run_id);
  SET v_gate_blockers = (SELECT IFNULL(SUM(blocker_count), 0)
    FROM `pacific-plating-282708.sap_integration_v3.v3_automation_gate_result`
    WHERE pipeline_run_id = p_pipeline_run_id);
  SET v_notification_rows = (SELECT notification_rows
    FROM `pacific-plating-282708.sap_integration_v3.v3_notification_run_summary`
    WHERE pipeline_run_id = p_pipeline_run_id);

  CREATE TEMP TABLE _exports AS
  SELECT DISTINCT a.export_run_id
  FROM `pacific-plating-282708.sap_integration_v3.v3_unit5_payload_identity` i
  JOIN `pacific-plating-282708.sap_integration_v3.export_archive` a
    USING (order_item, period, charge_id)
  WHERE i.pipeline_run_id = p_pipeline_run_id;

  SET v_export_runs = (SELECT COUNT(*) FROM _exports);
  SET v_manifests = (SELECT COUNT(*)
    FROM `pacific-plating-282708.sap_integration_v3.export_file_manifest` m
    JOIN _exports e USING (export_run_id));

  ASSERT v_unit1 = 1 AS 'exactly one successful UNIT1_COMPLETE is required';
  ASSERT v_units2_5 = 1 AS 'exactly one successful UNITS_2_5_ARCHIVE is required';
  ASSERT v_magnitude_status = 'PASS' AS 'magnitude gate did not pass';
  ASSERT v_gate_blockers = 0 AS 'automation release gate contains blockers';
  ASSERT v_export_runs <= 1 AS 'one pipeline run resolved to multiple export runs';
  ASSERT v_manifests = v_export_runs
    AS 'nonzero export requires exactly one file manifest; healthy zero requires none';

  INSERT INTO `pacific-plating-282708.sap_integration_v3.v3_daily_completeness_metric`
    (pipeline_run_id, metric_group, population_grain, metric_code,
     records, orders, amount_satang, created_at)
  SELECT p_pipeline_run_id, 'UNIT2_OUTCOME', population_grain, outcome,
    records, distinct_orders, amount, CURRENT_TIMESTAMP()
  FROM `pacific-plating-282708.sap_integration_v3.v3_unit2_summary`
  WHERE pipeline_run_id = p_pipeline_run_id
  UNION ALL
  SELECT p_pipeline_run_id, 'NOTIFICATION', 'ITEM', notification_type,
    COUNT(*), COUNT(DISTINCT order_item), SUM(amount), CURRENT_TIMESTAMP()
  FROM `pacific-plating-282708.sap_integration_v3.v3_notification_item`
  WHERE pipeline_run_id = p_pipeline_run_id
  GROUP BY notification_type
  UNION ALL
  SELECT p_pipeline_run_id, 'DELIVERY', 'EVENT', IFNULL(a.delivery_status, 'NOT_ARCHIVED'),
    COUNT(*), COUNT(DISTINCT a.order_item), NULL, CURRENT_TIMESTAMP()
  FROM `pacific-plating-282708.sap_integration_v3.export_archive` a
  JOIN _exports e USING (export_run_id)
  GROUP BY IFNULL(a.delivery_status, 'NOT_ARCHIVED')
  UNION ALL
  SELECT p_pipeline_run_id, 'SAP_RESULT', 'EVENT', IFNULL(a.sap_result_status, 'PENDING_ACK'),
    COUNT(*), COUNT(DISTINCT a.order_item), NULL, CURRENT_TIMESTAMP()
  FROM `pacific-plating-282708.sap_integration_v3.export_archive` a
  JOIN _exports e USING (export_run_id)
  GROUP BY IFNULL(a.sap_result_status, 'PENDING_ACK');

  INSERT INTO `pacific-plating-282708.sap_integration_v3.v3_daily_completeness_evidence`
    (pipeline_run_id, evidence_type, evidence_key, evidence_status, evidence_detail, recorded_at)
  SELECT p_pipeline_run_id, 'PIPELINE_STEP', step, status,
    CONCAT('rows_out=', IFNULL(CAST(rows_out AS STRING), '<NULL>'),
      '; ', IFNULL(error_message, '')), CURRENT_TIMESTAMP()
  FROM `pacific-plating-282708.sap_integration_v3.pipeline_run_log`
  WHERE run_id = p_pipeline_run_id
  UNION ALL
  SELECT p_pipeline_run_id, 'MAGNITUDE', baseline_run_id, status,
    CONCAT('config=', config_id, '; compared=', compared_cells,
      '; breached=', breached_cells), CURRENT_TIMESTAMP()
  FROM `pacific-plating-282708.sap_integration_v3.v3_unit2_magnitude_run`
  WHERE pipeline_run_id = p_pipeline_run_id
  UNION ALL
  SELECT p_pipeline_run_id, 'AUTOMATION_GATE', gate_code,
    IF(blocker_count = 0, 'PASS', 'BLOCK'), gate_detail, CURRENT_TIMESTAMP()
  FROM `pacific-plating-282708.sap_integration_v3.v3_automation_gate_result`
  WHERE pipeline_run_id = p_pipeline_run_id
  UNION ALL
  SELECT p_pipeline_run_id, 'FILE_MANIFEST', m.export_run_id, m.delivery_status,
    CONCAT('archive=', IFNULL(m.archive_uri, '<NULL>'),
      '; production=', IFNULL(m.production_uri, '<NULL>'),
      '; generation=', IFNULL(m.production_generation, '<NULL>'),
      '; rows=', CAST(m.data_row_count AS STRING),
      '; size=', CAST(m.size_bytes AS STRING)), CURRENT_TIMESTAMP()
  FROM `pacific-plating-282708.sap_integration_v3.export_file_manifest` m
  JOIN _exports e USING (export_run_id);

  INSERT INTO `pacific-plating-282708.sap_integration_v3.v3_daily_completeness_run`
    (pipeline_run_id, snapshot_status, alert_delivery_status, unit1_complete_count,
     units2_5_complete_count, magnitude_status, gate_blocker_count, notification_rows,
     export_run_count, manifest_count, created_at)
  VALUES (p_pipeline_run_id, 'READY_TO_ALERT', 'PENDING', v_unit1, v_units2_5,
    v_magnitude_status, v_gate_blockers, v_notification_rows, v_export_runs, v_manifests,
    CURRENT_TIMESTAMP());
END;

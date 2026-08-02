-- SOURCE ONLY / Class A. No export, GCS write, scheduler mutation, or SAP mutation.
-- This is the single fail-closed boundary between evaluated V3 state and Unit 5 file creation.

CREATE TABLE IF NOT EXISTS `pacific-plating-282708.sap_integration_v3.v3_automation_gate_result` (
  pipeline_run_id STRING NOT NULL,
  gate_code STRING NOT NULL,
  blocker_count INT64 NOT NULL,
  gate_detail STRING NOT NULL,
  evaluated_at TIMESTAMP NOT NULL
)
PARTITION BY DATE(evaluated_at)
CLUSTER BY pipeline_run_id, gate_code;

CREATE OR REPLACE PROCEDURE `pacific-plating-282708.sap_integration_v3.sp_evaluate_v3_automation_gate`(
  p_pipeline_run_id STRING
)
BEGIN
  DECLARE v_blockers INT64;

  ASSERT NULLIF(TRIM(p_pipeline_run_id),'') IS NOT NULL
    AS 'Automation gate requires a non-empty pipeline_run_id';

  DELETE FROM `pacific-plating-282708.sap_integration_v3.v3_automation_gate_result`
  WHERE pipeline_run_id=p_pipeline_run_id;

  INSERT INTO `pacific-plating-282708.sap_integration_v3.v3_automation_gate_result`
  SELECT p_pipeline_run_id,'UNIT1_COMPLETE',
    ABS(1-COUNTIF(step='UNIT1_COMPLETE' AND status='SUCCESS')),
    'Exactly one successful Unit 1 completion is required',CURRENT_TIMESTAMP()
  FROM `pacific-plating-282708.sap_integration_v3.pipeline_run_log`
  WHERE run_id=p_pipeline_run_id
  UNION ALL
  SELECT p_pipeline_run_id,'UNIT2_EVALUATED',IF(COUNT(*)>0,0,1),
    'Unit 2 summary must exist for this run',CURRENT_TIMESTAMP()
  FROM `pacific-plating-282708.sap_integration_v3.v3_unit2_summary`
  WHERE pipeline_run_id=p_pipeline_run_id
  UNION ALL
  SELECT p_pipeline_run_id,'UNIT2_UNKNOWN_NOTIFICATION_COVERAGE',
    IF(n.pipeline_run_id IS NULL,1,ABS(u.unknown_rows-n.unknown_rows)),
    'UNKNOWN rows are quarantined, but every row must be copied to the notification detail with order_item',
    CURRENT_TIMESTAMP()
  FROM (SELECT IFNULL(SUM(records),0) AS unknown_rows
    FROM `pacific-plating-282708.sap_integration_v3.v3_unit2_summary`
    WHERE pipeline_run_id=p_pipeline_run_id AND outcome='HELD_CLASSIFICATION_UNKNOWN') u
  LEFT JOIN `pacific-plating-282708.sap_integration_v3.v3_notification_run_summary` n
    ON n.pipeline_run_id=p_pipeline_run_id
  UNION ALL
  SELECT p_pipeline_run_id,'UNIT3_EVALUATED',IF(COUNT(*)=1,0,1),
    'Unit 3 mapping evaluation must produce exactly one run summary',CURRENT_TIMESTAMP()
  FROM `pacific-plating-282708.sap_integration_v3.v3_unit3_run_summary`
  WHERE pipeline_run_id=p_pipeline_run_id
  UNION ALL
  SELECT p_pipeline_run_id,'UNIT3_MAPPING_HOLD_NOTIFICATION_COVERAGE',
    IF(n.pipeline_run_id IS NULL,1,ABS(u.held_events-n.mapping_hold_rows)),
    'Held mapping events are skipped; every hold reason must be copied to notification detail',
    CURRENT_TIMESTAMP()
  FROM (SELECT IFNULL(MAX(held_events),0) held_events
    FROM `pacific-plating-282708.sap_integration_v3.v3_unit3_run_summary`
    WHERE pipeline_run_id=p_pipeline_run_id) u
  LEFT JOIN `pacific-plating-282708.sap_integration_v3.v3_notification_run_summary` n
    ON n.pipeline_run_id=p_pipeline_run_id
  UNION ALL
  SELECT p_pipeline_run_id,'UNIT4_OPEN_PERIOD',ABS(1-COUNTIF(status='OPEN')),
    'Exactly one accounting period must be OPEN',CURRENT_TIMESTAMP()
  FROM `pacific-plating-282708.sap_integration_v3.sap_period_state`;

  SET v_blockers=(SELECT SUM(blocker_count)
    FROM `pacific-plating-282708.sap_integration_v3.v3_automation_gate_result`
    WHERE pipeline_run_id=p_pipeline_run_id);

  ASSERT v_blockers=0
    AS 'V3 automation release blocked; inspect v3_automation_gate_result before Unit 5';
END;

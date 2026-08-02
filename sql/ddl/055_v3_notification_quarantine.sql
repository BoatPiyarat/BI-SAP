-- SOURCE ONLY / Class A. Builds auditable notification detail; it sends no email and writes no GCS.
-- Boat 2026-08-02: incomplete/UNKNOWN rows are skipped from delivery and listed by order_item.

CREATE TABLE IF NOT EXISTS `pacific-plating-282708.sap_integration_v3.v3_notification_item` (
  pipeline_run_id STRING NOT NULL,
  notification_type STRING NOT NULL,
  population_grain STRING NOT NULL,
  order_item STRING,
  order_id STRING,
  period INT64,
  charge_id STRING,
  amount INT64,
  reason_code STRING NOT NULL,
  reason_detail STRING NOT NULL,
  created_at TIMESTAMP NOT NULL
)
PARTITION BY DATE(created_at)
CLUSTER BY pipeline_run_id, notification_type, order_item;

CREATE TABLE IF NOT EXISTS `pacific-plating-282708.sap_integration_v3.v3_notification_run_summary` (
  pipeline_run_id STRING NOT NULL,
  unknown_rows INT64 NOT NULL,
  mapping_hold_rows INT64 NOT NULL,
  notification_rows INT64 NOT NULL,
  created_at TIMESTAMP NOT NULL
)
PARTITION BY DATE(created_at)
CLUSTER BY pipeline_run_id;

CREATE OR REPLACE PROCEDURE `pacific-plating-282708.sap_integration_v3.sp_build_v3_notification_quarantine`(
  p_pipeline_run_id STRING
)
BEGIN
  ASSERT NULLIF(TRIM(p_pipeline_run_id),'') IS NOT NULL
    AS 'Notification quarantine requires a non-empty pipeline_run_id';
  ASSERT (SELECT COUNT(*) FROM `pacific-plating-282708.sap_integration_v3.v3_unit2_summary`
    WHERE pipeline_run_id=p_pipeline_run_id)>0
    AS 'Notification quarantine requires Unit 2 output for the same run';
  ASSERT (SELECT COUNT(*) FROM `pacific-plating-282708.sap_integration_v3.v3_unit3_run_summary`
    WHERE pipeline_run_id=p_pipeline_run_id)=1
    AS 'Notification quarantine requires exactly one Unit 3 summary for the same run';

  DELETE FROM `pacific-plating-282708.sap_integration_v3.v3_notification_item`
  WHERE pipeline_run_id=p_pipeline_run_id;

  INSERT INTO `pacific-plating-282708.sap_integration_v3.v3_notification_item`
  SELECT pipeline_run_id,'CLASSIFICATION_UNKNOWN','PAYMENT_EVENT',order_item,order_id,period,
    charge_id,charge_amount,'HELD_CLASSIFICATION_UNKNOWN',outcome_reason,CURRENT_TIMESTAMP()
  FROM `pacific-plating-282708.sap_integration_v3.v3_unit2_event_shadow`
  WHERE pipeline_run_id=p_pipeline_run_id AND outcome='HELD_CLASSIFICATION_UNKNOWN'
  UNION ALL
  SELECT pipeline_run_id,'CLASSIFICATION_UNKNOWN','SCHEDULE',order_item,order_id,period,
    NULL,NULL,'HELD_CLASSIFICATION_UNKNOWN',outcome_reason,CURRENT_TIMESTAMP()
  FROM `pacific-plating-282708.sap_integration_v3.v3_unit2_schedule_shadow`
  WHERE pipeline_run_id=p_pipeline_run_id AND outcome='HELD_CLASSIFICATION_UNKNOWN'
  UNION ALL
  SELECT pipeline_run_id,'MAPPING_HOLD',population_grain,order_item,order_id,period,charge_id,
    amount,hold_code,hold_reason,CURRENT_TIMESTAMP()
  FROM `pacific-plating-282708.sap_integration_v3.v3_unit3_mapping_hold`
  WHERE pipeline_run_id=p_pipeline_run_id;

  ASSERT (SELECT COUNT(*) FROM `pacific-plating-282708.sap_integration_v3.v3_notification_item`
    WHERE pipeline_run_id=p_pipeline_run_id AND order_item IS NULL)=0
    AS 'Every V3 notification item must identify order_item';

  DELETE FROM `pacific-plating-282708.sap_integration_v3.v3_notification_run_summary`
  WHERE pipeline_run_id=p_pipeline_run_id;
  INSERT INTO `pacific-plating-282708.sap_integration_v3.v3_notification_run_summary`
  SELECT p_pipeline_run_id,
    COUNTIF(notification_type='CLASSIFICATION_UNKNOWN'),
    COUNT(DISTINCT IF(notification_type='MAPPING_HOLD',
      TO_JSON_STRING(STRUCT(order_item,period,charge_id)),NULL)),
    COUNT(*),CURRENT_TIMESTAMP()
  FROM `pacific-plating-282708.sap_integration_v3.v3_notification_item`
  WHERE pipeline_run_id=p_pipeline_run_id;
END;

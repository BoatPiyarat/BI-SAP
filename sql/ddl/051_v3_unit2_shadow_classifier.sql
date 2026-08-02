-- SOURCE ONLY / Class A. Shadow classification only: no export, GCS write, or SAP mutation.
-- Payment events and schedules are different populations and conserve independently.

CREATE TABLE IF NOT EXISTS `pacific-plating-282708.sap_integration_v3.v3_unit2_event_shadow` (
  pipeline_run_id STRING NOT NULL, order_item STRING, order_id STRING, period INT64,
  charge_id STRING NOT NULL, invoice_no STRING, charge_amount INT64, charge_time TIMESTAMP,
  flow STRING, outcome STRING NOT NULL, outcome_reason STRING NOT NULL,
  computed_at TIMESTAMP NOT NULL
)
PARTITION BY DATE(computed_at) CLUSTER BY pipeline_run_id, outcome, order_item;

CREATE TABLE IF NOT EXISTS `pacific-plating-282708.sap_integration_v3.v3_unit2_schedule_shadow` (
  pipeline_run_id STRING NOT NULL, order_item STRING NOT NULL, order_id STRING, period INT64 NOT NULL,
  total_periods INT64, flow STRING, expected_status STRING, expected_invoice_no STRING,
  sap_status STRING, sap_invoice_no STRING, outcome STRING NOT NULL,
  outcome_reason STRING NOT NULL, computed_at TIMESTAMP NOT NULL
)
PARTITION BY DATE(computed_at) CLUSTER BY pipeline_run_id, outcome, order_item;

CREATE TABLE IF NOT EXISTS `pacific-plating-282708.sap_integration_v3.v3_unit2_summary` (
  pipeline_run_id STRING NOT NULL, population_grain STRING NOT NULL, outcome STRING NOT NULL,
  records INT64 NOT NULL, distinct_orders INT64 NOT NULL, amount INT64,
  computed_at TIMESTAMP NOT NULL
)
PARTITION BY DATE(computed_at) CLUSTER BY pipeline_run_id, population_grain, outcome;

CREATE OR REPLACE PROCEDURE `pacific-plating-282708.sap_integration_v3.sp_build_v3_unit2_shadow`(
  p_pipeline_run_id STRING
)
BEGIN
  DECLARE v_open_period_start DATE;
  DECLARE v_event_n INT64;
  DECLARE v_event_amount INT64;
  DECLARE v_schedule_n INT64;

  ASSERT NULLIF(TRIM(p_pipeline_run_id), '') IS NOT NULL
    AS 'Unit 2 requires a non-empty pipeline_run_id';
  ASSERT (SELECT COUNT(*) FROM `pacific-plating-282708.sap_integration_v3.pipeline_run_log`
    WHERE run_id=p_pipeline_run_id AND step='UNIT1_COMPLETE' AND status='SUCCESS')=1
    AS 'Unit 2 requires exactly one UNIT1_COMPLETE for the same run';
  ASSERT (SELECT COUNT(*) FROM `pacific-plating-282708.sap_integration_v3.sap_period_lock`
    WHERE lock_datetime>CURRENT_TIMESTAMP())=1
    AS 'Unit 2 requires exactly one active period';
  SET v_open_period_start=(SELECT open_period_start
    FROM `pacific-plating-282708.sap_integration_v3.sap_period_lock`
    WHERE lock_datetime>CURRENT_TIMESTAMP());

  CREATE TEMP TABLE _excluded AS
  SELECT order_item,period,STRING_AGG(DISTINCT rule_code,',' ORDER BY rule_code) rules
  FROM `pacific-plating-282708.sap_integration_v3.sap_excluded_records` GROUP BY 1,2;
  CREATE TEMP TABLE _invalid AS
  SELECT order_item,period,STRING_AGG(DISTINCT check_name,',' ORDER BY check_name) rules
  FROM `pacific-plating-282708.sap_integration_v3.sap_validation_error` GROUP BY 1,2;
  CREATE TEMP TABLE _archive AS SELECT * EXCEPT(rn) FROM (
    SELECT order_item,period,charge_id,delivery_status,sap_result_status,acknowledged_at,
      ROW_NUMBER() OVER(PARTITION BY order_item,period,charge_id
        ORDER BY exported_at DESC,export_run_id DESC) rn
    FROM `pacific-plating-282708.sap_integration_v3.export_archive`
  ) WHERE rn=1;

  -- Schedule grain includes Pending rows and excluded rows; it carries no amount equation.
  CREATE TEMP TABLE _schedule AS
  SELECT s.order_item,s.order_id,s.period,s.total_periods,s.flow,
    e.expected_status,e.expected_invoice_no,m.TransactionStatus sap_status,m.U_InvoiceNo sap_invoice_no,
    d.is_cancelled_effective,x.rules exclusion_rules,v.rules validation_rules,
    a.delivery_status,a.sap_result_status,a.acknowledged_at
  FROM `pacific-plating-282708.sap_integration_v3.stg_schedule` s
  LEFT JOIN `pacific-plating-282708.sap_integration_v3.expected_state` e
    USING(order_item,order_id,period,total_periods,flow)
  LEFT JOIN `pacific-plating-282708.sap_integration_v3.sap_mirror_state` m
    ON m.U_OrderItem=s.order_item AND m.U_Period=s.period
  LEFT JOIN `pacific-plating-282708.sap_integration_v3.stg_order_dim` d USING(order_item,order_id)
  LEFT JOIN _excluded x USING(order_item,period)
  LEFT JOIN _invalid v USING(order_item,period)
  LEFT JOIN (SELECT * EXCEPT(rn) FROM (
    SELECT order_item,period,delivery_status,sap_result_status,acknowledged_at,
      ROW_NUMBER() OVER(PARTITION BY order_item,period ORDER BY exported_at DESC,export_run_id DESC) rn
    FROM `pacific-plating-282708.sap_integration_v3.export_archive`) WHERE rn=1) a
    USING(order_item,period);

  CREATE TEMP TABLE _schedule_out AS SELECT *,
    CASE
      WHEN exclusion_rules IS NOT NULL THEN 'EXCLUDED_RULE'
      WHEN validation_rules IS NOT NULL THEN 'HELD_VALIDATION'
      WHEN is_cancelled_effective AND sap_status IN('Paid','Pending') THEN 'READY_CANCEL_CHANGE'
      WHEN is_cancelled_effective AND sap_status IS NULL THEN 'HELD_VALIDATION'
      WHEN sap_status IN('Paid','Cancelled','Cancelled (Change order / Rejected)')
       AND expected_invoice_no IS NOT NULL
       AND IFNULL(sap_invoice_no,'')!=IFNULL(expected_invoice_no,'') THEN 'HELD_VALIDATION'
      WHEN sap_result_status IN('REJECTED','PARTIAL_REJECT') AND acknowledged_at IS NULL
        THEN 'REJECTED_BY_SAP'
      WHEN expected_status=sap_status AND (expected_status='Pending'
        OR IFNULL(expected_invoice_no,'')=IFNULL(sap_invoice_no,'')) THEN 'ACKNOWLEDGED'
      WHEN sap_result_status='ACKNOWLEDGED' AND acknowledged_at IS NOT NULL THEN 'ACKNOWLEDGED'
      WHEN delivery_status IN('DELIVERED','PICKED_UP') AND sap_result_status IS NULL THEN 'PENDING_ACK'
      WHEN expected_status IS NOT NULL AND sap_status IS NULL THEN 'READY_CREATE_OR_PAYMENT'
      WHEN expected_status='Paid' AND sap_status='Pending' THEN 'READY_CREATE_OR_PAYMENT'
      ELSE 'HELD_CLASSIFICATION_UNKNOWN' END outcome,
    CASE
      WHEN exclusion_rules IS NOT NULL THEN CONCAT('rules=',exclusion_rules)
      WHEN validation_rules IS NOT NULL THEN CONCAT('validations=',validation_rules)
      WHEN is_cancelled_effective AND sap_status IN('Paid','Pending') THEN 'existing SAP row permits cancel/change'
      WHEN is_cancelled_effective AND sap_status IS NULL THEN 'cancel/change has no existing SAP row'
      WHEN sap_status IN('Paid','Cancelled','Cancelled (Change order / Rejected)')
       AND expected_invoice_no IS NOT NULL AND IFNULL(sap_invoice_no,'')!=IFNULL(expected_invoice_no,'')
        THEN 'immutable InvoiceNo differs; human action'
      WHEN sap_result_status IN('REJECTED','PARTIAL_REJECT') THEN CONCAT('SAP result=',sap_result_status)
      WHEN expected_status=sap_status THEN 'current SAP state matches expected schedule'
      WHEN sap_result_status='ACKNOWLEDGED' THEN 'row result acknowledged'
      WHEN delivery_status IN('DELIVERED','PICKED_UP') THEN 'delivered without terminal row result'
      WHEN expected_status IS NOT NULL AND sap_status IS NULL THEN 'expected schedule absent from SAP'
      WHEN expected_status='Paid' AND sap_status='Pending' THEN 'payment update required'
      ELSE 'no reviewed schedule rule matched' END outcome_reason
  FROM _schedule;

  -- Event grain keeps every in-scope successful charge, including top-ups in the same period.
  CREATE TEMP TABLE _event AS
  WITH sap_invoice AS (
    SELECT * EXCEPT(rn) FROM (
      SELECT U_OrderItem,U_Period,U_InvoiceNo,TransactionStatus,DocEntry,
        ROW_NUMBER() OVER(PARTITION BY U_OrderItem,U_Period,U_InvoiceNo
          ORDER BY UpdateDate DESC,UpdateTime DESC,DocEntry DESC) rn
      FROM `pacific-plating-282708.sap_integration_v3.sap_mirror_doc`)
  )
  SELECT p.order_item,p.order_id,p.period,p.charge_id,
    `pacific-plating-282708.sap_integration_v3.fn_invoice_no`(p.third_party_id) invoice_no,
    p.amount charge_amount,p.charge_time,s.flow,x.rules exclusion_rules,v.rules validation_rules,
    ms.TransactionStatus schedule_sap_status,ms.U_InvoiceNo schedule_sap_invoice_no,
    mi.DocEntry matching_docentry,mi.TransactionStatus matching_invoice_status,
    a.delivery_status,a.sap_result_status,a.acknowledged_at
  FROM `pacific-plating-282708.sap_integration_v3.stg_payment_events` p
  LEFT JOIN `pacific-plating-282708.sap_integration_v3.stg_schedule` s USING(order_item,order_id,period)
  LEFT JOIN `pacific-plating-282708.sap_integration_v3.expected_state` e
    USING(order_item,order_id,period,charge_id)
  LEFT JOIN `pacific-plating-282708.sap_integration_v3.sap_mirror_state` ms
    ON ms.U_OrderItem=p.order_item AND ms.U_Period=p.period
  LEFT JOIN sap_invoice mi ON mi.U_OrderItem=p.order_item AND mi.U_Period=p.period
    AND IFNULL(mi.U_InvoiceNo,'')=IFNULL(`pacific-plating-282708.sap_integration_v3.fn_invoice_no`(p.third_party_id),'')
  LEFT JOIN _excluded x USING(order_item,period)
  LEFT JOIN _invalid v USING(order_item,period)
  LEFT JOIN _archive a USING(order_item,period,charge_id)
  WHERE e.charge_id IS NOT NULL OR a.charge_id IS NOT NULL OR DATE(p.charge_time)>=v_open_period_start;

  CREATE TEMP TABLE _event_out AS SELECT *,
    CASE
      WHEN exclusion_rules IS NOT NULL THEN 'EXCLUDED_RULE'
      WHEN validation_rules IS NOT NULL OR invoice_no IS NULL OR order_item IS NULL OR period IS NULL
        THEN 'HELD_VALIDATION'
      WHEN sap_result_status IN('REJECTED','PARTIAL_REJECT') AND acknowledged_at IS NULL
        THEN 'REJECTED_BY_SAP'
      WHEN matching_docentry IS NOT NULL AND matching_invoice_status='Paid' THEN 'ACKNOWLEDGED'
      WHEN sap_result_status='ACKNOWLEDGED' AND acknowledged_at IS NOT NULL THEN 'ACKNOWLEDGED'
      WHEN delivery_status IN('DELIVERED','PICKED_UP') AND sap_result_status IS NULL THEN 'PENDING_ACK'
      WHEN schedule_sap_status IN('Paid','Cancelled','Cancelled (Change order / Rejected)')
       AND IFNULL(schedule_sap_invoice_no,'')!=IFNULL(invoice_no,'') THEN 'HELD_VALIDATION'
      WHEN flow IS NOT NULL THEN 'READY_CREATE_OR_PAYMENT'
      ELSE 'HELD_CLASSIFICATION_UNKNOWN' END outcome,
    CASE
      WHEN exclusion_rules IS NOT NULL THEN CONCAT('rules=',exclusion_rules)
      WHEN validation_rules IS NOT NULL THEN CONCAT('validations=',validation_rules)
      WHEN invoice_no IS NULL OR order_item IS NULL OR period IS NULL THEN 'event identity incomplete'
      WHEN sap_result_status IN('REJECTED','PARTIAL_REJECT') THEN CONCAT('SAP result=',sap_result_status)
      WHEN matching_docentry IS NOT NULL THEN 'matching LIVE DocEntry and InvoiceNo found'
      WHEN sap_result_status='ACKNOWLEDGED' THEN 'row result acknowledged'
      WHEN delivery_status IN('DELIVERED','PICKED_UP') THEN 'delivered without terminal row result'
      WHEN schedule_sap_status IN('Paid','Cancelled','Cancelled (Change order / Rejected)')
       AND IFNULL(schedule_sap_invoice_no,'')!=IFNULL(invoice_no,'')
        THEN 'top-up/different InvoiceNo would mutate immutable LIVE state; hold'
      WHEN flow IS NOT NULL THEN 'qualified event is ready'
      ELSE 'event has no schedule route' END outcome_reason
  FROM _event;

  SET v_event_n=(SELECT COUNT(*) FROM _event);
  SET v_event_amount=(SELECT IFNULL(SUM(charge_amount),0) FROM _event);
  SET v_schedule_n=(SELECT COUNT(*) FROM _schedule);
  ASSERT v_event_n=(SELECT COUNT(*) FROM _event_out) AS 'event record conservation failed';
  ASSERT v_event_amount=(SELECT IFNULL(SUM(charge_amount),0) FROM _event_out)
    AS 'event amount conservation failed';
  ASSERT v_schedule_n=(SELECT COUNT(*) FROM _schedule_out) AS 'schedule record conservation failed';
  ASSERT (SELECT COUNT(*) FROM _event_out WHERE outcome IS NULL)=0 AS 'NULL event outcome';
  ASSERT (SELECT COUNT(*) FROM _schedule_out WHERE outcome IS NULL)=0 AS 'NULL schedule outcome';

  DELETE FROM `pacific-plating-282708.sap_integration_v3.v3_unit2_event_shadow`
    WHERE pipeline_run_id=p_pipeline_run_id;
  INSERT INTO `pacific-plating-282708.sap_integration_v3.v3_unit2_event_shadow`
  SELECT p_pipeline_run_id,order_item,order_id,period,charge_id,invoice_no,charge_amount,charge_time,
    flow,outcome,outcome_reason,CURRENT_TIMESTAMP() FROM _event_out;
  DELETE FROM `pacific-plating-282708.sap_integration_v3.v3_unit2_schedule_shadow`
    WHERE pipeline_run_id=p_pipeline_run_id;
  INSERT INTO `pacific-plating-282708.sap_integration_v3.v3_unit2_schedule_shadow`
  SELECT p_pipeline_run_id,order_item,order_id,period,total_periods,flow,expected_status,
    expected_invoice_no,sap_status,sap_invoice_no,outcome,outcome_reason,CURRENT_TIMESTAMP()
  FROM _schedule_out;
  DELETE FROM `pacific-plating-282708.sap_integration_v3.v3_unit2_summary`
    WHERE pipeline_run_id=p_pipeline_run_id;
  INSERT INTO `pacific-plating-282708.sap_integration_v3.v3_unit2_summary`
  SELECT p_pipeline_run_id,'PAYMENT_EVENT',outcome,COUNT(*),COUNT(DISTINCT order_id),
    SUM(charge_amount),CURRENT_TIMESTAMP() FROM _event_out GROUP BY outcome
  UNION ALL SELECT p_pipeline_run_id,'SCHEDULE',outcome,COUNT(*),COUNT(DISTINCT order_id),NULL,
    CURRENT_TIMESTAMP() FROM _schedule_out GROUP BY outcome;
END;

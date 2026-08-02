-- SOURCE ONLY / Class A. Unit 3 closed, effective-dated mapping registries and coverage holds.
-- This file creates no mapping values. Registry rows require separately reviewed SAP-success
-- evidence and Boat approval; absence/ambiguity fails closed.

CREATE TABLE IF NOT EXISTS `pacific-plating-282708.sap_integration_v3.insurance_group_registry` (
  mapping_id STRING NOT NULL,
  source_insurance_group STRING NOT NULL,
  product_scope STRING NOT NULL,
  business_unit STRING NOT NULL,
  sap_insurance_group STRING NOT NULL,
  effective_start DATE NOT NULL,
  effective_end DATE,
  approval_state STRING NOT NULL,
  evidence_type STRING NOT NULL,
  evidence_reference STRING NOT NULL,
  approved_by STRING,
  approved_at TIMESTAMP,
  created_at TIMESTAMP NOT NULL,
  retired_at TIMESTAMP,
  reason STRING NOT NULL
)
CLUSTER BY source_insurance_group, product_scope, business_unit, approval_state;

CREATE TABLE IF NOT EXISTS `pacific-plating-282708.sap_integration_v3.payment_mapping_registry` (
  mapping_id STRING NOT NULL,
  flow STRING NOT NULL,
  product_scope STRING NOT NULL,
  is_credit_shell BOOL NOT NULL,
  payment_source_type STRING NOT NULL,
  payment_method_source STRING NOT NULL,
  payment_channel_source STRING NOT NULL,
  sap_payment_method STRING NOT NULL,
  sap_payment_channel STRING NOT NULL,
  effective_start DATE NOT NULL,
  effective_end DATE,
  approval_state STRING NOT NULL,
  evidence_type STRING NOT NULL,
  evidence_reference STRING NOT NULL,
  approved_by STRING,
  approved_at TIMESTAMP,
  created_at TIMESTAMP NOT NULL,
  retired_at TIMESTAMP,
  reason STRING NOT NULL
)
CLUSTER BY flow, product_scope, is_credit_shell, payment_source_type;

CREATE TABLE IF NOT EXISTS `pacific-plating-282708.sap_integration_v3.v3_unit3_mapping_hold` (
  pipeline_run_id STRING NOT NULL,
  population_grain STRING NOT NULL,
  order_item STRING,
  order_id STRING,
  period INT64,
  charge_id STRING,
  amount INT64,
  raw_payment_date DATE,
  flow STRING,
  source_insurance_group STRING,
  product_scope STRING,
  is_credit_shell BOOL,
  payment_source_type STRING,
  payment_method_source STRING,
  payment_channel_source STRING,
  hold_code STRING NOT NULL,
  hold_reason STRING NOT NULL,
  computed_at TIMESTAMP NOT NULL
)
PARTITION BY DATE(computed_at)
CLUSTER BY pipeline_run_id, hold_code, order_item;

CREATE TABLE IF NOT EXISTS `pacific-plating-282708.sap_integration_v3.v3_unit3_run_summary` (
  pipeline_run_id STRING NOT NULL,
  ready_events INT64 NOT NULL,
  held_events INT64 NOT NULL,
  releasable_events INT64 NOT NULL,
  evaluated_at TIMESTAMP NOT NULL
)
PARTITION BY DATE(evaluated_at)
CLUSTER BY pipeline_run_id;

CREATE OR REPLACE PROCEDURE `pacific-plating-282708.sap_integration_v3.sp_build_v3_unit3_mapping_holds`(
  p_pipeline_run_id STRING
)
BEGIN
  ASSERT NULLIF(TRIM(p_pipeline_run_id),'') IS NOT NULL
    AS 'Unit 3 requires a non-empty pipeline_run_id';
  ASSERT (SELECT COUNT(*) FROM `pacific-plating-282708.sap_integration_v3.v3_unit2_summary`
    WHERE pipeline_run_id=p_pipeline_run_id)>0
    AS 'Unit 3 requires Unit 2 output for the same run';
  ASSERT (SELECT COUNT(*) FROM `pacific-plating-282708.sap_integration_v3.insurance_group_registry`
    WHERE approval_state NOT IN('DRAFT','APPROVED','RETIRED'))=0
    AS 'Invalid InsuranceGroup registry approval_state';
  ASSERT (SELECT COUNT(*) FROM `pacific-plating-282708.sap_integration_v3.payment_mapping_registry`
    WHERE approval_state NOT IN('DRAFT','APPROVED','RETIRED'))=0
    AS 'Invalid payment registry approval_state';
  ASSERT (SELECT COUNT(*) FROM (
    SELECT mapping_id FROM `pacific-plating-282708.sap_integration_v3.insurance_group_registry`
    GROUP BY mapping_id HAVING COUNT(*)!=1))=0 AS 'Duplicate InsuranceGroup mapping_id';
  ASSERT (SELECT COUNT(*) FROM (
    SELECT mapping_id FROM `pacific-plating-282708.sap_integration_v3.payment_mapping_registry`
    GROUP BY mapping_id HAVING COUNT(*)!=1))=0 AS 'Duplicate payment mapping_id';
  ASSERT (SELECT COUNT(*) FROM `pacific-plating-282708.sap_integration_v3.insurance_group_registry`
    WHERE effective_end IS NOT NULL AND effective_end<=effective_start)=0
    AS 'Invalid InsuranceGroup effective window';
  ASSERT (SELECT COUNT(*) FROM `pacific-plating-282708.sap_integration_v3.payment_mapping_registry`
    WHERE effective_end IS NOT NULL AND effective_end<=effective_start)=0
    AS 'Invalid payment effective window';
  ASSERT (SELECT COUNT(*) FROM `pacific-plating-282708.sap_integration_v3.insurance_group_registry`
    WHERE approval_state='APPROVED'
      AND (approved_by IS NULL OR approved_at IS NULL OR NULLIF(TRIM(evidence_reference),'') IS NULL))=0
    AS 'Approved InsuranceGroup mapping lacks approval/evidence';
  ASSERT (SELECT COUNT(*) FROM `pacific-plating-282708.sap_integration_v3.payment_mapping_registry`
    WHERE approval_state='APPROVED'
      AND (approved_by IS NULL OR approved_at IS NULL OR NULLIF(TRIM(evidence_reference),'') IS NULL))=0
    AS 'Approved payment mapping lacks approval/evidence';
  ASSERT (SELECT COUNT(*) FROM (
    SELECT a.mapping_id
    FROM `pacific-plating-282708.sap_integration_v3.insurance_group_registry` a
    JOIN `pacific-plating-282708.sap_integration_v3.insurance_group_registry` b
      ON a.mapping_id<b.mapping_id
     AND a.source_insurance_group=b.source_insurance_group
     AND a.product_scope=b.product_scope AND a.business_unit=b.business_unit
     AND a.approval_state='APPROVED' AND b.approval_state='APPROVED'
     AND a.effective_start<IFNULL(b.effective_end,DATE '9999-12-31')
     AND b.effective_start<IFNULL(a.effective_end,DATE '9999-12-31')))=0
    AS 'Overlapping approved InsuranceGroup mappings';
  ASSERT (SELECT COUNT(*) FROM (
    SELECT a.mapping_id
    FROM `pacific-plating-282708.sap_integration_v3.payment_mapping_registry` a
    JOIN `pacific-plating-282708.sap_integration_v3.payment_mapping_registry` b
      ON a.mapping_id<b.mapping_id AND a.flow=b.flow
     AND a.product_scope=b.product_scope AND a.is_credit_shell=b.is_credit_shell
     AND a.payment_source_type=b.payment_source_type
     AND a.payment_method_source=b.payment_method_source
     AND a.payment_channel_source=b.payment_channel_source
     AND a.approval_state='APPROVED' AND b.approval_state='APPROVED'
     AND a.effective_start<IFNULL(b.effective_end,DATE '9999-12-31')
     AND b.effective_start<IFNULL(a.effective_end,DATE '9999-12-31')))=0
    AS 'Overlapping approved payment mappings';

  DELETE FROM `pacific-plating-282708.sap_integration_v3.v3_unit3_mapping_hold`
  WHERE pipeline_run_id=p_pipeline_run_id;

  INSERT INTO `pacific-plating-282708.sap_integration_v3.v3_unit3_mapping_hold`
  WITH nonmotor_category AS (
    SELECT human_id,
      COUNT(DISTINCT product_category) AS category_count,
      STRING_AGG(DISTINCT IFNULL(product_category,'<NULL>'),',' ORDER BY IFNULL(product_category,'<NULL>'))
        AS category_values
    FROM `pacific-plating-282708.analytics_reports.non_motor_report_order_for_accounting`
    GROUP BY human_id
  ), ready AS (
    SELECT u.pipeline_run_id,u.order_item,u.order_id,u.period,u.charge_id,u.charge_amount,
      DATE(p.charge_time) raw_payment_date,u.flow,
      IF(d.insurance_group_source='products/car-insurance',d.insurance_group_source,
        IF(n.category_count=1,n.category_values,
          CONCAT('__AMBIGUOUS_OR_MISSING__:',IFNULL(n.category_values,'<NULL>'))))
        AS insurance_group_source,
      p.payment_option,p.payment_method_source,p.payment_channel_source,
      IF(d.insurance_group_source='products/car-insurance','MOTOR','NONMOTOR') product_scope,
      co.current_human_id IS NOT NULL is_credit_shell,
      IF(u.flow='ONETIME','RCB','RCL') business_unit
    FROM `pacific-plating-282708.sap_integration_v3.v3_unit2_event_shadow` u
    JOIN `pacific-plating-282708.sap_integration_v3.stg_payment_events` p USING(charge_id)
    LEFT JOIN `pacific-plating-282708.sap_integration_v3.stg_order_dim` d
      USING(order_item,order_id)
    LEFT JOIN nonmotor_category n ON n.human_id=u.order_id
    LEFT JOIN (SELECT DISTINCT current_human_id
      FROM `pacific-plating-282708.careos.cancelled_change_orders`) co
      ON co.current_human_id=u.order_id
    WHERE u.pipeline_run_id=p_pipeline_run_id AND u.outcome='READY_CREATE_OR_PAYMENT'
  ), classified AS (
    SELECT r.*,
      (SELECT COUNT(*) FROM `pacific-plating-282708.sap_integration_v3.insurance_group_registry` g
       WHERE g.approval_state='APPROVED'
         AND g.source_insurance_group=r.insurance_group_source
         AND g.product_scope=IF(r.insurance_group_source='products/car-insurance','MOTOR','NONMOTOR')
         AND g.business_unit=r.business_unit
         AND r.raw_payment_date>=g.effective_start
         AND r.raw_payment_date<IFNULL(g.effective_end,DATE '9999-12-31')) insurance_matches,
      (SELECT COUNT(*) FROM `pacific-plating-282708.sap_integration_v3.payment_mapping_registry` m
       WHERE m.approval_state='APPROVED' AND m.flow=r.flow
         AND m.product_scope=r.product_scope AND m.is_credit_shell=r.is_credit_shell
         AND m.payment_source_type=IFNULL(r.payment_option,'')
         AND m.payment_method_source=IFNULL(r.payment_method_source,'')
         AND m.payment_channel_source=IFNULL(r.payment_channel_source,'')
         AND r.raw_payment_date>=m.effective_start
         AND r.raw_payment_date<IFNULL(m.effective_end,DATE '9999-12-31')) payment_matches
    FROM ready r
  )
  SELECT pipeline_run_id,'PAYMENT_EVENT',order_item,order_id,period,charge_id,charge_amount,
    raw_payment_date,flow,insurance_group_source,product_scope,is_credit_shell,
    payment_option,payment_method_source,
    payment_channel_source,'HOLD_INSURANCE_GROUP_MAPPING',
    'NonMotor or unknown product lacks exactly one approved effective InsuranceGroup mapping',
    CURRENT_TIMESTAMP()
  FROM classified
  WHERE raw_payment_date>=DATE '2026-08-01'
    AND IFNULL(insurance_group_source,'')!='products/car-insurance'
    AND insurance_matches!=1
  UNION ALL
  SELECT pipeline_run_id,'PAYMENT_EVENT',order_item,order_id,period,charge_id,charge_amount,
    raw_payment_date,flow,insurance_group_source,product_scope,is_credit_shell,
    payment_option,payment_method_source,
    payment_channel_source,'HOLD_PAYMENT_MAPPING',
    'Payment source tuple lacks exactly one approved effective SAP-success mapping',
    CURRENT_TIMESTAMP()
  FROM classified WHERE payment_matches!=1;

  DELETE FROM `pacific-plating-282708.sap_integration_v3.v3_unit3_run_summary`
  WHERE pipeline_run_id=p_pipeline_run_id;
  INSERT INTO `pacific-plating-282708.sap_integration_v3.v3_unit3_run_summary`
  WITH ready AS (
    SELECT COUNT(*) AS ready_events
    FROM `pacific-plating-282708.sap_integration_v3.v3_unit2_event_shadow`
    WHERE pipeline_run_id=p_pipeline_run_id AND outcome='READY_CREATE_OR_PAYMENT'
  ), held AS (
    SELECT COUNT(DISTINCT TO_JSON_STRING(STRUCT(order_item,period,charge_id))) AS held_events
    FROM `pacific-plating-282708.sap_integration_v3.v3_unit3_mapping_hold`
    WHERE pipeline_run_id=p_pipeline_run_id
  )
  SELECT p_pipeline_run_id,ready_events,held_events,ready_events-held_events,CURRENT_TIMESTAMP()
  FROM ready CROSS JOIN held;

  ASSERT (SELECT COUNT(*) FROM `pacific-plating-282708.sap_integration_v3.v3_unit3_run_summary`
    WHERE pipeline_run_id=p_pipeline_run_id AND releasable_events<0)=0
    AS 'Unit 3 hold population exceeds Unit 2 READY event population';
END;

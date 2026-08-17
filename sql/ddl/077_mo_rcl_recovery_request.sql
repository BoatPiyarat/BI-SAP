-- Source only / Class A. Immutable Mo-list request and mapping classification.
-- No payload, GCS, SAP, scheduler, or production-interface write occurs in this file.

CREATE TABLE IF NOT EXISTS `pacific-plating-282708.sap_integration_v3.mo_rcl_recovery_request` (
  request_id STRING NOT NULL,
  requested_by STRING NOT NULL,
  source_reference STRING NOT NULL,
  expected_pair_count INT64 NOT NULL,
  request_status STRING NOT NULL,
  created_at TIMESTAMP NOT NULL
)
CLUSTER BY request_id;

CREATE TABLE IF NOT EXISTS `pacific-plating-282708.sap_integration_v3.mo_rcl_recovery_scope` (
  request_id STRING NOT NULL,
  order_id STRING NOT NULL,
  reported_period INT64 NOT NULL,
  captured_at TIMESTAMP NOT NULL
)
CLUSTER BY request_id, order_id;

CREATE TABLE IF NOT EXISTS `pacific-plating-282708.sap_integration_v3.mo_rcl_recovery_mapping` (
  request_id STRING NOT NULL,
  order_id STRING NOT NULL,
  reported_period INT64 NOT NULL,
  order_item STRING NOT NULL,
  charge_id STRING NOT NULL,
  mapped_at TIMESTAMP NOT NULL
)
CLUSTER BY request_id, order_item;

CREATE TABLE IF NOT EXISTS `pacific-plating-282708.sap_integration_v3.mo_rcl_recovery_hold` (
  request_id STRING NOT NULL,
  order_id STRING NOT NULL,
  reported_period INT64 NOT NULL,
  order_item STRING,
  rule_code STRING NOT NULL,
  detail STRING NOT NULL,
  detected_at TIMESTAMP NOT NULL
)
CLUSTER BY request_id, rule_code, order_id;

CREATE OR REPLACE PROCEDURE `pacific-plating-282708.sap_integration_v3.sp_seed_mo_rcl_recovery`(
  p_request_id STRING,
  p_pairs ARRAY<STRUCT<order_id STRING, period INT64>>,
  p_requested_by STRING,
  p_source_reference STRING
)
BEGIN
  ASSERT NULLIF(TRIM(p_request_id),'') IS NOT NULL AS 'request_id is required';
  ASSERT NULLIF(TRIM(p_requested_by),'') IS NOT NULL AS 'requested_by is required';
  ASSERT NULLIF(TRIM(p_source_reference),'') IS NOT NULL AS 'source_reference is required';
  ASSERT ARRAY_LENGTH(IFNULL(p_pairs,[]))>0 AS 'at least one pair is required';
  ASSERT (SELECT COUNT(*) FROM UNNEST(p_pairs)
    WHERE NULLIF(TRIM(order_id),'') IS NULL OR period IS NULL OR period<1)=0
    AS 'scope contains a blank OrderID or invalid period';
  ASSERT (SELECT COUNT(*) FROM (
    SELECT TRIM(order_id),period,COUNT(*) n FROM UNNEST(p_pairs)
    GROUP BY 1,2 HAVING n!=1))=0 AS 'scope contains duplicate pairs';
  ASSERT (SELECT COUNT(*)
    FROM `pacific-plating-282708.sap_integration_v3.mo_rcl_recovery_request`
    WHERE request_id=p_request_id)=0 AS 'request_id is immutable and already exists';
  ASSERT (SELECT COUNT(*)
    FROM `pacific-plating-282708.sap_integration_v3.mo_rcl_recovery_scope`
    WHERE request_id=p_request_id)=0 AS 'request scope already exists';

  BEGIN TRANSACTION;
    INSERT INTO `pacific-plating-282708.sap_integration_v3.mo_rcl_recovery_request`
      (request_id,requested_by,source_reference,expected_pair_count,request_status,created_at)
    VALUES (TRIM(p_request_id),TRIM(p_requested_by),TRIM(p_source_reference),
      ARRAY_LENGTH(p_pairs),'SEEDED',CURRENT_TIMESTAMP());

    INSERT INTO `pacific-plating-282708.sap_integration_v3.mo_rcl_recovery_scope`
      (request_id,order_id,reported_period,captured_at)
    SELECT TRIM(p_request_id),TRIM(order_id),period,CURRENT_TIMESTAMP()
    FROM UNNEST(p_pairs);
  COMMIT TRANSACTION;

  ASSERT (SELECT COUNT(*)
    FROM `pacific-plating-282708.sap_integration_v3.mo_rcl_recovery_scope`
    WHERE request_id=p_request_id)=ARRAY_LENGTH(p_pairs) AS 'seed conservation failed';
END;

CREATE OR REPLACE PROCEDURE `pacific-plating-282708.sap_integration_v3.sp_classify_mo_rcl_recovery`(
  p_request_id STRING
)
BEGIN
  DECLARE v_expected INT64;

  ASSERT NULLIF(TRIM(p_request_id),'') IS NOT NULL AS 'request_id is required';
  ASSERT (SELECT COUNT(*)
    FROM `pacific-plating-282708.sap_integration_v3.mo_rcl_recovery_request`
    WHERE request_id=p_request_id AND request_status='SEEDED')=1
    AS 'classification requires one immutable SEEDED request';
  SET v_expected=(SELECT expected_pair_count
    FROM `pacific-plating-282708.sap_integration_v3.mo_rcl_recovery_request`
    WHERE request_id=p_request_id);
  ASSERT (SELECT COUNT(*)
    FROM `pacific-plating-282708.sap_integration_v3.mo_rcl_recovery_scope`
    WHERE request_id=p_request_id)=v_expected AS 'request scope count changed';
  ASSERT (SELECT COUNT(*)
    FROM `pacific-plating-282708.sap_integration_v3.mo_rcl_recovery_mapping`
    WHERE request_id=p_request_id)=0 AS 'request mapping already exists';
  ASSERT (SELECT COUNT(*)
    FROM `pacific-plating-282708.sap_integration_v3.mo_rcl_recovery_hold`
    WHERE request_id=p_request_id)=0 AS 'request holds already exist';

  CREATE TEMP TABLE _classified AS
  WITH real_sap AS (
    SELECT DISTINCT U_OrderItem, U_Period
    FROM `pacific-plating-282708.sap_integration_v3.stg_sap_state`
    WHERE NULLIF(TRIM(U_InvoiceNo),'') IS NOT NULL
  ), pair_resolution AS (
    SELECT sc.order_id,sc.reported_period,
      ARRAY_AGG(DISTINCT p.order_item IGNORE NULLS) order_items,
      ARRAY_AGG(DISTINCT p.charge_id IGNORE NULLS) charge_ids
    FROM `pacific-plating-282708.sap_integration_v3.mo_rcl_recovery_scope` sc
    LEFT JOIN `pacific-plating-282708.sap_integration_v3.stg_payment_events` p
      ON p.order_id=sc.order_id AND p.period=sc.reported_period
    WHERE sc.request_id=p_request_id
    GROUP BY sc.order_id,sc.reported_period
  ), one_pair AS (
    SELECT order_id,reported_period,ARRAY_LENGTH(order_items) item_count,
      ARRAY_LENGTH(charge_ids) charge_count,order_items[SAFE_OFFSET(0)] order_item,
      charge_ids[SAFE_OFFSET(0)] charge_id
    FROM pair_resolution
  ), schedule_flow AS (
    SELECT p.order_id,p.reported_period,
      STRING_AGG(DISTINCT IFNULL(s.flow,'__NULL__'),',' ORDER BY IFNULL(s.flow,'__NULL__'))
        reported_flows,
      STRING_AGG(DISTINCT IFNULL(full_s.flow,'__NULL__'),',' ORDER BY IFNULL(full_s.flow,'__NULL__'))
        full_spine_flows
    FROM one_pair p
    LEFT JOIN `pacific-plating-282708.sap_integration_v3.stg_schedule` s
      ON s.order_item=p.order_item AND s.period=p.reported_period
    LEFT JOIN `pacific-plating-282708.sap_integration_v3.stg_schedule` full_s
      ON full_s.order_item=p.order_item
    GROUP BY p.order_id,p.reported_period
  ), exclusions AS (
    SELECT p.order_id,p.reported_period,
      STRING_AGG(DISTINCT x.rule_code,',' ORDER BY x.rule_code) exclusion_rule
    FROM one_pair p
    LEFT JOIN `pacific-plating-282708.sap_integration_v3.sap_excluded_records` x
      ON x.order_item=p.order_item AND x.period=p.reported_period
    GROUP BY p.order_id,p.reported_period
  ), validations AS (
    SELECT p.order_id,p.reported_period,
      STRING_AGG(DISTINCT v.check_name,',' ORDER BY v.check_name) validation_rule
    FROM one_pair p
    LEFT JOIN `pacific-plating-282708.sap_integration_v3.sap_validation_error` v
      ON v.order_item=p.order_item AND (v.period=p.reported_period OR v.period IS NULL)
    GROUP BY p.order_id,p.reported_period
  )
  SELECT p.*,f.reported_flows,f.full_spine_flows,
    sap.U_OrderItem IS NOT NULL already_in_sap,x.exclusion_rule,v.validation_rule
  FROM one_pair p
  LEFT JOIN schedule_flow f USING(order_id,reported_period)
  LEFT JOIN exclusions x USING(order_id,reported_period)
  LEFT JOIN validations v USING(order_id,reported_period)
  LEFT JOIN real_sap sap ON sap.U_OrderItem=p.order_item AND sap.U_Period=p.reported_period;

  CREATE TEMP TABLE _decision AS
  SELECT *,CASE
    WHEN order_item IS NULL THEN 'NO_EVENT_ITEM_MAPPING'
    WHEN item_count!=1 THEN 'AMBIGUOUS_EVENT_ITEM_MAPPING'
    WHEN charge_count!=1 THEN 'MULTIPLE_OR_MISSING_REPORTED_CHARGE'
    WHEN already_in_sap THEN 'ALREADY_IN_SAP_NOW'
    WHEN exclusion_rule IS NOT NULL THEN 'EXCLUDED_RULE'
    WHEN validation_rule IS NOT NULL THEN 'VALIDATION_RULE'
    WHEN reported_flows!='RCL' THEN 'REPORTED_PERIOD_NOT_RCL'
    WHEN full_spine_flows!='RCL' THEN 'FULL_SPINE_NOT_RCL'
    ELSE 'ACCEPT_MAPPING' END decision
  FROM _classified;

  BEGIN TRANSACTION;
    INSERT INTO `pacific-plating-282708.sap_integration_v3.mo_rcl_recovery_mapping`
      (request_id,order_id,reported_period,order_item,charge_id,mapped_at)
    SELECT p_request_id,order_id,reported_period,order_item,charge_id,CURRENT_TIMESTAMP()
    FROM _decision WHERE decision='ACCEPT_MAPPING';

    INSERT INTO `pacific-plating-282708.sap_integration_v3.mo_rcl_recovery_hold`
      (request_id,order_id,reported_period,order_item,rule_code,detail,detected_at)
    SELECT p_request_id,order_id,reported_period,order_item,decision,
      FORMAT('item_count=%d; charge_count=%d; reported_flows=%s; full_spine_flows=%s; exclusion=%s; validation=%s',
        item_count,charge_count,IFNULL(reported_flows,'NULL'),IFNULL(full_spine_flows,'NULL'),
        IFNULL(exclusion_rule,'NULL'),IFNULL(validation_rule,'NULL')),CURRENT_TIMESTAMP()
    FROM _decision WHERE decision!='ACCEPT_MAPPING';

    UPDATE `pacific-plating-282708.sap_integration_v3.mo_rcl_recovery_request`
    SET request_status='CLASSIFIED'
    WHERE request_id=p_request_id AND request_status='SEEDED';
  COMMIT TRANSACTION;

  ASSERT (SELECT COUNT(*)
    FROM `pacific-plating-282708.sap_integration_v3.mo_rcl_recovery_mapping`
    WHERE request_id=p_request_id)+(SELECT COUNT(*)
    FROM `pacific-plating-282708.sap_integration_v3.mo_rcl_recovery_hold`
    WHERE request_id=p_request_id)=v_expected AS 'classification conservation failed';
END;

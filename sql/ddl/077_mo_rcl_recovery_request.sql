-- Source only / Class A. Immutable Mo-list request and mapping classification.
-- No payload, GCS, SAP, scheduler, or production-interface write occurs in this file.

CREATE TABLE IF NOT EXISTS `pacific-plating-282708.sap_integration_v3.mo_rcl_recovery_request` (
  request_id STRING NOT NULL,
  requested_by STRING NOT NULL,
  source_reference STRING NOT NULL,
  expected_pair_count INT64 NOT NULL,
  request_status STRING NOT NULL,
  source_request_id STRING,
  created_at TIMESTAMP NOT NULL
)
CLUSTER BY request_id;

ALTER TABLE `pacific-plating-282708.sap_integration_v3.mo_rcl_recovery_request`
ADD COLUMN IF NOT EXISTS source_request_id STRING;

CREATE TABLE IF NOT EXISTS `pacific-plating-282708.sap_integration_v3.mo_rcl_recovery_lock` (
  lock_name STRING NOT NULL,
  claim_epoch INT64 NOT NULL,
  claimed_at TIMESTAMP NOT NULL
);

MERGE `pacific-plating-282708.sap_integration_v3.mo_rcl_recovery_lock` t
USING (SELECT 'MO_RCL_RECOVERY' lock_name) s ON t.lock_name=s.lock_name
WHEN NOT MATCHED THEN INSERT(lock_name,claim_epoch,claimed_at)
VALUES(s.lock_name,0,TIMESTAMP '2000-01-01 00:00:00+00');

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
  DECLARE v_request_id STRING DEFAULT TRIM(p_request_id);
  DECLARE v_scope_hash STRING;
  ASSERT NULLIF(TRIM(p_request_id),'') IS NOT NULL AS 'request_id is required';
  ASSERT NULLIF(TRIM(p_requested_by),'') IS NOT NULL AS 'requested_by is required';
  ASSERT NULLIF(TRIM(p_source_reference),'') IS NOT NULL AS 'source_reference is required';
  ASSERT ARRAY_LENGTH(IFNULL(p_pairs,[]))=2295 AS 'scope must contain exactly 2,295 Mo pairs';
  ASSERT (SELECT COUNT(*) FROM UNNEST(p_pairs)
    WHERE NULLIF(TRIM(order_id),'') IS NULL OR period IS NULL OR period<1)=0
    AS 'scope contains a blank OrderID or invalid period';
  ASSERT (SELECT COUNT(*) FROM (
    SELECT TRIM(order_id),period,COUNT(*) n FROM UNNEST(p_pairs)
    GROUP BY 1,2 HAVING n!=1))=0 AS 'scope contains duplicate pairs';
  SET v_scope_hash=(SELECT LOWER(TO_HEX(SHA256(STRING_AGG(
    CONCAT(TRIM(order_id),'|',CAST(period AS STRING)),'\n'
    ORDER BY TRIM(order_id),period)))) FROM UNNEST(p_pairs));
  ASSERT v_scope_hash='33b91e08b301d3e37e3aa6acdf77d51cfb7f0fedda58862c92f8ddb3799cd9a8'
    AS 'scope does not equal the exact reviewed Mo 2,295-pair allowlist';

  BEGIN TRANSACTION;
    UPDATE `pacific-plating-282708.sap_integration_v3.mo_rcl_recovery_lock`
    SET claim_epoch=claim_epoch+1,claimed_at=CURRENT_TIMESTAMP()
    WHERE lock_name='MO_RCL_RECOVERY';
    ASSERT @@row_count=1 AS 'recovery lock is missing or duplicated';
    ASSERT (SELECT COUNT(*)
      FROM `pacific-plating-282708.sap_integration_v3.mo_rcl_recovery_request`
      WHERE request_id=v_request_id)=0 AS 'request_id is immutable and already exists';
    ASSERT (SELECT COUNT(*)
      FROM `pacific-plating-282708.sap_integration_v3.mo_rcl_recovery_scope`
      WHERE request_id=v_request_id)=0 AS 'request scope already exists';
    INSERT INTO `pacific-plating-282708.sap_integration_v3.mo_rcl_recovery_request`
      (request_id,requested_by,source_reference,expected_pair_count,request_status,created_at)
    VALUES (v_request_id,TRIM(p_requested_by),TRIM(p_source_reference),
      ARRAY_LENGTH(p_pairs),'SEEDED',CURRENT_TIMESTAMP());

    INSERT INTO `pacific-plating-282708.sap_integration_v3.mo_rcl_recovery_scope`
      (request_id,order_id,reported_period,captured_at)
    SELECT v_request_id,TRIM(order_id),period,CURRENT_TIMESTAMP()
    FROM UNNEST(p_pairs);
    ASSERT (SELECT COUNT(*)
      FROM `pacific-plating-282708.sap_integration_v3.mo_rcl_recovery_scope`
      WHERE request_id=v_request_id)=ARRAY_LENGTH(p_pairs) AS 'seed conservation failed';
  COMMIT TRANSACTION;
END;

CREATE OR REPLACE PROCEDURE `pacific-plating-282708.sap_integration_v3.sp_clone_mo_rcl_recovery_request`(
  p_request_id STRING,p_source_request_id STRING,p_requested_by STRING,p_source_reference STRING
)
BEGIN
  DECLARE v_request_id STRING DEFAULT TRIM(p_request_id);
  DECLARE v_source_request_id STRING DEFAULT TRIM(p_source_request_id);
  ASSERT NULLIF(v_request_id,'') IS NOT NULL AND NULLIF(v_source_request_id,'') IS NOT NULL
    AS 'request_id and source_request_id are required';
  ASSERT (SELECT COUNT(*) FROM `pacific-plating-282708.sap_integration_v3.mo_rcl_recovery_request`
    WHERE request_id=v_source_request_id AND expected_pair_count=2295 AND request_status='CLASSIFIED')=1
    AS 'source request must be the immutable classified Mo request';
  ASSERT (SELECT COUNT(*) FROM `pacific-plating-282708.sap_integration_v3.mo_rcl_recovery_event_snapshot`
    WHERE source_request_id=v_source_request_id)>0 AS 'source request has no reviewed event snapshot';
  BEGIN TRANSACTION;
    UPDATE `pacific-plating-282708.sap_integration_v3.mo_rcl_recovery_lock`
    SET claim_epoch=claim_epoch+1,claimed_at=CURRENT_TIMESTAMP() WHERE lock_name='MO_RCL_RECOVERY';
    ASSERT @@row_count=1 AS 'recovery lock is missing or duplicated';
    ASSERT (SELECT COUNT(*) FROM `pacific-plating-282708.sap_integration_v3.mo_rcl_recovery_request`
      WHERE request_id=v_request_id)=0 AS 'request_id is immutable and already exists';
    INSERT INTO `pacific-plating-282708.sap_integration_v3.mo_rcl_recovery_request`
      (request_id,requested_by,source_reference,expected_pair_count,request_status,source_request_id,created_at)
    VALUES (v_request_id,TRIM(p_requested_by),TRIM(p_source_reference),2295,'SEEDED',
      v_source_request_id,CURRENT_TIMESTAMP());
    INSERT INTO `pacific-plating-282708.sap_integration_v3.mo_rcl_recovery_scope`
      (request_id,order_id,reported_period,captured_at)
    SELECT v_request_id,order_id,reported_period,CURRENT_TIMESTAMP()
    FROM `pacific-plating-282708.sap_integration_v3.mo_rcl_recovery_scope`
    WHERE request_id=v_source_request_id;
    ASSERT @@row_count=2295 AS 'cloned Mo scope must contain exactly 2,295 pairs';
  COMMIT TRANSACTION;
END;

CREATE OR REPLACE PROCEDURE `pacific-plating-282708.sap_integration_v3.sp_classify_mo_rcl_recovery`(
  p_request_id STRING
)
BEGIN
  DECLARE v_expected INT64;
  DECLARE v_request_id STRING DEFAULT TRIM(p_request_id);
  DECLARE v_source_request_id STRING;

  ASSERT NULLIF(TRIM(p_request_id),'') IS NOT NULL AS 'request_id is required';
  ASSERT (SELECT COUNT(*)
    FROM `pacific-plating-282708.sap_integration_v3.mo_rcl_recovery_request`
    WHERE request_id=v_request_id AND request_status='SEEDED')=1
    AS 'classification requires one immutable SEEDED request';
  SET v_expected=(SELECT expected_pair_count
    FROM `pacific-plating-282708.sap_integration_v3.mo_rcl_recovery_request`
    WHERE request_id=v_request_id);
  SET v_source_request_id=(SELECT source_request_id
    FROM `pacific-plating-282708.sap_integration_v3.mo_rcl_recovery_request`
    WHERE request_id=v_request_id);
  ASSERT (SELECT COUNT(*)
    FROM `pacific-plating-282708.sap_integration_v3.mo_rcl_recovery_scope`
    WHERE request_id=v_request_id)=v_expected AS 'request scope count changed';
  ASSERT (SELECT COUNT(*)
    FROM `pacific-plating-282708.sap_integration_v3.mo_rcl_recovery_mapping`
    WHERE request_id=v_request_id)=0 AS 'request mapping already exists';
  ASSERT (SELECT COUNT(*)
    FROM `pacific-plating-282708.sap_integration_v3.mo_rcl_recovery_hold`
    WHERE request_id=v_request_id)=0 AS 'request holds already exist';

  CREATE TEMP TABLE _classified AS
  WITH real_sap AS (
    SELECT DISTINCT U_OrderItem, U_Period
    FROM `pacific-plating-282708.sap_integration_v3.stg_sap_state`
    WHERE NULLIF(TRIM(U_InvoiceNo),'') IS NOT NULL
  ), recovery_events AS (
    SELECT charge_id,order_item,order_id,period
    FROM `pacific-plating-282708.sap_integration_v3.stg_payment_events`
    WHERE DATE(charge_time) BETWEEN DATE '2026-08-01' AND DATE '2026-08-15'
    UNION ALL
    SELECT charge_id,order_item,order_id,period
    FROM `pacific-plating-282708.sap_integration_v3.mo_rcl_recovery_event_snapshot`
    WHERE source_request_id=v_source_request_id
  ), item_resolution AS (
    SELECT sc.order_id,sc.reported_period,
      ARRAY_AGG(DISTINCT p.order_item IGNORE NULLS) order_items
    FROM `pacific-plating-282708.sap_integration_v3.mo_rcl_recovery_scope` sc
    LEFT JOIN recovery_events p
      ON p.order_id=sc.order_id AND p.period=sc.reported_period
    WHERE sc.request_id=v_request_id
    GROUP BY sc.order_id,sc.reported_period
  ), qualified_events AS (
    SELECT p.order_id,p.period,p.order_item,p.charge_id
    FROM recovery_events p
    JOIN `pacific-plating-282708.careos.carepay_charges` c
      ON c.id=p.charge_id AND c.status='SUCCESSFUL'
  ), successful_resolution AS (
    SELECT sc.order_id,sc.reported_period,
      ARRAY_AGG(DISTINCT q.charge_id IGNORE NULLS) charge_ids,
      ARRAY_AGG(DISTINCT q.order_item IGNORE NULLS) qualified_order_items
    FROM `pacific-plating-282708.sap_integration_v3.mo_rcl_recovery_scope` sc
    LEFT JOIN qualified_events q
      ON q.order_id=sc.order_id AND q.period=sc.reported_period
    WHERE sc.request_id=v_request_id
    GROUP BY sc.order_id,sc.reported_period
  ), pair_resolution AS (
    SELECT i.order_id,i.reported_period,i.order_items,s.charge_ids,s.qualified_order_items
    FROM item_resolution i JOIN successful_resolution s USING(order_id,reported_period)
  ), one_pair AS (
    SELECT order_id,reported_period,IFNULL(ARRAY_LENGTH(order_items),0) item_count,
      IFNULL(ARRAY_LENGTH(charge_ids),0) charge_count,
      IFNULL(ARRAY_LENGTH(qualified_order_items),0) qualified_item_count,
      order_items[SAFE_OFFSET(0)] order_item,
      qualified_order_items[SAFE_OFFSET(0)] qualified_order_item,
      charge_ids[SAFE_OFFSET(0)] charge_id
    FROM pair_resolution
  ), schedule_flow AS (
    SELECT p.order_id,p.reported_period,
      STRING_AGG(DISTINCT IFNULL(s.flow,'__NULL__'),',' ORDER BY IFNULL(s.flow,'__NULL__'))
        reported_flows,
      STRING_AGG(DISTINCT IFNULL(full_s.flow,'__NULL__'),',' ORDER BY IFNULL(full_s.flow,'__NULL__'))
        full_spine_flows,
      COUNT(DISTINCT full_s.period) spine_period_count,
      COUNT(full_s.period) spine_row_count,
      MIN(full_s.period) first_period,MAX(full_s.period) last_period,
      COUNT(DISTINCT full_s.total_periods) total_period_versions,
      MAX(full_s.total_periods) total_periods
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
      ON x.order_item=p.order_item
    GROUP BY p.order_id,p.reported_period
  ), validations AS (
    SELECT p.order_id,p.reported_period,
      STRING_AGG(DISTINCT v.check_name,',' ORDER BY v.check_name) validation_rule
    FROM one_pair p
    LEFT JOIN `pacific-plating-282708.sap_integration_v3.sap_validation_error` v
      ON v.order_item=p.order_item
    GROUP BY p.order_id,p.reported_period
  )
  SELECT p.*,f.reported_flows,f.full_spine_flows,f.spine_period_count,f.spine_row_count,f.first_period,
    f.last_period,f.total_period_versions,f.total_periods,
    sap.U_OrderItem IS NOT NULL already_in_sap,x.exclusion_rule,v.validation_rule
  FROM one_pair p
  LEFT JOIN schedule_flow f USING(order_id,reported_period)
  LEFT JOIN exclusions x USING(order_id,reported_period)
  LEFT JOIN validations v USING(order_id,reported_period)
  LEFT JOIN real_sap sap ON sap.U_OrderItem=p.order_item AND sap.U_Period=p.reported_period;

  CREATE TEMP TABLE _initial_decision AS
  SELECT *,CASE
    WHEN order_item IS NULL THEN 'NO_EVENT_ITEM_MAPPING'
    WHEN item_count!=1 THEN 'AMBIGUOUS_EVENT_ITEM_MAPPING'
    WHEN charge_count=0 THEN 'NO_SUCCESSFUL_REPORTED_CHARGE'
    WHEN charge_count>1 THEN 'MULTIPLE_SUCCESSFUL_REPORTED_CHARGES'
    WHEN qualified_item_count=0 THEN 'SUCCESSFUL_CHARGE_HAS_NO_ITEM_MAPPING'
    WHEN qualified_item_count>1 THEN 'SUCCESSFUL_CHARGE_ITEM_AMBIGUOUS'
    WHEN qualified_order_item!=order_item THEN 'SUCCESSFUL_CHARGE_ITEM_MISMATCH'
    WHEN already_in_sap THEN 'ALREADY_IN_SAP_NOW'
    WHEN exclusion_rule IS NOT NULL THEN 'EXCLUDED_RULE'
    WHEN validation_rule IS NOT NULL THEN 'VALIDATION_RULE'
    WHEN reported_flows IS NULL OR reported_flows!='RCL' THEN 'REPORTED_PERIOD_NOT_RCL'
    WHEN full_spine_flows IS NULL OR full_spine_flows!='RCL' THEN 'FULL_SPINE_NOT_RCL'
    WHEN total_period_versions!=1 OR total_periods IS NULL OR total_periods<1
      OR first_period!=1 OR last_period!=total_periods OR spine_period_count!=total_periods
      OR spine_row_count!=total_periods
      THEN 'INCOMPLETE_PERIOD_SPINE'
    ELSE 'ACCEPT_MAPPING' END decision
  FROM _classified;

  CREATE TEMP TABLE _decision AS
  SELECT * EXCEPT(decision,item_has_hold),
    IF(decision='ACCEPT_MAPPING' AND item_has_hold,'ITEM_SPINE_QUARANTINED',decision) decision
  FROM (
    SELECT d.*,COUNTIF(decision!='ACCEPT_MAPPING') OVER(PARTITION BY order_item)>0 item_has_hold
    FROM _initial_decision d
  );

  ASSERT (SELECT COUNT(*) FROM _decision)=v_expected AS 'decision count conservation failed';
  ASSERT (SELECT COUNT(*) FROM (
    SELECT order_id,reported_period,COUNT(*) n FROM _decision GROUP BY 1,2 HAVING n!=1))=0
    AS 'decision key is not unique';

  BEGIN TRANSACTION;
    UPDATE `pacific-plating-282708.sap_integration_v3.mo_rcl_recovery_lock`
    SET claim_epoch=claim_epoch+1,claimed_at=CURRENT_TIMESTAMP()
    WHERE lock_name='MO_RCL_RECOVERY';
    ASSERT @@row_count=1 AS 'recovery lock is missing or duplicated';
    ASSERT (SELECT COUNT(*)
      FROM `pacific-plating-282708.sap_integration_v3.mo_rcl_recovery_request`
      WHERE request_id=v_request_id AND request_status='SEEDED')=1
      AS 'request state changed before classification claim';
    INSERT INTO `pacific-plating-282708.sap_integration_v3.mo_rcl_recovery_mapping`
      (request_id,order_id,reported_period,order_item,charge_id,mapped_at)
    SELECT v_request_id,order_id,reported_period,order_item,charge_id,CURRENT_TIMESTAMP()
    FROM _decision WHERE decision='ACCEPT_MAPPING';

    INSERT INTO `pacific-plating-282708.sap_integration_v3.mo_rcl_recovery_hold`
      (request_id,order_id,reported_period,order_item,rule_code,detail,detected_at)
    SELECT v_request_id,order_id,reported_period,order_item,decision,
      FORMAT('item_count=%d; charge_count=%d; reported_flows=%s; full_spine_flows=%s; exclusion=%s; validation=%s',
        IFNULL(item_count,0),IFNULL(charge_count,0),IFNULL(reported_flows,'NULL'),IFNULL(full_spine_flows,'NULL'),
        IFNULL(exclusion_rule,'NULL'),IFNULL(validation_rule,'NULL')),CURRENT_TIMESTAMP()
    FROM _decision WHERE decision!='ACCEPT_MAPPING';

    UPDATE `pacific-plating-282708.sap_integration_v3.mo_rcl_recovery_request`
    SET request_status='CLASSIFIED'
    WHERE request_id=v_request_id AND request_status='SEEDED';
    ASSERT @@row_count=1 AS 'classification state transition failed';
    ASSERT (SELECT COUNT(*)
      FROM `pacific-plating-282708.sap_integration_v3.mo_rcl_recovery_mapping`
      WHERE request_id=v_request_id)+(SELECT COUNT(*)
      FROM `pacific-plating-282708.sap_integration_v3.mo_rcl_recovery_hold`
      WHERE request_id=v_request_id)=v_expected AS 'classification conservation failed';
  COMMIT TRANSACTION;
END;

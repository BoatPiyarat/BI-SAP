-- Immutable, request-scoped historical-event snapshot for Mo recovery.
-- It does not mutate shared staging and does not write an interface file.
CREATE TABLE IF NOT EXISTS `pacific-plating-282708.sap_integration_v3.mo_rcl_recovery_event_snapshot` (
  source_request_id STRING NOT NULL, charge_id STRING NOT NULL, third_party_id STRING,
  order_item STRING NOT NULL, order_id STRING NOT NULL, transaction_id STRING NOT NULL,
  period INT64 NOT NULL, amount INT64, charge_time TIMESTAMP NOT NULL, payment_option STRING,
  payment_method_source STRING, payment_channel_source STRING, lead_human_id STRING,
  captured_at TIMESTAMP NOT NULL
) CLUSTER BY source_request_id,order_id,order_item;

CREATE TABLE IF NOT EXISTS `pacific-plating-282708.sap_integration_v3.mo_rcl_recovery_event_hold` (
  source_request_id STRING NOT NULL, charge_id STRING NOT NULL, rule_code STRING NOT NULL,
  transaction_id STRING, amount INT64, charge_time TIMESTAMP, captured_at TIMESTAMP NOT NULL
) CLUSTER BY source_request_id,rule_code;

CREATE OR REPLACE PROCEDURE `pacific-plating-282708.sap_integration_v3.sp_snapshot_mo_rcl_historical_events`(
  p_source_request_id STRING
)
BEGIN
  DECLARE v_request_id STRING DEFAULT TRIM(p_source_request_id);
  DECLARE v_raw INT64;
  DECLARE v_watermark TIMESTAMP;
  ASSERT (SELECT COUNT(*) FROM `pacific-plating-282708.sap_integration_v3.mo_rcl_recovery_request`
    WHERE request_id=v_request_id AND expected_pair_count=2295 AND request_status='CLASSIFIED')=1
    AS 'snapshot requires the immutable classified Mo 2,295-pair request';
  ASSERT (SELECT COUNT(*) FROM `pacific-plating-282708.sap_integration_v3.mo_rcl_recovery_event_snapshot`
    WHERE source_request_id=v_request_id)=0 AS 'event snapshot already exists';
  ASSERT (SELECT COUNT(*) FROM `pacific-plating-282708.sap_integration_v3.mo_rcl_recovery_event_hold`
    WHERE source_request_id=v_request_id)=0 AS 'event hold snapshot already exists';
  SET v_watermark=(SELECT MAX(charge_time)
    FROM `pacific-plating-282708.sap_integration_v3.stg_payment_events`
    WHERE DATE(charge_time)<=DATE '2026-08-15');
  ASSERT v_watermark IS NOT NULL AS 'bounded staging watermark is missing';

  CREATE TEMP TABLE _linked AS
  SELECT c.id charge_id,COALESCE(c.third_party_id,oi.human_id) third_party_id,
    oi.human_id order_item,o.human_id order_id,c.transaction_id,c.installment_number period,
    c.amount,c.update_time charge_time,t.payment_option,c.payment_method payment_method_source,
    c.service_provider payment_channel_source,t.lead_human_id,o.id order_pk,oi.id order_item_pk,
    l.id lead_pk,l.status lead_status,
    ROW_NUMBER() OVER (PARTITION BY c.id
      ORDER BY IF(oi.motor_item_type='MOTOR_TYPE_COMPULSORY',2,1)) item_rank
  FROM `pacific-plating-282708.sap_integration_v3.mo_rcl_recovery_hold` h
  JOIN `pacific-plating-282708.careos.careos_orders` o ON o.human_id=h.order_id
  JOIN `pacific-plating-282708.careos.carepay_transactions` t
    ON CONCAT('transactions/',t.id)=o.payment
  JOIN `pacific-plating-282708.careos.carepay_charges` c
    ON c.transaction_id=t.id AND c.installment_number=h.reported_period AND c.status='SUCCESSFUL'
  LEFT JOIN `pacific-plating-282708.careos.careos_order_items` oi ON oi.order_id=o.id
  LEFT JOIN `pacific-plating-282708.careos.careos_leads` l ON CONCAT('leads/',l.id)=o.lead
  WHERE h.request_id=v_request_id AND h.rule_code='NO_EVENT_ITEM_MAPPING';

  CREATE TEMP TABLE _qualification AS
  SELECT charge_id,ANY_VALUE(transaction_id) transaction_id,ANY_VALUE(amount) amount,
    ANY_VALUE(charge_time) charge_time,
    CASE WHEN COUNTIF(order_pk IS NOT NULL)=0 THEN 'NO_ORDER'
      WHEN COUNTIF(order_item_pk IS NOT NULL)=0 THEN 'NO_ORDER_ITEM'
      WHEN COUNTIF(NULLIF(TRIM(order_item),'') IS NOT NULL)=0 THEN 'EMPTY_ORDER_ITEM_HUMAN_ID'
      WHEN COUNTIF(lead_pk IS NOT NULL AND lead_status='LEAD_STATUS_PURCHASED')=0
        THEN 'LEAD_NOT_PURCHASED'
      WHEN COUNTIF(item_rank=1 AND NULLIF(TRIM(order_item),'') IS NULL)>0
        THEN 'SELECTED_ORDER_ITEM_HUMAN_ID_EMPTY'
      ELSE 'QUALIFIED' END rule_code
  FROM _linked GROUP BY charge_id;
  SET v_raw=(SELECT COUNT(*) FROM _qualification);
  ASSERT v_raw>0 AS 'no successful source charges found for NO_EVENT holds';
  ASSERT (SELECT COUNT(*) FROM _linked l JOIN _qualification q USING(charge_id)
    WHERE q.rule_code='QUALIFIED' AND l.item_rank=1 AND l.charge_time>v_watermark)=0
    AS 'snapshot contains a post-watermark event; investigate nightly staging instead';
  ASSERT (SELECT COUNT(*) FROM _linked l JOIN _qualification q USING(charge_id)
    JOIN `pacific-plating-282708.sap_integration_v3.stg_payment_events` e
      ON e.order_id=l.order_id AND e.period=l.period
      AND DATE(e.charge_time) BETWEEN DATE '2026-08-01' AND DATE '2026-08-15'
    WHERE q.rule_code='QUALIFIED' AND l.item_rank=1)=0
    AS 'snapshot event already resolves in bounded staging; historical-gap proof failed';

  BEGIN TRANSACTION;
    UPDATE `pacific-plating-282708.sap_integration_v3.mo_rcl_recovery_lock`
    SET claim_epoch=claim_epoch+1,claimed_at=CURRENT_TIMESTAMP() WHERE lock_name='MO_RCL_RECOVERY';
    ASSERT @@row_count=1 AS 'recovery lock is missing or duplicated';
    ASSERT (SELECT COUNT(*) FROM `pacific-plating-282708.sap_integration_v3.mo_rcl_recovery_event_snapshot`
      WHERE source_request_id=v_request_id)=0 AS 'event snapshot already exists after claim';
    ASSERT (SELECT COUNT(*) FROM `pacific-plating-282708.sap_integration_v3.mo_rcl_recovery_event_hold`
      WHERE source_request_id=v_request_id)=0 AS 'event hold snapshot already exists after claim';
    INSERT INTO `pacific-plating-282708.sap_integration_v3.mo_rcl_recovery_event_snapshot`
      (source_request_id,charge_id,third_party_id,order_item,order_id,transaction_id,period,amount,
       charge_time,payment_option,payment_method_source,payment_channel_source,lead_human_id,captured_at)
    SELECT v_request_id,l.charge_id,l.third_party_id,l.order_item,l.order_id,l.transaction_id,l.period,
      l.amount,l.charge_time,l.payment_option,l.payment_method_source,l.payment_channel_source,
      l.lead_human_id,CURRENT_TIMESTAMP()
    FROM _linked l JOIN _qualification q USING(charge_id)
    WHERE q.rule_code='QUALIFIED' AND l.item_rank=1;

    INSERT INTO `pacific-plating-282708.sap_integration_v3.mo_rcl_recovery_event_hold`
      (source_request_id,charge_id,rule_code,transaction_id,amount,charge_time,captured_at)
    SELECT v_request_id,charge_id,rule_code,transaction_id,amount,charge_time,CURRENT_TIMESTAMP()
    FROM _qualification WHERE rule_code!='QUALIFIED';

    ASSERT (SELECT COUNT(*) FROM `pacific-plating-282708.sap_integration_v3.mo_rcl_recovery_event_snapshot`
      WHERE source_request_id=v_request_id)+(SELECT COUNT(*)
      FROM `pacific-plating-282708.sap_integration_v3.mo_rcl_recovery_event_hold`
      WHERE source_request_id=v_request_id)=v_raw AS 'event snapshot conservation failed';
  COMMIT TRANSACTION;
END;

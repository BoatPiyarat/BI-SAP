-- Insert-only repair for historical SUCCESSFUL charges that predate the incremental
-- stg_payment_events watermark. Limited to one immutable Mo recovery request.
CREATE OR REPLACE PROCEDURE `pacific-plating-282708.sap_integration_v3.sp_backfill_mo_rcl_payment_events`(p_request_id STRING)
BEGIN
  DECLARE v_request_id STRING DEFAULT TRIM(p_request_id);
  DECLARE v_watermark TIMESTAMP;
  DECLARE v_min_date DATE;
  DECLARE v_max_date DATE;
  DECLARE v_raw_charges INT64;
  DECLARE v_qualified_charges INT64;
  DECLARE v_excluded_charges INT64;

  ASSERT NULLIF(v_request_id,'') IS NOT NULL AS 'request_id is required';
  ASSERT (SELECT COUNT(*) FROM `pacific-plating-282708.sap_integration_v3.mo_rcl_recovery_request`
    WHERE request_id=v_request_id AND expected_pair_count=2295 AND request_status='CLASSIFIED')=1
    AS 'backfill requires the immutable classified Mo 2,295-pair request';
  SET v_watermark=(SELECT MAX(charge_time)
    FROM `pacific-plating-282708.sap_integration_v3.stg_payment_events`);
  ASSERT v_watermark IS NOT NULL AS 'stg_payment_events watermark is missing';

  CREATE TEMP TABLE _linked AS
  WITH held_pairs AS (
    SELECT order_id,reported_period
    FROM `pacific-plating-282708.sap_integration_v3.mo_rcl_recovery_hold`
    WHERE request_id=v_request_id AND rule_code='NO_EVENT_ITEM_MAPPING'
  )
  SELECT c.id charge_id,COALESCE(c.third_party_id,oi.human_id) third_party_id,
    c.transaction_id,c.installment_number period,c.amount,c.update_time charge_time,
    t.payment_option,c.payment_method payment_method_source,
    c.service_provider payment_channel_source,t.lead_human_id,
    o.id order_pk,o.human_id order_id,oi.id order_item_pk,oi.human_id order_item,
    l.id lead_pk,l.status lead_status,
    ROW_NUMBER() OVER (PARTITION BY c.id
      ORDER BY IF(oi.motor_item_type='MOTOR_TYPE_COMPULSORY',2,1)) item_rank
  FROM held_pairs h
  JOIN `pacific-plating-282708.careos.careos_orders` o ON o.human_id=h.order_id
  JOIN `pacific-plating-282708.careos.carepay_transactions` t
    ON CONCAT('transactions/',t.id)=o.payment
  JOIN `pacific-plating-282708.careos.carepay_charges` c
    ON c.transaction_id=t.id AND c.installment_number=h.reported_period AND c.status='SUCCESSFUL'
  LEFT JOIN `pacific-plating-282708.careos.careos_order_items` oi ON oi.order_id=o.id
  LEFT JOIN `pacific-plating-282708.careos.careos_leads` l ON CONCAT('leads/',l.id)=o.lead;

  CREATE TEMP TABLE _qualification AS
  SELECT charge_id,ANY_VALUE(transaction_id) transaction_id,ANY_VALUE(amount) amount,
    ANY_VALUE(charge_time) charge_time,
    CASE WHEN COUNTIF(order_pk IS NOT NULL)=0 THEN 'NO_ORDER'
      WHEN COUNTIF(order_item_pk IS NOT NULL)=0 THEN 'NO_ORDER_ITEM'
      WHEN COUNTIF(NULLIF(TRIM(order_item),'') IS NOT NULL)=0 THEN 'EMPTY_ORDER_ITEM_HUMAN_ID'
      WHEN COUNTIF(lead_pk IS NOT NULL AND lead_status='LEAD_STATUS_PURCHASED')=0
        THEN 'LEAD_NOT_PURCHASED'
      ELSE 'QUALIFIED' END rule_code
  FROM _linked GROUP BY charge_id;

  CREATE TEMP TABLE _source AS
  SELECT l.charge_id,l.third_party_id,l.order_item,l.order_id,l.transaction_id,l.period,l.amount,
    l.charge_time,l.payment_option,l.payment_method_source,l.payment_channel_source,l.lead_human_id
  FROM _linked l JOIN _qualification q USING(charge_id)
  WHERE q.rule_code='QUALIFIED' AND l.item_rank=1;

  SET v_raw_charges=(SELECT COUNT(*) FROM _qualification);
  SET v_qualified_charges=(SELECT COUNT(*) FROM _source);
  SET v_excluded_charges=(SELECT COUNT(*) FROM _qualification WHERE rule_code!='QUALIFIED');
  SET v_min_date=(SELECT MIN(DATE(charge_time)) FROM _qualification);
  SET v_max_date=(SELECT MAX(DATE(charge_time)) FROM _qualification);
  ASSERT v_raw_charges>0 AS 'no historical successful charges found for request holds';
  ASSERT v_raw_charges=v_qualified_charges+v_excluded_charges
    AS 'raw charge qualification conservation failed';
  ASSERT (SELECT COUNT(*) FROM _source WHERE charge_time>v_watermark)=0
    AS 'repair contains a post-watermark charge; investigate nightly staging instead';
  ASSERT (SELECT COUNT(*) FROM (SELECT charge_id,COUNT(*) n FROM _source
    GROUP BY charge_id HAVING n!=1))=0 AS 'qualified source is not unique by charge_id';
  ASSERT (SELECT COUNT(*) FROM `pacific-plating-282708.sap_integration_v3.stg_payment_events` t
    JOIN _source s ON t.charge_id=s.charge_id
    WHERE DATE(t.charge_time) BETWEEN v_min_date AND v_max_date)=0
    AS 'a qualified charge already exists in staging; overwrite is prohibited';

  BEGIN TRANSACTION;
    MERGE `pacific-plating-282708.sap_integration_v3.sap_payment_qualification_exclusion` t
    USING (SELECT * FROM _qualification WHERE rule_code!='QUALIFIED') s
      ON t.charge_id=s.charge_id AND t.rule_code=s.rule_code
      AND DATE(t.charge_time) BETWEEN v_min_date AND v_max_date
    WHEN NOT MATCHED THEN INSERT
      (charge_id,transaction_id,amount,charge_time,rule_code,reason,detected_at)
    VALUES (s.charge_id,s.transaction_id,s.amount,s.charge_time,s.rule_code,
      CONCAT('Successful charge excluded from SAP interface: ',s.rule_code),CURRENT_TIMESTAMP());

    MERGE `pacific-plating-282708.sap_integration_v3.stg_payment_events` t
    USING _source s ON t.charge_id=s.charge_id
      AND DATE(t.charge_time) BETWEEN v_min_date AND v_max_date
    WHEN NOT MATCHED THEN INSERT
      (charge_id,third_party_id,order_item,order_id,transaction_id,period,amount,charge_time,
       payment_option,payment_method_source,payment_channel_source,lead_human_id,event_refreshed_at)
    VALUES (s.charge_id,s.third_party_id,s.order_item,s.order_id,s.transaction_id,s.period,s.amount,
      s.charge_time,s.payment_option,s.payment_method_source,s.payment_channel_source,
      s.lead_human_id,CURRENT_TIMESTAMP());

    ASSERT (SELECT COUNT(*) FROM _source s
      JOIN `pacific-plating-282708.sap_integration_v3.stg_payment_events` t
        ON t.charge_id=s.charge_id AND DATE(t.charge_time) BETWEEN v_min_date AND v_max_date
      WHERE t.third_party_id IS NOT DISTINCT FROM s.third_party_id
        AND t.order_item=s.order_item AND t.order_id=s.order_id AND t.transaction_id=s.transaction_id
        AND t.period=s.period AND t.amount=s.amount AND t.charge_time=s.charge_time
        AND t.payment_option IS NOT DISTINCT FROM s.payment_option
        AND t.payment_method_source IS NOT DISTINCT FROM s.payment_method_source
        AND t.payment_channel_source IS NOT DISTINCT FROM s.payment_channel_source
        AND t.lead_human_id IS NOT DISTINCT FROM s.lead_human_id)=v_qualified_charges
      AS 'backfill full-field reconciliation failed';
    ASSERT (SELECT COUNT(DISTINCT q.charge_id) FROM _qualification q
      LEFT JOIN `pacific-plating-282708.sap_integration_v3.stg_payment_events` e
        ON e.charge_id=q.charge_id AND DATE(e.charge_time) BETWEEN v_min_date AND v_max_date
      LEFT JOIN `pacific-plating-282708.sap_integration_v3.sap_payment_qualification_exclusion` x
        ON x.charge_id=q.charge_id AND x.rule_code=q.rule_code
        AND DATE(x.charge_time) BETWEEN v_min_date AND v_max_date
      WHERE e.charge_id IS NOT NULL OR x.charge_id IS NOT NULL)=v_raw_charges
      AS 'source charge must end staged or explicitly excluded';
  COMMIT TRANSACTION;
END;

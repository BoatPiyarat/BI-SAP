-- Source only / Class A. V3-owned fail-closed CreditShell flow classifier.
-- It does not alter v2 and does not emit an interface payload or write GCS.

CREATE OR REPLACE VIEW
  `pacific-plating-282708.sap_integration_v3.vw_creditshell_flow_classification` AS
WITH links AS (
  SELECT
    current_human_id,
    COUNT(*) AS link_count,
    ANY_VALUE(old_human_id) AS old_human_id
  FROM `pacific-plating-282708.careos.cancelled_change_orders`
  GROUP BY current_human_id
),
transaction_dim AS (
  SELECT
    id,
    COUNT(DISTINCT payment_option) AS payment_option_count,
    ANY_VALUE(payment_option) AS payment_option
  FROM `pacific-plating-282708.careos.carepay_transactions`
  GROUP BY id
),
order_dim AS (
  SELECT
    o.human_id AS order_id,
    COUNT(DISTINCT t.payment_option) AS payment_option_count,
    ANY_VALUE(t.payment_option) AS payment_option
  FROM `pacific-plating-282708.careos.careos_orders` AS o
  LEFT JOIN transaction_dim AS t
    ON o.payment=CONCAT('transactions/',t.id)
  WHERE DATE(o.create_time)>='2025-01-01'
  GROUP BY o.human_id
),
schedule AS (
  SELECT
    order_id,
    order_item,
    COUNT(DISTINCT flow) AS schedule_flow_count,
    ANY_VALUE(flow) AS flow,
    COUNT(DISTINCT total_periods) AS total_periods_count,
    ANY_VALUE(total_periods) AS total_periods,
    COUNT(*) AS schedule_period_rows,
    COUNT(DISTINCT period) AS schedule_distinct_periods,
    MIN(period) AS min_period,
    MAX(period) AS max_period
  FROM `pacific-plating-282708.sap_integration_v3.stg_schedule`
  GROUP BY order_id,order_item
)
SELECT
  l.current_human_id AS order_id,
  s.order_item,
  l.old_human_id,
  l.link_count,
  o.payment_option,
  s.flow AS schedule_flow,
  s.total_periods,
  s.schedule_period_rows,
  s.schedule_distinct_periods,
  CASE
    WHEN l.link_count!=1 THEN 'HOLD_CHANGE_LINK_AMBIGUOUS'
    WHEN s.order_item IS NULL THEN 'HOLD_SCHEDULE_MISSING'
    WHEN s.schedule_flow_count!=1 OR s.total_periods_count!=1
      THEN 'HOLD_SCHEDULE_CLASSIFICATION_AMBIGUOUS'
    WHEN o.payment_option_count>1 THEN 'HOLD_PAYMENT_OPTION_AMBIGUOUS'
    WHEN o.payment_option IS NULL THEN 'HOLD_PAYMENT_OPTION_NULL'
    WHEN o.payment_option IN ('FULL_PAYMENT','CREDIT_CARD_INSTALLMENT')
      AND (s.flow!='ONETIME' OR s.total_periods!=1 OR s.schedule_period_rows!=1
        OR s.schedule_distinct_periods!=1 OR s.min_period!=1 OR s.max_period!=1)
      THEN 'HOLD_ONETIME_INVARIANT'
    WHEN o.payment_option='RABBIT_CARE_INSTALLMENT'
      AND (s.flow!='RCL' OR s.total_periods<=1 OR s.schedule_period_rows!=s.total_periods
        OR s.schedule_distinct_periods!=s.total_periods OR s.min_period!=1
        OR s.max_period!=s.total_periods)
      THEN 'HOLD_RCL_SPINE_INVALID'
    WHEN o.payment_option NOT IN
      ('FULL_PAYMENT','CREDIT_CARD_INSTALLMENT','RABBIT_CARE_INSTALLMENT')
      THEN 'HOLD_PAYMENT_OPTION_UNKNOWN'
    WHEN o.payment_option IN ('FULL_PAYMENT','CREDIT_CARD_INSTALLMENT')
      THEN 'ROUTE_RCB_CREDITSHELL'
    WHEN o.payment_option='RABBIT_CARE_INSTALLMENT' THEN 'ROUTE_RCL_CREDIT_SHELL'
    ELSE 'HOLD_UNCLASSIFIED'
  END AS routing_decision,
  CASE
    WHEN o.payment_option IN ('FULL_PAYMENT','CREDIT_CARD_INSTALLMENT')
      AND s.schedule_flow_count=1 AND s.total_periods_count=1
      AND s.flow='ONETIME' AND s.total_periods=1
      AND s.schedule_period_rows=1 AND s.schedule_distinct_periods=1
      AND s.min_period=1 AND s.max_period=1 THEN 'RCB-CreditShell'
    WHEN o.payment_option='RABBIT_CARE_INSTALLMENT'
      AND s.schedule_flow_count=1 AND s.total_periods_count=1
      AND s.flow='RCL' AND s.total_periods>1
      AND s.schedule_period_rows=s.total_periods
      AND s.schedule_distinct_periods=s.total_periods
      AND s.min_period=1 AND s.max_period=s.total_periods THEN 'RCL-Credit Shell'
    ELSE NULL
  END AS target_payment_method,
  CASE
    WHEN o.payment_option IN ('FULL_PAYMENT','CREDIT_CARD_INSTALLMENT')
      AND s.schedule_flow_count=1 AND s.total_periods_count=1
      AND s.flow='ONETIME' AND s.total_periods=1
      AND s.schedule_period_rows=1 AND s.schedule_distinct_periods=1
      AND s.min_period=1 AND s.max_period=1 THEN 'RCB-CreditShell'
    WHEN o.payment_option='RABBIT_CARE_INSTALLMENT'
      AND s.schedule_flow_count=1 AND s.total_periods_count=1
      AND s.flow='RCL' AND s.total_periods>1
      AND s.schedule_period_rows=s.total_periods
      AND s.schedule_distinct_periods=s.total_periods
      AND s.min_period=1 AND s.max_period=s.total_periods THEN 'RCL-Credit Shell'
    ELSE NULL
  END AS target_payment_channel
FROM links AS l
LEFT JOIN order_dim AS o ON o.order_id=l.current_human_id
LEFT JOIN schedule AS s ON s.order_id=l.current_human_id;

CREATE OR REPLACE VIEW
  `pacific-plating-282708.sap_integration_v3.vw_creditshell_routing_hold` AS
SELECT
  order_id,order_item,old_human_id,payment_option,schedule_flow,total_periods,
  routing_decision AS rule_code
FROM `pacific-plating-282708.sap_integration_v3.vw_creditshell_flow_classification`
WHERE STARTS_WITH(routing_decision,'HOLD_');

CREATE OR REPLACE VIEW
  `pacific-plating-282708.sap_integration_v3.vw_creditshell_routing_ready` AS
SELECT
  order_id,order_item,old_human_id,payment_option,schedule_flow,total_periods,
  target_payment_method,target_payment_channel
FROM `pacific-plating-282708.sap_integration_v3.vw_creditshell_flow_classification`
WHERE routing_decision IN ('ROUTE_RCB_CREDITSHELL','ROUTE_RCL_CREDIT_SHELL');

-- Durable regression guard consumed by validation/reporting before any future CreditShell export.
CREATE OR REPLACE VIEW
  `pacific-plating-282708.sap_integration_v3.vw_creditshell_routing_violation` AS
SELECT
  order_id,order_item,payment_option,schedule_flow,total_periods,
  target_payment_method,target_payment_channel,
  'ONETIME_ROUTED_TO_RCL' AS rule_code
FROM `pacific-plating-282708.sap_integration_v3.vw_creditshell_flow_classification`
WHERE schedule_flow='ONETIME'
  AND (STARTS_WITH(COALESCE(target_payment_method,''),'RCL')
    OR STARTS_WITH(COALESCE(target_payment_channel,''),'RCL'));

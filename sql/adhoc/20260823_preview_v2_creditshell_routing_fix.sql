-- READ ONLY. Preview for Boat to inspect the live v2 CreditShell routing correction.
-- This file performs no DDL and must not be converted into v2 DDL by an agent.
WITH links AS (
  SELECT current_human_id, COUNT(*) AS link_count, ANY_VALUE(old_human_id) AS old_human_id
  FROM `pacific-plating-282708.careos.cancelled_change_orders`
  GROUP BY current_human_id
),
orders AS (
  SELECT o.human_id AS order_id, t.payment_option
  FROM `pacific-plating-282708.careos.careos_orders` AS o
  LEFT JOIN `pacific-plating-282708.careos.carepay_transactions` AS t
    ON o.payment=CONCAT('transactions/',t.id)
  WHERE DATE(o.create_time)>='2025-01-01'
),
live_rows AS (
  SELECT OrderID,OrderItem,Period,TotalPeriods,PaymentMethod,PaymentChannel
  FROM `pacific-plating-282708.sap_integration_v2.RCL 04_new order credit shell new tunning`
)
SELECT
  CURRENT_TIMESTAMP() AS checked_at,
  r.OrderID,r.OrderItem,r.Period,r.TotalPeriods,o.payment_option,l.old_human_id,l.link_count,
  r.PaymentMethod AS current_payment_method,
  r.PaymentChannel AS current_payment_channel,
  CASE
    WHEN l.link_count!=1 THEN NULL
    WHEN o.payment_option IN ('FULL_PAYMENT','CREDIT_CARD_INSTALLMENT')
      AND SAFE_CAST(r.TotalPeriods AS INT64)=1 THEN 'RCB-CreditShell'
    WHEN o.payment_option='RABBIT_CARE_INSTALLMENT'
      AND SAFE_CAST(r.TotalPeriods AS INT64)>1 THEN 'RCL-Credit Shell'
    ELSE NULL
  END AS proposed_payment_method,
  CASE
    WHEN l.link_count!=1 THEN NULL
    WHEN o.payment_option IN ('FULL_PAYMENT','CREDIT_CARD_INSTALLMENT')
      AND SAFE_CAST(r.TotalPeriods AS INT64)=1 THEN 'RCB-CreditShell'
    WHEN o.payment_option='RABBIT_CARE_INSTALLMENT'
      AND SAFE_CAST(r.TotalPeriods AS INT64)>1 THEN 'RCL-Credit Shell'
    ELSE NULL
  END AS proposed_payment_channel,
  CASE
    WHEN l.link_count!=1 THEN 'HOLD_CHANGE_LINK_AMBIGUOUS'
    WHEN o.payment_option IS NULL THEN 'HOLD_PAYMENT_OPTION_NULL'
    WHEN o.payment_option IN ('FULL_PAYMENT','CREDIT_CARD_INSTALLMENT')
      AND SAFE_CAST(r.TotalPeriods AS INT64)!=1 THEN 'HOLD_ONETIME_PERIOD_INVALID'
    WHEN o.payment_option='RABBIT_CARE_INSTALLMENT'
      AND SAFE_CAST(r.TotalPeriods AS INT64)<=1 THEN 'HOLD_RCL_PERIOD_INVALID'
    WHEN o.payment_option NOT IN
      ('FULL_PAYMENT','CREDIT_CARD_INSTALLMENT','RABBIT_CARE_INSTALLMENT')
      THEN 'HOLD_PAYMENT_OPTION_UNKNOWN'
    WHEN o.payment_option IN ('FULL_PAYMENT','CREDIT_CARD_INSTALLMENT') THEN 'ROUTE_RCB_CREDITSHELL'
    WHEN o.payment_option='RABBIT_CARE_INSTALLMENT' THEN 'ROUTE_RCL_CREDIT_SHELL'
    ELSE 'HOLD_UNCLASSIFIED'
  END AS routing_decision
FROM live_rows AS r
JOIN links AS l ON l.current_human_id=r.OrderID
LEFT JOIN orders AS o ON o.order_id=r.OrderID
ORDER BY r.OrderItem,SAFE_CAST(r.Period AS INT64);

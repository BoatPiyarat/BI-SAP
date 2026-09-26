-- 2026-09-26 same-period payment correction. Source only; not deployed.
-- RCL 05_paid by period -- FIXED & CREATED 2026-08-29 (Boat review)
-- Previously this logic lived (mislabeled) under `RCL 05_newpayment`.
-- Bug fixed here: original version joined `sap` to `charges` (ALL periods
-- ever paid) instead of `charges_ranking` (latest period only), then
-- relied on DISTINCT to collapse -- this let orders where an OLD period
-- was still missing from SAP mask the fact that the LATEST period was
-- already Paid+Paid, producing false "qualified" rows
-- (e.g. "1/10 CareOS paid, SAP paid" wrongly surfaced).
-- Fix: NOT EXISTS check scoped to charges_ranking.installment_number
-- (the actual latest period) plus OrderItem-level join key (was OrderID-only).
WITH charges AS (
  SELECT *
  FROM `pacific-plating-282708.careos.carepay_charges`
  WHERE status = 'SUCCESSFUL'
),

charges_ranking AS (
  SELECT *,
    ROW_NUMBER() OVER (PARTITION BY transaction_id ORDER BY installment_number DESC) AS rank
  FROM charges
  QUALIFY rank = 1
),

sap_paid_periods AS (
  -- exact per-(OrderItem, Period) existence check -- NOT a MAX watermark, NOT an all-period fan-out
  SELECT DISTINCT
    U_OrderItem AS order_item,
    SAFE_CAST(U_Period AS INT64) AS period
  FROM `pacific-plating-282708.sap_integration_v2.SAP_LIVE_FULL`
  WHERE TransactionStatus IN ('Paid', 'paid')
)
,
additional_items AS (
  -- Only genuinely unsent additional events can reopen an already-paid item.
  SELECT DISTINCT OrderItem
  FROM `pacific-plating-282708.sap_integration_v2.RCL 05_newpayment` n
  JOIN `pacific-plating-282708.careos.careos_order_items` oi ON oi.human_id = n.OrderItem
  JOIN `pacific-plating-282708.careos.careos_orders` o ON o.id = oi.order_id
  JOIN `pacific-plating-282708.careos.carepay_charges` c
    ON o.payment = CONCAT('transactions/', c.transaction_id)
    AND c.installment_number = SAFE_CAST(n.Period AS INT64)
    AND n.InvoiceNo = CASE WHEN c.installment_number = 1
      THEN CONCAT('2_', c.third_party_id) ELSE c.third_party_id END
    AND c.status = 'SUCCESSFUL' AND c.service_provider = 'RABBIT_LENDING'
  WHERE ExpectedReceived = 0
    AND ActualReceived > 0
    AND LOWER(TRIM(TransactionStatus)) = 'paid'
    AND NULLIF(TRIM(InvoiceNo), '') IS NOT NULL
    AND UPPER(TRIM(InvoiceNo)) != 'NULL'
    AND DATE(c.update_time)
      BETWEEN DATE_TRUNC(DATE_SUB(CURRENT_DATE(), INTERVAL 2 MONTH), MONTH)
      AND CURRENT_DATE()
)

SELECT DISTINCT
  orders.human_id,
  oi.human_id AS order_item,
  orders.create_time AS order_create_time,
  orders.update_time AS order_update_time,
  orders.is_fully_paid,
  orders.is_cancelled,
  transactions.payment_option,
  charges_ranking.installment_number,
  orders.cancel_time,
  charges_ranking.update_time AS charges_update_time,
  CASE
    WHEN orders.create_time < '2024-03-28' THEN 'icollection'
    ELSE 'carepay'
  END AS sql_view_using,
  orders.product,
  oi.motor_item_type AS InsuranceType
FROM `pacific-plating-282708.careos.careos_orders` AS orders
LEFT JOIN `pacific-plating-282708.careos.careos_order_items` AS oi
  ON orders.id = oi.order_id
LEFT JOIN `pacific-plating-282708.careos.carepay_transactions` AS transactions
  ON CONCAT('transactions/', transactions.id) = orders.payment
LEFT JOIN charges_ranking
  ON charges_ranking.transaction_id = transactions.id
LEFT JOIN additional_items AS additional
  ON additional.OrderItem = oi.human_id
WHERE 1=1
  AND charges_ranking.installment_number IS NOT NULL
  AND (
    DATE(charges_ranking.update_time)
      BETWEEN DATE_TRUNC(DATE_SUB(CURRENT_DATE(), INTERVAL 2 MONTH), MONTH)
      AND CURRENT_DATE()
    OR additional.OrderItem IS NOT NULL
  )
  AND transactions.payment_option = 'RABBIT_CARE_INSTALLMENT'
  AND (
    NOT EXISTS (
      SELECT 1
      FROM sap_paid_periods p
      WHERE p.order_item = oi.human_id
        AND p.period = charges_ranking.installment_number
    )
    OR additional.OrderItem IS NOT NULL
  )
ORDER BY orders.create_time ASC;

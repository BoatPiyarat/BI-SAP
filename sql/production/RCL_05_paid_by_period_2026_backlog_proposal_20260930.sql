-- PROPOSAL ONLY: full SELECT replacement for sap_integration_v2.RCL 05_paid by period.
-- Extends receipt eligibility to 2026 backlog; preserves invoice-aware terminal checks.
-- No deployment. A downstream sap_view payload still requires its full validation gate.
WITH charges AS (
  SELECT id, transaction_id, installment_number, third_party_id, payment_date, create_time, update_time
  FROM `pacific-plating-282708.careos.carepay_charges`
  WHERE status = 'SUCCESSFUL'
),

charges_ranking AS (
  SELECT *,
    ROW_NUMBER() OVER (PARTITION BY transaction_id ORDER BY installment_number DESC, update_time DESC, create_time DESC, id DESC) AS rank
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
outstanding_receipt_items AS (
  -- Any recent unsent receipt can reopen an item, even if a later period is Paid.
  SELECT DISTINCT OrderItem
  FROM `pacific-plating-282708.sap_integration_v2.RCL 05_newpayment` n
  JOIN `pacific-plating-282708.careos.careos_order_items` oi ON oi.human_id = n.OrderItem
  JOIN `pacific-plating-282708.careos.careos_orders` o ON o.id = oi.order_id
  JOIN (
    SELECT transaction_id, installment_number, third_party_id, update_time, payment_date, create_time,
      ROW_NUMBER() OVER (PARTITION BY transaction_id, installment_number ORDER BY create_time, id) AS source_charge_rank
    FROM `pacific-plating-282708.careos.carepay_charges`
    WHERE status='SUCCESSFUL' AND service_provider='RABBIT_LENDING'
  ) c
    ON o.payment = CONCAT('transactions/', c.transaction_id)
    AND c.installment_number = SAFE_CAST(n.Period AS INT64)
    AND n.InvoiceNo = CASE WHEN c.installment_number = 1
      THEN CONCAT('2_', IF(c.source_charge_rank=1, COALESCE(c.third_party_id,oi.human_id),c.third_party_id)) ELSE IF(c.source_charge_rank=1,COALESCE(c.third_party_id,oi.human_id),c.third_party_id) END
    AND c.source_charge_rank >= 1
  WHERE ActualReceived > 0
    AND LOWER(TRIM(TransactionStatus)) = 'paid'
    AND NULLIF(TRIM(InvoiceNo), '') IS NOT NULL
    AND UPPER(TRIM(InvoiceNo)) != 'NULL'
    AND DATE(COALESCE(c.payment_date, c.update_time, c.create_time), 'Asia/Bangkok') >= DATE '2026-01-01'
    AND DATE(COALESCE(c.payment_date, c.update_time, c.create_time), 'Asia/Bangkok') < DATE '2027-01-01'
    AND COALESCE(c.payment_date, c.update_time, c.create_time) <= CURRENT_TIMESTAMP()
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
LEFT JOIN outstanding_receipt_items AS outstanding
  ON outstanding.OrderItem = oi.human_id
WHERE 1=1
  AND charges_ranking.installment_number IS NOT NULL
  AND (
    DATE(COALESCE(charges_ranking.payment_date, charges_ranking.update_time, charges_ranking.create_time), 'Asia/Bangkok') >= DATE '2026-01-01'
    AND DATE(COALESCE(charges_ranking.payment_date, charges_ranking.update_time, charges_ranking.create_time), 'Asia/Bangkok') < DATE '2027-01-01'
    AND COALESCE(charges_ranking.payment_date, charges_ranking.update_time, charges_ranking.create_time) <= CURRENT_TIMESTAMP()
    OR outstanding.OrderItem IS NOT NULL
  )
  AND transactions.payment_option = 'RABBIT_CARE_INSTALLMENT'
  AND (
    NOT EXISTS (
      SELECT 1
      FROM sap_paid_periods p
      WHERE p.order_item = oi.human_id
        AND p.period = charges_ranking.installment_number
    )
    OR outstanding.OrderItem IS NOT NULL
  )
ORDER BY orders.create_time ASC
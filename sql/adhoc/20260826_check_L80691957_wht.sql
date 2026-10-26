WITH o AS (
  SELECT id, human_id, payment FROM `pacific-plating-282708.careos.careos_orders`
  WHERE human_id = 'L80691957'
),
t AS (
  SELECT tr.id AS transaction_id FROM `pacific-plating-282708.careos.carepay_transactions` tr
  JOIN o ON CONCAT('transactions/', tr.id) = o.payment
),
ts AS (
  SELECT s.* FROM `pacific-plating-282708.careos.carepay_transaction_snapshots` s
  JOIN t ON s.transaction_id = t.transaction_id
)
SELECT ts.id AS snapshot_id, ts.is_current, ps.discount_amount, ps.wht_amount, ps.net_premium_amount
FROM ts
JOIN `pacific-plating-282708.careos.carepay_transaction_snapshot_price_summaries` ps ON ps.snapshot_id = ts.id

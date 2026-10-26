-- READ-ONLY. Trace the actual transaction/charge/snapshot values behind order L80512627's
-- combined EDC/KBANK card charge, to find where the 163.94 THB gap between theoretical combined
-- premium and the real charged amount comes from.
WITH o AS (
  SELECT id, human_id, payment FROM `pacific-plating-282708.careos.careos_orders`
  WHERE human_id = 'L80512627'
),
t AS (
  SELECT tr.* FROM `pacific-plating-282708.careos.carepay_transactions` tr
  JOIN o ON CONCAT('transactions/', tr.id) = o.payment
),
c AS (
  SELECT ch.* FROM `pacific-plating-282708.careos.carepay_charges` ch
  JOIN t ON ch.transaction_id = t.id
),
ts AS (
  SELECT tsn.* FROM `pacific-plating-282708.careos.carepay_transaction_snapshots` tsn
  JOIN t ON tsn.transaction_id = t.id
),
tsps AS (
  SELECT ps.* FROM `pacific-plating-282708.careos.carepay_transaction_snapshot_price_summaries` ps
  JOIN ts ON ps.snapshot_id = ts.id
)
SELECT 'charge' AS src, c.amount, c.status, CAST(NULL AS FLOAT64) AS discount_amount, CAST(NULL AS FLOAT64) AS net_discount_amount
FROM c
UNION ALL
SELECT 'price_summary', CAST(NULL AS FLOAT64), CAST(NULL AS STRING),
  tsps.discount_amount, tsps.net_discount_amount
FROM tsps;

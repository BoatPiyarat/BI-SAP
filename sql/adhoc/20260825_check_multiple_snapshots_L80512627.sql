-- READ-ONLY. The view joins transaction_snapshot_price_summaries via transaction_snapshots
-- WITHOUT filtering transaction_snapshots.is_current = TRUE. Check whether L80512627's
-- transaction has multiple snapshots with different discount_amount / price figures - if so,
-- the view may be picking up a stale (non-current) snapshot's discount instead of the real one.
WITH o AS (
  SELECT id, human_id, payment, invoice_price FROM `pacific-plating-282708.careos.careos_orders`
  WHERE human_id = 'L80512627'
),
t AS (
  SELECT tr.id AS transaction_id, tr.amount AS transaction_amount, tr.create_time
  FROM `pacific-plating-282708.careos.carepay_transactions` tr
  JOIN o ON CONCAT('transactions/', tr.id) = o.payment
)
SELECT
  ts.id AS snapshot_id, ts.is_current, ts.version, ts.create_time AS snapshot_create_time,
  ts.number_of_installment, tsps.discount_amount, tsps.processing_fee_amount, tsps.net_premium_amount,
  tsps.initial_amount, t.transaction_amount, o.invoice_price
FROM t
CROSS JOIN o
LEFT JOIN `pacific-plating-282708.careos.carepay_transaction_snapshots` ts ON ts.transaction_id = t.transaction_id
LEFT JOIN `pacific-plating-282708.careos.carepay_transaction_snapshot_price_summaries` tsps ON tsps.snapshot_id = ts.id
ORDER BY ts.create_time;

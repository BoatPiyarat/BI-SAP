WITH o AS (
  SELECT id, human_id, payment FROM `pacific-plating-282708.careos.careos_orders`
  WHERE human_id IN ('L78745610','L80580491','L80616601')
),
t AS (
  SELECT tr.id AS transaction_id, o.human_id FROM `pacific-plating-282708.careos.carepay_transactions` tr
  JOIN o ON CONCAT('transactions/', tr.id) = o.payment
)
SELECT 'snapshot' AS src, t.human_id, ts.id, CAST(ts.is_current AS STRING), CAST(ts.version AS STRING), CAST(ts.number_of_installment AS STRING)
FROM t JOIN `pacific-plating-282708.careos.carepay_transaction_snapshots` ts ON ts.transaction_id = t.transaction_id

UNION ALL

SELECT 'followup', t.human_id, f.id, CAST(f.installment AS STRING), CAST(NULL AS STRING), CAST(NULL AS STRING)
FROM t JOIN `pacific-plating-282708.careos.carepay_follow_ups` f ON f.transaction_id = t.transaction_id

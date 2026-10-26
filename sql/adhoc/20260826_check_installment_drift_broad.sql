WITH o AS (
  SELECT id, human_id, payment FROM `pacific-plating-282708.careos.careos_orders`
  WHERE human_id IN ('L78242486','L78478651','L78525515','L78533160','L78547453','L78593580',
                      'L78599289','L78601967','L78605728','L78614447','L78667850','L78620491')
),
t AS (
  SELECT tr.id AS transaction_id, o.human_id FROM `pacific-plating-282708.careos.carepay_transactions` tr
  JOIN o ON CONCAT('transactions/', tr.id) = o.payment
)
SELECT t.human_id, ts.number_of_installment, ts.is_current
FROM t JOIN `pacific-plating-282708.careos.carepay_transaction_snapshots` ts ON ts.transaction_id = t.transaction_id
ORDER BY t.human_id

WITH o AS (
  SELECT id, human_id, payment FROM `pacific-plating-282708.careos.careos_orders`
  WHERE human_id IN ('L78242486','L78478651','L78525515','L78533160','L78547453','L78593580',
                      'L78599289','L78601967','L78605728','L78614447','L78667850','L78620491')
)
SELECT o.human_id, tr.payment_option
FROM o JOIN `pacific-plating-282708.careos.carepay_transactions` tr
  ON CONCAT('transactions/', tr.id) = o.payment
ORDER BY o.human_id

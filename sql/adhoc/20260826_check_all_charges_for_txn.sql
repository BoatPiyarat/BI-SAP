WITH o AS (
  SELECT id, human_id, payment FROM `pacific-plating-282708.careos.careos_orders`
  WHERE human_id IN ('L78745610','L80580491','L80616601')
),
t AS (
  SELECT tr.id, tr.amount AS tx_amount, o.human_id FROM `pacific-plating-282708.careos.carepay_transactions` tr
  JOIN o ON CONCAT('transactions/', tr.id) = o.payment
)
SELECT t.human_id, c.id AS charge_id, c.amount AS charge_amount, c.status, c.service_provider, c.create_time
FROM `pacific-plating-282708.careos.carepay_charges` c
JOIN t ON c.transaction_id = t.id
ORDER BY t.human_id, c.create_time

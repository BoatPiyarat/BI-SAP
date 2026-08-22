-- Read-only exception trace for SAP-Paid item missing from canonical stg_payment_events.
SELECT
  CURRENT_TIMESTAMP() AS checked_at,
  o.human_id AS order_id,
  i.human_id AS order_item,
  t.id AS transaction_id,
  t.status AS transaction_status,
  t.payment_option,
  t.installments,
  c.id AS charge_id,
  c.status AS charge_status,
  c.installment_number,
  c.amount,
  c.payment_date,
  c.third_party_id
FROM `pacific-plating-282708.careos.careos_order_items` AS i
JOIN `pacific-plating-282708.careos.careos_orders` AS o
  ON o.id = i.order_id
LEFT JOIN `pacific-plating-282708.careos.carepay_transactions` AS t
  ON o.payment = CONCAT('transactions/', t.id)
LEFT JOIN `pacific-plating-282708.careos.carepay_charges` AS c
  ON c.transaction_id = t.id
  AND DATE(c.create_time) >= '2025-01-01'
WHERE i.human_id = 'L80545799-V1'
  AND DATE(i.create_time) >= '2025-01-01'
  AND DATE(o.create_time) >= '2025-01-01'
ORDER BY c.installment_number, c.update_time DESC;

-- Read-only source trace. Executed read-only 2026-09-25; see linked finding for evidence.
-- Preserve every source charge, including non-successful rows and duplicates.
-- One order/charge row; item inventory nested to avoid multiplying charge amounts.
WITH targets AS (
  SELECT id, human_id, payment, product
  FROM `pacific-plating-282708.careos.careos_orders`
  WHERE human_id IN ('L80570054', 'L79109956')
)
, item_inventory AS (
  SELECT oi.order_id, ARRAY_AGG(STRUCT(oi.human_id AS OrderItem, oi.product,
    oi.motor_item_type, oi.is_cancelled, oi.cancel_time) ORDER BY oi.human_id) AS items
  FROM `pacific-plating-282708.careos.careos_order_items` oi
  JOIN targets o ON o.id = oi.order_id GROUP BY oi.order_id
)
SELECT CURRENT_TIMESTAMP() AS checked_at_utc,
  o.human_id AS OrderID, o.id AS order_pk, o.product,
  o.payment AS transaction_reference,
  t.id AS transaction_id, t.payment_option, t.status AS transaction_status,
  c.id AS charge_id, c.third_party_id AS raw_invoice_no,
  c.installment_number AS Period, c.status AS charge_status,
  c.amount AS amount_satang, ROUND(c.amount / 100, 2) AS amount_thb,
  c.payment_method, c.service_provider,
  c.payment_date, c.create_time, c.update_time,
  i.items
FROM targets o LEFT JOIN item_inventory i ON i.order_id = o.id
LEFT JOIN `pacific-plating-282708.careos.carepay_transactions` t
  ON o.payment = CONCAT('transactions/', t.id)
LEFT JOIN `pacific-plating-282708.careos.carepay_charges` c
  ON c.transaction_id = t.id
ORDER BY OrderID, Period, c.create_time, charge_id;



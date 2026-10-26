-- Read-only allocation check for all items sharing the three MS-01 orders.
SELECT
  o.human_id AS OrderID,
  oi.human_id AS OrderItem,
  oi.product,
  oi.packagetype,
  oi.gross_premium,
  oi.is_cancelled,
  oi.cancel_time,
  c.id AS charge_id,
  c.amount AS charge_amount_satang,
  c.payment_method,
  c.service_provider,
  c.payment_date
FROM `pacific-plating-282708.careos.careos_orders` o
JOIN `pacific-plating-282708.careos.careos_order_items` oi
  ON oi.order_id = o.id
JOIN `pacific-plating-282708.careos.carepay_transactions` t
  ON CONCAT('transactions/', t.id) = o.payment
JOIN `pacific-plating-282708.careos.carepay_charges` c
  ON c.transaction_id = t.id
 AND c.status = 'SUCCESSFUL'
WHERE o.human_id IN ('L80720286', 'L80797823', 'L80799909')
ORDER BY OrderID, OrderItem, c.payment_date, c.id;

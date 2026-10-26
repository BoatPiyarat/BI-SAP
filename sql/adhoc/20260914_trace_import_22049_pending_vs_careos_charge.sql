-- Check whether the four SAP Pending anchor periods are already paid in CareOS.

WITH targets AS (
  SELECT OrderItem, AnchorPeriod
  FROM UNNEST([
    STRUCT('L79180940-1' AS OrderItem, 5 AS AnchorPeriod),
    STRUCT('L79308561-1' AS OrderItem, 7 AS AnchorPeriod),
    STRUCT('L79510340-1' AS OrderItem, 6 AS AnchorPeriod),
    STRUCT('L79949677-1' AS OrderItem, 4 AS AnchorPeriod)
  ])
)
SELECT
  t.OrderItem,
  t.AnchorPeriod,
  o.human_id AS OrderID,
  tx.id AS transaction_id,
  tx.payment_option,
  c.installment_number AS charge_period,
  c.id AS charge_id,
  c.third_party_id AS InvoiceNo,
  c.status AS charge_status,
  c.amount,
  c.payment_method,
  c.service_provider,
  COALESCE(c.payment_date, c.update_time) AS charge_time,
  IF(c.installment_number = t.AnchorPeriod, 'ANCHOR_PERIOD', 'OTHER_PERIOD') AS period_role
FROM targets AS t
JOIN `pacific-plating-282708.careos.careos_order_items` AS oi
  ON oi.human_id = t.OrderItem
JOIN `pacific-plating-282708.careos.careos_orders` AS o
  ON o.id = oi.order_id
JOIN `pacific-plating-282708.careos.carepay_transactions` AS tx
  ON CONCAT('transactions/', tx.id) = o.payment
LEFT JOIN `pacific-plating-282708.careos.carepay_charges` AS c
  ON c.transaction_id = tx.id
 AND c.status = 'SUCCESSFUL'
ORDER BY OrderItem, charge_period, charge_time, charge_id;

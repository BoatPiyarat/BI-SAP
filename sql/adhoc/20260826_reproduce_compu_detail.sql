-- Reproduce the view's exact compu_detail CTE logic for our 3 orders to see if it matches anything.
WITH compu_detail AS (
  SELECT
    orders.human_id AS order_id,
    CASE WHEN order_items.gross_premium IS NULL THEN 0 ELSE order_items.gross_premium END AS gross_premium,
    order_items.human_id AS item_human_id
  FROM `pacific-plating-282708.careos.careos_order_items` order_items
  LEFT JOIN `pacific-plating-282708.careos.careos_orders` orders ON order_items.order_id = orders.id
  WHERE order_items.motor_item_type = 'MOTOR_TYPE_COMPULSORY'
    AND orders.product = 'products/car-insurance'
    AND order_items.policy_start_date >= '2025-01-01'
)
SELECT * FROM compu_detail
WHERE order_id IN ('L78745610', 'L80580491', 'L80616601')

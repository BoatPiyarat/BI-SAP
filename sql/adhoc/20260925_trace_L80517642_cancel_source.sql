SELECT CURRENT_TIMESTAMP() AS checked_at_utc, o.human_id AS OrderID, oi.human_id AS OrderItem, oi.product, oi.motor_item_type, oi.is_cancelled, oi.cancel_time, o.payment FROM `pacific-plating-282708.careos.careos_order_items` oi LEFT JOIN `pacific-plating-282708.careos.careos_orders` o ON o.id=oi.order_id WHERE oi.human_id='L80517642-1';


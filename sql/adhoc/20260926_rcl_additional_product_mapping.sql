SELECT CURRENT_TIMESTAMP() AS checked_at_utc,oi.product,oi.motor_item_type,COUNT(*) AS item_count
FROM `pacific-plating-282708.careos.careos_order_items` oi
JOIN `pacific-plating-282708.careos.careos_orders` o ON o.id=oi.order_id
WHERE EXISTS (SELECT 1 FROM `pacific-plating-282708._script46ab18514cd926b622b3c7ad4e224e5f9fa65717.population_a` c WHERE o.payment=CONCAT('transactions/',c.transaction_id))
GROUP BY 2,3;

SELECT human_id, motor_item_type, gross_premium, net_premium, vat_amount, stamp_duty
FROM `pacific-plating-282708.careos.careos_order_items`
WHERE human_id LIKE 'L78745610%' OR human_id LIKE 'L80580491%' OR human_id LIKE 'L80616601%'
ORDER BY human_id

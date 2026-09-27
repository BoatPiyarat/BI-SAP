SELECT 'CANCELLED_MONTH_ITEM_WITHOUT_ORDER' AS metric,COUNT(*) AS row_count
FROM `pacific-plating-282708.careos.careos_order_items` oi
LEFT JOIN `pacific-plating-282708.careos.careos_orders` o ON o.id=oi.order_id
WHERE o.id IS NULL AND (oi.is_cancelled OR oi.cancel_time IS NOT NULL)
AND DATE(oi.cancel_time,'Asia/Bangkok')>=DATE '2026-09-01' AND DATE(oi.cancel_time,'Asia/Bangkok')<DATE '2026-10-01'
UNION ALL
SELECT 'SUCCESSFUL_CHARGE_WITHOUT_ANY_PAID_DATE',COUNT(*)
FROM `pacific-plating-282708.careos.carepay_charges`
WHERE status='SUCCESSFUL' AND payment_date IS NULL AND update_time IS NULL;

-- READ-ONLY. Trace L80512627 order items raw pricing fields directly from careos source tables.
SELECT
  human_id, price, gross_premium, net_premium, vat_amount, stamp_duty, adjusted_premium
FROM `pacific-plating-282708.careos.careos_order_items`
WHERE human_id IN ('L80512627-M1','L80512627-V1')
ORDER BY human_id;

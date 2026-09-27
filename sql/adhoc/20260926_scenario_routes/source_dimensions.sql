SELECT a.order_item,d.order_created_at,d.item_created_at,d.cancel_time,d.order_item_count,d.compulsory_item_count,
 d.payment_option,d.snapshot_periods,d.lead_status,oi.insurer AS source_insurer,
 d.is_change_order_new,d.is_change_order_old,d.item_deleted_at,d.order_deleted_at,
 STRING_AGG(DISTINCT co.old_human_id,',') AS change_old_order_ids
FROM (SELECT DISTINCT order_item FROM `pacific-plating-282708._script854956d6400364d5179432334ac884bec17498b8.audit_result` WHERE reconciliation_status='MISSING_TERMINAL_SAP_EVIDENCE' AND order_item IS NOT NULL) a
JOIN `pacific-plating-282708._script854956d6400364d5179432334ac884bec17498b8.dimensions` d USING(order_item)
LEFT JOIN `pacific-plating-282708.careos.careos_order_items` oi ON oi.id=d.item_pk
LEFT JOIN `pacific-plating-282708.careos.cancelled_change_orders` co ON co.current_human_id=d.order_id
GROUP BY a.order_item,d.order_created_at,d.item_created_at,d.cancel_time,d.order_item_count,d.compulsory_item_count,d.payment_option,d.snapshot_periods,d.lead_status,oi.insurer,d.is_change_order_new,d.is_change_order_old,d.item_deleted_at,d.order_deleted_at;

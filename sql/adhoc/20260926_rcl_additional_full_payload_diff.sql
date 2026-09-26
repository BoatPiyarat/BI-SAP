WITH added AS (
 SELECT TO_JSON_STRING(c) AS payload FROM `pacific-plating-282708._script4f06476e8de4bc85e3fcd9aa533fc6d797e4adf1.candidate_wrapper` c
 EXCEPT DISTINCT SELECT TO_JSON_STRING(b) FROM `pacific-plating-282708._script4f06476e8de4bc85e3fcd9aa533fc6d797e4adf1.baseline_wrapper` b
), extras AS (
 SELECT c.OrderItem,c.Period,c.InvoiceNo,c.ActualReceived,c.PaymentDate
 FROM `pacific-plating-282708._script4f06476e8de4bc85e3fcd9aa533fc6d797e4adf1.candidate_wrapper` c
 JOIN added a ON a.payload=TO_JSON_STRING(c)
 WHERE c.ExpectedReceived=0 AND c.ActualReceived>0
)
SELECT CURRENT_TIMESTAMP() AS checked_at_utc,
 (SELECT COUNT(*) FROM (SELECT TO_JSON_STRING(b) FROM `pacific-plating-282708._script4f06476e8de4bc85e3fcd9aa533fc6d797e4adf1.baseline_wrapper` b EXCEPT DISTINCT SELECT TO_JSON_STRING(c) FROM `pacific-plating-282708._script4f06476e8de4bc85e3fcd9aa533fc6d797e4adf1.candidate_wrapper` c)) AS full_payload_old_rows_removed,
 (SELECT COUNT(*) FROM (SELECT TO_JSON_STRING(b) FROM `pacific-plating-282708._script4f06476e8de4bc85e3fcd9aa533fc6d797e4adf1.baseline_dashboard` b EXCEPT DISTINCT SELECT TO_JSON_STRING(c) FROM `pacific-plating-282708._script4f06476e8de4bc85e3fcd9aa533fc6d797e4adf1.candidate_dashboard` c)) AS dashboard_old_rows_removed,
 (SELECT COUNT(*) FROM added) AS added_payload_rows,
 (SELECT COUNT(*) FROM extras) AS added_additional_rows,
 (SELECT COUNT(DISTINCT OrderItem) FROM extras) AS additional_items,
 (SELECT ROUND(SUM(ActualReceived),2) FROM extras) AS additional_actual_received_thb,
 (SELECT COUNT(*) FROM extras e
 JOIN `pacific-plating-282708.careos.careos_order_items` oi ON oi.human_id=e.OrderItem
 JOIN `pacific-plating-282708.careos.careos_orders` o ON o.id=oi.order_id
 JOIN `pacific-plating-282708.careos.carepay_charges` c ON o.payment=CONCAT('transactions/',c.transaction_id)
 AND c.installment_number=SAFE_CAST(e.Period AS INT64)
 AND e.InvoiceNo=CASE WHEN c.installment_number=1 THEN CONCAT('2_',c.third_party_id) ELSE c.third_party_id END
 WHERE DATE(c.update_time)<DATE_TRUNC(DATE_SUB(CURRENT_DATE(),INTERVAL 2 MONTH),MONTH)) AS old_events_carried_by_recent_item;

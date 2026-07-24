-- BASELINE CAPTURE 2026-07-25 -- pulled verbatim from live BigQuery view definition
-- Object: sap_view.RCB_NonMotor_process_2_cancel
-- Part of the 11 sap_view process views confirmed as real nightly production, that
-- read directly from sap_integration_v2.SAP_LIVE_FULL. Repointing to
-- sap_integration_v3.stg_sap_state (deduped, no duplicate (OrderItem,Period) rows).
-- See docs/knowledge/30_SAP_CHANGELOG.md 2026-07-25 entry.

--Cancel--
WITH cancel as (SELECT i.human_id
FROM `pacific-plating-282708.careos.careos_order_items` i 
LEFT JOIN `pacific-plating-282708.sap_integration_v3.stg_sap_state` sap
ON sap.U_OrderItem = i.human_id
WHERE i.product = 'products/health-insurance'
AND (i.cancel_time IS NOT NULL )
AND sap.U_OrderID like '%C%'

),

refunds AS (SELECT distinct i.human_id
FROM `pacific-plating-282708.careos.careos_order_items` i 
LEFT JOIN  `pacific-plating-282708.careos.refunds` s
ON SPLIT(s.order_item, "/")[OFFSET(3)] = i.id
INNER JOIN pacific-plating-282708.careos.careos_accounting a
ON a.id = i.id
WHERE 
 i.product = 'products/health-insurance'
AND (i.cancel_time IS NOT NULL
OR s.human_id IS NOT NULL
OR i.underwriting_status = 'ITEM_UNDERWRITING_STATUS_REJECTED'
OR a.cancellation_status is NOT NULL)
)


SELECT non.* 
FROM `pacific-plating-282708.sap_integration_v2.2_nonMotor_items_cancel` non
LEFT JOIN cancel ON cancel.human_id = non.OrderItem
LEFT JOIN refunds ON non.OrderItem = refunds.human_id
WHERE cancel.human_id IS NULL
AND refunds.human_id IS NOT NULL

Order BY OrderItem, Period
;

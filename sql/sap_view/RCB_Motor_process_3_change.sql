-- BASELINE CAPTURE 2026-07-25 -- pulled verbatim from live BigQuery view definition
-- Object: sap_view.RCB_Motor_process_3_change
-- Part of the 11 sap_view process views confirmed as real nightly production, that
-- read directly from sap_integration_v2.SAP_LIVE_FULL. Repointing to
-- sap_integration_v3.stg_sap_state (deduped, no duplicate (OrderItem,Period) rows).
-- See docs/knowledge/30_SAP_CHANGELOG.md 2026-07-25 entry.

--cancelled change order--
WITH cancelled AS (
  SELECT U_OrderItem
  FROM `pacific-plating-282708.sap_integration_v2.SAP_LIVE_FULL`
  WHERE (U_OrderID LIKE '%C%' OR TransactionStatus LIKE ('%Cancelled%'))
  AND (PaymentChannel LIKE '%RCB%' OR PaymentChannel = 'Credit Shell')
)

SELECT DISTINCT interface.* except(cancel_time)
FROM `pacific-plating-282708.sap_integration_v2.03_cancel change orders` interface
LEFT JOIN cancelled
  ON interface.OrderItem = cancelled.U_OrderItem
WHERE 
interface.TransactionStatus = 'Cancelled (Change order / Rejected)'
AND cancelled.U_OrderItem IS NULL
AND OrderID <> 'L78639783' --Insurer/22
Order by OrderID
;

-- BASELINE CAPTURE 2026-07-25 -- pulled verbatim from live BigQuery view definition
-- Object: sap_view.RCB_Motor_process_4_creditshell
-- Part of the 11 sap_view process views confirmed as real nightly production, that
-- read directly from sap_integration_v2.SAP_LIVE_FULL. Repointing to
-- sap_integration_v3.stg_sap_state (deduped, no duplicate (OrderItem,Period) rows).
-- See docs/knowledge/30_SAP_CHANGELOG.md 2026-07-25 entry.

--create new order form credit shell--
WITH sap AS (
  SELECT distinct U_OrderItem
  FROM pacific-plating-282708.sap_integration_v2.SAP_LIVE_FULL
)

SELECT DISTINCT interface.*
FROM `pacific-plating-282708.sap_integration_v2.04_new order credit shell` interface
LEFT JOIN sap
  ON interface.OrderItem = sap.U_OrderItem
WHERE sap.U_OrderItem IS NULL
AND FirstName <> 'Test'
AND ActualReceived NOT LIKE '%-%'
AND interface.OrderID NOT IN (
  -- 4 orders are non-motor (Muang Thai Life Assurance PCL)
  'L79242348','L79258562','L79258563','L79275933'
)

ORDER BY interface.OrderID, interface.OrderDate;


--new create order--
WITH sap AS (
  SELECT U_OrderItem
  FROM `pacific-plating-282708.sap_integration_v2.SAP_LIVE_FULL`
)

SELECT distinct interface.*
FROM `pacific-plating-282708.sap_data_engineer.sap_dashboard_carepay_fully_paid` interface
LEFT JOIN sap s
  ON interface.OrderItem = s.U_OrderItem
WHERE s.U_OrderItem IS NULL
AND
ExpectedReceived IS NOT NULL
AND FirstName <> 'Test'
AND InsurerCode NOT IN ('22', '49','45')
AND OrderDate NOT LIKE '%2025'


ORDER BY interface.OrderID, OrderItem;

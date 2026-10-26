-- Report-only trace for the explicit insurer exclusions in RCB_Motor_process_create.

WITH upstream AS (
  SELECT interface.*
  FROM `pacific-plating-282708.sap_data_engineer.sap_dashboard_carepay_fully_paid` AS interface
  WHERE interface.InsurerCode IN ('22', '49', '45')
    AND interface.ExpectedReceived IS NOT NULL
    AND interface.FirstName <> 'Test'
    AND interface.OrderDate NOT LIKE '%2025'
    AND NOT EXISTS (
      SELECT 1
      FROM `pacific-plating-282708.sap_integration_v2.SAP_LIVE_FULL` AS sap
      WHERE sap.U_OrderItem = interface.OrderItem
    )
)

SELECT
  (SELECT COUNT(*) FROM upstream) AS excluded_rows,
  (SELECT COUNT(DISTINCT OrderItem) FROM upstream) AS excluded_items,
  ARRAY(
    SELECT AS STRUCT InsurerCode, InsuranceGroup, InsuranceType,
      COUNT(*) AS row_count, COUNT(DISTINCT OrderItem) AS item_count
    FROM upstream
    GROUP BY InsurerCode, InsuranceGroup, InsuranceType
    ORDER BY InsurerCode, InsuranceType
  ) AS shapes,
  ARRAY(
    SELECT AS STRUCT OrderID, OrderItem, InsurerCode, InsuranceType,
      InvoiceNo, PaymentMethod, PaymentChannel, ExpectedReceived, ActualReceived
    FROM upstream
    ORDER BY OrderItem
  ) AS excluded_details;

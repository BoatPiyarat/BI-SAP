-- Read-only trace for SAP import Upload LogID 22049.
-- Failed file: RCB_MOTOR_INSURANCE_RCB_02_RCB_MOTOR_PROCESS_2_CANCEL_NEW_20260913.csv

WITH
  target_orders AS (
    SELECT OrderID
    FROM UNNEST([
      'L74079056', 'L77083183', 'L77121047', 'L77833033',
      'L79180940', 'L79308561', 'L79510340', 'L79949677',
      'L80511750', 'L80513404', 'L80518454'
    ]) AS OrderID
  ),

  interface_rows AS (
    SELECT v.*
    FROM `pacific-plating-282708.sap_view.RCB_Motor_process_2_cancel_new` AS v
    JOIN target_orders USING (OrderID)
  ),

  sap_by_period AS (
    SELECT
      sap.U_OrderItem AS OrderItem,
      SAFE_CAST(sap.U_Period AS INT64) AS Period,
      COUNT(*) AS sap_row_count,
      STRING_AGG(DISTINCT sap.TransactionStatus, ' | ' ORDER BY sap.TransactionStatus) AS sap_statuses,
      STRING_AGG(DISTINCT NULLIF(sap.U_InvoiceNo, 'NULL'), ' | ' ORDER BY NULLIF(sap.U_InvoiceNo, 'NULL')) AS sap_invoices,
      STRING_AGG(DISTINCT NULLIF(sap.U_ProductType, 'NULL'), ' | ' ORDER BY NULLIF(sap.U_ProductType, 'NULL')) AS sap_product_types
    FROM `pacific-plating-282708.sap_integration_v2.SAP_LIVE_FULL` AS sap
    WHERE sap.U_OrderID IN (SELECT OrderID FROM target_orders)
    GROUP BY sap.U_OrderItem, Period
  ),

  traced AS (
    SELECT
      i.OrderID,
      i.OrderItem,
      SAFE_CAST(i.Period AS INT64) AS Period,
      SAFE_CAST(i.TotalPeriods AS INT64) AS TotalPeriods,
      i.InvoiceNo,
      i.ProductType,
      i.TransactionStatus,
      i.PaymentDate,
      i.ExpectedDate,
      i.BatchRunDate,
      SAFE_CAST(i.TotalEIR AS FLOAT64) AS TotalEIR,
      SAFE_CAST(i.InterestEIRThisPeriod AS FLOAT64) AS InterestEIRThisPeriod,
      SAFE_CAST(i.ExpectedReceived AS FLOAT64) AS ExpectedReceived,
      SAFE_CAST(i.ActualReceived AS FLOAT64) AS ActualReceived,
      SAFE_CAST(i.PendingPayment AS FLOAT64) AS PendingPayment,
      s.sap_row_count,
      s.sap_statuses,
      s.sap_invoices,
      s.sap_product_types,
      SUM(COALESCE(SAFE_CAST(i.InterestEIRThisPeriod AS FLOAT64), 0)) OVER (
        PARTITION BY i.OrderItem
      ) AS interface_sum_interest_eir,
      IF(s.OrderItem IS NULL, 'SUPPLEMENTED_NOT_IN_SAP', 'SAP_BACKED') AS row_origin,
      IF(
        s.OrderItem IS NULL
          OR NOT REGEXP_CONTAINS(COALESCE(s.sap_statuses, ''), r'(?i)paid|pending'),
        1,
        0
      ) AS predicts_policy_status_error,
      IF(
        s.OrderItem IS NOT NULL
          AND NULLIF(i.InvoiceNo, '') IS NOT NULL
          AND NOT REGEXP_CONTAINS(
            CONCAT('|', COALESCE(s.sap_invoices, ''), '|'),
            CONCAT(r'\|', REGEXP_REPLACE(i.InvoiceNo, r'([\\.^$|?*+(){}\[\]])', r'\\\1'), r'\|')
          ),
        1,
        0
      ) AS predicts_invoice_immutable_error,
      IF(i.ProductType != 'Insurance', 1, 0) AS predicts_product_type_error
    FROM interface_rows AS i
    LEFT JOIN sap_by_period AS s
      ON s.OrderItem = i.OrderItem
     AND s.Period = SAFE_CAST(i.Period AS INT64)
  )

SELECT
  *,
  IF(
    ABS(COALESCE(TotalEIR, 0) - interface_sum_interest_eir) > 0.01,
    1,
    0
  ) AS predicts_total_eir_error
FROM traced
ORDER BY OrderID, OrderItem, Period, InvoiceNo;

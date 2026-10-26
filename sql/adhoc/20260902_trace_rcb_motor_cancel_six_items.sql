-- Read-only trace for the six current cancel-spine failures.

WITH targets AS (
  SELECT item
  FROM UNNEST([
    'L77833033-V1',
    'L78563233-V1',
    'L78563312-V1',
    'L80511750-V1',
    'L80513404-V1',
    'L80518454-V1'
  ]) AS item
),
sap_distinct AS (
  SELECT DISTINCT sap.*
  FROM `pacific-plating-282708.sap_integration_v2.SAP_LIVE_FULL` AS sap
  JOIN targets
    ON targets.item = sap.U_OrderItem
),
sap_ranked AS (
  SELECT
    sap.*,
    ROW_NUMBER() OVER (
      PARTITION BY U_OrderItem, U_Period
      ORDER BY TransactionStatus, U_InvoiceNo, BatchRunDate DESC
    ) AS legacy_dup,
    FARM_FINGERPRINT(TO_JSON_STRING(sap)) AS full_row_fingerprint
  FROM sap_distinct AS sap
)

SELECT
  U_OrderItem AS OrderItem,
  U_OrderID AS OrderID,
  U_Period AS Period,
  TotalPeriods,
  TransactionStatus,
  U_InvoiceNo AS InvoiceNo,
  ExpectedReceived,
  U_ActualReceived AS ActualReceived,
  PaymentDate,
  PaymentMethod,
  PaymentChannel,
  BatchRunDate,
  legacy_dup,
  full_row_fingerprint,
  CASE
    WHEN U_Period = 1 AND legacy_dup = 1 THEN 'SELECTED_PERIOD_1_WINNER'
    WHEN U_Period = 1 AND ExpectedReceived = 0 THEN 'SELECTED_PERIOD_1_ZERO_EXPECTED'
    WHEN U_Period > 1 AND legacy_dup = 1 THEN 'SELECTED_LATER_PERIOD_WINNER'
    ELSE 'FILTERED_OUT'
  END AS legacy_filter_result
FROM sap_ranked
ORDER BY OrderItem, Period, legacy_dup, BatchRunDate DESC;

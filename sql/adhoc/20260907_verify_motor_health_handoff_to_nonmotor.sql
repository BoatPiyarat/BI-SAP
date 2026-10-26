-- Read-only handoff coverage check for Health rows removed from
-- sap_view.RCL_Motor_process_2_newpayment by the Motor-only root fix.

WITH
motor_health AS (
  SELECT
    OrderID,
    OrderItem,
    SAFE_CAST(Period AS INT64) AS Period,
    NULLIF(TRIM(InvoiceNo), '') AS InvoiceNo,
    SAFE_CAST(ExpectedReceived AS NUMERIC) AS ExpectedReceived,
    SAFE_CAST(ActualReceived AS NUMERIC) AS ActualReceived,
    TransactionStatus
  FROM `pacific-plating-282708.sap_view.RCL_Motor_process_2_newpayment`
  WHERE InsuranceGroup = 'Health'
),

nonmotor AS (
  SELECT
    OrderID,
    OrderItem,
    SAFE_CAST(Period AS INT64) AS Period,
    NULLIF(TRIM(InvoiceNo), '') AS InvoiceNo,
    SAFE_CAST(ExpectedReceived AS NUMERIC) AS ExpectedReceived,
    SAFE_CAST(ActualReceived AS NUMERIC) AS ActualReceived,
    TransactionStatus
  FROM `pacific-plating-282708.sap_view.RCL_NonMotor_process_2_newpayment`
  WHERE InsuranceGroup = 'Health'
),

sap_paid AS (
  SELECT
    U_OrderItem AS OrderItem,
    SAFE_CAST(U_Period AS INT64) AS Period,
    NULLIF(TRIM(U_InvoiceNo), '') AS InvoiceNo
  FROM `pacific-plating-282708.sap_integration_v2.SAP_LIVE_FULL`
  WHERE U_InsuranceGroup = 'Health'
    AND LOWER(TRIM(TransactionStatus)) = 'paid'
),

row_coverage AS (
  SELECT
    motor_health.*,
    EXISTS (
      SELECT 1
      FROM nonmotor
      WHERE nonmotor.OrderItem = motor_health.OrderItem
        AND nonmotor.Period = motor_health.Period
        AND COALESCE(nonmotor.InvoiceNo, '') = COALESCE(motor_health.InvoiceNo, '')
    ) AS exact_business_key_covered,
    EXISTS (
      SELECT 1
      FROM nonmotor
      WHERE nonmotor.OrderItem = motor_health.OrderItem
        AND nonmotor.Period = motor_health.Period
    ) AS period_covered,
    EXISTS (
      SELECT 1
      FROM nonmotor
      WHERE nonmotor.OrderItem = motor_health.OrderItem
    ) AS item_covered
    ,
    EXISTS (
      SELECT 1
      FROM sap_paid
      WHERE sap_paid.OrderItem = motor_health.OrderItem
        AND sap_paid.Period = motor_health.Period
        AND COALESCE(sap_paid.InvoiceNo, '') = COALESCE(motor_health.InvoiceNo, '')
    ) AS exact_sap_paid_covered
  FROM motor_health
),

item_coverage AS (
  SELECT
    OrderID,
    OrderItem,
    COUNT(*) AS motor_health_rows,
    COUNTIF(exact_business_key_covered) AS exact_covered_rows,
    COUNTIF(period_covered) AS period_covered_rows,
    COUNTIF(exact_business_key_covered OR exact_sap_paid_covered) AS safely_covered_rows,
    LOGICAL_OR(item_covered) AS item_covered
  FROM row_coverage
  GROUP BY OrderID, OrderItem
)

SELECT
  CASE
    WHEN COUNTIF(safely_covered_rows != motor_health_rows) = 0
    THEN 'GREEN'
    ELSE 'RED'
  END AS verdict,
  COUNT(*) AS motor_health_items,
  SUM(motor_health_rows) AS motor_health_rows,
  COUNTIF(item_covered) AS items_covered_in_nonmotor,
  SUM(period_covered_rows) AS rows_covered_by_item_period,
  SUM(exact_covered_rows) AS rows_covered_by_item_period_invoice,
  SUM(safely_covered_rows - exact_covered_rows) AS rows_covered_by_existing_sap_paid,
  COUNTIF(safely_covered_rows != motor_health_rows) AS items_not_safely_covered,
  ARRAY(
    SELECT AS STRUCT
      OrderID, OrderItem, motor_health_rows, exact_covered_rows, safely_covered_rows,
      period_covered_rows, item_covered
    FROM item_coverage
    WHERE safely_covered_rows != motor_health_rows
    ORDER BY OrderItem
    LIMIT 50
  ) AS missing_samples
FROM item_coverage;

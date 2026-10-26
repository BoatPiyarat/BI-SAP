-- Red/green reproduction for the reported pending-V1 payload defect.
-- Expected business rule for pending periods:
--   InvoiceNo/PaymentDate/PaymentMethod/PaymentChannel = blank,
--   ExpectedReceived = scheduled amount, ActualReceived = 0,
--   and periods form a complete 1..TotalPeriods spine.

WITH
  eligible_rcl_items AS (
    SELECT DISTINCT order_items.human_id AS OrderItem
    FROM `pacific-plating-282708.careos.careos_orders` AS orders
    JOIN `pacific-plating-282708.careos.careos_order_items` AS order_items
      ON order_items.order_id = orders.id
    JOIN `pacific-plating-282708.careos.carepay_transactions` AS transactions
      ON CONCAT('transactions/', transactions.id) = orders.payment
     AND transactions.payment_option = 'RABBIT_CARE_INSTALLMENT'
    WHERE EXISTS (
      SELECT 1
      FROM `pacific-plating-282708.careos.carepay_charges` AS charges
      WHERE charges.transaction_id = transactions.id
        AND charges.status = 'SUCCESSFUL'
        AND charges.service_provider = 'RABBIT_LENDING'
    )
  ),

  interface AS (
    SELECT dashboard.*
    FROM `pacific-plating-282708.sap_data_engineer.sap_dashboard_carepay_installment` AS dashboard
    JOIN eligible_rcl_items USING (OrderItem)
  ),

  filtered AS (
    SELECT interface.*
    FROM interface
    WHERE interface.OrderItem NOT IN (
      SELECT U_OrderItem
      FROM `pacific-plating-282708.sap_integration_v2.SAP_LIVE_FULL`
    )
      AND interface.OrderID NOT IN (
        SELECT current_human_id
        FROM `pacific-plating-282708.careos.cancelled_change_orders`
      )
      AND interface.OrderDate NOT LIKE '%2023%'
      AND interface.OrderDate NOT LIKE '%2024%'
      AND interface.InsurerCode NOT IN ('45', '49')
      AND LOWER(TRIM(COALESCE(interface.FirstName, ''))) != 'test'
      AND LOWER(TRIM(COALESCE(interface.LastName, ''))) != 'test'
  ),

  spine_metrics AS (
    SELECT
      OrderItem,
      COUNT(*) AS row_count,
      COUNT(DISTINCT SAFE_CAST(Period AS INT64)) AS distinct_periods,
      MIN(SAFE_CAST(Period AS INT64)) AS min_period,
      MAX(SAFE_CAST(Period AS INT64)) AS max_period,
      COUNT(DISTINCT SAFE_CAST(TotalPeriods AS INT64)) AS total_period_versions,
      MAX(SAFE_CAST(TotalPeriods AS INT64)) AS total_periods,
      COUNTIF(SAFE_CAST(ExpectedReceived AS FLOAT64) IS NULL) AS null_expected_rows,
      COUNTIF(SAFE_CAST(ActualReceived AS FLOAT64) IS NULL) AS null_actual_rows,
      COUNTIF(NULLIF(TRIM(COALESCE(ExpectedDate, '')), '') IS NULL)
        AS blank_expected_date_rows
    FROM filtered
    GROUP BY OrderItem
  ),

  candidate AS (
    SELECT filtered.*
    FROM filtered
    JOIN spine_metrics USING (OrderItem)
    WHERE
      (
        filtered.InsuranceType = 'MOTOR_TYPE_COMPULSORY'
        AND SAFE_CAST(filtered.Period AS INT64) = 1
        AND SAFE_CAST(filtered.TotalPeriods AS INT64) = 1
        AND SAFE_CAST(filtered.ExpectedReceived AS FLOAT64) IS NOT NULL
        AND SAFE_CAST(filtered.ActualReceived AS FLOAT64) IS NOT NULL
        AND NULLIF(TRIM(COALESCE(filtered.ExpectedDate, '')), '') IS NOT NULL
      )
      OR (
        COALESCE(filtered.InsuranceType, '') != 'MOTOR_TYPE_COMPULSORY'
        AND spine_metrics.row_count > 1
        AND spine_metrics.total_periods > 1
        AND spine_metrics.total_period_versions = 1
        AND spine_metrics.min_period = 1
        AND spine_metrics.max_period = spine_metrics.total_periods
        AND spine_metrics.distinct_periods = spine_metrics.total_periods
        AND spine_metrics.null_expected_rows = 0
        AND spine_metrics.null_actual_rows = 0
        AND spine_metrics.blank_expected_date_rows = 0
      )
  ),

  pending_v1 AS (
    SELECT *
    FROM candidate
    WHERE COALESCE(InsuranceType, '') != 'MOTOR_TYPE_COMPULSORY'
      AND LOWER(COALESCE(TransactionStatus, 'pending')) = 'pending'
  ),

  v1_spines AS (
    SELECT
      OrderItem,
      MAX(SAFE_CAST(TotalPeriods AS INT64)) AS total_periods,
      MIN(SAFE_CAST(Period AS INT64)) AS min_period,
      MAX(SAFE_CAST(Period AS INT64)) AS max_period,
      COUNT(DISTINCT SAFE_CAST(Period AS INT64)) AS distinct_periods,
      COUNTIF(SAFE_CAST(Period AS INT64) IS NULL) AS null_period_rows,
      COUNTIF(SAFE_CAST(TotalPeriods AS INT64) IS NULL) AS null_total_period_rows
    FROM candidate
    WHERE COALESCE(InsuranceType, '') != 'MOTOR_TYPE_COMPULSORY'
    GROUP BY OrderItem
  ),

  failing_samples AS (
    SELECT
      OrderID, OrderItem, Period, TotalPeriods, TransactionStatus,
      InvoiceNo, ExpectedReceived, ActualReceived,
      PaymentDate, PaymentMethod, PaymentChannel, ExpectedDate
    FROM pending_v1
    WHERE SAFE_CAST(ExpectedReceived AS FLOAT64) IS NULL
      OR SAFE_CAST(ActualReceived AS FLOAT64) IS NULL
      OR SAFE_CAST(ActualReceived AS FLOAT64) != 0
      OR NULLIF(TRIM(COALESCE(InvoiceNo, '')), '') IS NOT NULL
      OR NULLIF(TRIM(COALESCE(PaymentDate, '')), '') IS NOT NULL
      OR NULLIF(TRIM(COALESCE(PaymentMethod, '')), '') IS NOT NULL
      OR NULLIF(TRIM(COALESCE(PaymentChannel, '')), '') IS NOT NULL
  )

SELECT
  CASE
    WHEN COUNTIF(SAFE_CAST(ExpectedReceived AS FLOAT64) IS NULL) = 0
      AND COUNTIF(SAFE_CAST(ActualReceived AS FLOAT64) IS NULL) = 0
      AND COUNTIF(SAFE_CAST(ActualReceived AS FLOAT64) != 0) = 0
      AND COUNTIF(NULLIF(TRIM(COALESCE(InvoiceNo, '')), '') IS NOT NULL) = 0
      AND COUNTIF(NULLIF(TRIM(COALESCE(PaymentDate, '')), '') IS NOT NULL) = 0
      AND COUNTIF(NULLIF(TRIM(COALESCE(PaymentMethod, '')), '') IS NOT NULL) = 0
      AND COUNTIF(NULLIF(TRIM(COALESCE(PaymentChannel, '')), '') IS NOT NULL) = 0
      AND (SELECT COUNT(*) FROM v1_spines
        WHERE min_period != 1
          OR max_period != total_periods
          OR distinct_periods != total_periods
          OR null_period_rows > 0
          OR null_total_period_rows > 0) = 0
    THEN 'PASS'
    ELSE 'FAIL'
  END AS verdict,
  COUNT(*) AS pending_v1_rows,
  COUNT(DISTINCT OrderItem) AS pending_v1_items,
  COUNTIF(NULLIF(TRIM(COALESCE(InvoiceNo, '')), '') IS NULL) AS blank_invoice_rows,
  COUNTIF(SAFE_CAST(ExpectedReceived AS FLOAT64) IS NULL) AS null_expected_rows,
  COUNTIF(SAFE_CAST(ActualReceived AS FLOAT64) IS NULL) AS null_actual_rows,
  COUNTIF(SAFE_CAST(ActualReceived AS FLOAT64) != 0) AS nonzero_actual_rows,
  COUNTIF(NULLIF(TRIM(COALESCE(PaymentDate, '')), '') IS NOT NULL)
    AS nonblank_payment_date_rows,
  COUNTIF(NULLIF(TRIM(COALESCE(PaymentMethod, '')), '') IS NOT NULL)
    AS nonblank_payment_method_rows,
  COUNTIF(NULLIF(TRIM(COALESCE(PaymentChannel, '')), '') IS NOT NULL)
    AS nonblank_payment_channel_rows,
  (SELECT COUNT(*) FROM v1_spines
    WHERE min_period != 1
      OR max_period != total_periods
      OR distinct_periods != total_periods
      OR null_period_rows > 0
      OR null_total_period_rows > 0) AS incomplete_v1_spines,
  ARRAY(
    SELECT AS STRUCT *
    FROM failing_samples
    ORDER BY OrderItem, Period
    LIMIT 30
  ) AS failing_samples
FROM pending_v1;

-- Read-only validation for the source-only RCL Motor create M1 fix.
-- This repeats the candidate wrapper in a CTE so no live view replacement is needed.

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

  upstream AS (
    SELECT dashboard.*
    FROM `pacific-plating-282708.sap_data_engineer.sap_dashboard_carepay_installment` AS dashboard
    JOIN eligible_rcl_items USING (OrderItem)
  ),

  filtered AS (
    SELECT upstream.*
    FROM upstream
    WHERE upstream.OrderItem NOT IN (
      SELECT U_OrderItem
      FROM `pacific-plating-282708.sap_integration_v2.SAP_LIVE_FULL`
    )
      AND upstream.OrderID NOT IN (
        SELECT current_human_id
        FROM `pacific-plating-282708.careos.cancelled_change_orders`
      )
      AND upstream.OrderDate NOT LIKE '%2023%'
      AND upstream.OrderDate NOT LIKE '%2024%'
      AND upstream.InsurerCode NOT IN ('45', '49')
      AND LOWER(TRIM(COALESCE(upstream.FirstName, ''))) != 'test'
      AND LOWER(TRIM(COALESCE(upstream.LastName, ''))) != 'test'
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
        InsuranceType = 'MOTOR_TYPE_COMPULSORY'
        AND SAFE_CAST(Period AS INT64) = 1
        AND SAFE_CAST(TotalPeriods AS INT64) = 1
        AND SAFE_CAST(ExpectedReceived AS FLOAT64) IS NOT NULL
        AND SAFE_CAST(ActualReceived AS FLOAT64) IS NOT NULL
        AND NULLIF(TRIM(COALESCE(ExpectedDate, '')), '') IS NOT NULL
      )
      OR (
        COALESCE(InsuranceType, '') != 'MOTOR_TYPE_COMPULSORY'
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
  )

SELECT
  COUNT(*) AS candidate_rows,
  COUNT(DISTINCT OrderItem) AS candidate_items,
  COUNTIF(InsuranceType = 'MOTOR_TYPE_COMPULSORY') AS candidate_m1_rows,
  COUNTIF(
    InsuranceType = 'MOTOR_TYPE_COMPULSORY'
    AND (
      SAFE_CAST(Period AS INT64) != 1
      OR SAFE_CAST(TotalPeriods AS INT64) != 1
    )
  ) AS invalid_m1_not_1_1_rows,
  COUNTIF(
    SAFE_CAST(ExpectedReceived AS FLOAT64) IS NULL
  ) AS null_expected_rows,
  COUNTIF(
    SAFE_CAST(ActualReceived AS FLOAT64) IS NULL
  ) AS null_actual_rows,
  COUNTIF(
    NULLIF(TRIM(COALESCE(ExpectedDate, '')), '') IS NULL
  ) AS blank_expected_date_rows,
  COUNTIF(
    COALESCE(InsuranceType, '') != 'MOTOR_TYPE_COMPULSORY'
    AND (
      spine_metrics.row_count <= 1
      OR spine_metrics.total_periods <= 1
      OR spine_metrics.total_period_versions != 1
      OR spine_metrics.min_period != 1
      OR spine_metrics.max_period != spine_metrics.total_periods
      OR spine_metrics.distinct_periods != spine_metrics.total_periods
    )
  ) AS incomplete_v1_spine_rows,
  COUNTIF(
    COALESCE(InsuranceType, '') != 'MOTOR_TYPE_COMPULSORY'
    AND LOWER(COALESCE(TransactionStatus, 'pending')) = 'pending'
    AND (
      NULLIF(TRIM(COALESCE(InvoiceNo, '')), '') IS NOT NULL
      OR NULLIF(TRIM(COALESCE(PaymentDate, '')), '') IS NOT NULL
      OR NULLIF(TRIM(COALESCE(PaymentMethod, '')), '') IS NOT NULL
      OR NULLIF(TRIM(COALESCE(PaymentChannel, '')), '') IS NOT NULL
      OR SAFE_CAST(ActualReceived AS FLOAT64) != 0
    )
  ) AS invalid_pending_payment_fields,
  COUNTIF(
    COALESCE(InsuranceType, '') != 'MOTOR_TYPE_COMPULSORY'
    AND LOWER(COALESCE(TransactionStatus, 'pending')) = 'pending'
  ) AS pending_v1_rows,
  COUNT(DISTINCT IF(
    COALESCE(InsuranceType, '') != 'MOTOR_TYPE_COMPULSORY'
    AND LOWER(COALESCE(TransactionStatus, 'pending')) = 'pending',
    OrderItem,
    NULL
  )) AS pending_v1_items
FROM candidate
JOIN spine_metrics USING (OrderItem);

-- Read-only shadow validation for the source-only candidate:
--   sql/production/RCL_Motor_process_2_newpayment_rootfix_20260907.sql

WITH
  interface AS (
    SELECT * FROM `pacific-plating-282708.sap_integration_v2.RCL 05_paid`
    UNION ALL
    SELECT * FROM `pacific-plating-282708.sap_integration_v2.RCL 05_newpayment`
  ),

  eligible_newpayment_items AS (
    SELECT DISTINCT paid_by_period.order_item
    FROM `pacific-plating-282708.sap_integration_v2.RCL 05_paid by period` AS paid_by_period
    JOIN `pacific-plating-282708.careos.careos_order_items` AS order_item
      ON order_item.human_id = paid_by_period.order_item
    WHERE paid_by_period.product = 'products/car-insurance'
      AND paid_by_period.InsuranceType != 'MOTOR_TYPE_COMPULSORY'
      AND order_item.is_cancelled IS NOT TRUE
      AND order_item.cancel_time IS NULL
  ),

  source AS (
    SELECT DISTINCT interface.*
    FROM interface
    JOIN eligible_newpayment_items
      ON eligible_newpayment_items.order_item = interface.OrderItem
    WHERE SAFE.PARSE_DATE('%d%m%Y', interface.OrderDate) >= DATE '2026-01-01'
      AND interface.InsuranceGroup = 'Motor'
      AND interface.InsuranceType != 'MOTOR_TYPE_COMPULSORY'
  ),

  classified AS (
    SELECT
      source.*,
      ROW_NUMBER() OVER (
        PARTITION BY
          source.OrderItem,
          source.Period,
          CASE
            WHEN COALESCE(source.ExpectedReceived, 0) = 0
              AND COALESCE(source.ActualReceived, 0) > 0
            THEN COALESCE(
              NULLIF(source.InvoiceNo, ''),
              CONCAT('additional_', CAST(source.ActualReceived AS STRING), '_',
                     COALESCE(source.PaymentDate, ''))
            )
            ELSE 'normal_period_row'
          END
        ORDER BY
          CASE WHEN source.InvoiceNo IS NOT NULL
                 AND source.InvoiceNo NOT IN ('', 'null', 'NULL') THEN 1 ELSE 2 END,
          CASE WHEN source.PolicyNo IS NOT NULL
                 AND source.PolicyNo NOT IN ('', 'null', 'NULL') THEN 1 ELSE 2 END,
          CASE WHEN source.PaymentDate IS NOT NULL
                 AND source.PaymentDate NOT IN ('', 'null', 'NULL') THEN 1 ELSE 2 END,
          source.PaymentDate DESC
      ) AS rn
    FROM source
  ),

  candidate AS (
    SELECT * EXCEPT (rn)
    FROM classified
    WHERE rn = 1
  ),

  base AS (
    SELECT
      OrderID,
      OrderItem,
      InvoiceNo,
      InsuranceGroup,
      InsuranceType,
      TransactionStatus,
      SAFE_CAST(ExpectedReceived AS NUMERIC) AS ExpectedReceived,
      SAFE_CAST(ActualReceived AS NUMERIC) AS ActualReceived,
      PaymentDate,
      SAFE_CAST(Period AS INT64) AS Period,
      SAFE_CAST(TotalPeriods AS INT64) AS TotalPeriods,
      PaymentMethod,
      PaymentChannel,
      FARM_FINGERPRINT(TO_JSON_STRING(candidate)) AS full_row_hash
    FROM candidate
  ),

  spines AS (
    SELECT
      OrderItem,
      COUNT(*) AS row_count,
      COUNT(DISTINCT Period) AS distinct_periods,
      MIN(Period) AS min_period,
      MAX(Period) AS max_period,
      MAX(TotalPeriods) AS max_total_periods,
      COUNT(DISTINCT TotalPeriods) AS total_period_versions,
      COUNTIF(Period IS NULL) AS null_period_rows,
      COUNTIF(TotalPeriods IS NULL) AS null_total_period_rows
    FROM base
    GROUP BY OrderItem
  ),

  duplicate_periods AS (
    SELECT
      OrderItem,
      Period,
      COUNT(*) AS row_count,
      COUNTIF(COALESCE(ExpectedReceived, 0) > 0) AS positive_expected_rows,
      COUNT(DISTINCT NULLIF(TRIM(InvoiceNo), '')) AS distinct_nonblank_invoices
    FROM base
    GROUP BY OrderItem, Period
    HAVING COUNT(*) > 1
  ),

  exact_duplicates AS (
    SELECT full_row_hash, COUNT(*) AS row_count
    FROM base
    GROUP BY full_row_hash
    HAVING COUNT(*) > 1
  ),

  candidate_items AS (
    SELECT DISTINCT OrderItem FROM candidate
  ),

  removed_live AS (
    SELECT
      live.OrderItem,
      live.InsuranceGroup,
      order_item.is_cancelled,
      order_item.cancel_time,
      COUNT(*) AS removed_rows
    FROM `pacific-plating-282708.sap_view.RCL_Motor_process_2_newpayment` AS live
    LEFT JOIN candidate_items USING (OrderItem)
    LEFT JOIN `pacific-plating-282708.careos.careos_order_items` AS order_item
      ON order_item.human_id = live.OrderItem
    WHERE candidate_items.OrderItem IS NULL
    GROUP BY live.OrderItem, live.InsuranceGroup,
      order_item.is_cancelled, order_item.cancel_time
  )

SELECT
  CASE
    WHEN COUNTIF(Period IS NULL OR TotalPeriods IS NULL) > 0
      OR COUNTIF(Period < 1 OR Period > TotalPeriods) > 0
      OR (SELECT COUNTIF(
            null_period_rows > 0 OR null_total_period_rows > 0
            OR total_period_versions != 1 OR min_period != 1
            OR max_period != max_total_periods
            OR distinct_periods != max_total_periods) FROM spines) > 0
      OR (SELECT COUNTIF(positive_expected_rows > 1) FROM duplicate_periods) > 0
      OR (SELECT COUNT(*) FROM exact_duplicates) > 0
      OR COUNTIF(LOWER(TRIM(TransactionStatus)) = 'pending'
        AND (COALESCE(TRIM(PaymentMethod), '') != ''
          OR COALESCE(TRIM(PaymentChannel), '') != ''
          OR COALESCE(TRIM(PaymentDate), '') != '')) > 0
    THEN 'RED'
    ELSE 'GREEN'
  END AS verdict,
  COUNT(*) AS candidate_rows,
  COUNT(DISTINCT OrderID) AS candidate_orders,
  COUNT(DISTINCT OrderItem) AS candidate_items,
  (SELECT COUNT(*) FROM `pacific-plating-282708.sap_view.RCL_Motor_process_2_newpayment`) AS live_rows,
  (SELECT COUNT(DISTINCT OrderItem)
   FROM `pacific-plating-282708.sap_view.RCL_Motor_process_2_newpayment`) AS live_items,
  COUNTIF(Period IS NULL) AS null_period_rows,
  COUNTIF(TotalPeriods IS NULL) AS null_total_period_rows,
  COUNTIF(Period < 1 OR Period > TotalPeriods) AS invalid_period_rows,
  (SELECT COUNTIF(
      null_period_rows > 0 OR null_total_period_rows > 0
      OR total_period_versions != 1 OR min_period != 1
      OR max_period != max_total_periods
      OR distinct_periods != max_total_periods) FROM spines) AS incomplete_or_conflicting_items,
  (SELECT COUNT(*) FROM duplicate_periods) AS duplicate_period_keys,
  (SELECT COUNTIF(positive_expected_rows > 1) FROM duplicate_periods)
    AS duplicate_period_repeated_expected_keys,
  (SELECT COUNT(*) FROM exact_duplicates) AS exact_duplicate_hashes,
  COUNTIF(LOWER(TRIM(TransactionStatus)) = 'pending') AS pending_rows,
  COUNTIF(LOWER(TRIM(TransactionStatus)) = 'pending'
    AND (COALESCE(TRIM(PaymentMethod), '') != ''
      OR COALESCE(TRIM(PaymentChannel), '') != '')) AS pending_payment_identity_violations,
  COUNTIF(LOWER(TRIM(TransactionStatus)) = 'pending'
    AND COALESCE(TRIM(PaymentDate), '') != '') AS pending_payment_date_violations,
  COUNTIF(LOWER(TRIM(TransactionStatus)) = 'paid'
    AND COALESCE(TRIM(InvoiceNo), '') = '') AS paid_blank_invoice_rows,
  COUNTIF(STARTS_WITH(UPPER(TRIM(PaymentChannel)), 'RCB')) AS rcb_channel_rows_in_rcl_view,
  COUNTIF(InsuranceGroup != 'Motor' OR InsuranceGroup IS NULL) AS nonmotor_rows,
  (SELECT COUNT(*) FROM removed_live) AS removed_items,
  (SELECT COALESCE(SUM(removed_rows), 0) FROM removed_live) AS removed_rows,
  (SELECT COUNTIF(InsuranceGroup = 'Health') FROM removed_live) AS removed_health_items,
  (SELECT COUNTIF(is_cancelled IS TRUE OR cancel_time IS NOT NULL)
   FROM removed_live) AS removed_cancelled_items,
  ARRAY(
    SELECT AS STRUCT OrderItem, InsuranceGroup, is_cancelled, cancel_time, removed_rows
    FROM removed_live
    ORDER BY InsuranceGroup, OrderItem
    LIMIT 20
  ) AS removed_samples,
  ARRAY(
    SELECT AS STRUCT OrderItem, Period, row_count,
      positive_expected_rows, distinct_nonblank_invoices
    FROM duplicate_periods
    ORDER BY OrderItem, Period
    LIMIT 30
  ) AS duplicate_period_samples
FROM base;

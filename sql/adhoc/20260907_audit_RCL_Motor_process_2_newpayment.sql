-- Red-capable read-only audit for:
--   pacific-plating-282708.sap_view.RCL_Motor_process_2_newpayment

WITH
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
    FARM_FINGERPRINT(TO_JSON_STRING(v)) AS full_row_hash
  FROM `pacific-plating-282708.sap_view.RCL_Motor_process_2_newpayment` v
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
)

SELECT
  CASE
    WHEN COUNTIF(Period IS NULL OR TotalPeriods IS NULL) > 0
      OR COUNTIF(Period < 1 OR Period > TotalPeriods) > 0
      OR (SELECT COUNTIF(null_period_rows > 0 OR null_total_period_rows > 0
                        OR total_period_versions != 1
                        OR min_period != 1
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
  COUNT(*) AS output_rows,
  COUNT(DISTINCT OrderID) AS orders,
  COUNT(DISTINCT OrderItem) AS items,
  COUNTIF(Period IS NULL) AS null_period_rows,
  COUNTIF(TotalPeriods IS NULL) AS null_total_period_rows,
  COUNTIF(Period < 1 OR Period > TotalPeriods) AS invalid_period_rows,
  (SELECT COUNTIF(null_period_rows > 0 OR null_total_period_rows > 0
                  OR total_period_versions != 1
                  OR min_period != 1
                  OR max_period != max_total_periods
                  OR distinct_periods != max_total_periods) FROM spines) AS incomplete_or_conflicting_items,
  (SELECT COUNT(*) FROM duplicate_periods) AS duplicate_period_keys,
  (SELECT COUNTIF(positive_expected_rows > 1) FROM duplicate_periods) AS duplicate_period_repeated_expected_keys,
  (SELECT COUNT(*) FROM exact_duplicates) AS exact_duplicate_hashes,
  (SELECT COALESCE(SUM(row_count - 1), 0) FROM exact_duplicates) AS exact_duplicate_extra_rows,
  COUNTIF(LOWER(TRIM(TransactionStatus)) = 'pending') AS pending_rows,
  COUNTIF(LOWER(TRIM(TransactionStatus)) = 'pending'
          AND (COALESCE(TRIM(PaymentMethod), '') != ''
               OR COALESCE(TRIM(PaymentChannel), '') != '')) AS pending_payment_identity_violations,
  COUNTIF(LOWER(TRIM(TransactionStatus)) = 'pending'
          AND COALESCE(TRIM(PaymentDate), '') != '') AS pending_payment_date_violations,
  COUNTIF(LOWER(TRIM(TransactionStatus)) = 'paid'
          AND COALESCE(TRIM(InvoiceNo), '') = '') AS paid_blank_invoice_rows,
  COUNTIF(STARTS_WITH(UPPER(TRIM(PaymentChannel)), 'RCB')) AS rcb_channel_rows_in_rcl_view,
  ARRAY(
    SELECT AS STRUCT InsuranceGroup, InsuranceType
    FROM base
    GROUP BY InsuranceGroup, InsuranceType
    LIMIT 30
  ) AS product_shapes,
  ARRAY(
    SELECT AS STRUCT OrderItem, row_count, distinct_periods, min_period, max_period,
      max_total_periods, total_period_versions, null_period_rows, null_total_period_rows
    FROM spines
    WHERE null_period_rows > 0 OR null_total_period_rows > 0
       OR total_period_versions != 1 OR min_period != 1
       OR max_period != max_total_periods OR distinct_periods != max_total_periods
    ORDER BY OrderItem
    LIMIT 30
  ) AS bad_spine_samples,
  ARRAY(
    SELECT AS STRUCT OrderItem, Period, row_count, positive_expected_rows, distinct_nonblank_invoices
    FROM duplicate_periods
    ORDER BY OrderItem, Period
    LIMIT 30
  ) AS duplicate_period_samples
FROM base;

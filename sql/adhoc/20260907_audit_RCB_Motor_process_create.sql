-- Red-capable read-only audit for:
--   pacific-plating-282708.sap_view.RCB_Motor_process_create

WITH
base AS (
  SELECT
    view_row.*,
    SAFE_CAST(Period AS INT64) AS period_int,
    SAFE_CAST(TotalPeriods AS INT64) AS total_periods_int,
    SAFE_CAST(ExpectedReceived AS NUMERIC) AS expected_num,
    SAFE_CAST(ActualReceived AS NUMERIC) AS actual_num,
    FARM_FINGERPRINT(TO_JSON_STRING(view_row)) AS full_row_hash
  FROM `pacific-plating-282708.sap_view.RCB_Motor_process_create` AS view_row
),

duplicate_invoice_period AS (
  SELECT OrderItem, period_int, InvoiceNo, COUNT(*) AS row_count,
    COUNT(DISTINCT full_row_hash) AS distinct_full_rows
  FROM base
  GROUP BY OrderItem, period_int, InvoiceNo
  HAVING COUNT(*) > 1
),

exact_duplicates AS (
  SELECT full_row_hash, COUNT(*) AS row_count
  FROM base
  GROUP BY full_row_hash
  HAVING COUNT(*) > 1
),

output_items AS (
  SELECT DISTINCT OrderItem
  FROM base
),

excluded_upstream AS (
  SELECT
    interface.OrderItem,
    interface.OrderID,
    interface.InsurerCode,
    interface.OrderDate,
    interface.InsuranceType,
    interface.PaymentChannel,
    CASE
      WHEN sap.U_OrderItem IS NOT NULL THEN 'ALREADY_IN_SAP'
      WHEN interface.ExpectedReceived IS NULL THEN 'NULL_EXPECTED'
      WHEN interface.FirstName = 'Test' THEN 'TEST_NAME'
      WHEN interface.InsurerCode IN ('22', '49', '45') THEN 'EXCLUDED_INSURER'
      WHEN interface.OrderDate LIKE '%2025' THEN 'EXCLUDED_2025'
      WHEN output_items.OrderItem IS NOT NULL THEN 'IN_OUTPUT'
      ELSE 'ELIGIBLE_BUT_MISSING_OUTPUT'
    END AS disposition
  FROM `pacific-plating-282708.sap_data_engineer.sap_dashboard_carepay_fully_paid` AS interface
  LEFT JOIN (
    SELECT DISTINCT U_OrderItem
    FROM `pacific-plating-282708.sap_integration_v2.SAP_LIVE_FULL`
  ) AS sap
    ON sap.U_OrderItem = interface.OrderItem
  LEFT JOIN output_items
    ON output_items.OrderItem = interface.OrderItem
),

careos_items AS (
  SELECT human_id AS OrderItem, is_cancelled, cancel_time
  FROM `pacific-plating-282708.careos.careos_order_items`
)

SELECT
  CASE
    WHEN COUNTIF(period_int IS NULL OR total_periods_int IS NULL) > 0
      OR COUNTIF(period_int != 1 OR total_periods_int != 1) > 0
      OR COUNTIF(COALESCE(TRIM(InvoiceNo), '') = '') > 0
      OR COUNTIF(COALESCE(TRIM(InsurerCode), '') = '') > 0
      OR COUNTIF(COALESCE(TRIM(InsuranceGroup), '') != 'Motor') > 0
      OR COUNTIF(NOT STARTS_WITH(UPPER(TRIM(PaymentChannel)), 'RCB')) > 0
      OR COUNTIF(careos_items.is_cancelled IS TRUE OR careos_items.cancel_time IS NOT NULL) > 0
      OR (SELECT COUNT(*) FROM duplicate_invoice_period) > 0
      OR (SELECT COUNT(*) FROM exact_duplicates) > 0
      OR (SELECT COUNTIF(disposition = 'ELIGIBLE_BUT_MISSING_OUTPUT') FROM excluded_upstream) > 0
    THEN 'RED'
    ELSE 'GREEN'
  END AS verdict,
  COUNT(*) AS output_rows,
  COUNT(DISTINCT OrderID) AS orders,
  COUNT(DISTINCT OrderItem) AS items,
  COUNTIF(period_int IS NULL) AS null_period_rows,
  COUNTIF(total_periods_int IS NULL) AS null_total_period_rows,
  COUNTIF(period_int != 1 OR total_periods_int != 1) AS invalid_onetime_period_rows,
  COUNTIF(COALESCE(TRIM(InvoiceNo), '') = '') AS blank_invoice_rows,
  COUNTIF(COALESCE(TRIM(InsurerCode), '') = '') AS blank_insurer_rows,
  COUNTIF(COALESCE(TRIM(InsuranceGroup), '') != 'Motor') AS nonmotor_rows,
  COUNTIF(NOT STARTS_WITH(UPPER(TRIM(PaymentChannel)), 'RCB')) AS non_rcb_channel_rows,
  COUNTIF(expected_num IS NULL) AS null_expected_rows,
  COUNTIF(actual_num IS NULL) AS null_actual_rows,
  COUNTIF(careos_items.is_cancelled IS TRUE OR careos_items.cancel_time IS NOT NULL)
    AS canonically_cancelled_rows,
  COUNT(DISTINCT IF(careos_items.is_cancelled IS TRUE OR careos_items.cancel_time IS NOT NULL,
    base.OrderItem, NULL)) AS canonically_cancelled_items,
  (SELECT COUNT(*) FROM duplicate_invoice_period) AS duplicate_invoice_period_keys,
  (SELECT COUNT(*) FROM exact_duplicates) AS exact_duplicate_hashes,
  (SELECT COUNTIF(disposition = 'ELIGIBLE_BUT_MISSING_OUTPUT') FROM excluded_upstream)
    AS eligible_upstream_missing_rows,
  ARRAY(
    SELECT AS STRUCT disposition, COUNT(*) AS row_count, COUNT(DISTINCT OrderItem) AS item_count
    FROM excluded_upstream
    GROUP BY disposition
    ORDER BY row_count DESC
  ) AS upstream_dispositions,
  ARRAY(
    SELECT AS STRUCT base.OrderID, base.OrderItem, base.InvoiceNo,
      careos_items.is_cancelled, careos_items.cancel_time
    FROM base
    JOIN careos_items USING (OrderItem)
    WHERE careos_items.is_cancelled IS TRUE OR careos_items.cancel_time IS NOT NULL
    ORDER BY base.OrderItem
    LIMIT 30
  ) AS cancelled_samples,
  ARRAY(
    SELECT AS STRUCT OrderItem, period_int AS Period, InvoiceNo,
      row_count, distinct_full_rows
    FROM duplicate_invoice_period
    ORDER BY OrderItem, Period, InvoiceNo
    LIMIT 30
  ) AS duplicate_samples
FROM base
LEFT JOIN careos_items USING (OrderItem);

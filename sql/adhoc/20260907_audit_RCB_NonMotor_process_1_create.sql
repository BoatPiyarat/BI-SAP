-- Red-capable read-only audit for:
--   pacific-plating-282708.sap_view.RCB_NonMotor_process_1_create
-- Live definition checked on 2026-09-07 ICT.

WITH
  upstream AS (
    SELECT
      'RCB_HEALTH' AS source_name,
      CompanyDB, OrderID, OrderItem, InvoiceNo, OrderDate,
      FirstName, LastName, InsurerCode, InsuranceGroup, InsuranceType,
      InsuranceProduct, PolicyDate, PolicyNo, GrossPremium, StampDuty, VAT,
      TotalPremium, TransactionStatus, ExpectedReceived, ActualReceived,
      PaymentDate, Period, TotalPeriods, PaymentMethod, PaymentChannel
    FROM `pacific-plating-282708.sap_data_engineer.RCB_HEALTH`

    UNION ALL

    SELECT
      'RCB_TRAVEL' AS source_name,
      CompanyDB, OrderID, OrderItem, InvoiceNo, OrderDate,
      FirstName, LastName, InsurerCode, InsuranceGroup, InsuranceType,
      InsuranceProduct, PolicyDate, PolicyNo, GrossPremium, StampDuty, VAT,
      TotalPremium, TransactionStatus, ExpectedReceived, ActualReceived,
      PaymentDate, Period, TotalPeriods, PaymentMethod, PaymentChannel
    FROM `pacific-plating-282708.sap_data_engineer.RCB_TRAVEL`
  ),

  sap_items AS (
    SELECT DISTINCT U_OrderItem AS OrderItem
    FROM `pacific-plating-282708.sap_integration_v3.stg_sap_state`
  ),

  expected_output AS (
    SELECT upstream.*
    FROM upstream
    LEFT JOIN sap_items USING (OrderItem)
    WHERE sap_items.OrderItem IS NULL
      AND upstream.TransactionStatus IS NOT NULL
  ),

  output AS (
    SELECT
      CompanyDB, OrderID, OrderItem, InvoiceNo, OrderDate,
      FirstName, LastName, InsurerCode, InsuranceGroup, InsuranceType,
      InsuranceProduct, PolicyDate, PolicyNo, GrossPremium, StampDuty, VAT,
      TotalPremium, TransactionStatus, ExpectedReceived, ActualReceived,
      PaymentDate, Period, TotalPeriods, PaymentMethod, PaymentChannel
    FROM `pacific-plating-282708.sap_view.RCB_NonMotor_process_1_create`
  ),

  output_tagged AS (
    SELECT
      output.*,
      CASE
        WHEN InsuranceGroup = 'Health' THEN 'RCB_HEALTH'
        WHEN InsuranceGroup = 'Travel' THEN 'RCB_TRAVEL'
        ELSE 'UNKNOWN'
      END AS source_name,
      FARM_FINGERPRINT(TO_JSON_STRING(output)) AS full_row_hash
    FROM output
  ),

  careos_items AS (
    SELECT human_id AS OrderItem, is_cancelled, cancel_time
    FROM `pacific-plating-282708.careos.careos_order_items`
  ),

  duplicate_keys AS (
    SELECT OrderItem, Period, InvoiceNo, COUNT(*) AS row_count,
      COUNT(DISTINCT full_row_hash) AS distinct_full_rows
    FROM output_tagged
    GROUP BY OrderItem, Period, InvoiceNo
    HAVING COUNT(*) > 1
  ),

  exact_duplicates AS (
    SELECT full_row_hash, COUNT(*) AS row_count
    FROM output_tagged
    GROUP BY full_row_hash
    HAVING COUNT(*) > 1
  ),

  upstream_orders AS (
    SELECT DISTINCT OrderID, source_name
    FROM upstream
  ),

  raw_successful_charge_pairs AS (
    SELECT DISTINCT
      upstream_orders.source_name,
      orders.human_id AS OrderID,
      charges.payment_method,
      charges.service_provider
    FROM upstream_orders
    JOIN `pacific-plating-282708.careos.careos_orders` AS orders
      ON orders.human_id = upstream_orders.OrderID
    JOIN `pacific-plating-282708.careos.carepay_transactions` AS transactions
      ON CONCAT('transactions/', transactions.id) = orders.payment
    JOIN `pacific-plating-282708.careos.carepay_charges` AS charges
      ON charges.transaction_id = transactions.id
    WHERE charges.status = 'SUCCESSFUL'
      AND charges.service_provider != 'ICOLLECTION'
  ),

  expected_minus_output AS (
    SELECT * EXCEPT (source_name) FROM expected_output
    EXCEPT DISTINCT
    SELECT * EXCEPT (source_name, full_row_hash) FROM output_tagged
  ),

  output_minus_expected AS (
    SELECT * EXCEPT (source_name, full_row_hash) FROM output_tagged
    EXCEPT DISTINCT
    SELECT * EXCEPT (source_name) FROM expected_output
  )

SELECT
  CASE
    WHEN COUNTIF(COALESCE(TRIM(CompanyDB), '') != 'RCB') > 0
      OR COUNTIF(InsuranceGroup NOT IN ('Health', 'Travel') OR InsuranceGroup IS NULL) > 0
      OR COUNTIF(NOT STARTS_WITH(COALESCE(PaymentChannel, ''), 'RCB-')) > 0
      OR COUNTIF(SAFE_CAST(Period AS INT64) != 1 OR Period IS NULL) > 0
      OR COUNTIF(SAFE_CAST(TotalPeriods AS INT64) != 1 OR TotalPeriods IS NULL) > 0
      OR COUNTIF(LOWER(TRIM(COALESCE(FirstName, ''))) = 'test'
        OR LOWER(TRIM(COALESCE(LastName, ''))) = 'test') > 0
      OR COUNTIF(careos_items.is_cancelled IS TRUE OR careos_items.cancel_time IS NOT NULL) > 0
      OR COUNTIF(COALESCE(TRIM(InvoiceNo), '') IN ('', 'NULL', 'null')) > 0
      OR COUNTIF(COALESCE(TRIM(InsurerCode), '') IN ('', 'NULL', 'null')) > 0
      OR COUNTIF(SAFE.PARSE_DATE('%d%m%Y', OrderDate) IS NULL) > 0
      OR COUNTIF(SAFE.PARSE_DATE('%d%m%Y', PolicyDate) IS NULL) > 0
      OR COUNTIF(SAFE.PARSE_DATE('%d%m%Y', PaymentDate) IS NULL) > 0
      OR (SELECT COUNT(*) FROM duplicate_keys) > 0
      OR (SELECT COUNT(*) FROM exact_duplicates) > 0
      OR (SELECT COUNT(*) FROM expected_minus_output) > 0
      OR (SELECT COUNT(*) FROM output_minus_expected) > 0
    THEN 'RED'
    ELSE 'GREEN'
  END AS verdict,
  COUNT(*) AS output_rows,
  COUNT(DISTINCT OrderID) AS output_orders,
  COUNT(DISTINCT OrderItem) AS output_items,
  COUNTIF(source_name = 'RCB_HEALTH') AS health_rows,
  COUNTIF(source_name = 'RCB_TRAVEL') AS travel_rows,
  COUNTIF(COALESCE(TRIM(CompanyDB), '') != 'RCB') AS non_rcb_company_rows,
  COUNTIF(InsuranceGroup NOT IN ('Health', 'Travel') OR InsuranceGroup IS NULL)
    AS wrong_group_rows,
  COUNTIF(NOT STARTS_WITH(COALESCE(PaymentChannel, ''), 'RCB-')) AS non_rcb_channel_rows,
  COUNTIF(SAFE_CAST(Period AS INT64) != 1 OR Period IS NULL) AS invalid_period_rows,
  COUNTIF(SAFE_CAST(TotalPeriods AS INT64) != 1 OR TotalPeriods IS NULL)
    AS invalid_total_period_rows,
  COUNTIF(LOWER(TRIM(COALESCE(FirstName, ''))) = 'test'
    OR LOWER(TRIM(COALESCE(LastName, ''))) = 'test') AS test_rows,
  COUNTIF(careos_items.is_cancelled IS TRUE OR careos_items.cancel_time IS NOT NULL)
    AS cancelled_rows,
  COUNT(DISTINCT IF(careos_items.is_cancelled IS TRUE OR careos_items.cancel_time IS NOT NULL,
    output_tagged.OrderItem, NULL)) AS cancelled_items,
  COUNTIF(COALESCE(TRIM(InvoiceNo), '') IN ('', 'NULL', 'null')) AS blank_invoice_rows,
  COUNTIF(COALESCE(TRIM(InsurerCode), '') IN ('', 'NULL', 'null')) AS blank_insurer_rows,
  COUNTIF(SAFE.PARSE_DATE('%d%m%Y', OrderDate) IS NULL) AS bad_order_date_rows,
  COUNTIF(SAFE.PARSE_DATE('%d%m%Y', PolicyDate) IS NULL) AS bad_policy_date_rows,
  COUNTIF(SAFE.PARSE_DATE('%d%m%Y', PaymentDate) IS NULL) AS bad_payment_date_rows,
  COUNTIF(ExpectedReceived IS NULL) AS null_expected_rows,
  COUNTIF(ActualReceived IS NULL) AS null_actual_rows,
  COUNTIF(ROUND(ExpectedReceived, 2) != ROUND(ActualReceived, 2))
    AS expected_actual_mismatch_rows,
  (SELECT COUNT(*) FROM duplicate_keys) AS duplicate_keys,
  (SELECT COUNT(*) FROM exact_duplicates) AS exact_duplicate_hashes,
  (SELECT COUNT(*) FROM expected_minus_output) AS expected_rows_missing_from_output,
  (SELECT COUNT(*) FROM output_minus_expected) AS unexpected_output_rows,
  (SELECT COUNT(*) FROM upstream WHERE TransactionStatus IS NULL)
    AS upstream_null_status_rows,
  ARRAY(
    SELECT AS STRUCT source_name, COUNT(*) AS row_count, COUNT(DISTINCT OrderItem) AS item_count
    FROM upstream
    GROUP BY source_name
    ORDER BY source_name
  ) AS upstream_counts,
  ARRAY(
    SELECT AS STRUCT source_name, payment_method, service_provider,
      COUNT(DISTINCT OrderID) AS order_count
    FROM raw_successful_charge_pairs
    GROUP BY source_name, payment_method, service_provider
    ORDER BY source_name, order_count DESC, payment_method, service_provider
  ) AS raw_successful_payment_pairs,
  ARRAY(
    SELECT AS STRUCT OrderID, OrderItem, source_name, is_cancelled, cancel_time
    FROM output_tagged
    JOIN careos_items USING (OrderItem)
    WHERE is_cancelled IS TRUE OR cancel_time IS NOT NULL
    ORDER BY OrderItem
    LIMIT 30
  ) AS cancelled_samples,
  ARRAY(
    SELECT AS STRUCT OrderItem, Period, InvoiceNo, row_count, distinct_full_rows
    FROM duplicate_keys
    ORDER BY OrderItem, Period, InvoiceNo
    LIMIT 30
  ) AS duplicate_samples
FROM output_tagged
LEFT JOIN careos_items USING (OrderItem);

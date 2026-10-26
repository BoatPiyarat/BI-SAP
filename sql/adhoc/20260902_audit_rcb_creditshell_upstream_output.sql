-- Read-only output audit for sap_integration_v2.04_new order credit shell.

WITH upstream AS (
  SELECT *
  FROM `pacific-plating-282708.sap_integration_v2.04_new order credit shell`
),
invoice_period_duplicates AS (
  SELECT
    OrderItem,
    Period,
    IFNULL(InvoiceNo, '') AS InvoiceNo,
    COUNT(*) AS row_count,
    COUNT(DISTINCT PaymentDate) AS payment_date_versions,
    COUNT(DISTINCT RefOrder) AS ref_order_versions,
    COUNT(DISTINCT TO_JSON_STRING(u)) AS payload_versions
  FROM upstream AS u
  GROUP BY OrderItem, Period, IFNULL(InvoiceNo, '')
  HAVING COUNT(*) > 1
),
period_duplicates AS (
  SELECT OrderItem, Period, COUNT(*) AS row_count
  FROM upstream
  GROUP BY OrderItem, Period
  HAVING COUNT(*) > 1
)

SELECT
  (SELECT COUNT(*) FROM upstream) AS row_count,
  (SELECT COUNT(DISTINCT OrderItem) FROM upstream) AS item_count,
  (SELECT COUNT(*) - COUNT(DISTINCT TO_JSON_STRING(u)) FROM upstream AS u)
    AS exact_full_row_duplicates,
  (SELECT COUNT(*) FROM invoice_period_duplicates) AS duplicate_invoice_period_keys,
  (SELECT COUNT(*) FROM period_duplicates) AS duplicate_period_keys,
  COUNTIF(Period IS NULL OR TotalPeriods IS NULL) AS null_period_rows,
  COUNTIF(Period != 1 OR TotalPeriods != 1) AS non_onetime_rows,
  ARRAY(
    SELECT AS STRUCT
      OrderItem,
      Period,
      InvoiceNo,
      row_count,
      payment_date_versions,
      ref_order_versions,
      payload_versions
    FROM invoice_period_duplicates
    ORDER BY row_count DESC, OrderItem
    LIMIT 100
  ) AS duplicate_invoice_period_samples
FROM upstream;

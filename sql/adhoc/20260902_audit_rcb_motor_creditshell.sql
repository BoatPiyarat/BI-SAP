-- Read-only red/green audit for sap_view.RCB_Motor_process_4_creditshell.

WITH payload AS (
  SELECT *
  FROM `pacific-plating-282708.sap_view.RCB_Motor_process_4_creditshell`
),
invoice_period_duplicates AS (
  SELECT
    OrderItem,
    Period,
    IFNULL(InvoiceNo, '') AS InvoiceNo,
    COUNT(*) AS row_count
  FROM payload
  GROUP BY OrderItem, Period, IFNULL(InvoiceNo, '')
  HAVING COUNT(*) > 1
),
period_duplicates AS (
  SELECT OrderItem, Period, COUNT(*) AS row_count
  FROM payload
  GROUP BY OrderItem, Period
  HAVING COUNT(*) > 1
)

SELECT
  (SELECT COUNT(*) FROM payload) AS row_count,
  (SELECT COUNT(DISTINCT OrderItem) FROM payload) AS item_count,
  (SELECT COUNT(*) - COUNT(DISTINCT TO_JSON_STRING(p)) FROM payload AS p)
    AS exact_full_row_duplicates,
  (SELECT COUNT(*) FROM invoice_period_duplicates) AS duplicate_invoice_period_keys,
  (SELECT COUNT(*) FROM period_duplicates) AS duplicate_period_keys,
  COUNTIF(Period IS NULL OR TotalPeriods IS NULL) AS null_period_rows,
  COUNTIF(Period != 1 OR TotalPeriods != 1) AS non_onetime_rows,
  COUNTIF(
    LOWER(IFNULL(TransactionStatus, '')) = 'pending'
    AND (NULLIF(PaymentMethod, '') IS NOT NULL OR NULLIF(PaymentChannel, '') IS NOT NULL)
  ) AS pending_payment_field_violations,
  ARRAY(
    SELECT AS STRUCT OrderItem, Period, InvoiceNo, row_count
    FROM invoice_period_duplicates
    ORDER BY OrderItem, Period, InvoiceNo
    LIMIT 50
  ) AS duplicate_invoice_period_samples
FROM payload;

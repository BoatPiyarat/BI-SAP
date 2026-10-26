-- Red/green regression loop for the reported legacy RCL CreditShell payload defect.
-- Read-only: asserts the exact live symptoms and returns a compact summary plus samples.

WITH live AS (
  SELECT *
  FROM `pacific-plating-282708.sap_integration_v2.RCL 04_new order credit shell`
),

spines AS (
  SELECT
    OrderItem,
    COUNT(*) AS row_count,
    COUNT(DISTINCT Period) AS distinct_periods,
    MAX(TotalPeriods) AS total_periods,
    COUNT(DISTINCT COALESCE(NULLIF(InvoiceNo, ''), '<BLANK>')) AS invoice_states,
    COUNT(DISTINCT CONCAT(
      COALESCE(NULLIF(PaymentDate, ''), '<BLANK>'), '|',
      COALESCE(NULLIF(PaymentMethod, ''), '<BLANK>'), '|',
      COALESCE(NULLIF(PaymentChannel, ''), '<BLANK>')
    )) AS payment_identity_states,
    COUNTIF(
      LOWER(COALESCE(TransactionStatus, '')) = 'pending'
      AND (
        COALESCE(NULLIF(InvoiceNo, ''), '') <> ''
        OR COALESCE(NULLIF(PaymentDate, ''), '') <> ''
        OR COALESCE(NULLIF(PaymentMethod, ''), '') <> ''
        OR COALESCE(NULLIF(PaymentChannel, ''), '') <> ''
      )
    ) AS pending_identity_rows,
    COUNTIF(
      COALESCE(NULLIF(InsurerCode, ''), '') = ''
      OR COALESCE(NULLIF(InsuranceGroup, ''), '') = ''
      OR COALESCE(NULLIF(InsuranceType, ''), '') = ''
      OR COALESCE(NULLIF(InsuranceProduct, ''), '') = ''
      OR COALESCE(NULLIF(PolicyDate, ''), '') = ''
    ) AS missing_insurance_rows,
    COUNTIF(
      GrossPremium IS NULL
      OR StampDuty IS NULL
      OR VAT IS NULL
      OR TotalPremium IS NULL
      OR TotalAmount IS NULL
    ) AS missing_financial_rows
  FROM live
  GROUP BY OrderItem
),

violations AS (
  SELECT
    *,
    distinct_periods > 1 AND invoice_states = 1 AS same_invoice_whole_spine,
    distinct_periods > 1 AND payment_identity_states = 1 AS same_payment_whole_spine
  FROM spines
  WHERE distinct_periods > 1
),

summary AS (
  SELECT
    COUNT(*) AS multi_period_items,
    COUNTIF(same_invoice_whole_spine) AS same_invoice_items,
    COUNTIF(same_payment_whole_spine) AS same_payment_items,
    COUNTIF(pending_identity_rows > 0) AS pending_identity_items,
    COUNTIF(missing_insurance_rows > 0) AS missing_insurance_items,
    COUNTIF(missing_financial_rows > 0) AS missing_financial_items
  FROM violations
)

SELECT
  CASE
    WHEN same_invoice_items = 0
      AND same_payment_items = 0
      AND pending_identity_items = 0
      AND missing_insurance_items = 0
      AND missing_financial_items = 0
    THEN 'GREEN'
    ELSE 'RED'
  END AS verdict,
  summary.*,
  ARRAY(
    SELECT AS STRUCT
      OrderItem,
      row_count,
      distinct_periods,
      total_periods,
      invoice_states,
      payment_identity_states,
      pending_identity_rows,
      missing_insurance_rows,
      missing_financial_rows,
      same_invoice_whole_spine,
      same_payment_whole_spine
    FROM violations
    WHERE same_invoice_whole_spine
       OR same_payment_whole_spine
       OR pending_identity_rows > 0
       OR missing_insurance_rows > 0
       OR missing_financial_rows > 0
    ORDER BY OrderItem
    LIMIT 20
  ) AS sample_items
FROM summary;

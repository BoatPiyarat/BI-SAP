-- Minimal source trace for two reproducible defect classes in the live RCL CreditShell view.
-- Read-only. JSON payloads keep unlike source schemas in one result set.

WITH target_items AS (
  SELECT 'L78482063-1' AS OrderItem -- missing insurance master fields
  UNION ALL
  SELECT 'L77391285-V1'             -- identical payment tuple across the spine
),

live_rows AS (
  SELECT v.*
  FROM `pacific-plating-282708.sap_integration_v2.RCL 04_new order credit shell` v
  JOIN target_items USING (OrderItem)
),

current_order_items AS (
  SELECT
    o.human_id AS OrderID,
    i.human_id AS OrderItem,
    i.insurer,
    i.product,
    i.motor_item_type,
    i.package,
    i.policy_start_date,
    i.policy_number,
    i.net_premium,
    i.stamp_duty,
    i.vat_amount,
    i.gross_premium,
    REGEXP_EXTRACT(o.payment, r'transactions/(.+)') AS transaction_id
  FROM `pacific-plating-282708.careos.careos_order_items` i
  JOIN `pacific-plating-282708.careos.careos_orders` o ON o.id = i.order_id
  JOIN target_items t ON t.OrderItem = i.human_id
),

raw_charges AS (
  SELECT
    c.transaction_id,
    c.id AS charge_id,
    c.installment_number,
    c.third_party_id,
    c.status,
    c.amount,
    c.payment_method,
    c.service_provider,
    c.payment_date,
    c.update_time
  FROM `pacific-plating-282708.careos.carepay_charges` c
  JOIN current_order_items i ON CAST(c.transaction_id AS STRING) = i.transaction_id
),

field_summary AS (
  SELECT AS STRUCT
    COUNT(DISTINCT OrderItem) AS items,
    COUNTIF(COALESCE(NULLIF(InsurerCode, ''), '') = '') AS blank_insurer_rows,
    COUNTIF(COALESCE(NULLIF(InsuranceGroup, ''), '') = '') AS blank_group_rows,
    COUNTIF(COALESCE(NULLIF(InsuranceType, ''), '') = '') AS blank_type_rows,
    COUNTIF(COALESCE(NULLIF(InsuranceProduct, ''), '') = '') AS blank_product_rows,
    COUNTIF(COALESCE(NULLIF(PolicyDate, ''), '') = '') AS blank_policydate_rows,
    COUNTIF(GrossPremium IS NULL OR GrossPremium = 0) AS zero_gross_rows,
    COUNTIF(StampDuty IS NULL OR StampDuty = 0) AS zero_stamp_rows,
    COUNTIF(VAT IS NULL OR VAT = 0) AS zero_vat_rows,
    COUNTIF(TotalPremium IS NULL OR TotalPremium = 0) AS zero_totalpremium_rows,
    COUNTIF(TotalAmount IS NULL OR TotalAmount = 0) AS zero_totalamount_rows
  FROM `pacific-plating-282708.sap_integration_v2.RCL 04_new order credit shell`
)

SELECT 'SUMMARY' AS source, TO_JSON_STRING(field_summary) AS payload FROM field_summary
UNION ALL
SELECT
  'LIVE',
  TO_JSON_STRING(STRUCT(
    OrderID, OrderItem, RefOrder, Period, TotalPeriods, InvoiceNo,
    InsurerCode, InsuranceGroup, InsuranceType, InsuranceProduct, PolicyDate,
    GrossPremium, StampDuty, VAT, TotalPremium, TotalAmount,
    TransactionStatus, PaymentDate, PaymentMethod, PaymentChannel
  ))
FROM live_rows
UNION ALL
SELECT 'CURRENT_ITEM', TO_JSON_STRING(i) FROM current_order_items i
UNION ALL
SELECT 'RAW_CHARGE', TO_JSON_STRING(c) FROM raw_charges c
ORDER BY source, payload;

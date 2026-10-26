-- Trace historical August Health/BAY SAP rows to the exact CareOS charge.
-- Read-only; confirms whether the generic QR + RABBIT_LENDING branch was the source signal.

WITH bad_sap AS (
  SELECT
    U_OrderID AS OrderID,
    U_OrderItem AS OrderItem,
    U_Period AS Period,
    U_InvoiceNo AS InvoiceNo,
    PaymentDate,
    BatchRunDate,
    UpdateDate
  FROM `pacific-plating-282708.sap_integration_v2.SAP_LIVE_FULL`
  WHERE PaymentChannel = 'RCL-Omise QR Prompt Pay-BAY'
    AND (
      U_InsuranceGroup IN ('Health', 'products/health-insurance')
      OR U_InsuranceType = 'Health'
    )
    AND SAFE.PARSE_DATE('%d%m%Y', NULLIF(PaymentDate, ''))
      BETWEEN DATE '2026-08-01' AND DATE '2026-08-31'
),

traced AS (
  SELECT
    s.*,
    i.product,
    c.id AS charge_id,
    c.status AS charge_status,
    c.payment_method,
    c.service_provider,
    c.payment_date AS raw_payment_date,
    c.update_time AS raw_update_time
  FROM bad_sap s
  LEFT JOIN `pacific-plating-282708.careos.careos_order_items` i
    ON i.human_id = s.OrderItem
  LEFT JOIN `pacific-plating-282708.careos.careos_orders` o
    ON o.id = i.order_id
  LEFT JOIN `pacific-plating-282708.careos.carepay_charges` c
    ON CAST(c.transaction_id AS STRING) = REGEXP_EXTRACT(o.payment, r'transactions/(.+)')
   AND c.installment_number = s.Period
   AND c.third_party_id = s.InvoiceNo
)

SELECT
  COUNT(*) AS sap_bad_rows,
  COUNTIF(charge_id IS NOT NULL) AS exact_charge_matches,
  COUNTIF(product = 'products/health-insurance') AS health_product_matches,
  COUNTIF(payment_method = 'QR_CODE' AND service_provider = 'RABBIT_LENDING')
    AS generic_bay_signal_matches,
  COUNTIF(OrderID IN (
    'L80552297', 'L79770471', 'L80637895', 'L79360431', 'L80474626',
    'L80682561', 'L79916653', 'L80005306', 'L79112016', 'L80421605'
  )) AS first_ten_reported_matches,
  ARRAY_AGG(STRUCT(
    OrderID, OrderItem, Period, InvoiceNo, PaymentDate, BatchRunDate, UpdateDate,
    product, charge_status, payment_method, service_provider, raw_payment_date
  ) ORDER BY OrderID, Period LIMIT 30) AS samples
FROM traced;

-- Red-capable reproduction for Root Cause 8 reported August 2026 Health/CI rows.
-- Read-only; uses SAP mirror values and current upstream labels at the same order/period grain.

WITH sap_health_bay AS (
  SELECT
    U_OrderID AS OrderID,
    U_OrderItem AS OrderItem,
    U_Period AS Period,
    PaymentDate,
    PaymentChannel,
    U_InsuranceGroup AS InsuranceGroup,
    U_InsuranceType AS InsuranceType,
    U_InvoiceNo AS InvoiceNo,
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

current_installment AS (
  SELECT OrderID, OrderItem, Period, PaymentChannel
  FROM `pacific-plating-282708.sap_data_engineer.sap_dashboard_carepay_installment`
),

current_health AS (
  SELECT OrderID, OrderItem, Period, PaymentChannel
  FROM `pacific-plating-282708.sap_data_engineer.RCL_HEALTH`
)

SELECT
  CASE WHEN COUNT(*) > 0 THEN 'RED' ELSE 'GREEN' END AS verdict,
  COUNT(*) AS sap_bad_rows,
  COUNT(DISTINCT OrderID) AS sap_bad_orders,
  COUNT(DISTINCT CONCAT(OrderID, '#', CAST(Period AS STRING))) AS sap_bad_order_periods,
  MIN(UpdateDate) AS first_mirror_update,
  MAX(UpdateDate) AS last_mirror_update,
  COUNTIF(i.PaymentChannel = 'RCL-Omise QR Prompt Pay-Health') AS now_health_in_installment,
  COUNTIF(h.PaymentChannel = 'RCL-Omise QR Prompt Pay-Health') AS now_health_in_rcl_health,
  ARRAY_AGG(STRUCT(
    s.OrderID,
    s.OrderItem,
    s.Period,
    s.PaymentDate,
    s.BatchRunDate,
    s.InvoiceNo,
    i.PaymentChannel AS current_installment_channel,
    h.PaymentChannel AS current_health_channel
  ) ORDER BY s.OrderID, s.Period LIMIT 30) AS samples
FROM sap_health_bay s
LEFT JOIN current_installment i USING (OrderID, OrderItem, Period)
LEFT JOIN current_health h USING (OrderID, OrderItem, Period);

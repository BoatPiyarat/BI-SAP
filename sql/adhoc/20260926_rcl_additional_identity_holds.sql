-- 2026-09-26 same-period payment correction. Source only; not deployed.
-- SELECT-only replacement for sap_integration_v2.RCL 05_newpayment.
-- Ordinary periods keep the existing paid-period exclusion.
-- Additional payments use immutable event identity, including the established
-- raw/2_ invoice alias for installment 1. No SAP values are rewritten.
WITH
  sap_paid_periods AS (
    SELECT DISTINCT U_OrderItem AS order_item, SAFE_CAST(U_Period AS INT64) AS period
    FROM `pacific-plating-282708.sap_integration_v2.SAP_LIVE_FULL`
    WHERE TransactionStatus IN ('Paid', 'paid')
  ),
  sap_terminal_events AS (
    SELECT DISTINCT U_OrderItem AS order_item, SAFE_CAST(U_Period AS INT64) AS period,
      U_InvoiceNo AS invoice_no
    FROM `pacific-plating-282708.sap_integration_v2.SAP_LIVE_FULL`
    WHERE LOWER(TRIM(TransactionStatus)) IN
      ('paid', 'cancelled', 'cancelled (change order / rejected)')
      AND NULLIF(TRIM(U_InvoiceNo), '') IS NOT NULL
      AND UPPER(TRIM(U_InvoiceNo)) != 'NULL'
  ),
  source_receipts AS (
    SELECT id, transaction_id, installment_number, third_party_id, create_time, update_time,
      COUNT(*) OVER (PARTITION BY transaction_id, installment_number, third_party_id) AS invoice_rows,
      COUNT(*) OVER (PARTITION BY transaction_id, installment_number, create_time) AS timestamp_rows
    FROM `pacific-plating-282708.careos.carepay_charges`
    WHERE status = 'SUCCESSFUL' AND service_provider = 'RABBIT_LENDING'
  ),
  valid_additional_events AS (
    SELECT oi.human_id AS order_item, c.installment_number AS period,
      CASE WHEN c.installment_number = 1 THEN CONCAT('2_', c.third_party_id)
        ELSE c.third_party_id END AS invoice_no,
      MIN(c.update_time) AS raw_update_time
    FROM source_receipts c
    JOIN `pacific-plating-282708.careos.careos_orders` o
      ON o.payment = CONCAT('transactions/', c.transaction_id)
    JOIN `pacific-plating-282708.careos.careos_order_items` oi
      ON oi.order_id = o.id
    WHERE NULLIF(TRIM(c.id), '') IS NOT NULL
      AND NULLIF(TRIM(c.third_party_id), '') IS NOT NULL
      AND UPPER(TRIM(c.third_party_id)) != 'NULL'
      AND NULLIF(TRIM(oi.human_id), '') IS NOT NULL
      AND c.invoice_rows = 1 AND c.timestamp_rows = 1
    GROUP BY order_item, period, invoice_no
    HAVING COUNT(*) = 1
  ),
  interface AS (
    SELECT
      CompanyDB,
      OrderID,
      OrderItem,
      InvoiceNo,
      OrderDate,
      InsuredID,
      Title,
      FirstName,
      LastName,
      InsurerCode,
      InsuranceGroup,
      InsuranceType,
      InsuranceProduct,
      ProductType,
      PolicyType,
      Endorse,
      PolicyDate,
      PolicyNo,
      EndorsementNo,
      ChassisNo,
      LicensePlate,
      GrossPremium,
      StampDuty,
      VAT,
      TotalPremium,
      WHT,
      TotalEIR,
      TotalSBT,
      ProcessingFee,
      ProcessingFeeVat,
      ShippingFee,
      ShippingFeeVat,
      TotalAmount,
      Discount,
      TransactionStatus,
      SubmissionStatus,
      ApprovalStatus,
      PaymentStatus,
      ExpectedReceived,
      ActualReceived,
      InterestThisPeriod,
      PrincipleThisPeriod,
      InterestEIRThisPeriod,
      PrincipleEIRThisPeriod,
      PaymentDate,
      Period,
      TotalPeriods,
      PendingPayment,
      PaymentMethod,
      PaymentChannel,
      ExpectedDate,
      RefOrder,
      CAST(RefundAmountBeforeFee AS FLOAT64) AS RefundAmountBeforeFee,
      CAST(RefundAmountAfterFee AS FLOAT64) AS RefundAmountAfterFee,
      BillingAddress,
      BatchRunDate,
      SAFE_CAST(Period AS INT64) AS careos_installment,
      COALESCE(ExpectedReceived = 0, FALSE)
        AND COALESCE(ActualReceived, 0) > 0
        AND LOWER(TRIM(COALESCE(TransactionStatus, ''))) = 'paid'
        AS is_additional_payment
    FROM `pacific-plating-282708.sap_data_engineer.sap_dashboard_carepay_installment`
  )
SELECT CURRENT_TIMESTAMP() AS checked_at_utc, interface.OrderID, interface.OrderItem,
 interface.Period,interface.InvoiceNo,interface.ActualReceived,
 'HOLD_AMBIGUOUS_OR_MISSING_SOURCE_RECEIPT' AS rule_code
FROM interface
WHERE interface.is_additional_payment
AND NOT EXISTS (
 SELECT 1 FROM valid_additional_events v
 WHERE v.order_item=interface.OrderItem AND v.period=interface.careos_installment
 AND v.invoice_no=interface.InvoiceNo
);

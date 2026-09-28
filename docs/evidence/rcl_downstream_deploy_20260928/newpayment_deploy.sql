CREATE OR REPLACE VIEW `pacific-plating-282708.sap_integration_v2.RCL 05_newpayment` AS
-- 2026-09-27 downstream candidate; SELECT only, NOT DEPLOYED.
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
      ROW_NUMBER() OVER (PARTITION BY transaction_id, installment_number ORDER BY create_time, id) AS source_charge_rank,
      COUNT(*) OVER (PARTITION BY id) AS charge_id_rows,
      COUNT(*) OVER (PARTITION BY transaction_id, installment_number, third_party_id) AS invoice_rows,
      COUNT(*) OVER (PARTITION BY transaction_id, installment_number, create_time) AS timestamp_rows
    FROM `pacific-plating-282708.careos.carepay_charges`
    WHERE status = 'SUCCESSFUL' AND service_provider = 'RABBIT_LENDING'
  ),
  source_receipt_events AS (
    -- Preserve rank lineage even when additional-receipt eligibility fails.
    -- The fallback mirrors dashboard identity ONLY for classification; it is
    -- never accepted as a new additional receipt's invoice identity.
    SELECT oi.human_id AS order_item, c.installment_number AS period,
      CASE WHEN c.installment_number = 1 AND oi.motor_item_type='MOTOR_TYPE_COMPULSORY'
        THEN CONCAT('2_',c.third_party_id)
        WHEN c.installment_number = 1 THEN CONCAT('2_', COALESCE(c.third_party_id, oi.human_id))
        ELSE COALESCE(c.third_party_id, oi.human_id) END AS invoice_no,
      MIN(c.update_time) AS raw_update_time,
      CASE WHEN COUNT(*) = 1 THEN MIN(c.source_charge_rank) END AS source_charge_rank,
      COUNT(*) AS source_event_rows,
      COUNT(*) = 1 AND COUNTIF(
        NULLIF(TRIM(c.id), '') IS NULL
        OR NULLIF(TRIM(c.third_party_id), '') IS NULL
        OR UPPER(TRIM(c.third_party_id)) = 'NULL'
        OR c.charge_id_rows != 1 OR c.invoice_rows != 1 OR c.timestamp_rows != 1
      ) = 0 AS additional_identity_valid
    FROM source_receipts c
    JOIN `pacific-plating-282708.careos.careos_orders` o
      ON o.payment = CONCAT('transactions/', c.transaction_id)
    JOIN `pacific-plating-282708.careos.careos_order_items` oi
      ON oi.order_id = o.id
    WHERE NULLIF(TRIM(oi.human_id), '') IS NOT NULL
      AND (COALESCE(oi.motor_item_type,'') != 'MOTOR_TYPE_COMPULSORY' OR c.source_charge_rank=1)
    GROUP BY order_item, period, invoice_no
  ),
  interface AS (
    SELECT
      d.CompanyDB,
      d.OrderID,
      d.OrderItem,
      d.InvoiceNo,
      d.OrderDate,
      d.InsuredID,
      d.Title,
      d.FirstName,
      d.LastName,
      d.InsurerCode,
      d.InsuranceGroup,
      d.InsuranceType,
      d.InsuranceProduct,
      d.ProductType,
      d.PolicyType,
      d.Endorse,
      d.PolicyDate,
      d.PolicyNo,
      d.EndorsementNo,
      d.ChassisNo,
      d.LicensePlate,
      d.GrossPremium,
      d.StampDuty,
      d.VAT,
      d.TotalPremium,
      d.WHT,
      d.TotalEIR,
      d.TotalSBT,
      d.ProcessingFee,
      d.ProcessingFeeVat,
      d.ShippingFee,
      d.ShippingFeeVat,
      d.TotalAmount,
      d.Discount,
      d.TransactionStatus,
      d.SubmissionStatus,
      d.ApprovalStatus,
      d.PaymentStatus,
      d.ExpectedReceived,
      d.ActualReceived,
      d.InterestThisPeriod,
      d.PrincipleThisPeriod,
      d.InterestEIRThisPeriod,
      d.PrincipleEIRThisPeriod,
      d.PaymentDate,
      d.Period,
      d.TotalPeriods,
      d.PendingPayment,
      d.PaymentMethod,
      d.PaymentChannel,
      d.ExpectedDate,
      d.RefOrder,
      CAST(d.RefundAmountBeforeFee AS FLOAT64) AS RefundAmountBeforeFee,
      CAST(d.RefundAmountAfterFee AS FLOAT64) AS RefundAmountAfterFee,
      d.BillingAddress,
      d.BatchRunDate,
      SAFE_CAST(d.Period AS INT64) AS careos_installment,
      v.source_charge_rank, v.source_event_rows, v.additional_identity_valid,
      COALESCE(ExpectedReceived = 0, FALSE)
        AND COALESCE(ActualReceived, 0) > 0
        AND LOWER(TRIM(COALESCE(TransactionStatus, ''))) = 'paid'
        AS has_additional_shape
    FROM `pacific-plating-282708.sap_data_engineer.sap_dashboard_carepay_installment` d
    LEFT JOIN source_receipt_events v ON v.order_item=d.OrderItem
      AND v.period=SAFE_CAST(d.Period AS INT64) AND v.invoice_no IS NOT DISTINCT FROM d.InvoiceNo
  )
SELECT DISTINCT
  interface.CompanyDB,
  interface.OrderID,
  interface.OrderItem,
  interface.InvoiceNo,
  interface.OrderDate,
  interface.InsuredID,
  interface.Title,
  interface.FirstName,
  interface.LastName,
  interface.InsurerCode,
  interface.InsuranceGroup,
  interface.InsuranceType,
  interface.InsuranceProduct,
  interface.ProductType,
  interface.PolicyType,
  interface.Endorse,
  interface.PolicyDate,
  interface.PolicyNo,
  interface.EndorsementNo,
  interface.ChassisNo,
  interface.LicensePlate,
  interface.GrossPremium,
  interface.StampDuty,
  interface.VAT,
  interface.TotalPremium,
  interface.WHT,
  interface.TotalEIR,
  interface.TotalSBT,
  interface.ProcessingFee,
  interface.ProcessingFeeVat,
  interface.ShippingFee,
  interface.ShippingFeeVat,
  interface.TotalAmount,
  interface.Discount,
  interface.TransactionStatus,
  interface.SubmissionStatus,
  interface.ApprovalStatus,
  interface.PaymentStatus,
  interface.ExpectedReceived,
  interface.ActualReceived,
  interface.InterestThisPeriod,
  interface.PrincipleThisPeriod,
  interface.InterestEIRThisPeriod,
  interface.PrincipleEIRThisPeriod,
  interface.PaymentDate,
  interface.Period,
  interface.TotalPeriods,
  interface.PendingPayment,
  interface.PaymentMethod,
  interface.PaymentChannel,
  interface.ExpectedDate,
  interface.RefOrder,
  interface.RefundAmountBeforeFee,
  interface.RefundAmountAfterFee,
  interface.BillingAddress,
  interface.BatchRunDate
FROM interface
WHERE IF(
  interface.source_event_rows IS NULL AND COALESCE(interface.ActualReceived, 0) != 0
  AND NOT EXISTS (
    SELECT 1 FROM sap_terminal_events e
    WHERE e.order_item=interface.OrderItem AND e.period=interface.careos_installment
      AND (e.invoice_no=interface.InvoiceNo OR (interface.careos_installment=1
        AND STARTS_WITH(interface.InvoiceNo,'2_') AND e.invoice_no=SUBSTR(interface.InvoiceNo,3)))
  ),
  ERROR('RCL_MISSING_PAID_RECEIPT_LINEAGE: run downstream receipt diagnostics before export'),
  interface.careos_installment IS NOT NULL
  AND (
    (
      (
        interface.source_charge_rank = 1
        OR (interface.source_event_rows IS NULL AND COALESCE(interface.ActualReceived, 0) = 0)
      )
      AND NOT EXISTS (
        SELECT 1 FROM sap_paid_periods p
        WHERE p.order_item = interface.OrderItem
          AND p.period = interface.careos_installment
      )
    )
    OR (
      interface.source_charge_rank > 1
      AND interface.has_additional_shape
      AND interface.additional_identity_valid
      AND NULLIF(TRIM(interface.InvoiceNo), '') IS NOT NULL
      AND UPPER(TRIM(interface.InvoiceNo)) != 'NULL'
      AND NOT EXISTS (
        SELECT 1 FROM sap_terminal_events e
        WHERE e.order_item = interface.OrderItem
          AND e.period = interface.careos_installment
          AND (
            e.invoice_no = interface.InvoiceNo
            OR (
              interface.careos_installment = 1
              AND STARTS_WITH(interface.InvoiceNo, '2_')
              AND e.invoice_no = SUBSTR(interface.InvoiceNo, 3)
            )
          )
      )
    )
  )
)
ORDER BY interface.OrderItem, interface.Period
;

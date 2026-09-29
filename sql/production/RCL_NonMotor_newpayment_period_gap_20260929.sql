WITH base AS (
WITH
  sap AS (
  SELECT
    DISTINCT CompanyDB,
    U_OrderID OrderID,
    U_OrderItem OrderItem,
    U_InvoiceNo InvoiceNo,
    OrderDate AS OrderDate,
    U_InsuredID InsuredID,
    U_Title Title,
    U_FirstName FirstName,
    U_LastName LastName,
    SPLIT(U_InsurerCode, '-')[OFFSET(1)] AS InsurerCode,
    U_InsuranceGroup InsuranceGroup,
    U_InsuranceType InsuranceType,
    U_InsuranceProduct InsuranceProduct,
    CASE
      WHEN U_ProductType = 'NULL' THEN 'Insurance'
      ELSE U_ProductType
  END
    AS ProductType,
    U_PolicyType PolicyType,
    'N' Endorse,
    PolicyDate AS PolicyDate,
    U_PolicyNo PolicyNo,
    CAST(EndorsementNo AS STRING) EndorsementNo,
    U_ChassisNo ChassisNo,
    U_LicensePlate LicensePlate,
    GrossPremium GrossPremium,
    StampDuty StampDuty,
    VAT VAT,
    TotalPremium TotalPremium,
    WHT WHT,
    TotalEIR TotalEIR,
    TotalSBT TotalSBT,
    U_ProcessingFee ProcessingFee,
    U_ProcessingFeeVat ProcessingFeeVat,
    U_ShippingFee ShippingFee,
    U_ShippingFeeVat ShippingFeeVat,
    U_TotalAmount TotalAmount,
    U_Discount Discount,
    TransactionStatus,
    U_SubmissionStatus SubmissionStatus,
    U_ApprovalStatus ApprovalStatus,
    U_PaymentStatus PaymentStatus,
    ExpectedReceived,
    U_ActualReceived ActualReceived,
    U_InterestThisPeriod InterestThisPeriod,
    U_PrincipleThisPeriod PrincipleThisPeriod,
    U_InterestEIRThisPeriod InterestEIRThisPeriod,
    U_PrincipleEIRThisPeriod PrincipleEIRThisPeriod,
    CASE
      WHEN PaymentDate = 'NULL' THEN ''
      ELSE PaymentDate
  END
    AS PaymentDate,
    U_Period Period,
    TotalPeriods TotalPeriods,
    PendingPayment PendingPayment,
    CASE
      WHEN PaymentMethod = 'NULL' THEN ''
      ELSE PaymentMethod
  END
    AS PaymentMethod,
    CASE
      WHEN PaymentChannel = 'NULL' THEN ''
      ELSE PaymentChannel
  END
    AS PaymentChannel,
    ExpectedDate AS ExpectedDate,
    RefOrder RefOrder,
    CAST(RefundAmountBeforeFee AS STRING) RefundAmountBeforeFee,
    CAST(RefundAmountAfterFee AS STRING) RefundAmountAfterFee,
    BillingAddress BillingAddress,
    CAST(FORMAT_DATE('%d%m%Y', CURRENT_DATE()) AS STRING)  AS BatchRunDate,
    CONCAT(U_OrderItem,U_Period) keys
  FROM
    `pacific-plating-282708.sap_integration_v2.SAP_LIVE_FULL`
  WHERE U_InsuranceGroup NOT IN ( 'Motor', 'Corporate')
  AND PolicyDate NOT LIKE '%2023%'
  AND PolicyDate NOT LIKE '%2024%'),

  cancelled AS (  SELECT distinct U_OrderItem
  FROM `pacific-plating-282708.sap_integration_v2.SAP_LIVE_FULL`
  WHERE STARTS_WITH(COALESCE(U_OrderID, ''), 'C#')
  OR LOWER(TransactionStatus) IN ('cancelled','cancelled (change order / rejected)')
),

  newpayment AS (
  SELECT
    U_OrderItem order_item
  FROM
    `pacific-plating-282708.sap_integration_v2.RCL 05-1_paid by period_NonMotor` p INNER JOIN
    `pacific-plating-282708.sap_integration_v2.SAP_LIVE_FULL` s
  ON p.order_item = s.U_OrderItem
  WHERE
  (s.TransactionStatus in ('Paid', 'paid') )
  AND DATE(p.charges_update_time) BETWEEN '2025-11-01' AND '2026-12-31'
  GROUP BY U_OrderItem
  ),

interface AS (
  SELECT
    *, CONCAT(OrderItem,Period) keys,
    SAFE_CAST(Period AS INT64) AS careos_installment
  FROM `pacific-plating-282708.sap_data_engineer.RCL_HEALTH`
),

combine AS (SELECT
  sap.CompanyDB,
    sap.OrderID,
    sap.OrderItem,
    sap.InvoiceNo,
    sap.OrderDate,
    sap.InsuredID,
    sap.Title,
    sap.FirstName,
    sap.LastName,
    sap.InsurerCode,
    sap.InsuranceGroup,
    sap.InsuranceType,
    sap.InsuranceProduct,
    sap.ProductType,
    sap.PolicyType,
    sap.Endorse,
    sap.PolicyDate,
    sap.PolicyNo,
    sap.EndorsementNo,
    sap.ChassisNo,
    sap.LicensePlate,
    sap.GrossPremium,
    sap.StampDuty,
    sap.VAT,
    sap.TotalPremium,
    sap.WHT,
    sap.TotalEIR,
    sap.TotalSBT,
    sap.ProcessingFee,
    sap.ProcessingFeeVat,
    sap.ShippingFee,
    sap.ShippingFeeVat,
    sap.TotalAmount,
    sap.Discount,
    sap.TransactionStatus,
    sap.SubmissionStatus,
    sap.ApprovalStatus,
    sap.PaymentStatus,
    sap.ExpectedReceived,
    sap.ActualReceived,
    sap.InterestThisPeriod,
    sap.PrincipleThisPeriod,
    sap.InterestEIRThisPeriod,
    sap.PrincipleEIRThisPeriod,
    sap.PaymentDate,
    sap.Period,
    sap.TotalPeriods,
    sap.PendingPayment,
    sap.PaymentMethod,
    sap.PaymentChannel,
    sap.ExpectedDate,
    sap.RefOrder,
    sap.RefundAmountBeforeFee,
    sap.RefundAmountAfterFee,
    sap.BillingAddress,
    sap.BatchRunDate
FROM sap
JOIN newpayment
ON sap.OrderItem = newpayment.order_item
WHERE
  LOWER(sap.TransactionStatus) = 'paid'
AND OrderID NOT LIKE '%_X%'
AND OrderID NOT LIKE 'C#%'
AND PaymentDate IS NOT NULL
AND PaymentDate <> ''

UNION ALL

SELECT
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
JOIN newpayment
  ON interface.OrderItem = newpayment.order_item
WHERE
  NOT EXISTS (
    SELECT 1 FROM sap AS paid_period
    WHERE paid_period.OrderItem = interface.OrderItem
      AND SAFE_CAST(paid_period.Period AS INT64) = interface.careos_installment
      AND LOWER(paid_period.TransactionStatus) = 'paid'
  )
AND OrderID NOT LIKE '%_X%'
AND OrderID NOT LIKE 'C#%'
)

SELECT *
FROM combine
WHERE LOWER(FirstName) <> 'test'
  AND NOT EXISTS (SELECT 1 FROM cancelled c WHERE c.U_OrderItem = combine.OrderItem)
),
item_spine AS (
 SELECT OrderItem,COUNT(*) row_count,COUNT(DISTINCT Period) distinct_periods,
 COUNTIF(Period IS NULL) null_periods,COUNTIF(TotalPeriods IS NULL) null_totals,
 COUNT(DISTINCT TotalPeriods) total_variants,MAX(TotalPeriods) total_periods,
 MIN(Period) min_period,MAX(Period) max_period,
 COUNTIF(COALESCE(LOWER(TransactionStatus),'') NOT IN ('paid','pending')) invalid_status_rows
 FROM base GROUP BY OrderItem
)
SELECT base.* REPLACE(
  CASE LOWER(TransactionStatus) WHEN 'paid' THEN 'Paid' WHEN 'pending' THEN 'Pending' ELSE TransactionStatus END AS TransactionStatus,
  CASE
    WHEN PaymentDate IS NULL OR PaymentDate = '' THEN PaymentDate
    WHEN PARSE_DATE('%d%m%Y', PaymentDate) < DATE_TRUNC(CURRENT_DATE(), MONTH)
      THEN FORMAT_DATE('%d%m%Y', DATE_TRUNC(CURRENT_DATE(), MONTH))
    ELSE PaymentDate
  END AS PaymentDate
)
FROM base JOIN item_spine spine USING(OrderItem)
WHERE spine.null_periods=0 AND spine.null_totals=0
 AND spine.total_variants=1 AND spine.total_periods>=1
 AND spine.row_count=spine.total_periods AND spine.distinct_periods=spine.total_periods
 AND spine.min_period=1 AND spine.max_period=spine.total_periods
 AND spine.invalid_status_rows=0
ORDER BY OrderItem, Period
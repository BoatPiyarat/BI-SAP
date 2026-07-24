-- BASELINE CAPTURE 2026-07-25 -- pulled verbatim from live BigQuery view definition
-- Object: sap_view.RCL_NonMotor_process_2_newpayment
-- Part of the 11 sap_view process views confirmed as real nightly production, that
-- read directly from sap_integration_v2.SAP_LIVE_FULL. Repointing to
-- sap_integration_v3.stg_sap_state (deduped, no duplicate (OrderItem,Period) rows).
-- See docs/knowledge/30_SAP_CHANGELOG.md 2026-07-25 entry.

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
    CAST(EndorsementNo AS STRING) EndorsementNo,  -- fix 2026-07-25: was U_EndorsementNo, doesn't exist (query wouldn't even parse before this)
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
  WHERE U_OrderID like '%C%'
  OR TransactionStatus in ('Cancelled','Cancelled (Change order / Rejected)')
),

  newpayment AS (
  SELECT
    U_OrderItem order_item,
    MAX(U_Period) installment_number 
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
  sap.* except(keys)
FROM sap
JOIN newpayment
ON sap.OrderItem = newpayment.order_item
WHERE 
  sap.Period <= newpayment.installment_number
AND OrderID NOT LIKE '%_X%'
AND OrderID NOT LIKE 'C#%'
AND PaymentDate IS NOT NULL 
AND PaymentDate <> '' 

UNION ALL

SELECT
  interface.* except(keys,careos_installment)
FROM interface
JOIN newpayment
  ON interface.OrderItem = newpayment.order_item
WHERE 
  interface.careos_installment > newpayment.installment_number
AND OrderID NOT LIKE '%_X%'
AND OrderID NOT LIKE 'C#%'
)

SELECT *
FROM combine
WHERE LOWER(FirstName) <> 'test'
ORDER BY OrderItem, Period


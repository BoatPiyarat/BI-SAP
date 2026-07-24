-- BASELINE CAPTURE 2026-07-25 -- pulled verbatim from live BigQuery view definition
-- Object: sap_view.RCL_Motor_process_3_cancel
-- Part of the 11 sap_view process views confirmed as real nightly production, that
-- read directly from sap_integration_v2.SAP_LIVE_FULL. Repointing to
-- sap_integration_v3.stg_sap_state (deduped, no duplicate (OrderItem,Period) rows).
-- See docs/knowledge/30_SAP_CHANGELOG.md 2026-07-25 entry.

  -- RCL cancel--
WITH
  cancelled AS (
  SELECT
    DISTINCT U_OrderItem
  FROM
    `pacific-plating-282708.sap_integration_v2.SAP_LIVE_FULL`
  WHERE
    (U_OrderID LIKE 'C#%'
      AND PaymentChannel LIKE 'RCL%')
    OR (TransactionStatus IN ('Cancelled',
        'Cancelled (Change order / Rejected)')
      AND PaymentChannel LIKE '%RCL%') ),

  multi AS(
  SELECT
    charges.*,
    ROW_NUMBER() OVER (PARTITION BY charges.transaction_id ORDER BY charges.update_time DESC) AS rnk,
    ROW_NUMBER() OVER (PARTITION BY charges.transaction_id, installment_number ORDER BY charges.update_time DESC) AS multi,
    human_id,
    orders.cancel_time order_cancelltime,
    is_cancelled
  FROM
    `pacific-plating-282708.careos.carepay_charges` charges
  LEFT JOIN
    `pacific-plating-282708.careos.careos_orders` orders
  ON
    orders.payment = CONCAT('transactions/',charges.transaction_id)
  WHERE
    status = 'SUCCESSFUL'
    AND orders.human_id IS NOT NULL),

  sap1 AS (
  SELECT
    U_OrderItem
  FROM
    `pacific-plating-282708.sap_integration_v2.SAP_LIVE_FULL`
  WHERE
    (PaymentDate = 'NULL' OR PaymentDate = ''
      AND U_InvoiceNo LIKE 'L%') ),

  sap AS(
  SELECT
    ROW_NUMBER() OVER (PARTITION BY U_OrderItem, U_Period ORDER BY U_OrderItem, U_Period, TransactionStatus, U_InvoiceNo) AS dup
    ,* 
  FROM
    `pacific-plating-282708.sap_integration_v2.SAP_LIVE_FULL`

  ORDER BY U_Period
    ),

  item_cancelled AS (
  SELECT
    human_id,
    cancel_time
  FROM
    `pacific-plating-282708.careos.careos_order_items`
  WHERE
 cancel_time >= '2025-01-01' ),

  change AS (
  SELECT
    *
  FROM
    pacific-plating-282708.careos.cancelled_change_orders )

SELECT
  DISTINCT CompanyDB,
  U_OrderID OrderID,
  U_OrderItem OrderItem,
  CASE
    WHEN U_InvoiceNo = 'NULL' THEN ''
    ELSE U_InvoiceNo
END
  AS InvoiceNo,
  OrderDate AS OrderDate,
  U_InsuredID InsuredID,
  U_Title Title,
  U_FirstName FirstName,
  U_LastName LastName,
  SPLIT(U_InsurerCode, '-')[
OFFSET
  (1)] AS InsurerCode,
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
  U_EndorsementNo EndorsementNo,
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
  CASE
    WHEN change.old_human_id IS NOT NULL THEN 'Cancelled (Change order / Rejected)'
    ELSE 'Cancelled'
END
  AS TransactionStatus,
  U_SubmissionStatus SubmissionStatus,
  U_ApprovalStatus ApprovalStatus,
  U_PaymentStatus PaymentStatus,
  CASE WHEN
    (ExpectedReceived = 0 OR ExpectedReceived IS NULL )
   AND  sap.dup=1
  THEN U_ActualReceived
  WHEN ExpectedReceived >0 THEN ExpectedReceived
  END AS ExpectedReceived,
  U_ActualReceived ActualReceived,
  U_InterestThisPeriod InterestThisPeriod,
  U_PrincipleThisPeriod PrincipleThisPeriod,
  U_InterestEIRThisPeriod InterestEIRThisPeriod,
  U_PrincipleEIRThisPeriod PrincipleEIRThisPeriod,
  CASE
    WHEN PaymentDate = 'NULL' OR PaymentDate = '' THEN ''
    ELSE PaymentDate
END
  AS PaymentDate,
  U_Period Period,
  TotalPeriods TotalPeriods,
  PendingPayment,
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
  CASE
    WHEN PaymentDate = 'NULL' OR PaymentDate = '' OR PaymentChannel = 'NULL' OR PaymentMethod = 'NULL' OR PaymentChannel = '' OR PaymentMethod = '' THEN ''
    ELSE PaymentDate
END
  AS ExpectedDate,
  RefOrder RefOrder,
  RefundAmountBeforeFee RefundAmountBeforeFee,
  RefundAmountAfterFee RefundAmountAfterFee,
  BillingAddress BillingAddress,
  CAST(FORMAT_DATE('%d%m%Y', CURRENT_DATE()) AS STRING) AS BatchRunDate,
  --sap.dup 
FROM
  sap
LEFT JOIN
  item_cancelled
ON
  human_id = U_OrderItem
LEFT JOIN
  change
ON
  change.old_human_id = sap.U_OrderID
WHERE 
  item_cancelled.human_id IS NOT NULL
 AND NOT EXISTS (
  SELECT
    U_OrderItem
  FROM
    cancelled
  WHERE
     cancelled.U_OrderItem = sap.U_OrderItem )
 AND sap.TotalPeriods > 1
  AND item_cancelled.cancel_time IS NOT NULL 
  AND item_cancelled.cancel_time >= '2025-01-01' 
  AND OrderDate NOT LIKE '%2023%'
  AND OrderDate NOT LIKE '%2024%' 
  AND sap.U_OrderID NOT LIKE '%_2%' 
 AND (sap.PaymentChannel NOT LIKE '%RCB%'
    OR sap.PaymentChannel IS NULL
    OR sap.PaymentChannel = 'NULL')  
  AND sap.U_OrderID NOT LIKE 'C#%' 
/*     AND (U_InvoiceNo NOT LIKE 'L%'
  OR U_InvoiceNo = 'NULL'
  OR U_InvoiceNo IS NULL)  */
AND sap.U_OrderID NOT LIKE '%_X%' 
AND (sap.U_Period = 1 OR (sap.U_Period > 1 AND sap.dup = 1))   


ORDER BY
  U_OrderItem,
  U_Period

-- BASELINE CAPTURE 2026-07-24 -- pulled verbatim from live BigQuery view definition
-- Object: sap_data_engineer.sap_dashboard_carepay_installment
-- This is the CURRENT production query, exactly as running tonight's schedule.
-- Do not hand-edit without diffing against a fresh pull first (it may have
-- changed in BigQuery since this capture). See docs/knowledge/30_SAP_CHANGELOG.md
-- (2026-07-24 entry) for what was found wrong with it and why.

-- Update query 13/08/2024 : Update ProcessingFee,ProcessingFeeVAT by PAM
-- RCL คิดจาก 3.3% ของ column Processing Fee (เนื่องจากเสียภาษีธุรกิจเฉพาะ SBT ไม่ใช่ภาษีมูลค่าเพิ่ม VAT) ซึ่งยอดรวมของ order จะถูก split เป็น 2 column คือ-- 1. ProcessingFeeVAT *3.3% , -- 2. ที่เหลือคือ xx.xx ProcessingFee
-- 26/12/2024 Update query 1.PaymentChannel , PaymentMethod 2.Order NONMOTOR RCL create on CareOS -> InsuranceGroup
-- 07/02/2025 Update case InterestEIRThisPeriod **UCCESS yet by Petch data eng.
-- 19/Jul/2025 Piyarat fixed ExpectedReceived of multiple payment per period
-------------------------------------------------------------------------------------------------------------------------
WITH
charges AS (
  SELECT * ,
  ROW_NUMBER() OVER (PARTITION BY transaction_id, installment_number ORDER BY create_time) AS charge_rank
  FROM `pacific-plating-282708.careos.carepay_charges`
  WHERE status = 'SUCCESSFUL'
  --AND service_provider = 'RABBIT_LENDING'
), 

follow_ups AS ( 
  SELECT * FROM `pacific-plating-282708.careos.carepay_follow_ups`
),

payment_options AS ( 
  SELECT * FROM `pacific-plating-282708.careos.carepay_payment_options`
),

prices AS ( 
  SELECT * FROM `pacific-plating-282708.careos.carepay_prices`
),

refunds AS ( 
  SELECT * FROM `pacific-plating-282708.careos.carepay_refunds`
),

transaction_snapshot_installment_details AS ( 
  SELECT * FROM `pacific-plating-282708.careos.carepay_transaction_snapshot_installment_details`
),

transaction_snapshot_price_summaries AS ( 
  SELECT * FROM `pacific-plating-282708.careos.carepay_transaction_snapshot_price_summaries`
),
 
transaction_snapshots AS ( 
  SELECT * FROM `pacific-plating-282708.careos.carepay_transaction_snapshots`
  WHERE number_of_installment > 1
),

transactions AS (
  SELECT * FROM `pacific-plating-282708.careos.carepay_transactions`
),

orders AS (
  SELECT * FROM `pacific-plating-282708.careos.careos_orders`
),

order_items AS (
  SELECT * FROM `pacific-plating-282708.careos.careos_order_items`
),

leads AS (
  SELECT * FROM `pacific-plating-282708.careos.careos_leads`
),

change AS (SELECT current_human_id human_id, old_human_id
FROM pacific-plating-282708.careos.cancelled_change_orders ),

check_order_items AS (
SELECT 
  orders.human_id AS OrderID, 
  COUNT(order_items) AS no_items
FROM `pacific-plating-282708.careos.careos_order_items` order_items
LEFT JOIN `pacific-plating-282708.careos.careos_orders` orders
    ON order_items.order_id = orders.id
GROUP BY orders.human_id
),
--------------------------------------------------------------------------------------------------------

takeaway_compulsary AS (
  SELECT 
    transaction_snapshot_installment_details.id AS transaction_snapshot_installment_detail_id, 
    transaction_snapshot_installment_details.period, 
    ROUND((1/100) * transaction_snapshot_installment_details.add_ons,2) AS add_ons, 
    transaction_snapshots.id AS transaction_snapshot_id, 
    transactions.id AS transaction_id
  FROM transaction_snapshot_installment_details
  LEFT JOIN transaction_snapshots
    ON transaction_snapshots.id = transaction_snapshot_installment_details.snapshot_id
  LEFT JOIN transactions
    ON transactions.id = transaction_snapshots.transaction_id
  WHERE transaction_snapshot_installment_details.period = 1 
  AND transaction_snapshot_installment_details.add_ons IS NOT NULL

),
--------------------------------------------------------------------------------------------------------
--------------------------------------------------------------------------------------------------------

rcl_voluntary_installment_details AS (
  SELECT
    'rcl_voluntary_installment_details' AS CTE_source,
    'RCB' AS CompanyDB,
    orders.human_id AS OrderID,
    order_items.human_id AS OrderItem,
CASE WHEN charges.installment_number = 1 THEN CONCAT('2_',COALESCE(charges.third_party_id,order_items.human_id))
  WHEN charges.third_party_id is null AND charges.status = 'SUCCESSFUL' THEN order_items.human_id
  WHEN charges.third_party_id is null AND charges.status <> 'SUCCESSFUL' THEN ''
  ELSE  charges.third_party_id 
END AS InvoiceNo,
    orders.create_time AS OrderDate,
    CASE 
      WHEN JSON_VALUE(orders.data, '$.policyHolder.isCompany') ='true' THEN 
    JSON_VALUE(orders.data, '$.policyHolder.companyTaxId') 
      ELSE JSON_VALUE(orders.data, '$.idNumber') 
    END AS InsuredID,
    JSON_VALUE(orders.data, '$.policyHolder.title') AS Title,
    COALESCE(JSON_VALUE(orders.data, '$.policyHolder.firstName'),JSON_VALUE(orders.data, '$.policyHolder.policyAddress.companyName')) AS FirstName,
    JSON_VALUE(orders.data, '$.policyHolder.lastName') AS LastName,
    order_items.insurer AS InsurerCode,
    order_items.product AS InsuranceGroup,
    order_items.motor_item_type AS InsuranceType,
    CASE WHEN JSON_VALUE(orders.data, '$.oicCode') in ('TYPE_610','TYPE_620', 'TYPE_630') 
    THEN 'MotorBike'  
    ELSE 'Motor'
    END AS InsuranceProduct,
    'Insurance' ProductType,
    leads.type AS PolicyType,
    'N' AS Endorse,
    order_items.policy_start_date AS PolicyDate,
    order_items.policy_number AS PolicyNo,
    NULL AS EndorsementNo,
    JSON_VALUE(orders.data, '$.chassisNumber') AS ChassisNo,
    JSON_VALUE(orders.data, '$.carLicensePlate') AS LicensePlate,
    order_items.net_premium AS GrossPremium,
    order_items.stamp_duty AS StampDuty,
    order_items.vat_amount AS VAT,
    order_items.gross_premium AS TotalPremium,
    ROUND((1 / 100) * transaction_snapshot_price_summaries.wht_amount,2) AS WHT,
    CASE
      WHEN transaction_snapshot_price_summaries.interest_amount IS NULL THEN 0
      ELSE ROUND(ROUND((1 / 100) * transaction_snapshot_price_summaries.interest_amount,2) - ((ROUND((1 / 100) * transaction_snapshot_price_summaries.interest_amount,2) * 3.3) / 103.3),2)
    END AS TotalEIR,
    CASE
      WHEN transaction_snapshot_price_summaries.interest_amount IS NULL THEN 0
      ELSE ROUND(((ROUND((1 / 100) * transaction_snapshot_price_summaries.interest_amount,2) * 3.3) / 103.3),2)
    END AS TotalSBT,
    CASE 
      WHEN transaction_snapshot_price_summaries.processing_fee_amount IS NULL THEN 0
      ELSE ROUND (ROUND((1 / 100) * transaction_snapshot_price_summaries.processing_fee_amount,2) * (100/103.3),2)
    END AS ProcessingFee,
    CASE
      WHEN transaction_snapshot_price_summaries.processing_fee_amount IS NULL THEN 0
      ELSE ROUND(ROUND((1 / 100) * transaction_snapshot_price_summaries.processing_fee_amount,2)-(ROUND((1 / 100) * transaction_snapshot_price_summaries.processing_fee_amount,2) * (100/103.3)),2)
    END AS ProcessingFeeVat,
    CASE
      WHEN transaction_snapshot_price_summaries.shipment_fee IS NULL THEN 0
      ELSE ROUND(ROUND((1 / 100) * transaction_snapshot_price_summaries.shipment_fee,2) * (100/107),2)
    END AS ShippingFee,
    CASE
      WHEN transaction_snapshot_price_summaries.shipment_fee IS NULL THEN 0
      ELSE ROUND(ROUND((1 / 100) * transaction_snapshot_price_summaries.shipment_fee,2) - ROUND((1 / 100) * transaction_snapshot_price_summaries.shipment_fee,2) * (100/107),2)
    END AS ShippingFeeVat,
    --ROUND((1 / 100) * transaction_snapshot_price_summaries.net_premium_amount,2) AS TotalAmount, 
    CASE 
      WHEN takeaway_compulsary IS NOT NULL THEN ROUND(((1 / 100) * transaction_snapshot_price_summaries.net_premium_amount - takeaway_compulsary.add_ons),2)
      ELSE ROUND((1 / 100) * transaction_snapshot_price_summaries.net_premium_amount,2)
    END AS TotalAmount,
    COALESCE(ROUND((1 / 100) * transaction_snapshot_price_summaries.discount_amount,2),0) AS Discount,
    charges.status AS TransactionStatus,
    order_items.submission_status AS SubmissionStatus,
    order_items.approval_status AS ApprovalStatus,
    transactions.status AS PaymentStatus,
    CASE WHEN charge_rank <> 1 THEN 0
      WHEN transaction_snapshot_installment_details.period = 1 THEN ROUND(ROUND((1 / 100) * transaction_snapshot_installment_details.payment_amount,2) - ROUND((1 / 100) * transaction_snapshot_installment_details.add_ons,2),2)
      ELSE ROUND((1 / 100) * transaction_snapshot_installment_details.payment_amount,2)
    END AS ExpectedReceived,
 CASE WHEN charge_rank = 1 THEN ROUND(ROUND((1 / 100) * charges.amount,2)- ROUND((1 / 100) * transaction_snapshot_installment_details.add_ons,2),2)
 ELSE ROUND((1 / 100) * COALESCE(charges.amount,transaction_snapshot_installment_details.payment_amount),2) END AS ActualReceived,
    CASE WHEN charge_rank <> 1 THEN 0
      WHEN transaction_snapshot_price_summaries.interest_amount = 0 OR transaction_snapshots.number_of_installment - 1 = 0 THEN 0
      WHEN transaction_snapshot_installment_details.period = 1 THEN 0
      ELSE ROUND((ROUND((1 / 100) * transaction_snapshot_price_summaries.interest_amount,2) - ((ROUND((1 / 100) * transaction_snapshot_price_summaries.interest_amount,2) * 3.3) / 103.3)) / (transaction_snapshots.number_of_installment - 1),2)
    END AS InterestThisPeriod,  
    CASE 
      WHEN (transaction_snapshots.number_of_installment - 1) = 0 THEN 0
      WHEN transaction_snapshot_installment_details.period = 1 AND charge_rank = 1 THEN ROUND((1 / 100) * charges.amount- ROUND((1 / 100) * transaction_snapshot_installment_details.add_ons,2),2)
      WHEN transaction_snapshot_installment_details.period = 1 AND charge_rank <> 1 THEN ROUND((1 / 100) * charges.amount,2)
      ELSE ROUND((ROUND((1/100)*transaction_snapshot_installment_details.payment_amount,2)) - ((ROUND((1/100)*transaction_snapshot_price_summaries.interest_amount,2) - ((ROUND((1/100)*transaction_snapshot_price_summaries.interest_amount,2)*3.3)/103.3))/(transaction_snapshots.number_of_installment-1)),2)
    END AS PrincipleThisPeriod,
    CASE WHEN charge_rank <> 1 THEN 0 ELSE ROUND((1 / 100) * transaction_snapshot_installment_details.interest,2) END AS InterestEIRThisPeriod,
    CASE WHEN (transaction_snapshots.number_of_installment - 1) = 0 THEN 0
      WHEN transaction_snapshot_installment_details.period = 1 AND charge_rank = 1 THEN ROUND((1 / 100) * charges.amount- ROUND((1 / 100) * transaction_snapshot_installment_details.add_ons,2),2)
      WHEN transaction_snapshot_installment_details.period = 1 AND charge_rank <> 1 THEN ROUND((1 / 100) * charges.amount,2)
      ELSE ROUND((1 / 100) * transaction_snapshot_installment_details.principal,2) END AS PrincipleEIRThisPeriod,  
    charges.update_time AS PaymentDate,
    transaction_snapshot_installment_details.period AS Period,
    transaction_snapshots.number_of_installment AS TotalPeriods, 
    CASE WHEN charge_rank <> 1 THEN 0 ELSE ROUND((1 / 100) * transaction_snapshot_installment_details.principal_balance,2) END AS PendingPayment, -- Need to check
    CASE WHEN transaction_snapshot_installment_details.period = 1 AND change.human_id IS NOT NULL AND charges.payment_method <> 'DIRECT_PAYMENT' THEN "RCL-Credit Shell" 
      WHEN change.human_id IS NOT NULL AND charges.payment_method = 'DIRECT_PAYMENT' THEN 'DIRECT_PAYMENT'
      ELSE charges.payment_method END AS PaymentMethod,
    CASE WHEN transaction_snapshot_installment_details.period = 1 AND change.human_id IS NOT NULL AND charges.payment_method <> 'DIRECT_PAYMENT' THEN "RCL-Credit Shell" 
      WHEN change.human_id IS NOT NULL AND charges.payment_method = 'DIRECT_PAYMENT' THEN 'RCL-DIRECT PAYMENT'
      ELSE charges.service_provider END AS PaymentChannel,
    follow_ups.due_date AS ExpectedDate,
    change.old_human_id AS RefOrder,
    0 AS RefundAmountBeforeFee,
    0 AS RefundAmountAfterFee,
    --ROUND(refunds.amount * (100/107),2) AS RefundAmountBeforeFee,
    --refunds.amount AS RefundAmountAfterFee,
    CASE
      WHEN JSON_VALUE(orders.data, '$.policyHolder.policyAddress.isBillingAddress') = 'true' 
        THEN CONCAT(
          COALESCE(JSON_VALUE(orders.data, '$.policyHolder.policyAddress.fullName'),JSON_VALUE(orders.data, '$.policyHolder.policyAddress.companyName')), ', ',
          JSON_VALUE(orders.data, '$.policyHolder.policyAddress.address'), ', ',
          JSON_VALUE(orders.data, '$.policyHolder.policyAddress.subDistrict'), ', ',
          JSON_VALUE(orders.data, '$.policyHolder.policyAddress.district'), ', ',
          JSON_VALUE(orders.data, '$.policyHolder.policyAddress.province'), ', ',  
          JSON_VALUE(orders.data, '$.policyHolder.policyAddress.postCode')
        )
        ELSE CONCAT(
          JSON_VALUE(orders.data, '$.policyHolder.billingAddress.fullName'), ', ',
          JSON_VALUE(orders.data, '$.policyHolder.billingAddress.address'), ', ',
          JSON_VALUE(orders.data, '$.policyHolder.billingAddress.subDistrict'), ', ',
          JSON_VALUE(orders.data, '$.policyHolder.billingAddress.district'), ', ',
          JSON_VALUE(orders.data, '$.policyHolder.billingAddress.province'), ', ',
          JSON_VALUE(orders.data, '$.policyHolder.billingAddress.postCode')
      ) 
    END AS BillingAddress,
    CURRENT_DATE() AS BatchRunDate

  FROM orders
  LEFT JOIN leads
    ON CONCAT('leads/',leads.id) = orders.lead
  LEFT JOIN transactions
    ON CONCAT('transactions/',transactions.id) = orders.payment
  LEFT JOIN transaction_snapshots
    ON transaction_snapshots.transaction_id = transactions.id
  LEFT JOIN transaction_snapshot_price_summaries
    ON transaction_snapshot_price_summaries.snapshot_id = transaction_snapshots.id
  LEFT JOIN transaction_snapshot_installment_details
    ON transaction_snapshot_installment_details.snapshot_id = transaction_snapshots.id
  LEFT JOIN charges
    ON charges.transaction_id = transactions.id 
    AND charges.installment_number = transaction_snapshot_installment_details.period 
    AND charges.status NOT IN ('FAILED','PENDING')
  LEFT JOIN order_items
    ON order_items.order_id = orders.id
  LEFT JOIN refunds
    ON refunds.transaction_id = transactions.id
  LEFT JOIN follow_ups
    ON follow_ups.transaction_id = transactions.id
    AND follow_ups.installment = transaction_snapshot_installment_details.period
  LEFT JOIN takeaway_compulsary
    ON takeaway_compulsary.transaction_snapshot_id = transaction_snapshots.id
  LEFT JOIN change on change.human_id = orders.human_id
 WHERE 
  (transaction_snapshot_installment_details.id IS NOT NULL OR transactions.installments > 1) 
   AND order_items.motor_item_type != 'MOTOR_TYPE_COMPULSORY'
   AND (follow_ups.transaction_id IS NOT NULL)
   --AND charges.service_provider = 'RABBIT_LENDING' 
),
--------------------------------------------------------------------------------------------------------
--------------------------------------------------------------------------------------------------------

compulsary_installment_details AS (
  SELECT
    'compulsary_installment_details' AS CTE_source, 
    'RCB' AS CompanyDB,
    orders.human_id AS OrderID,
    order_items.human_id AS OrderItem,
CASE WHEN charges.installment_number = 1 THEN CONCAT('2_',charges.third_party_id)
  WHEN charges.third_party_id is null AND charges.status = 'SUCCESSFUL' THEN order_items.human_id
  WHEN charges.third_party_id is null AND charges.status <> 'SUCCESSFUL' THEN ''
  ELSE  charges.third_party_id 
END AS InvoiceNo,
    orders.create_time AS OrderDate,
    CASE 
      WHEN JSON_VALUE(orders.data, '$.policyHolder.isCompany') ='true' THEN 
      JSON_VALUE(orders.data, '$.policyHolder.companyTaxId') 
      ELSE JSON_VALUE(orders.data, '$.idNumber') 
    END AS InsuredID,
    JSON_VALUE(orders.data, '$.policyHolder.title') AS Title,
    COALESCE(JSON_VALUE(orders.data, '$.policyHolder.firstName'),JSON_VALUE(orders.data, '$.policyHolder.policyAddress.companyName')) AS FirstName,
    JSON_VALUE(orders.data, '$.policyHolder.lastName') AS LastName,
    order_items.insurer AS InsurerCode,
    order_items.product AS InsuranceGroup,
    order_items.motor_item_type AS InsuranceType,
    CASE WHEN JSON_VALUE(orders.data, '$.oicCode') in ('TYPE_610','TYPE_620', 'TYPE_630') 
    THEN 'MotorBike'  
    ELSE 'Motor'
    END AS InsuranceProduct,
    'Insurance' ProductType,
    leads.type AS PolicyType,
    'N' AS Endorse,
    order_items.policy_start_date AS PolicyDate,
    order_items.policy_number AS PolicyNo,
    NULL AS EndorsementNo,
    JSON_VALUE(orders.data, '$.chassisNumber') AS ChassisNo,
    JSON_VALUE(orders.data, '$.carLicensePlate') AS LicensePlate,
    order_items.net_premium AS GrossPremium,
    order_items.stamp_duty AS StampDuty,
    order_items.vat_amount AS VAT,
    order_items.gross_premium AS TotalPremium,
    0 AS WHT,
    0 AS TotalEIR,
    0 AS TotalSBT,
    0 AS ProcessingFee,
    0 AS ProcessingFeeVat,
    0 AS ShippingFee,
    0 AS ShippingFeeVat,
    -- ROUND(ROUND((1 / 100) * transaction_snapshot_installment_details.payment_amount,2) - ROUND((1 / 100) * transaction_snapshot_installment_details.principal,2) - ROUND((1 / 100) * transaction_snapshot_installment_details.processing_fee,2),2) AS TotalAmount,
    order_items.gross_premium  as TotalAmount,
    0 AS Discount,
    charges.status AS TransactionStatus,
    order_items.submission_status AS SubmissionStatus,
    order_items.approval_status AS ApprovalStatus,
    transactions.status AS PaymentStatus,
    -- ROUND((1 / 100) * transaction_snapshot_installment_details.add_ons,2) AS ActualReceived,
    order_items.gross_premium  as ExpectedReceived,
    order_items.gross_premium  as ActualReceived,    
    0 AS InterestThisPeriod,
    0 AS PrincipleThisPeriod,
    0 AS InterestEIRThisPeriod,
    0 AS PrincipleEIRThisPeriod,
    charges.update_time AS PaymentDate,
    transaction_snapshot_installment_details.period AS Period,
    transaction_snapshot_installment_details.period AS TotalPeriods,
    -- CASE
    --   WHEN ROUND((1 / 100) * transaction_snapshot_installment_details.add_ons,2) IS NOT NULL THEN 0
    --   ELSE ROUND((1 / 100) * transaction_snapshot_installment_details.payment_amount,2) - ROUND((1 / 100) * transaction_snapshot_installment_details.principal,2) - ROUND((1 / 100) * transaction_snapshot_installment_details.processing_fee,2)
    -- END AS PendingPayment,
    0 as PendingPayment,
    CASE WHEN change.human_id IS NOT NULL AND charges.payment_method <> 'DIRECT_PAYMENT' THEN "RCL-Credit Shell" 
      WHEN change.human_id IS NOT NULL AND charges.payment_method = 'DIRECT_PAYMENT' THEN 'DIRECT_PAYMENT'
      ELSE charges.payment_method END AS PaymentMethod,
    CASE WHEN change.human_id IS NOT NULL AND charges.payment_method <> 'DIRECT_PAYMENT' THEN "RCL-Credit Shell" 
      WHEN change.human_id IS NOT NULL AND charges.payment_method = 'DIRECT_PAYMENT' THEN 'RCL-DIRECT PAYMENT'
      ELSE charges.service_provider END AS PaymentChannel,
    follow_ups.due_date AS ExpectedDate,
    change.old_human_id AS RefOrder,
    NULL AS RefundAmountBeforeFee,
    NULL AS RefundAmountAfterFee,
    CASE
      WHEN JSON_VALUE(orders.data, '$.policyHolder.policyAddress.isBillingAddress') = 'true' 
        THEN CONCAT(
          COALESCE(JSON_VALUE(orders.data, '$.policyHolder.policyAddress.fullName'),JSON_VALUE(orders.data, '$.policyHolder.policyAddress.companyName')), ', ',
          JSON_VALUE(orders.data, '$.policyHolder.policyAddress.address'), ', ',
          JSON_VALUE(orders.data, '$.policyHolder.policyAddress.subDistrict'), ', ',
          JSON_VALUE(orders.data, '$.policyHolder.policyAddress.district'), ', ',
          JSON_VALUE(orders.data, '$.policyHolder.policyAddress.province'), ', ',  
          JSON_VALUE(orders.data, '$.policyHolder.policyAddress.postCode')
        )
        ELSE CONCAT(
          JSON_VALUE(orders.data, '$.policyHolder.billingAddress.fullName'), ', ',
          JSON_VALUE(orders.data, '$.policyHolder.billingAddress.address'), ', ',
          JSON_VALUE(orders.data, '$.policyHolder.billingAddress.subDistrict'), ', ',
          JSON_VALUE(orders.data, '$.policyHolder.billingAddress.district'), ', ',
          JSON_VALUE(orders.data, '$.policyHolder.billingAddress.province'), ', ',
          JSON_VALUE(orders.data, '$.policyHolder.billingAddress.postCode')
      ) 
    END AS BillingAddress,
    CURRENT_DATE() AS BatchRunDate

  FROM orders
  LEFT JOIN order_items
    ON order_items.order_id = orders.id
  LEFT JOIN transactions
    ON CONCAT('transactions/',transactions.id) = orders.payment
  LEFT JOIN transaction_snapshots
    ON transaction_snapshots.transaction_id = transactions.id
  LEFT JOIN transaction_snapshot_price_summaries
    ON transaction_snapshot_price_summaries.snapshot_id = transaction_snapshots.id
  LEFT JOIN transaction_snapshot_installment_details
    ON transaction_snapshot_installment_details.snapshot_id = transaction_snapshots.id
  LEFT JOIN charges
    ON charges.transaction_id = transactions.id 
    AND charges.installment_number = transaction_snapshot_installment_details.period
  LEFT JOIN leads
    ON CONCAT('leads/',leads.id) = orders.lead
  LEFT JOIN follow_ups
    ON follow_ups.transaction_id = transactions.id
    AND follow_ups.installment = transaction_snapshot_installment_details.period
  LEFT JOIN change on change.human_id = orders.human_id
  WHERE 
    order_items.motor_item_type = 'MOTOR_TYPE_COMPULSORY'
    AND charges.status = 'SUCCESSFUL'
    AND charges.service_provider = 'RABBIT_LENDING'
AND transaction_snapshot_installment_details.period = 1
    AND charge_rank = 1 
),
--------------------------------------------------------------------------------------------------------
--------------------------------------------------------------------------------------------------------

combine AS (
  SELECT * FROM rcl_voluntary_installment_details
  UNION ALL
  SELECT * FROM compulsary_installment_details
),
--------------------------------------------------------------------------------------------------------

transformation AS (
  SELECT
    CTE_source,
    CompanyDB,
    OrderID,
    OrderItem,
    CASE WHEN InvoiceNo IS NULL AND TransactionStatus <> 'SUCCESSFUL' THEN '' ELSE InvoiceNo END AS InvoiceNo,
    CAST(FORMAT_DATE('%d%m%Y', OrderDate) AS STRING) AS OrderDate,
    case 
      WHEN InsuredID='' OR InsuredID is NULL THEN '-' 
      ELSE InsuredID 
    END AS InsuredID,
    CASE
      WHEN Title = 'KHUN' THEN 'คุณ'
      WHEN Title = 'MISS' THEN 'นางสาว'
      WHEN Title = 'MR' THEN 'นาย'
      WHEN Title = 'MRS' THEN 'นาง'
      ELSE ''
    END AS Title,
    FirstName,
    LastName,
    TRIM(InsurerCode,'insurer/') AS InsurerCode,
    CASE
      WHEN InsuranceGroup = 'products/car-insurance' THEN 'Motor'
      ELSE InsuranceGroup
    END AS InsuranceGroup,
  InsuranceType AS InsuranceType,
    CASE
      WHEN InsuranceGroup = 'products/car-insurance' THEN 'Motor'
      ELSE InsuranceGroup
    END AS InsuranceProduct,
    'Insurance' AS ProductType,
    CASE
      WHEN PolicyType = 'LEAD_TYPE_RENEWAL' THEN 'R'
      ELSE 'N'
    END AS PolicyType,
    Endorse,
    CAST(FORMAT_DATE('%d%m%Y', PolicyDate) AS STRING) AS PolicyDate,
    PolicyNo,
    CAST(EndorsementNo AS STRING) EndorsementNo,
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
    ROUND ((TotalPremium+TotalEIR+TotalSBT+ProcessingFee+ProcessingFeeVat+ShippingFee+ShippingFeeVat),2) as TotalAmount,
    Discount,
    CASE 
      WHEN TransactionStatus = 'SUCCESSFUL' THEN 'paid'
      WHEN TransactionStatus = 'PENDING' THEN 'pending'
      WHEN TransactionStatus = 'FOLLOWUP_STATUS_CANCELLED' THEN 'pending'
      WHEN TransactionStatus = 'FOLLOWUP_STATUS_OVERDUE' THEN 'pending'
      WHEN TransactionStatus = 'FOLLOWUP_STATUS_PAID' THEN 'paid'
      WHEN TransactionStatus = 'FOLLOWUP_STATUS_PENDING' THEN 'pending'
      ELSE 'Pending'
    END AS TransactionStatus,
    CASE
      WHEN SubmissionStatus = 'ITEM_SUBMISSION_STATUS_READY_TO_SUBMIT' THEN 'PENDING'
      WHEN SubmissionStatus = 'ITEM_SUBMISSION_STATUS_PRESUBMITTED' THEN 'PRE-SUBMITTED'
      WHEN SubmissionStatus = 'ITEM_SUBMISSION_STATUS_SUBMITTED' THEN 'SUBMITTED'
      WHEN SubmissionStatus = 'ITEM_SUBMISSION_STATUS_PENDING' THEN 'PENDING'
      ELSE SubmissionStatus
    END AS SubmissionStatus,
    CASE
      WHEN ApprovalStatus = 'ITEM_APPROVAL_STATUS_APPROVED' THEN 'APPROVED'
      WHEN ApprovalStatus = 'ITEM_APPROVAL_STATUS_REJECTED' THEN 'REJECTED'
      WHEN ApprovalStatus = 'ITEM_APPROVAL_STATUS_PENDING' THEN 'PENDING'
      WHEN ApprovalStatus = 'ITEM_APPROVAL_STATUS_POLICY_UPLOADED' THEN 'POLICY UPLOADED'
    END AS ApprovalStatus,
    CASE
      WHEN PaymentStatus = 'SUCCESSFUL' THEN 'fully paid'
      WHEN PaymentStatus = 'PENDING' THEN 'Not fully paid'
      ELSE PaymentStatus
    END AS PaymentStatus,
    ExpectedReceived,
    ActualReceived,
    -- ROUND((((TotalPremium+WHT+TotalEIR+TotalSBT+ProcessingFee+ProcessingFeeVat+ShippingFee+ShippingFeeVat)-Discount)/TotalPeriods),2) as ActualReceived, -- 
  InterestThisPeriod,
  PrincipleThisPeriod,
  InterestEIRThisPeriod,
  PrincipleEIRThisPeriod,
CASE
  WHEN DATE(PaymentDate) < DATE_TRUNC(CURRENT_DATE(), MONTH)
       AND CURRENT_DATE() > DATE_ADD(
             LAST_DAY(DATE_SUB(CURRENT_DATE(), INTERVAL 1 MONTH)),
             INTERVAL 3 DAY
           )
  THEN FORMAT_DATE('%d%m%Y', DATE_TRUNC(CURRENT_DATE(), MONTH))

  ELSE FORMAT_DATE('%d%m%Y', DATE(PaymentDate))
END AS PaymentDate,
  Period,
  TotalPeriods,
-- PendingPayment,-- ผิด 
  ROUND(((((TotalPremium+TotalEIR+TotalSBT+ProcessingFee+ProcessingFeeVat+ShippingFee+ShippingFeeVat)-Discount)-Discount)/TotalPeriods)*(TotalPeriods-Period),2) as PendingPayment,
/*
case 
  WHEN InsuranceType ='MOTOR_TYPE_COMPULSORY' then 'RCL-CMI-channel'  
  WHEN PaymentMethod='CASH' then 'TRF Transfer'  
  WHEN PaymentMethod='QR_CODE' then 'OME Omise QR Prompt Pay' else PaymentMethod end as PaymentMethod,
case 
  WHEN InsuranceType ='MOTOR_TYPE_COMPULSORY' then 'RCL-CMI-channel' 
  when PaymentMethod='CASH' then 'RCL-Transfer-อื่นๆ' 
  when PaymentMethod='QR_CODE' AND PaymentChannel='RABBIT_LENDING' then 'RCL-Omise QR Prompt Pay-BAY' else PaymentChannel end as PaymentChannel, 
*/
  CASE WHEN PaymentMethod ='DIRECT_PAYMENT'and PaymentChannel ='SERVICE_PROVIDER_UNSPECIFIED' THEN 'DPM จ่ายตรงกับบริษัทประกัน'
    WHEN InsuranceType = 'MOTOR_TYPE_COMPULSORY' THEN 'RCL-CMI-channel'
    WHEN PaymentMethod = 'CASH' THEN 'TRF Transfer'
    WHEN PaymentMethod = 'QR_CODE' THEN 'OME Omise QR Prompt Pay'
    WHEN PaymentMethod = 'BANK_TRANSFER' THEN 'TRF Transfer'
    ELSE PaymentMethod 
  END AS PaymentMethod,
  CASE WHEN PaymentMethod ='DIRECT_PAYMENT'and PaymentChannel ='SERVICE_PROVIDER_UNSPECIFIED' THEN 'RCL-DIRECT PAYMENT'
    WHEN InsuranceType = 'MOTOR_TYPE_COMPULSORY' THEN 'RCL-CMI-channel'
    WHEN PaymentMethod = 'CASH' THEN 'RCL-Transfer-อื่นๆ'
    WHEN PaymentMethod = 'QR_CODE' AND PaymentChannel = 'RABBIT_LENDING' THEN 'RCL-Omise QR Prompt Pay-BAY'
    WHEN PaymentMethod = 'DIRECT_DEBIT' AND PaymentChannel = 'RABBIT_LENDING' THEN 'RCL-Direct Debit'
    WHEN PaymentMethod = 'QR_CODE' AND PaymentChannel = 'RCB' THEN 'RCL-Omise QR Prompt Pay-BAY'
     WHEN PaymentMethod = 'BANK_TRANSFER' THEN 'RCL-Transfer-อื่นๆ'
    ELSE PaymentChannel 
  END AS PaymentChannel,

CAST(FORMAT_DATE('%d%m%Y', ExpectedDate) AS STRING) AS ExpectedDate,
    RefOrder,
    RefundAmountBeforeFee,
    RefundAmountAfterFee,
    BillingAddress,
    CAST(FORMAT_DATE('%d%m%Y', BatchRunDate) AS STRING) AS BatchRunDate,
  FROM combine

),
--------------------------------------------------------------------------------------------------------

arrange AS (
  SELECT
  OrderItem ,
  ROUND(SUM(InterestEIRThisPeriod),2) AS interest_amount
  FROM transformation
  GROUP BY OrderItem
),
old_final AS (
SELECT 
  transformation.* EXCEPT(CTE_source) 
FROM transformation 
LEFT JOIN check_order_items 
  ON transformation.OrderID = check_order_items.OrderID

ORDER BY OrderID,	TotalPeriods ,Period
),
finish AS (
  SELECT
  transformation.CompanyDB, 
  transformation.OrderID ,
  transformation.OrderItem ,
  transformation.InvoiceNo ,
  transformation.OrderDate,
  transformation.InsuredID,
  transformation.Title,
  transformation.FirstName,
  transformation.LastName,
  transformation.InsurerCode,
  transformation.InsuranceGroup,
  transformation.InsuranceType,
  transformation.InsuranceProduct,
  transformation.ProductType,
  transformation.PolicyType,
  transformation.Endorse,
  transformation.PolicyDate,
  transformation.PolicyNo ,
  transformation.EndorsementNo ,
  transformation.ChassisNo,
  transformation.LicensePlate,
  transformation.GrossPremium,
  transformation.StampDuty,
  transformation.VAT,
  transformation.TotalPremium,
  transformation.WHT,
  transformation.TotalEIR,
  transformation.TotalSBT,
  transformation.ProcessingFee,
  transformation.ProcessingFeeVat,
  transformation.ShippingFee,
  transformation.ShippingFeeVat,
  transformation.TotalAmount,
  transformation.Discount,
  transformation.TransactionStatus,
  transformation.SubmissionStatus,
  transformation.ApprovalStatus,
  transformation.PaymentStatus,
  transformation.ExpectedReceived,
  transformation.ActualReceived,
  transformation.InterestThisPeriod,
  transformation.PrincipleThisPeriod,
  CASE
    WHEN (arrange.interest_amount != transformation.TotalEIR AND transformation.Period != 1) THEN ABS(ROUND((transformation.InterestEIRThisPeriod)-(transformation.TotalSBT/NULLIF((transformation.TotalPeriods-1),0)),2))
    ELSE transformation.InterestEIRThisPeriod
  END AS InterestEIRThisPeriod ,
  transformation.PrincipleEIRThisPeriod,
  transformation.PaymentDate,
  transformation.Period,
  transformation.TotalPeriods,
  transformation.PendingPayment,
  transformation.PaymentMethod,
  transformation.PaymentChannel,
  transformation.ExpectedDate,
  transformation.RefOrder,
  transformation.RefundAmountBeforeFee,
  transformation.RefundAmountAfterFee,
  transformation.BillingAddress,
  transformation.BatchRunDate,
  FROM transformation
  LEFT JOIN arrange
  ON transformation.OrderItem = arrange.OrderItem
  ORDER BY OrderDate , OrderItem , Period
),
arrange_again AS (
  SELECT
  OrderItem ,
  ROUND(SUM(InterestEIRThisPeriod),2) AS interest_amount
  FROM finish
  GROUP BY OrderItem
),
finish_2 AS (
  SELECT
  finish.CompanyDB, 
  finish.OrderID ,
  finish.OrderItem ,
  finish.InvoiceNo ,
  finish.OrderDate,
  finish.InsuredID,
  finish.Title,
  finish.FirstName,
  finish.LastName,
  finish.InsurerCode,
  finish.InsuranceGroup,
  finish.InsuranceType,
  finish.InsuranceProduct,
  finish.ProductType,
  finish.PolicyType,
  finish.Endorse,
  finish.PolicyDate,
  finish.PolicyNo ,
  finish.EndorsementNo ,
  finish.ChassisNo,
  finish.LicensePlate,
  finish.GrossPremium,
  finish.StampDuty,
  finish.VAT,
  finish.TotalPremium,
  finish.WHT,
  finish.TotalEIR,
  finish.TotalSBT,
  finish.ProcessingFee,
  finish.ProcessingFeeVat,
  finish.ShippingFee,
  finish.ShippingFeeVat,
  finish.TotalAmount,
  finish.Discount,
  finish.TransactionStatus,
  finish.SubmissionStatus,
  finish.ApprovalStatus,
  finish.PaymentStatus,
  finish.ExpectedReceived,
  finish.ActualReceived,
  finish.InterestThisPeriod,
  finish.PrincipleThisPeriod,
  CASE
    WHEN arrange_again.interest_amount != finish.TotalEIR THEN
    CASE
      WHEN finish.Period = finish.TotalPeriods THEN ROUND((finish.InterestEIRThisPeriod)-(arrange_again.interest_amount - finish.TotalEIR),2)
      ELSE finish.InterestEIRThisPeriod
    END
    ELSE finish.InterestEIRThisPeriod
  END AS InterestEIRThisPeriod ,
  finish.PrincipleEIRThisPeriod,
  finish.PaymentDate,
  finish.Period,
  finish.TotalPeriods,
  finish.PendingPayment,
  finish.PaymentMethod,
  finish.PaymentChannel,
  finish.ExpectedDate,
  finish.RefOrder,
  finish.RefundAmountBeforeFee,
  finish.RefundAmountAfterFee,
  finish.BillingAddress,
  finish.BatchRunDate,
  FROM finish
  LEFT JOIN arrange_again
  ON finish.OrderItem = arrange_again.OrderItem
  ORDER BY OrderDate , OrderItem , Period
)


SELECT * FROM finish_2
ORDER BY OrderItem, Period


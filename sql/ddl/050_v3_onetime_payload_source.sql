-- BASELINE CAPTURE 2026-07-24 -- pulled verbatim from live BigQuery view definition
-- 050_v3_onetime_payload_source.sql
-- Source-only / Class A. V3-owned 56-column ONETIME transformer derived from the captured live
-- fully-paid definition. Differences are intentionally narrow: latest snapshot rather than
-- number_of_installment=1, and no policy-year filter (E1/RULE-09 lives in expected_state).
-- Change-order exclusion remains intact; those rows belong to the separate credit-shell flow.
CREATE OR REPLACE VIEW `pacific-plating-282708.sap_integration_v3.vw_onetime_payload_source` AS
-- The body below started from the captured production baseline; the V3 deviations are listed above.

--sap_dashboard_carepay_fully_paid--

 -- 11/04/2024
 -- 09/12/2024 Haruethai Update Column 'InsuranceGroup', 'InsuranceType', 'InsuranceProduct' for order NONMOTOR on CareOs
 -- 16/03/2025 Piyarat excludes credit shell(new order from cancel change order) and correct ref.orders from CareOS
 -- 4/July/2025 Piyarat fixed the price after discount in snapshot price summary
 -- 19/July/2025 Piyarat changed ExpectedReceived for Multipu payment per period
 -- 29/Jun/2026 Piyarat changes CMI identifier to motor_item_type = 'MOTOR_TYPE_COMPULSORY'
-- sap_dashboard_carepay_fully_paid -- TUNED VERSION
-- Tuned: 2026-07-11
-- Changes:
--  1. Removed redundant 2nd join to `charges` in onetime_master_go
--     (charge_rank now carried forward from onetime_master's first join)
--  2. Replaced full SAP_LIVE_FULL join with pre-aggregated lookup
--     (only U_OrderID + MAX(BatchRunDate), non-compulsory rows only)
--  3. V3 removes the legacy policy_start_date cutoff because expected_state owns E1/RULE-09.
--  4. V3 selects the latest transaction snapshot without using installment count as a router.
-- ============================================================

WITH

charges AS (
  SELECT * ,
    ROW_NUMBER() OVER (PARTITION BY transaction_id ORDER BY create_time) AS charge_rank
  FROM `pacific-plating-282708.careos.carepay_charges`
  WHERE status = 'SUCCESSFUL'
  AND service_provider <> 'RABBIT_LENDING'
),

follow_ups AS (
  SELECT * FROM `pacific-plating-282708.careos.carepay_follow_ups`
),

transaction_snapshot_installment_details AS (
  SELECT * FROM `pacific-plating-282708.careos.carepay_transaction_snapshot_installment_details`
),

transaction_snapshot_price_summaries AS (
  SELECT * FROM `pacific-plating-282708.careos.carepay_transaction_snapshot_price_summaries`
),

transaction_snapshots AS (
  SELECT * FROM `pacific-plating-282708.careos.carepay_transaction_snapshots`
  QUALIFY ROW_NUMBER() OVER (PARTITION BY transaction_id ORDER BY update_time DESC, id DESC) = 1
 
),

transactions AS (
  SELECT * FROM `pacific-plating-282708.careos.carepay_transactions`
),

orders AS (
  SELECT * FROM `pacific-plating-282708.careos.careos_orders`
),

-- FIX 3: date filter pushed here (early), instead of only in the final WHERE
order_items AS (
  SELECT * FROM `pacific-plating-282708.careos.careos_order_items`
),

leads AS (
  SELECT * FROM `pacific-plating-282708.careos.careos_leads`
),

change AS (
  SELECT * FROM `pacific-plating-282708.careos.cancelled_change_orders`
),

compu_detail AS (
  SELECT
    orders.human_id AS order_id,
    CASE
      WHEN order_items.gross_premium IS NULL THEN 0
      ELSE order_items.gross_premium
    END AS gross_premium
  FROM
    `pacific-plating-282708.careos.careos_order_items` order_items
  LEFT JOIN
    `pacific-plating-282708.careos.careos_orders` orders
  ON
    order_items.order_id = orders.id
  WHERE
    order_items.motor_item_type = 'MOTOR_TYPE_COMPULSORY'
    AND orders.product = 'products/car-insurance'
),

-- FIX 2: pre-aggregate SAP_LIVE_FULL down to just what's needed
-- (U_OrderID + latest BatchRunDate, non-compulsory only) BEFORE joining
-- instead of joining the entire wide view per row
sap_batchrun AS (
  SELECT
    U_OrderID,
    MAX(BatchRunDate) AS BatchRunDate
  FROM `pacific-plating-282708.sap_integration_v2.SAP_LIVE_FULL`
  WHERE U_InsuranceType <> 'MOTOR_TYPE_COMPULSORY'
  GROUP BY U_OrderID
),

onetime_master AS (
  SELECT
    DISTINCT CAST(charges.amount AS FLOAT64) AS charges_amount,
    order_items.motor_item_type,
    order_items.packagetype,
    charges.service_provider,
    charges.charge_rank,                                    -- FIX 1: carried forward
    orders.create_time AS OrderDate,
    charges.status,
    orders.human_id OrderID,
    order_items.human_id AS OrderItem,
    order_items.price price,
    order_items.net_premium AS GrossPremium,
    order_items.stamp_duty AS StampDuty,
    order_items.vat_amount AS VAT,
    order_items.gross_premium TotalPremium,
    COALESCE(ROUND((1 / 100) * transaction_snapshot_price_summaries.wht_amount,2),0) AS WHT_master,
    ROUND((1 / 100) * transaction_snapshot_price_summaries.interest_amount,2) AS TotalEIR_check,
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
      ELSE ROUND (ROUND((1 / 100) * transaction_snapshot_price_summaries.processing_fee_amount,2) * (100/107),2)
    END AS ProcessingFee_master,
    CASE
      WHEN transaction_snapshot_price_summaries.processing_fee_amount IS NULL THEN 0
      ELSE ROUND(ROUND((1 / 100) * transaction_snapshot_price_summaries.processing_fee_amount,2) - (ROUND((1 / 100) * transaction_snapshot_price_summaries.processing_fee_amount,2) * (100/107)),2)
    END AS ProcessingFeeVat_master,
    CASE
      WHEN transaction_snapshot_price_summaries.shipment_fee IS NULL THEN 0
      ELSE ROUND(ROUND((1 / 100) * transaction_snapshot_price_summaries.shipment_fee,2) * (100/107),2)
    END AS ShippingFee_master,
    CASE
      WHEN transaction_snapshot_price_summaries.shipment_fee IS NULL THEN 0
      ELSE ROUND(ROUND((1 / 100) * transaction_snapshot_price_summaries.shipment_fee,2) - ROUND((1 / 100) * transaction_snapshot_price_summaries.shipment_fee,2) * (100/107),2)
    END AS ShippingFeeVat_master,
    COALESCE(ROUND((1 / 100) * transaction_snapshot_price_summaries.discount_amount,2),0) AS Discount_master,
    charges.status AS TransactionStatus,
    order_items.submission_status AS SubmissionStatus,
    order_items.approval_status AS ApprovalStatus,
    transactions.status AS PaymentStatus,
    ROUND(((1 / 100) * charges.amount),2) AS ActualReceived_master,  -- จำนวนเงินที่ลูกค้าจ่ายมาจริงๆ ห้ามเปลี่ยน
    0 AS PrincipleThisPeriod,
    transaction_snapshot_price_summaries.interest_amount AS InterestEIRThisPeriod,
    0 AS PrincipleEIRThisPeriod,
    CASE
      -- กรณีมี BatchRunDate
      WHEN sap_batchrun.BatchRunDate IS NOT NULL THEN
        CASE
          WHEN DATE(PARSE_TIMESTAMP('%d%m%Y', sap_batchrun.BatchRunDate))
               < DATE_TRUNC(CURRENT_DATE(), MONTH)
               AND CURRENT_DATE() > DATE_ADD(
                     LAST_DAY(DATE_SUB(CURRENT_DATE(), INTERVAL 1 MONTH)),
                     INTERVAL 3 DAY
                   )
          THEN TIMESTAMP(DATE_TRUNC(CURRENT_DATE(), MONTH))
          ELSE PARSE_TIMESTAMP('%d%m%Y', sap_batchrun.BatchRunDate)
        END
      -- กรณีไม่มี BatchRunDate
      WHEN DATE(COALESCE(charges.payment_date, charges.update_time))
           < DATE_TRUNC(CURRENT_DATE(), MONTH)
           AND CURRENT_DATE() > DATE_ADD(
                 LAST_DAY(DATE_SUB(CURRENT_DATE(), INTERVAL 1 MONTH)),
                 INTERVAL 3 DAY
               )
      THEN TIMESTAMP(DATE_TRUNC(CURRENT_DATE(), MONTH))
      ELSE COALESCE(charges.payment_date, charges.update_time)
    END AS PaymentDate,
    charges.installment_number AS Period,
    1 AS TotalPeriods,
    0 AS PendingPayment,
    charges.create_time AS ExpectedDate,
    charges.id AS charges_id,
    CASE
      WHEN charges.third_party_id IS NULL AND charges.status = 'SUCCESSFUL' THEN CONCAT(charges.charge_rank,"_",order_items.human_id)
      WHEN charges.third_party_id IS NULL AND charges.status <> 'SUCCESSFUL' THEN ''
      ELSE charges.third_party_id
    END AS InvoiceNo,
    order_items.insurer AS InsurerCode,
    order_items.product AS InsuranceGroup,
    order_items.motor_item_type AS InsuranceType,
    CASE
      WHEN JSON_VALUE(orders.data, '$.oicCode') IN ('TYPE_610', 'TYPE_620', 'TYPE_630') THEN 'MotorBike'
      WHEN JSON_VALUE(orders.data, '$.oicCode') IS NOT NULL THEN 'Motor'
      ELSE order_items.product
    END AS InsuranceProduct,
    'Insurance' AS ProductType,
    leads.type AS PolicyType,
    'N' AS Endorse,
    order_items.policy_start_date AS PolicyDate,
    order_items.policy_number AS PolicyNo,
    NULL AS EndorsementNo,
    JSON_VALUE(orders.data, '$.chassisNumber') AS ChassisNo,
    JSON_VALUE(orders.data, '$.carLicensePlate') AS LicensePlate,
    charges.payment_method AS PaymentMethod,
    charges.service_provider AS PaymentChannel,
    CASE
      WHEN JSON_VALUE(orders.data, '$.policyHolder.isCompany') ='true' AND JSON_VALUE(orders.data, '$.policyHolder.companyTaxId') IS NULL THEN '-'
      WHEN JSON_VALUE(orders.data, '$.policyHolder.isCompany') ='true' AND JSON_VALUE(orders.data, '$.policyHolder.companyTaxId') IS NOT NULL THEN JSON_VALUE(orders.data, '$.policyHolder.companyTaxId')
      WHEN JSON_VALUE(orders.data, '$.idNumber') IS NULL OR JSON_VALUE(orders.data, '$.idNumber') IN ('', ' ') THEN '-'
      ELSE JSON_VALUE(orders.data, '$.idNumber')
    END AS InsuredID,
    JSON_VALUE(orders.data, '$.policyHolder.title') AS Title,
    COALESCE(JSON_VALUE(orders.data, '$.policyHolder.firstName'),JSON_VALUE(orders.data, '$.policyHolder.policyAddress.companyName')) AS FirstName,
    JSON_VALUE(orders.data, '$.policyHolder.lastName') AS LastName,
    0 AS RefundAmountBeforeFee,
    0 AS RefundAmountAfterFee,
    CASE
      WHEN JSON_VALUE(orders.data, '$.policyHolder.policyAddress.isBillingAddress') = 'true' THEN CONCAT( COALESCE(JSON_VALUE(orders.data, '$.policyHolder.policyAddress.fullName'),JSON_VALUE(orders.data, '$.policyHolder.policyAddress.companyName')), ', ', JSON_VALUE(orders.data, '$.policyHolder.policyAddress.address'), ', ', JSON_VALUE(orders.data, '$.policyHolder.policyAddress.subDistrict'), ', ', JSON_VALUE(orders.data, '$.policyHolder.policyAddress.district'), ', ', JSON_VALUE(orders.data, '$.policyHolder.policyAddress.province'), ', ', JSON_VALUE(orders.data, '$.policyHolder.policyAddress.postCode') )
      ELSE CONCAT( JSON_VALUE(orders.data, '$.policyHolder.billingAddress.fullName'), ', ', JSON_VALUE(orders.data, '$.policyHolder.billingAddress.address'), ', ', JSON_VALUE(orders.data, '$.policyHolder.billingAddress.subDistrict'), ', ', JSON_VALUE(orders.data, '$.policyHolder.billingAddress.district'), ', ', JSON_VALUE(orders.data, '$.policyHolder.billingAddress.province'), ', ', JSON_VALUE(orders.data, '$.policyHolder.billingAddress.postCode') )
    END AS BillingAddress,
    CURRENT_DATE() AS BatchRunDate,
    'RCB' AS CompanyDB,
    ch.old_human_id AS RefOrder,
    ROW_NUMBER() OVER (PARTITION BY order_items.human_id ORDER BY order_items.create_time,charges.create_time) AS cmi_rank
  FROM
    orders
  LEFT JOIN leads ON CONCAT('leads/',leads.id) = orders.lead
  LEFT JOIN transactions ON CONCAT('transactions/',transactions.id) = orders.payment
  LEFT JOIN follow_ups ON follow_ups.transaction_id = transactions.id
  LEFT JOIN charges ON charges.transaction_id = transactions.id
  LEFT JOIN order_items ON order_items.order_id = orders.id
  LEFT JOIN transaction_snapshots ON transaction_snapshots.transaction_id = transactions.id
  LEFT JOIN transaction_snapshot_price_summaries ON transaction_snapshot_price_summaries.snapshot_id = transaction_snapshots.id
  LEFT JOIN change ch ON ch.current_human_id = orders.human_id
  LEFT JOIN sap_batchrun ON sap_batchrun.U_OrderID = ch.old_human_id           -- FIX 2: lightweight join
  WHERE
    charges.status = 'SUCCESSFUL'
    AND charges.service_provider <> 'RABBIT_LENDING'
    AND (follow_ups.installment = 1 OR follow_ups.installment IS NULL)
    AND transactions.payment_option <> 'RABBIT_CARE_INSTALLMENT'
    AND orders.product = 'products/car-insurance'
),

onetime_master_go AS (
  SELECT
    * EXCEPT(charge_rank),
    charge_rank,                                              -- kept, no re-join needed
    CASE WHEN motor_item_type = 'MOTOR_TYPE_COMPULSORY' THEN 0 ELSE WHT_master END AS WHT,
    CASE WHEN motor_item_type = 'MOTOR_TYPE_COMPULSORY' THEN 0 ELSE ProcessingFee_master END AS ProcessingFee,
    CASE WHEN motor_item_type = 'MOTOR_TYPE_COMPULSORY' THEN 0 ELSE ProcessingFeeVat_master END AS ProcessingFeeVat,
    CASE WHEN motor_item_type = 'MOTOR_TYPE_COMPULSORY' THEN 0 ELSE ShippingFee_master END AS ShippingFee,
    CASE WHEN motor_item_type = 'MOTOR_TYPE_COMPULSORY' THEN 0 ELSE ShippingFeeVat_master END AS ShippingFeeVat,
    CASE
      WHEN motor_item_type = 'MOTOR_TYPE_COMPULSORY' THEN TotalPremium
      ELSE ROUND((TotalPremium)+TotalEIR+TotalSBT+ProcessingFee_master+ProcessingFeeVat_master+ShippingFee_master+ShippingFeeVat_master,2)
    END AS TotalAmount,
    CASE WHEN motor_item_type = 'MOTOR_TYPE_COMPULSORY' THEN 0 ELSE Discount_master END AS Discount,
    CASE
      WHEN motor_item_type = 'MOTOR_TYPE_COMPULSORY' THEN compu_detail.gross_premium
      WHEN charge_rank = 1 THEN ROUND((TotalPremium)+TotalEIR+TotalSBT+ProcessingFee_master+ProcessingFeeVat_master+ShippingFee_master+ShippingFeeVat_master-Discount_master,2)
      WHEN charge_rank <> 1 THEN 0
    END AS ExpectedReceived,
    CASE
      WHEN motor_item_type = 'MOTOR_TYPE_COMPULSORY' THEN compu_detail.gross_premium
      WHEN motor_item_type <> 'MOTOR_TYPE_COMPULSORY' AND charge_rank <> 1 THEN COALESCE(ActualReceived_master, ROUND(0.01*TotalPremium,2))
      WHEN compu_detail.gross_premium IS NOT NULL AND motor_item_type <> 'MOTOR_TYPE_COMPULSORY' AND charge_rank = 1 THEN ROUND(ActualReceived_master-compu_detail.gross_premium,2)
      ELSE COALESCE(ActualReceived_master, ROUND(0.01*TotalPremium,2))
    END AS ActualReceived,
    0 AS InterestThisPeriod
  FROM onetime_master
  LEFT JOIN compu_detail ON compu_detail.order_id = onetime_master.OrderID
  -- (2nd join to `charges` removed -- charge_rank now comes from onetime_master directly)
  WHERE
    service_provider != 'ICOLLECTION'
    AND service_provider <> 'RABBIT_LENDING'
    AND NOT (cmi_rank <> 1 AND motor_item_type = 'MOTOR_TYPE_COMPULSORY')
    AND OrderID NOT IN (SELECT current_human_id FROM change)
)

SELECT DISTINCT
  CompanyDB,
  OrderID,
  OrderItem,
  InvoiceNo,
  CAST(FORMAT_DATE('%d%m%Y', OrderDate) AS STRING) AS OrderDate,
  InsuredID,
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
    WHEN InsuranceGroup = 'products/health-insurance' THEN 'Health'
    WHEN InsuranceGroup = 'products/travel-insurance' THEN 'TA'
    ELSE InsuranceGroup
  END AS InsuranceGroup,
  CASE
    WHEN (InsuranceType IS NULL OR InsuranceType = ' ') AND InsuranceGroup = 'products/health-insurance' THEN 'Health'
    WHEN (InsuranceType IS NULL OR InsuranceType = ' ') AND InsuranceGroup = 'products/travel-insurance' THEN 'TA'
    ELSE InsuranceType
  END AS InsuranceType,
  CASE
    WHEN InsuranceGroup = 'products/car-insurance' THEN 'Motor'
    WHEN InsuranceGroup = 'products/health-insurance' THEN 'Health'
    WHEN InsuranceGroup = 'products/travel-insurance' THEN 'TA'
    ELSE InsuranceGroup
  END AS InsuranceProduct,
  'Insurance' ProductType,
  CASE WHEN PolicyType = 'LEAD_TYPE_RENEWAL' THEN 'R' ELSE 'N' END AS PolicyType,
  Endorse,
  CAST(FORMAT_DATE('%d%m%Y', PolicyDate) AS STRING) AS PolicyDate,
  PolicyNo,
  CAST(EndorsementNo AS STRING) EndorsementNo,
  ChassisNo,
  LicensePlate,
  FORMAT('%.2f',GrossPremium) GrossPremium,
  FORMAT('%.2f',StampDuty) StampDuty,
  FORMAT('%.2f',VAT) VAT,
  FORMAT('%.2f',TotalPremium) TotalPremium,
  FORMAT('%.2f',WHT) WHT,
  FORMAT('%.2f',TotalEIR) TotalEIR,
  FORMAT('%.2f',TotalSBT) TotalSBT,
  FORMAT('%.2f',ProcessingFee) ProcessingFee,
  FORMAT('%.2f',ProcessingFeeVat) ProcessingFeeVat,
  FORMAT('%.2f',ShippingFee) ShippingFee,
  FORMAT('%.2f',ShippingFeeVat) ShippingFeeVat,
  FORMAT('%.2f',TotalAmount) TotalAmount,
  FORMAT('%.2f',Discount) Discount,
  CASE
    WHEN TransactionStatus = 'FOLLOWUP_STATUS_PAID' THEN 'paid'
    WHEN TransactionStatus = 'FOLLOWUP_STATUS_PENDING' THEN 'pending'
    WHEN TransactionStatus = 'SUCCESSFUL' THEN 'paid'
    WHEN TransactionStatus = 'PENDING' THEN 'pending'
    ELSE TransactionStatus
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
    WHEN PaymentStatus = 'SUCCESSFUL' THEN 'Fully paid'
    WHEN PaymentStatus = 'PENDING' THEN 'Not fully paid'
    ELSE PaymentStatus
  END AS PaymentStatus,
  FORMAT('%.2f',ExpectedReceived) ExpectedReceived,
  FORMAT('%.2f',ActualReceived) ActualReceived,
  InterestThisPeriod,
  PrincipleThisPeriod,
  InterestEIRThisPeriod,
  PrincipleEIRThisPeriod,
  CAST(FORMAT_DATE('%d%m%Y', PaymentDate) AS STRING) AS PaymentDate,
  Period,
  TotalPeriods,
  PendingPayment,
  CASE
    WHEN current_human_id IS NOT NULL THEN 'RCB-CreditShell'
    WHEN PaymentMethod ='CASH' AND PaymentChannel='SERVICE_PROVIDER_UNSPECIFIED' THEN 'TRF Transfer'
    WHEN PaymentMethod ='BANK_TRANSFER' AND PaymentChannel='KASIKORN' THEN 'TRF Transfer'
    WHEN PaymentMethod ='BANK_TRANSFER' AND PaymentChannel='KRUNGSRI' THEN 'TRF Transfer'
    WHEN PaymentMethod ='BANK_TRANSFER' AND PaymentChannel='KRUNGTHAI' THEN 'TRF Transfer'
    WHEN PaymentMethod ='BANK_TRANSFER' AND PaymentChannel='SCB' THEN 'TRF Transfer'
    WHEN PaymentMethod ='DIRECT_PAYMENT' AND PaymentChannel='SERVICE_PROVIDER_UNSPECIFIED' THEN 'DPM จ่ายตรงกับบริษัทประกัน'
    WHEN PaymentMethod ='EDC' AND PaymentChannel='BANGKOK_BANK' THEN 'EDC EDC'
    WHEN PaymentMethod ='EDC' AND PaymentChannel='KASIKORN' THEN 'EDC EDC'
    WHEN PaymentMethod ='EDC' AND PaymentChannel='KRUNGSRI' THEN 'EDC EDC'
    WHEN PaymentMethod ='EDC' AND PaymentChannel='KRUNGTHAI' THEN 'EDC EDC'
    WHEN PaymentMethod ='EDC' AND PaymentChannel='SCB' THEN 'EDC EDC'
    WHEN PaymentMethod ='EDC' AND PaymentChannel='UOB' THEN 'EDC EDC'
    WHEN PaymentMethod ='ONLINECARD' AND PaymentChannel='OMISE' THEN 'OMC Omise Credit Card'
    WHEN PaymentMethod ='ONLINECARD' AND PaymentChannel='RCB' THEN 'OMC Omise Credit Card'
    WHEN PaymentMethod ='QR_CODE' AND PaymentChannel='OMISE' THEN 'OME Omise QR Prompt Pay'
    WHEN PaymentMethod ='QR_CODE' AND PaymentChannel='RABBIT_LENDING' THEN 'OME Omise QR Prompt Pay'
    WHEN PaymentMethod ='QR_CODE' AND PaymentChannel='RCB' THEN 'OME Omise QR Prompt Pay'
    WHEN PaymentMethod ='all' AND PaymentChannel='all' THEN 'RCL-CMI-channel'
    ELSE 'TRF Transfer'
  END AS PaymentMethod,
  CASE
    WHEN current_human_id IS NOT NULL THEN 'RCB-CreditShell'
    WHEN PaymentMethod ='CASH' AND PaymentChannel='SERVICE_PROVIDER_UNSPECIFIED' THEN 'RCB-Transfer-อื่นๆ'
    WHEN PaymentMethod ='BANK_TRANSFER' AND PaymentChannel='KASIKORN' THEN 'RCB-Transfer-KBANK'
    WHEN PaymentMethod ='BANK_TRANSFER' AND PaymentChannel='KRUNGSRI' THEN 'RCB-Transfer-BAY'
    WHEN PaymentMethod ='BANK_TRANSFER' AND PaymentChannel='KRUNGTHAI' THEN 'RCB-Transfer-KTB'
    WHEN PaymentMethod ='BANK_TRANSFER' AND PaymentChannel='SCB' THEN 'RCB-Transfer-SCB'
    WHEN PaymentMethod ='DIRECT_PAYMENT' AND PaymentChannel='SERVICE_PROVIDER_UNSPECIFIED' THEN 'RCB-DIRECT PAYMENT'
    WHEN PaymentMethod ='EDC' AND PaymentChannel='BANGKOK_BANK' THEN 'RCB-EDC-BBL'
    WHEN PaymentMethod ='EDC' AND PaymentChannel='KASIKORN' THEN 'RCB-EDC-KBANK'
    WHEN PaymentMethod ='EDC' AND PaymentChannel='KRUNGSRI' THEN 'RCB-EDC-BAY'
    WHEN PaymentMethod ='EDC' AND PaymentChannel='KRUNGTHAI' THEN 'RCB-EDC-KTB'
    WHEN PaymentMethod ='EDC' AND PaymentChannel='SCB' THEN 'RCB-EDC-SCB'
    WHEN PaymentMethod ='EDC' AND PaymentChannel='UOB' THEN 'RCB-EDC-UOB'
    WHEN PaymentMethod ='ONLINECARD' AND PaymentChannel='OMISE' THEN 'RCB-Omise Credit Card-BAY'
    WHEN PaymentMethod ='ONLINECARD' AND PaymentChannel='RCB' THEN 'RCB-Omise Credit Card-BAY'
    WHEN PaymentMethod ='QR_CODE' AND PaymentChannel='OMISE' THEN 'RCB-Omise QR Prompt Pay-BAY'
    WHEN PaymentMethod ='QR_CODE' AND PaymentChannel='RABBIT_LENDING' THEN 'RCB-Omise QR Prompt Pay-BAY'
    WHEN PaymentMethod ='QR_CODE' AND PaymentChannel='RCB' THEN 'RCB-Omise QR Prompt Pay-BAY'
    WHEN PaymentMethod ='all' AND PaymentChannel='all' THEN 'RCL-CMI-channel'
    ELSE 'RCB-Transfer-อื่นๆ'
  END AS PaymentChannel,
  CAST(FORMAT_DATE('%d%m%Y', ExpectedDate) AS STRING) AS ExpectedDate,
  ch.old_human_id AS RefOrder,
  RefundAmountBeforeFee,
  RefundAmountAfterFee,
  BillingAddress,
  CAST(FORMAT_DATE('%d%m%Y', BatchRunDate) AS STRING) AS BatchRunDate
FROM onetime_master_go
LEFT JOIN change ch ON ch.current_human_id = onetime_master_go.OrderID
ORDER BY OrderItem;

-- CLASS A / PRODUCTION DDL: DO NOT RUN WITHOUT BOAT'S EXPLICIT "deploy OK" IN SESSION.
-- Authority: Boat 2026-11-24 ICT chat: "ฉันอนุมัติให้ Claude code แก้ไข view" + hold RABBIT_CASH until fixed.
-- Finding: docs/FINDINGS_RABBIT_CASH_QR_GATEWAY_UNMAPPED_20261123.md
-- Change: add ONE WHEN branch (QR_CODE + RABBIT_CASH -> 'RCB-Rabbit Card') before the existing Omise QR
--   branch in each PaymentMethod and PaymentChannel CASE. No column added/moved; every other byte unchanged.
-- Fresh live sources captured 2026-11-24 ~02:00 ICT from INFORMATION_SCHEMA.VIEWS.

-- sap_data_engineer.sap_dashboard_carepay_fully_paid: live lastModifiedTime 1790762753637; live SHA-256 bfbece203be80428c1e5df2ad9f4e591a43634b264b9d3a267cbe9ef8584a31e; candidate SHA-256 8d01824060e7fa9d662e0d3b21ebd47f273af4561f7258e63d60b562be3ecdc1
-- sap_data_engineer.RCB_HEALTH: live lastModifiedTime 1790762751117; live SHA-256 af008000a8ddb7f4aad7659e170bdaa5771d5128bf6fee8403aa486d1d645694; candidate SHA-256 347b53502654f3d8bce3762e07c0311a50accfc572a4bf5ef4959fab45556c70
-- sap_view.RCB_NonMotor_process_2_cancel: live lastModifiedTime 1794210012573; live SHA-256 5900851a556d6ff85d86635bf12eb6dd5c5aae099707880905f8b01464221cee; candidate SHA-256 e19526c8018675068721ca02b7ff6f8cf931319eab34109c60edad1bf4efe0cb

CREATE OR REPLACE VIEW `pacific-plating-282708.sap_data_engineer.sap_dashboard_carepay_fully_paid` AS
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
--  3. Pushed policy_start_date filter into order_items CTE (filter early,
--     before the 9-way join, instead of after)
-- ============================================================
-- Fixed & re-tuned: 2026-08-28 (Boat review)
-- Changes:
--  4. FIX (logic gap): transactions.payment_option <> 'RABBIT_CARE_INSTALLMENT'
--     was a single-enum blacklist -- any OTHER installment payment_option value
--     would silently pass through. Removed this filter entirely; installment
--     exclusion is now defined ONLY by the structural signal
--     transaction_snapshots.number_of_installment = 1, which is already
--     enforced in two places below (see notes at each spot). This is more
--     complete than any enum list we could hardcode without a live check.
--  5. Removed unused CTE `transaction_snapshot_installment_details`
--     (declared, never joined/referenced -- dead code)
--  6. Pushed `orders.product = 'products/car-insurance'` filter into the
--     `orders` CTE (was applied post-join in WHERE) -- same result, less
--     data flowing through the 9-way join
--  7. Pushed `installment = 1` filter into the `follow_ups` CTE (was applied
--     post-join in WHERE as `follow_ups.installment = 1 OR ... IS NULL`) --
--     reduces fan-out from transactions with multiple follow_up rows before
--     the join, instead of after
--  8. Removed WHERE conditions in onetime_master that were already fully
--     enforced by upstream CTE filters (charges.status, charges.service_provider,
--     the follow_ups OR-IS-NULL condition) -- these became dead/always-true
--     predicates after changes #4/#6/#7 and cost cycles for no effect on result
-- NOT changed: final SELECT block is byte-identical to the original --
--     no change to result logic, calculation, or output format.
-- ============================================================


WITH

charges AS (
  SELECT * ,
    ROW_NUMBER() OVER (PARTITION BY transaction_id ORDER BY create_time) AS charge_rank
  FROM `pacific-plating-282708.careos.carepay_charges`
  WHERE status = 'SUCCESSFUL'
  AND (service_provider <> 'RABBIT_LENDING' OR (service_provider IS NULL AND payment_method = 'EDC'))
),

-- FIX 7: installment filter pushed here. A transaction with no row left after
-- this filter will simply produce NULL on the LEFT JOIN below, which is exactly
-- what "follow_ups.installment IS NULL" used to check for post-join -- same
-- result, computed on fewer rows before the join instead of after.
follow_ups AS (
  SELECT * FROM `pacific-plating-282708.careos.carepay_follow_ups`
  WHERE installment = 1
),

transaction_snapshot_price_summaries AS (
  SELECT * FROM `pacific-plating-282708.careos.carepay_transaction_snapshot_price_summaries`
),

-- Authoritative "is this a one-time / plain payment" signal (FIX 4).
-- Enforced here AND again in onetime_master's WHERE below -- the second
-- one is what actually matters for correctness (turns the LEFT JOIN into
-- an effective INNER JOIN); this CTE-level filter just shrinks the table
-- before the big join for performance.
transaction_snapshots AS (
  SELECT * FROM `pacific-plating-282708.careos.carepay_transaction_snapshots`
  WHERE number_of_installment = 1
),

transactions AS (
  SELECT * FROM `pacific-plating-282708.careos.carepay_transactions`
),

-- FIX 6: product filter pushed here (was in WHERE, post-join). Identical
-- result, less data through the 9-way join.
orders AS (
  SELECT * FROM `pacific-plating-282708.careos.careos_orders`
  WHERE product = 'products/car-insurance'
),

-- date filter pushed here (early), instead of only in the final WHERE
order_items AS (
  SELECT * FROM `pacific-plating-282708.careos.careos_order_items`
  WHERE policy_start_date >= '2025-01-01'
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
    AND order_items.policy_start_date >= '2025-01-01'
),

-- pre-aggregate SAP_LIVE_FULL down to just what's needed
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
    charges.charge_rank,
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
  LEFT JOIN sap_batchrun ON sap_batchrun.U_OrderID = ch.old_human_id
  WHERE
    -- FIX 4: this is now the ONLY installment/one-time gate. It is what makes
    -- the LEFT JOIN to transaction_snapshots behave as an INNER JOIN --
    -- rows with no matching number_of_installment=1 snapshot get excluded here.
    transaction_snapshots.number_of_installment = 1
    -- NOTE: the cmi_rank guard is NOT here -- cmi_rank is a window-function
    -- alias defined in this same SELECT, and BigQuery evaluates WHERE before
    -- window functions, so it can't be referenced here. It's applied one
    -- level up in onetime_master_go's WHERE instead (original location),
    -- where cmi_rank is a plain output column.
),

onetime_master_go AS (
  SELECT
    * EXCEPT(charge_rank),
    charge_rank,
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
  WHERE
    (service_provider != 'ICOLLECTION' OR (service_provider IS NULL AND PaymentMethod = 'EDC'))
    AND (service_provider <> 'RABBIT_LENDING' OR (service_provider IS NULL AND PaymentMethod = 'EDC'))
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
    WHEN PaymentMethod = 'EDC' THEN 'EDC EDC'
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
    WHEN PaymentMethod ='QR_CODE' AND PaymentChannel='RABBIT_CASH' THEN 'RCB-Rabbit Card' -- 2026-11-24 Rabbit Card Gateway: FA spec (Mo, 2026-09-30) One-Time RCB = RCB-Rabbit Card
    WHEN PaymentMethod ='QR_CODE' AND PaymentChannel='OMISE' THEN 'OME Omise QR Prompt Pay'
    WHEN PaymentMethod ='QR_CODE' AND PaymentChannel='RABBIT_LENDING' THEN 'OME Omise QR Prompt Pay'
    WHEN PaymentMethod ='QR_CODE' AND PaymentChannel='RCB' THEN 'OME Omise QR Prompt Pay'
    WHEN PaymentMethod ='all' AND PaymentChannel='all' THEN 'RCL-CMI-channel'
    ELSE 'TRF Transfer'
  END AS PaymentMethod,
  CASE
    WHEN current_human_id IS NOT NULL THEN 'RCB-CreditShell'
    WHEN PaymentMethod = 'EDC' THEN `pacific-plating-282708.sap_integration_v3.fn_rcb_payment_mapping`('EDC', PaymentChannel).sap_payment_channel
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
    WHEN PaymentMethod ='QR_CODE' AND PaymentChannel='RABBIT_CASH' THEN 'RCB-Rabbit Card' -- 2026-11-24 Rabbit Card Gateway: FA spec (Mo, 2026-09-30) One-Time RCB = RCB-Rabbit Card
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
ORDER BY OrderItem
;

CREATE OR REPLACE VIEW `pacific-plating-282708.sap_data_engineer.RCB_HEALTH` AS
-- FULL SOURCE-ONLY LEGACY ROOT-FIX PROPOSAL
-- Object: pacific-plating-282708.sap_data_engineer.RCB_HEALTH
-- Live definition captured: 2026-09-07 ICT
-- Root fix: classify CREDIT_CARD_INSTALLMENT as SAP ONETIME even when the CarePay
-- snapshot records the customer's bank term (3/6/10). The bank pays Rabbit Care
-- in full, so these rows must not be routed as RCL installments.
-- Every other live expression and mapping is preserved.

-- RCB NonMotor (onetime) -- FIXED & TUNED VERSION
-- Fixed & tuned: 2026-08-28 (Boat review)
-- Changes (confirmed with Boat):
--  1. FIX (correctness, major): added credit-shell exclusion, same pattern
--     as Motor onetime -- `change` CTE (cancelled_change_orders) + pushed
--     into the `orders` CTE: `human_id NOT IN (SELECT human_id FROM
--     change)`. Previously NonMotor had NO exclusion at all -- credit-shell
--     (rebooked/changed) orders would have been double-counted. RefOrder
--     (via get_charges_ref, informational only) is untouched and still
--     works off the raw, unfiltered tables -- it's just a label, not a gate.
--  2. FIX (correctness, major): added a second, structural layer for
--     "is this a one-time payment" alongside the existing follow_ups.id IS
--     NULL check -- `transaction_snapshots.number_of_installment = 1`
--     (pre-filtered in that CTE, enforced via `transaction_snapshots.id IS
--     NOT NULL` in onetime_master's WHERE, same mechanism as Motor) plus
--     `transactions.payment_option IS DISTINCT FROM 'CREDIT_CARD_INSTALLMENT'`
--     (NULL-safe, same as the Motor/EDC-installment fix). follow_ups.id IS
--     NULL is KEPT, not replaced -- this is belt-and-suspenders until it's
--     been checked against real data.
--  3. FIX (safety net): added SELECT DISTINCT to the final query, matching
--     Motor's defensive pattern -- this query joins transaction_snapshots
--     and get_charges_ref, neither of which is guaranteed 1:1, and there
--     was no dedup safety net at all before.
--  4. FIX (dead code): removed 12 CTEs that were declared but never
--     referenced anywhere in the query: card_tokens, contract_prices,
--     contract_records, contracts, customer_tokens, hydra_migrations,
--     payment_options, payment_records, prices, refunds,
--     transaction_snapshot_installment_details, check_order_items (and
--     check_order_items' now-pointless LEFT JOIN in onetime_master_go).
--  5. FIX (perf, major): `charge_one`'s inner `minn` subquery joined
--     orders + transactions + charges just to compute MIN(create_time) per
--     transaction_id from columns that only exist on `charges`
--     (status, service_provider) -- orders/transactions added nothing to
--     that filter. Rewritten to run over `charges` alone. Same tie-handling
--     semantics preserved (MIN + exact-timestamp self-join, not
--     ROW_NUMBER, so an exact tie still keeps both candidate charge ids,
--     matching the original behavior).
--  6. FIX (perf, major): the ENTIRE 8-way join + compu_detail + charge_one
--     computation used to run for EVERY product (including Motor) and only
--     filtered down to Health at the very last line (`WHERE InsuranceGroup
--     = 'products/health-insurance'`). Pushed the identical filter into
--     the `order_items` CTE instead (`WHERE product =
--     'products/health-insurance'`) -- InsuranceGroup is derived 1:1 from
--     order_items.product, so this is the exact same filter, just applied
--     before the expensive joins instead of after. The original final
--     WHERE is KEPT as a safety net (in case order_items doesn't match at
--     all for some order and InsuranceGroup comes through NULL) -- now
--     filtering a much smaller row set, effectively free.
--  7. Also pushed the same product filter into `compu_detail`'s raw
--     subquery for the same reason (was scanning order_items for every
--     product; matched only by exact order_id so was never a correctness
--     issue, purely wasted scan).
-- NOT changed: all financial calculations (WHT/EIR/SBT/fees), the
--     InsurerCode health-mapping table, InsuranceType/Group/Product logic,
--     PaymentMethod/PaymentChannel mapping, and every other CASE
--     expression are byte-identical to the original.
-- ============================================================

WITH
change AS (
  SELECT current_human_id human_id, old_human_id
  FROM `pacific-plating-282708.careos.cancelled_change_orders`
),

get_charges_ref AS (
  select charges.third_party_id , orders.human_id as order_id , orders.payment --, charges.*
  from `pacific-plating-282708.careos.carepay_charges` charges
  left join `pacific-plating-282708.careos.careos_orders` orders
  on orders.payment =  CONCAT('transactions/',charges.transaction_id)
  where 1=1
  and (service_provider != 'ICOLLECTION' OR (service_provider IS NULL AND charges.payment_method = 'EDC'))
  and status = 'SUCCESSFUL'
  and third_party_id is not null and orders.human_id is not null
),

charges AS (
  SELECT * FROM `pacific-plating-282708.careos.carepay_charges`
),

follow_ups AS (
  SELECT * FROM `pacific-plating-282708.careos.carepay_follow_ups`
),

transaction_snapshot_price_summaries AS (
  SELECT * FROM `pacific-plating-282708.careos.carepay_transaction_snapshot_price_summaries`
),

-- Root fix: retain the snapshot term here. The final gate treats normal payments
-- as one-time only at number_of_installment = 1, while CREDIT_CARD_INSTALLMENT
-- is SAP ONETIME regardless of the customer's 3/6/10-month bank term.
transaction_snapshots AS (
  SELECT * FROM `pacific-plating-282708.careos.carepay_transaction_snapshots`
),

-- Root fix: do not discard CREDIT_CARD_INSTALLMENT before the final ONETIME gate.
transactions AS (
  SELECT * FROM `pacific-plating-282708.careos.carepay_transactions`
),

-- FIX 1: credit-shell exclusion, same pattern as Motor.
orders AS (
  SELECT * FROM `pacific-plating-282708.careos.careos_orders`
  WHERE human_id NOT IN (SELECT human_id FROM change)
),

-- FIX 6: product filter pushed here (was only in the final WHERE).
order_items AS (
  SELECT * FROM `pacific-plating-282708.careos.careos_order_items`
  WHERE product = 'products/health-insurance'
),

leads AS (
  SELECT * FROM `pacific-plating-282708.careos.careos_leads`
),

-- FIX 5: removed the orders+transactions join -- MIN(create_time) only
-- ever depended on columns that live on `charges` itself.
charge_one AS (
  SELECT charges.id AS charges_id, charges.transaction_id
  FROM `pacific-plating-282708.careos.carepay_charges` charges
  JOIN (
    SELECT transaction_id, MIN(create_time) AS timee
    FROM `pacific-plating-282708.careos.carepay_charges`
    WHERE status = 'SUCCESSFUL' AND (service_provider != 'ICOLLECTION' OR (service_provider IS NULL AND payment_method = 'EDC'))
    GROUP BY transaction_id
  ) AS minn
  ON minn.transaction_id = charges.transaction_id AND charges.create_time = minn.timee
  WHERE charges.status = 'SUCCESSFUL' AND (charges.service_provider != 'ICOLLECTION' OR (charges.service_provider IS NULL AND payment_method = 'EDC'))
),

compu_detail as (
SELECT
orders.human_id as order_id,
case when order_items.gross_premium is null then 0 else order_items.gross_premium end as gross_premium
FROM `pacific-plating-282708.careos.careos_order_items` order_items
LEFT JOIN `pacific-plating-282708.careos.careos_orders` orders
    ON order_items.order_id = orders.id
where order_items.packagetype ='mandatoryPackages'
and order_items.product = 'products/health-insurance'  -- FIX 7: same product pushdown, correctness-neutral (matched by exact order_id anyway)
),

onetime_master as (
select
charges.amount as charges_amount,
order_items.motor_item_type,
order_items.packagetype,
charges.service_provider,
orders.create_time AS OrderDate,
charges.status ,
orders.human_id as OrderID,
order_items.human_id as OrderItem ,
order_items.price,
order_items.net_premium AS GrossPremium,
order_items.stamp_duty AS StampDuty,
order_items.vat_amount AS VAT,
order_items.gross_premium AS TotalPremium,
ROUND((1 / 100) * transaction_snapshot_price_summaries.wht_amount,2) AS WHT_master,
ROUND((1 / 100) * transaction_snapshot_price_summaries.interest_amount,2) as TotalEIR_check ,
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
ROUND((1 / 100) * transaction_snapshot_price_summaries.discount_amount,2) AS Discount_master,
charges.status AS TransactionStatus,
order_items.submission_status AS SubmissionStatus,
order_items.approval_status AS ApprovalStatus,
transactions.status AS PaymentStatus,
ROUND(((1 / 100) * charges.amount),2) AS ActualReceived_master, -- จำนวนเงินที่ลูกค้าจ่ายมาจริงๆ ห้ามเปลี่ยน
0 AS PrincipleThisPeriod,
transaction_snapshot_price_summaries.interest_amount AS InterestEIRThisPeriod,
0 AS PrincipleEIRThisPeriod,
CASE
  WHEN COALESCE(charges.payment_date, charges.update_time) < TIMESTAMP(DATE_TRUNC(CURRENT_DATE(), MONTH))
    THEN TIMESTAMP(DATE_TRUNC(CURRENT_DATE(), MONTH))
  ELSE COALESCE(charges.payment_date, charges.update_time)
END AS PaymentDate,
charges.installment_number AS Period,
1 as TotalPeriods,
0 as PendingPayment,
charges.create_time as ExpectedDate ,
charges.id as charges_id,
case
  when charges.third_party_id is null AND charges.payment_method ='DIRECT_PAYMENT' then CONCAT("dpm_",order_items.human_id)
  WHEN charges.third_party_id is null AND charges.payment_method ='BANK_TRANSFER' then CONCAT("trf_",order_items.human_id)
  WHEN charges.third_party_id is null AND charges.payment_method ='CASH' then CONCAT("cash_",order_items.human_id)
  WHEN charges.third_party_id is null AND charges.payment_method ='EDC' then CONCAT("edc_",order_items.human_id)
  WHEN charges.third_party_id is NULL THEN order_items.human_id
  else  charges.third_party_id
end as InvoiceNo,
order_items.insurer AS InsurerCode,
order_items.product AS InsuranceGroup,
order_items.motor_item_type AS InsuranceType,
order_items.package AS InsuranceProduct,
'Insurance' ProductType,
leads.type AS PolicyType,
'N' AS Endorse,
order_items.policy_start_date AS PolicyDate,
order_items.policy_number AS PolicyNo,
NULL AS EndorsementNo,
JSON_VALUE(orders.data, '$.chassisNumber') AS ChassisNo,
JSON_VALUE(orders.data, '$.carLicensePlate') AS LicensePlate,
charges.payment_method AS PaymentMethod,
charges.service_provider AS PaymentChannel,
case when JSON_VALUE(orders.data, '$.policyHolder.isCompany') ='true' then
JSON_VALUE(orders.data, '$.policyHolder.companyTaxId') else JSON_VALUE(orders.data, '$.idNumber') end as InsuredID ,
JSON_VALUE(orders.data, '$.policyHolder.title') AS Title,
COALESCE(JSON_VALUE(orders.data, '$.policyHolder.firstName'),JSON_VALUE(orders.data, '$.policyHolder.policyAddress.companyName')) AS FirstName,
JSON_VALUE(orders.data, '$.policyHolder.lastName') AS LastName,
0 as RefundAmountBeforeFee,0 as RefundAmountAfterFee,
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
CURRENT_DATE() AS BatchRunDate,
'RCB' as CompanyDB,
leads.reference AS RefOrder
FROM orders
LEFT JOIN leads ON CONCAT('leads/',leads.id) = orders.lead
LEFT JOIN transactions ON CONCAT('transactions/',transactions.id) = orders.payment
LEFT JOIN follow_ups ON follow_ups.transaction_id = transactions.id
LEFT JOIN charges ON charges.transaction_id = transactions.id
LEFT JOIN order_items ON order_items.order_id = orders.id
LEFT JOIN transaction_snapshots ON transaction_snapshots.transaction_id = transactions.id
LEFT JOIN transaction_snapshot_price_summaries ON transaction_snapshot_price_summaries.snapshot_id = transaction_snapshots.id
where 1=1
and orders.is_fully_paid is true
AND charges.status = 'SUCCESSFUL'
and follow_ups.id is null -- ไม่มีงวดต้องตาม = ไม่ผ่อน (kept, per Boat: belt-and-suspenders)
AND (
  transaction_snapshots.number_of_installment = 1
  OR transactions.payment_option = 'CREDIT_CARD_INSTALLMENT'
) -- Root fix: bank card installments are SAP ONETIME because the bank settles in full.
and (charges.service_provider != 'ICOLLECTION' OR (charges.service_provider IS NULL AND charges.payment_method = 'EDC'))
)
, onetime_master_go as (
select * ,
case when packagetype='mandatoryPackages' then 0 else WHT_master end as WHT ,
case when packagetype='mandatoryPackages' then 0 else ProcessingFee_master end  as  ProcessingFee ,
case when packagetype='mandatoryPackages' then 0 else ProcessingFeeVat_master end as  ProcessingFeeVat  ,
case when packagetype='mandatoryPackages' then 0 else ShippingFee_master end  as  ShippingFee ,
case when packagetype='mandatoryPackages' then 0 else ShippingFeeVat_master end as  ShippingFeeVat ,
case when packagetype='mandatoryPackages' then TotalPremium else
ROUND((TotalPremium)+TotalEIR+TotalSBT+ProcessingFee_master+ProcessingFeeVat_master+ShippingFee_master+ShippingFeeVat_master,2) end as TotalAmount  ,
case when packagetype='mandatoryPackages' then 0 else Discount_master end as  Discount  ,
case when packagetype='mandatoryPackages' then TotalPremium
  else case when compu_detail.gross_premium is null then ActualReceived_master else ROUND(ActualReceived_master-compu_detail.gross_premium,2) end
end as ExpectedReceived ,
case when packagetype='mandatoryPackages' then TotalPremium
  else case when compu_detail.gross_premium is null then ActualReceived_master else ROUND(ActualReceived_master-compu_detail.gross_premium,2) end
end as ActualReceived ,
0 as InterestThisPeriod
from onetime_master
left join compu_detail on compu_detail.order_id=onetime_master.OrderID
where 1=1
and onetime_master.charges_id in (select distinct charges_id from charge_one) -- ชำระเต็มงวดแรก  -- งวด 2 ทำ sub query เพิ่ม
)



select distinct
CompanyDB ,
OrderID ,
OrderItem ,
InvoiceNo ,
CAST(FORMAT_DATE('%d%m%Y', OrderDate) AS STRING) AS OrderDate,
InsuredID ,
CASE
WHEN Title = 'KHUN' THEN 'คุณ'
WHEN Title = 'MISS' THEN 'นางสาว'
WHEN Title = 'MR' THEN 'นาย'
WHEN Title = 'MRS' THEN 'นาง'
ELSE ''
END AS Title,
FirstName ,
LastName  ,
CASE
  WHEN InsuranceGroup = 'products/health-insurance'
  THEN
    CASE
      WHEN InsurerCode = 'insurers/1' THEN 'N024'
      WHEN InsurerCode = 'insurers/3' THEN 'N082'
      WHEN InsurerCode = 'insurers/6' THEN 'N067' --AXA--
      WHEN InsurerCode = 'insurers/7' THEN 'N021'
      WHEN InsurerCode = 'insurers/8' THEN 'N092'
      WHEN InsurerCode = 'insurers/9' THEN 'N072'
      WHEN InsurerCode = 'insurers/10' THEN 'N040'
      WHEN InsurerCode = 'insurers/11' THEN 'N003'
      WHEN InsurerCode = 'insurers/12' THEN 'N091'
      WHEN InsurerCode = 'insurers/13' THEN 'N066'
      WHEN InsurerCode = 'insurers/14' THEN 'N090'
      WHEN InsurerCode = 'insurers/15' THEN 'N058'
      WHEN InsurerCode = 'insurers/16' THEN 'N089'
      WHEN InsurerCode = 'insurers/17' THEN 'N015'
      WHEN InsurerCode = 'insurers/18' THEN 'N088'
      WHEN InsurerCode = 'insurers/20' THEN 'N054'
      WHEN InsurerCode = 'insurers/23' THEN 'N087'
      WHEN InsurerCode = 'insurers/24' THEN 'N086'
      WHEN InsurerCode = 'insurers/26' THEN 'N062'
      WHEN InsurerCode = 'insurers/27' THEN 'N017'
      WHEN InsurerCode = 'insurers/28' THEN 'N069'
      WHEN InsurerCode = 'insurers/29' THEN 'N085'
      WHEN InsurerCode = 'insurers/30' THEN 'N30' --Generali--
      WHEN InsurerCode = 'insurers/31' THEN 'N061'
      WHEN InsurerCode = 'insurers/33' THEN 'N011' --LMG--
      WHEN InsurerCode = 'insurers/34' THEN 'N079' --MSIG--
      WHEN InsurerCode = 'insurers/36' THEN 'N084'
      WHEN InsurerCode = 'insurers/37' THEN 'N083'
      WHEN InsurerCode = 'insurers/40' THEN 'N033'
      WHEN InsurerCode = 'insurers/42' THEN 'N064'
      WHEN InsurerCode = 'insurers/43' THEN 'N080'
      WHEN InsurerCode = 'insurers/44' THEN 'N081'
      WHEN InsurerCode = 'insurers/46' THEN 'N105' --Pacific Cross--
      WHEN InsurerCode = 'insurers/48' THEN 'N103' --RabbitLife-
      WHEN InsurerCode = 'insurers/49' THEN 'N107' --MuangThaiLife-
      ELSE InsurerCode
    END
  ELSE 'Not Health'
END AS InsurerCode,
CASE
  WHEN InsuranceGroup = 'products/car-insurance' THEN 'Motor'
  WHEN InsuranceGroup = 'products/health-insurance' THEN 'Health'
  ELSE InsuranceGroup
END AS InsuranceGroup,
CASE
  WHEN InsuranceType IS NULL OR InsuranceType = ' ' THEN 'Health'
  ELSE InsuranceType
END AS InsuranceType,
CASE
  WHEN InsuranceGroup = 'products/car-insurance' THEN 'Motor'
  WHEN InsuranceGroup = 'products/health-insurance' THEN 'Health'
  ELSE InsuranceGroup
END AS InsuranceProduct,
'Insurance' ProductType,
CASE
  WHEN PolicyType = 'LEAD_TYPE_RENEWAL' THEN 'R'
  ELSE 'N'
END AS PolicyType,
Endorse,
CAST(FORMAT_DATE('%d%m%Y', PolicyDate) AS STRING) AS PolicyDate,
PolicyNo  ,
CAST(EndorsementNo AS STRING) EndorsementNo,
ChassisNo ,
LicensePlate  ,
GrossPremium  ,
StampDuty ,
VAT ,
TotalPremium  ,
WHT ,
TotalEIR  ,
TotalSBT  ,
ProcessingFee ,
ProcessingFeeVat  ,
ShippingFee ,
ShippingFeeVat  ,
TotalAmount ,
Discount  ,
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
ExpectedReceived,
ActualReceived  ,
InterestThisPeriod  ,
PrincipleThisPeriod ,
InterestEIRThisPeriod ,
PrincipleEIRThisPeriod  ,
CAST(FORMAT_DATE('%d%m%Y', PaymentDate) AS STRING) AS PaymentDate,
Period  ,
TotalPeriods  ,
PendingPayment  ,
CASE
    WHEN PaymentMethod = 'EDC' THEN 'EDC EDC'
    WHEN PaymentMethod ='CASH'and PaymentChannel='SERVICE_PROVIDER_UNSPECIFIED' THEN 'TRF Transfer'
WHEN PaymentMethod ='BANK_TRANSFER'and PaymentChannel='KASIKORN' THEN 'TRF Transfer'
WHEN PaymentMethod ='BANK_TRANSFER'and PaymentChannel='KRUNGSRI' THEN 'TRF Transfer'
WHEN PaymentMethod ='BANK_TRANSFER'and PaymentChannel='KRUNGTHAI' THEN 'TRF Transfer'
WHEN PaymentMethod ='BANK_TRANSFER'and PaymentChannel='SCB' THEN 'TRF Transfer'
WHEN PaymentMethod ='DIRECT_PAYMENT'and PaymentChannel='SERVICE_PROVIDER_UNSPECIFIED' THEN 'DPM จ่ายตรงกับบริษัทประกัน'
WHEN PaymentMethod ='EDC'and PaymentChannel='BANGKOK_BANK' THEN 'EDC EDC'
WHEN PaymentMethod ='EDC'and PaymentChannel='KASIKORN' THEN 'EDC EDC'
WHEN PaymentMethod ='EDC'and PaymentChannel='KRUNGSRI' THEN 'EDC EDC'
WHEN PaymentMethod ='EDC'and PaymentChannel='KRUNGTHAI' THEN 'EDC EDC'
WHEN PaymentMethod ='EDC'and PaymentChannel='SCB' THEN 'EDC EDC'
WHEN PaymentMethod ='EDC'and PaymentChannel='UOB' THEN 'EDC EDC'
WHEN PaymentMethod ='ONLINECARD'and PaymentChannel='OMISE' THEN 'OMC Omise Credit Card'
WHEN PaymentMethod ='ONLINECARD'and PaymentChannel='RCB' THEN 'OMC Omise Credit Card'
WHEN PaymentMethod ='QR_CODE'and PaymentChannel='RABBIT_CASH' THEN 'RCB-Rabbit Card' -- 2026-11-24 Rabbit Card Gateway: FA spec (Mo, 2026-09-30) One-Time RCB = RCB-Rabbit Card
WHEN PaymentMethod ='QR_CODE'and PaymentChannel='OMISE' THEN 'OME Omise QR Prompt Pay'
WHEN PaymentMethod ='QR_CODE'and PaymentChannel='RABBIT_LENDING' THEN 'OME Omise QR Prompt Pay'
WHEN PaymentMethod ='QR_CODE'and PaymentChannel='RCB' THEN 'OME Omise QR Prompt Pay'
WHEN PaymentMethod ='EDC'and PaymentChannel='KRUNGTHAI' THEN 'EDC EDC'
WHEN PaymentMethod ='QR_CODE'and PaymentChannel='RABBIT_LENDING' THEN 'OME Omise QR Prompt Pay'
WHEN PaymentMethod ='all'and PaymentChannel='all' THEN 'RCL-CMI-channel'
ELSE   'TRF Transfer'
END AS PaymentMethod  ,
CASE
    WHEN PaymentMethod = 'EDC' THEN `pacific-plating-282708.sap_integration_v3.fn_rcb_payment_mapping`('EDC', PaymentChannel).sap_payment_channel
    WHEN PaymentMethod ='CASH'and PaymentChannel='SERVICE_PROVIDER_UNSPECIFIED' THEN 'RCB-Transfer-อื่นๆ'
WHEN PaymentMethod ='BANK_TRANSFER'and PaymentChannel='KASIKORN' THEN 'RCB-Transfer-KBANK'
WHEN PaymentMethod ='BANK_TRANSFER'and PaymentChannel='KRUNGSRI' THEN 'RCB-Transfer-BAY'
WHEN PaymentMethod ='BANK_TRANSFER'and PaymentChannel='KRUNGTHAI' THEN 'RCB-Transfer-KTB'
WHEN PaymentMethod ='BANK_TRANSFER'and PaymentChannel='SCB' THEN 'RCB-Transfer-SCB'
WHEN PaymentMethod ='DIRECT_PAYMENT'and PaymentChannel='SERVICE_PROVIDER_UNSPECIFIED' THEN 'RCB-DIRECT PAYMENT'
WHEN PaymentMethod ='EDC'and PaymentChannel='BANGKOK_BANK' THEN 'RCB-EDC-BBL'
WHEN PaymentMethod ='EDC'and PaymentChannel='KASIKORN' THEN 'RCB-EDC-KBANK'
WHEN PaymentMethod ='EDC'and PaymentChannel='KRUNGSRI' THEN 'RCB-EDC-BAY'
WHEN PaymentMethod ='EDC'and PaymentChannel='KRUNGTHAI' THEN 'RCB-EDC-KTB'
WHEN PaymentMethod ='EDC'and PaymentChannel='SCB' THEN 'RCB-EDC-SCB'
WHEN PaymentMethod ='EDC'and PaymentChannel='UOB' THEN 'RCB-EDC-UOB'
WHEN PaymentMethod ='ONLINECARD'and PaymentChannel='OMISE' THEN 'RCB-Omise Credit Card-BAY'
WHEN PaymentMethod ='ONLINECARD'and PaymentChannel='RCB' THEN 'RCB-Omise Credit Card-BAY'
WHEN PaymentMethod ='QR_CODE'and PaymentChannel='RABBIT_CASH' THEN 'RCB-Rabbit Card' -- 2026-11-24 Rabbit Card Gateway: FA spec (Mo, 2026-09-30) One-Time RCB = RCB-Rabbit Card
WHEN PaymentMethod ='QR_CODE'and PaymentChannel='OMISE' THEN 'RCB-Omise QR Prompt Pay-BAY'
WHEN PaymentMethod ='QR_CODE'and PaymentChannel='RABBIT_LENDING' THEN 'RCB-Omise QR Prompt Pay-BAY'
WHEN PaymentMethod ='QR_CODE'and PaymentChannel='RCB' THEN 'RCB-Omise QR Prompt Pay-BAY'
WHEN PaymentMethod ='EDC'and PaymentChannel='KRUNGTHAI' THEN 'RCL-EDC-KTB'
WHEN PaymentMethod ='QR_CODE'and PaymentChannel='RABBIT_LENDING' THEN 'RCL-Omise QR Prompt Pay-BAY'
WHEN PaymentMethod ='all'and PaymentChannel='all' THEN 'RCL-CMI-channel'
ELSE 'RCB-Transfer-อื่นๆ'
END AS PaymentChannel ,
CAST(FORMAT_DATE('%d%m%Y', ExpectedDate) AS STRING) AS ExpectedDate,
get_charges_ref.order_id as RefOrder,
RefundAmountBeforeFee ,
RefundAmountAfterFee  ,
BillingAddress  ,
CAST(FORMAT_DATE('%d%m%Y', BatchRunDate) AS STRING) AS BatchRunDate,
from onetime_master_go
left join get_charges_ref on onetime_master_go.InvoiceNo=get_charges_ref.third_party_id and get_charges_ref.order_id != onetime_master_go.OrderID

WHERE InsuranceGroup = 'products/health-insurance'
;

CREATE OR REPLACE VIEW `pacific-plating-282708.sap_view.RCB_NonMotor_process_2_cancel` AS
WITH base AS (
-- Full source-only legacy reuse proposal for:
--   pacific-plating-282708.sap_view.RCB_NonMotor_process_2_cancel
--
-- New responsibility (MS-01):
--   RCB Health new-order payloads whose current order is linked to an old order by
--   careos.cancelled_change_orders and whose current OrderItem is not yet in SAP.
--
-- Legacy rules preserved:
--   * RCB_HEALTH field calculations and insurer/payment mappings.
--   * Successful CareOS charges are the payment source.
--   * RABBIT_CARE_INSTALLMENT/RABBIT_LENDING are excluded to prevent RCB/RCL mixing.
--   * A legitimate later charge remains another Period 1 row, but its
--     ExpectedReceived is 0 so expected revenue is not repeated.
--   * SELECT DISTINCT removes only exact final-payload duplicates.
--
-- SELECT only: this file does not replace or deploy the live legacy view.

WITH
  change_orders AS (
    SELECT DISTINCT
      current_human_id,
      old_human_id
    FROM `pacific-plating-282708.careos.cancelled_change_orders`
    WHERE current_human_id IS NOT NULL
      AND old_human_id IS NOT NULL
  ),

  latest_snapshot AS (
    SELECT *
    FROM `pacific-plating-282708.careos.carepay_transaction_snapshots`
    QUALIFY ROW_NUMBER() OVER (
      PARTITION BY transaction_id
      ORDER BY update_time DESC, create_time DESC, id DESC
    ) = 1
  ),

  successful_charges AS (
    SELECT *
    FROM `pacific-plating-282708.careos.carepay_charges`
    WHERE status = 'SUCCESSFUL'
      AND (service_provider NOT IN ('ICOLLECTION', 'RABBIT_LENDING') OR (service_provider IS NULL AND payment_method = 'EDC'))
    QUALIFY ROW_NUMBER() OVER (
      PARTITION BY id
      ORDER BY update_time DESC, create_time DESC
    ) = 1
  ),

  source_rows AS (
    SELECT
      'RCB' AS CompanyDB,
      orders.human_id AS OrderID,
      order_items.human_id AS OrderItem,
      orders.create_time AS OrderDate,
      CASE
        WHEN JSON_VALUE(orders.data, '$.policyHolder.isCompany') = 'true'
          AND JSON_VALUE(orders.data, '$.policyHolder.companyTaxId') IS NULL THEN '-'
        WHEN JSON_VALUE(orders.data, '$.policyHolder.isCompany') = 'true'
          THEN JSON_VALUE(orders.data, '$.policyHolder.companyTaxId')
        WHEN JSON_VALUE(orders.data, '$.idNumber') IS NULL
          OR TRIM(JSON_VALUE(orders.data, '$.idNumber')) = '' THEN '-'
        ELSE JSON_VALUE(orders.data, '$.idNumber')
      END AS InsuredID,
      JSON_VALUE(orders.data, '$.policyHolder.title') AS source_title,
      COALESCE(
        JSON_VALUE(orders.data, '$.policyHolder.firstName'),
        JSON_VALUE(orders.data, '$.policyHolder.policyAddress.companyName')
      ) AS FirstName,
      JSON_VALUE(orders.data, '$.policyHolder.lastName') AS LastName,
      order_items.insurer AS source_insurer,
      order_items.product AS source_product,
      order_items.motor_item_type AS source_insurance_type,
      leads.type AS source_policy_type,
      order_items.policy_start_date AS PolicyDate,
      order_items.policy_number AS PolicyNo,
      JSON_VALUE(orders.data, '$.chassisNumber') AS ChassisNo,
      JSON_VALUE(orders.data, '$.carLicensePlate') AS LicensePlate,
      COALESCE(order_items.net_premium, 0) AS GrossPremium,
      COALESCE(order_items.stamp_duty, 0) AS StampDuty,
      COALESCE(order_items.vat_amount, 0) AS VAT,
      COALESCE(order_items.gross_premium, 0) AS TotalPremium,
      COALESCE(ROUND(price_summary.wht_amount / 100, 2), 0) AS WHT,
      CASE
        WHEN price_summary.interest_amount IS NULL THEN 0
        ELSE ROUND(
          ROUND(price_summary.interest_amount / 100, 2)
          - (ROUND(price_summary.interest_amount / 100, 2) * 3.3 / 103.3),
          2
        )
      END AS TotalEIR,
      CASE
        WHEN price_summary.interest_amount IS NULL THEN 0
        ELSE ROUND(
          ROUND(price_summary.interest_amount / 100, 2) * 3.3 / 103.3,
          2
        )
      END AS TotalSBT,
      CASE
        WHEN price_summary.processing_fee_amount IS NULL THEN 0
        ELSE ROUND(
          ROUND(price_summary.processing_fee_amount / 100, 2) * 100 / 107,
          2
        )
      END AS ProcessingFee,
      CASE
        WHEN price_summary.processing_fee_amount IS NULL THEN 0
        ELSE ROUND(
          ROUND(price_summary.processing_fee_amount / 100, 2)
          - ROUND(price_summary.processing_fee_amount / 100, 2) * 100 / 107,
          2
        )
      END AS ProcessingFeeVat,
      CASE
        WHEN price_summary.shipment_fee IS NULL THEN 0
        ELSE ROUND(
          ROUND(price_summary.shipment_fee / 100, 2) * 100 / 107,
          2
        )
      END AS ShippingFee,
      CASE
        WHEN price_summary.shipment_fee IS NULL THEN 0
        ELSE ROUND(
          ROUND(price_summary.shipment_fee / 100, 2)
          - ROUND(price_summary.shipment_fee / 100, 2) * 100 / 107,
          2
        )
      END AS ShippingFeeVat,
      COALESCE(ROUND(price_summary.discount_amount / 100, 2), 0) AS Discount,
      COALESCE(SAFE_CAST(price_summary.interest_amount AS INT64), 0)
        AS InterestEIRThisPeriod,
      order_items.submission_status AS source_submission_status,
      order_items.approval_status AS source_approval_status,
      transactions.status AS source_payment_status,
      COALESCE(SAFE_CAST(charges.installment_number AS INT64), 1) AS Period,
      charges.payment_method AS source_payment_method,
      charges.service_provider AS source_payment_channel,
      charges.third_party_id,
      charges.id AS charge_id,
      charges.create_time AS charge_create_time,
      COALESCE(charges.payment_date, charges.update_time, charges.create_time)
        AS source_payment_date,
      ROUND(charges.amount / 100, 2) AS ActualReceived,
      change_orders.old_human_id AS RefOrder,
      CASE
        WHEN JSON_VALUE(orders.data, '$.policyHolder.policyAddress.isBillingAddress') = 'true'
          THEN CONCAT(
            COALESCE(
              JSON_VALUE(orders.data, '$.policyHolder.policyAddress.fullName'),
              JSON_VALUE(orders.data, '$.policyHolder.policyAddress.companyName')
            ), ', ',
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
      ROW_NUMBER() OVER (
        PARTITION BY order_items.human_id
        ORDER BY
          COALESCE(charges.payment_date, charges.update_time, charges.create_time),
          charges.create_time,
          charges.id
      ) AS item_charge_rank
    FROM `pacific-plating-282708.careos.careos_orders` AS orders
    JOIN change_orders
      ON change_orders.current_human_id = orders.human_id
    JOIN `pacific-plating-282708.careos.careos_order_items` AS order_items
      ON order_items.order_id = orders.id
    JOIN `pacific-plating-282708.careos.carepay_transactions` AS transactions
      ON CONCAT('transactions/', transactions.id) = orders.payment
    JOIN successful_charges AS charges
      ON charges.transaction_id = transactions.id
    LEFT JOIN `pacific-plating-282708.careos.careos_leads` AS leads
      ON CONCAT('leads/', leads.id) = orders.lead
    LEFT JOIN latest_snapshot AS snapshot
      ON snapshot.transaction_id = transactions.id
    LEFT JOIN `pacific-plating-282708.careos.carepay_transaction_snapshot_price_summaries`
      AS price_summary
      ON price_summary.snapshot_id = snapshot.id
    LEFT JOIN `pacific-plating-282708.sap_integration_v3.stg_sap_state` AS sap
      ON sap.U_OrderItem = order_items.human_id
    WHERE order_items.product = 'products/health-insurance'
      AND order_items.is_cancelled IS NOT TRUE
      AND order_items.cancel_time IS NULL
      AND orders.is_fully_paid IS TRUE
      AND transactions.status = 'SUCCESSFUL'
      AND transactions.payment_option != 'RABBIT_CARE_INSTALLMENT'
      AND (
        snapshot.number_of_installment = 1
        OR transactions.payment_option = 'CREDIT_CARD_INSTALLMENT'
      )
      AND GREATEST(
        DATE(orders.create_time, 'Asia/Bangkok'),
        COALESCE(
          DATE(order_items.policy_start_date, 'Asia/Bangkok'),
          DATE(orders.create_time, 'Asia/Bangkok')
        )
      ) >= DATE '2026-01-01'
      AND sap.U_OrderItem IS NULL
      -- FIX 2026-10-28 (LogID 23230): stg_sap_state lags the nightly import by a day, so items posted
      -- last night were resent and rejected as duplicates. Also check SAP_LIVE_FULL, like the Motor views.
      AND NOT EXISTS (SELECT 1 FROM `pacific-plating-282708.sap_integration_v2.SAP_LIVE_FULL` AS sap_live WHERE sap_live.U_OrderItem = order_items.human_id)
      AND LOWER(TRIM(COALESCE(
        JSON_VALUE(orders.data, '$.policyHolder.firstName'),
        JSON_VALUE(orders.data, '$.policyHolder.policyAddress.companyName'),
        ''
      ))) != 'test'
      AND LOWER(TRIM(COALESCE(
        JSON_VALUE(orders.data, '$.policyHolder.lastName'),
        ''
      ))) != 'test'
  ),

  calculated AS (
    SELECT
      source_rows.*,
      ROUND(
        TotalPremium + TotalEIR + TotalSBT
        + ProcessingFee + ProcessingFeeVat + ShippingFee + ShippingFeeVat,
        2
      ) AS TotalAmount,
      CASE
        WHEN item_charge_rank = 1 THEN ROUND(
          TotalPremium + TotalEIR + TotalSBT
          + ProcessingFee + ProcessingFeeVat + ShippingFee + ShippingFeeVat
          - Discount,
          2
        )
        ELSE 0
      END AS ExpectedReceived,
      CASE
        WHEN DATE(source_payment_date, 'Asia/Bangkok')
          < DATE_TRUNC(CURRENT_DATE('Asia/Bangkok'), MONTH)
        THEN DATE_TRUNC(CURRENT_DATE('Asia/Bangkok'), MONTH)
        ELSE DATE(source_payment_date, 'Asia/Bangkok')
      END AS PaymentDate,
      COALESCE(
        NULLIF(third_party_id, ''),
        CONCAT(
          CASE source_payment_method
            WHEN 'DIRECT_PAYMENT' THEN 'dpm'
            WHEN 'BANK_TRANSFER' THEN 'trf'
            WHEN 'CASH' THEN 'cash'
            WHEN 'EDC' THEN 'edc'
            ELSE LOWER(COALESCE(source_payment_method, 'payment'))
          END,
          '_', CAST(item_charge_rank AS STRING), '_', OrderItem
        )
      ) AS InvoiceNo
    FROM source_rows
  )

SELECT DISTINCT
  CompanyDB,
  OrderID,
  OrderItem,
  InvoiceNo,
  FORMAT_DATE('%d%m%Y', DATE(OrderDate, 'Asia/Bangkok')) AS OrderDate,
  InsuredID,
  CASE source_title
    WHEN 'KHUN' THEN 'คุณ'
    WHEN 'MISS' THEN 'นางสาว'
    WHEN 'MR' THEN 'นาย'
    WHEN 'MRS' THEN 'นาง'
    ELSE ''
  END AS Title,
  FirstName,
  LastName,
  CASE source_insurer
    WHEN 'insurers/1' THEN 'N024'
    WHEN 'insurers/3' THEN 'N082'
    WHEN 'insurers/6' THEN 'N067'
    WHEN 'insurers/7' THEN 'N021'
    WHEN 'insurers/8' THEN 'N092'
    WHEN 'insurers/9' THEN 'N072'
    WHEN 'insurers/10' THEN 'N040'
    WHEN 'insurers/11' THEN 'N003'
    WHEN 'insurers/12' THEN 'N091'
    WHEN 'insurers/13' THEN 'N066'
    WHEN 'insurers/14' THEN 'N090'
    WHEN 'insurers/15' THEN 'N058'
    WHEN 'insurers/16' THEN 'N089'
    WHEN 'insurers/17' THEN 'N015'
    WHEN 'insurers/18' THEN 'N088'
    WHEN 'insurers/20' THEN 'N054'
    WHEN 'insurers/23' THEN 'N087'
    WHEN 'insurers/24' THEN 'N086'
    WHEN 'insurers/26' THEN 'N062'
    WHEN 'insurers/27' THEN 'N017'
    WHEN 'insurers/28' THEN 'N069'
    WHEN 'insurers/29' THEN 'N085'
    WHEN 'insurers/30' THEN 'N30'
    WHEN 'insurers/31' THEN 'N061'
    WHEN 'insurers/33' THEN 'N011'
    WHEN 'insurers/34' THEN 'N079'
    WHEN 'insurers/36' THEN 'N084'
    WHEN 'insurers/37' THEN 'N083'
    WHEN 'insurers/40' THEN 'N033'
    WHEN 'insurers/42' THEN 'N064'
    WHEN 'insurers/43' THEN 'N080'
    WHEN 'insurers/44' THEN 'N081'
    WHEN 'insurers/46' THEN 'N105'
    WHEN 'insurers/48' THEN 'N103'
    WHEN 'insurers/49' THEN 'N107'
    ELSE source_insurer
  END AS InsurerCode,
  'Health' AS InsuranceGroup,
  CASE
    WHEN source_insurance_type IS NULL OR TRIM(source_insurance_type) = '' THEN 'Health'
    ELSE source_insurance_type
  END AS InsuranceType,
  'Health' AS InsuranceProduct,
  'Insurance' AS ProductType,
  CASE WHEN source_policy_type = 'LEAD_TYPE_RENEWAL' THEN 'R' ELSE 'N' END AS PolicyType,
  'N' AS Endorse,
  FORMAT_DATE('%d%m%Y', DATE(PolicyDate, 'Asia/Bangkok')) AS PolicyDate,
  PolicyNo,
  CAST(NULL AS STRING) AS EndorsementNo,
  ChassisNo,
  LicensePlate,
  FORMAT('%.2f', GrossPremium) AS GrossPremium,
  FORMAT('%.2f', StampDuty) AS StampDuty,
  FORMAT('%.2f', VAT) AS VAT,
  FORMAT('%.2f', TotalPremium) AS TotalPremium,
  FORMAT('%.2f', WHT) AS WHT,
  FORMAT('%.2f', TotalEIR) AS TotalEIR,
  FORMAT('%.2f', TotalSBT) AS TotalSBT,
  FORMAT('%.2f', ProcessingFee) AS ProcessingFee,
  FORMAT('%.2f', ProcessingFeeVat) AS ProcessingFeeVat,
  FORMAT('%.2f', ShippingFee) AS ShippingFee,
  FORMAT('%.2f', ShippingFeeVat) AS ShippingFeeVat,
  FORMAT('%.2f', TotalAmount) AS TotalAmount,
  FORMAT('%.2f', Discount) AS Discount,
  'paid' AS TransactionStatus,
  CASE source_submission_status
    WHEN 'ITEM_SUBMISSION_STATUS_READY_TO_SUBMIT' THEN 'PENDING'
    WHEN 'ITEM_SUBMISSION_STATUS_PRESUBMITTED' THEN 'PRE-SUBMITTED'
    WHEN 'ITEM_SUBMISSION_STATUS_SUBMITTED' THEN 'SUBMITTED'
    WHEN 'ITEM_SUBMISSION_STATUS_PENDING' THEN 'PENDING'
    ELSE source_submission_status
  END AS SubmissionStatus,
  CASE source_approval_status
    WHEN 'ITEM_APPROVAL_STATUS_APPROVED' THEN 'APPROVED'
    WHEN 'ITEM_APPROVAL_STATUS_REJECTED' THEN 'REJECTED'
    WHEN 'ITEM_APPROVAL_STATUS_PENDING' THEN 'PENDING'
    WHEN 'ITEM_APPROVAL_STATUS_POLICY_UPLOADED' THEN 'POLICY UPLOADED'
    ELSE source_approval_status
  END AS ApprovalStatus,
  CASE source_payment_status
    WHEN 'SUCCESSFUL' THEN 'Fully paid'
    WHEN 'PENDING' THEN 'Not fully paid'
    ELSE source_payment_status
  END AS PaymentStatus,
  FORMAT('%.2f', ExpectedReceived) AS ExpectedReceived,
  FORMAT('%.2f', ActualReceived) AS ActualReceived,
  CAST(0 AS INT64) AS InterestThisPeriod,
  CAST(0 AS INT64) AS PrincipleThisPeriod,
  InterestEIRThisPeriod,
  CAST(0 AS INT64) AS PrincipleEIRThisPeriod,
  FORMAT_DATE('%d%m%Y', PaymentDate) AS PaymentDate,
  Period,
  CAST(1 AS INT64) AS TotalPeriods,
  CAST(0 AS INT64) AS PendingPayment,
  CASE
    WHEN source_payment_method = 'EDC' THEN 'EDC EDC'
    WHEN source_payment_method = 'CASH'
      AND source_payment_channel = 'SERVICE_PROVIDER_UNSPECIFIED' THEN 'TRF Transfer'
    WHEN source_payment_method = 'BANK_TRANSFER' THEN 'TRF Transfer'
    WHEN source_payment_method = 'DIRECT_PAYMENT'
      AND source_payment_channel = 'SERVICE_PROVIDER_UNSPECIFIED'
      THEN 'DPM จ่ายตรงกับบริษัทประกัน'
    WHEN source_payment_method = 'EDC' THEN 'EDC EDC'
    WHEN source_payment_method = 'ONLINECARD'
      AND source_payment_channel IN ('OMISE', 'RCB') THEN 'OMC Omise Credit Card'
    WHEN source_payment_method = 'QR_CODE'
      AND source_payment_channel = 'RABBIT_CASH' THEN 'RCB-Rabbit Card' -- 2026-11-24 Rabbit Card Gateway: FA spec (Mo, 2026-09-30) One-Time RCB = RCB-Rabbit Card
    WHEN source_payment_method = 'QR_CODE'
      AND source_payment_channel IN ('OMISE', 'RCB') THEN 'OME Omise QR Prompt Pay'
    ELSE 'TRF Transfer'
  END AS PaymentMethod,
  CASE
    WHEN source_payment_method = 'EDC' THEN `pacific-plating-282708.sap_integration_v3.fn_rcb_payment_mapping`('EDC', source_payment_channel).sap_payment_channel
    WHEN source_payment_method = 'CASH'
      AND source_payment_channel = 'SERVICE_PROVIDER_UNSPECIFIED' THEN 'RCB-Transfer-อื่นๆ'
    WHEN source_payment_method = 'BANK_TRANSFER'
      AND source_payment_channel = 'KASIKORN' THEN 'RCB-Transfer-KBANK'
    WHEN source_payment_method = 'BANK_TRANSFER'
      AND source_payment_channel = 'KRUNGSRI' THEN 'RCB-Transfer-BAY'
    WHEN source_payment_method = 'BANK_TRANSFER'
      AND source_payment_channel = 'KRUNGTHAI' THEN 'RCB-Transfer-KTB'
    WHEN source_payment_method = 'BANK_TRANSFER'
      AND source_payment_channel = 'SCB' THEN 'RCB-Transfer-SCB'
    WHEN source_payment_method = 'DIRECT_PAYMENT'
      AND source_payment_channel = 'SERVICE_PROVIDER_UNSPECIFIED' THEN 'RCB-DIRECT PAYMENT'
    WHEN source_payment_method = 'EDC'
      AND source_payment_channel = 'BANGKOK_BANK' THEN 'RCB-EDC-BBL'
    WHEN source_payment_method = 'EDC'
      AND source_payment_channel = 'KASIKORN' THEN 'RCB-EDC-KBANK'
    WHEN source_payment_method = 'EDC'
      AND source_payment_channel = 'KRUNGSRI' THEN 'RCB-EDC-BAY'
    WHEN source_payment_method = 'EDC'
      AND source_payment_channel = 'KRUNGTHAI' THEN 'RCB-EDC-KTB'
    WHEN source_payment_method = 'EDC'
      AND source_payment_channel = 'SCB' THEN 'RCB-EDC-SCB'
    WHEN source_payment_method = 'EDC'
      AND source_payment_channel = 'UOB' THEN 'RCB-EDC-UOB'
    WHEN source_payment_method = 'ONLINECARD'
      AND source_payment_channel IN ('OMISE', 'RCB') THEN 'RCB-Omise Credit Card-BAY'
    WHEN source_payment_method = 'QR_CODE'
      AND source_payment_channel = 'RABBIT_CASH' THEN 'RCB-Rabbit Card' -- 2026-11-24 Rabbit Card Gateway: FA spec (Mo, 2026-09-30) One-Time RCB = RCB-Rabbit Card
    WHEN source_payment_method = 'QR_CODE'
      AND source_payment_channel IN ('OMISE', 'RCB') THEN 'RCB-Omise QR Prompt Pay-BAY'
    ELSE 'RCB-Transfer-อื่นๆ'
  END AS PaymentChannel,
  FORMAT_DATE('%d%m%Y', DATE(charge_create_time, 'Asia/Bangkok')) AS ExpectedDate,
  RefOrder,
  CAST(0 AS INT64) AS RefundAmountBeforeFee,
  CAST(0 AS INT64) AS RefundAmountAfterFee,
  BillingAddress,
  FORMAT_DATE('%d%m%Y', CURRENT_DATE('Asia/Bangkok')) AS BatchRunDate
FROM calculated
ORDER BY OrderID, OrderItem, Period, InvoiceNo
),
-- FIX 2026-11-06 (Boat): InsuranceProduct must follow the master.
-- Motor rows: only 'Motor' or 'MotorBike'.
-- NonMotor rows: the value SAP already holds for the item, else the Strapi plan name with any
-- leading "(...)" prefix removed (it can hold a customer ID or policy number), cut to 30
-- characters, else the value computed above.
ip_sap AS (
  SELECT U_OrderItem AS OrderItem, ANY_VALUE(U_InsuranceProduct) AS ip
  FROM `pacific-plating-282708.sap_integration_v2.SAP_LIVE_FULL`
  WHERE U_OrderItem IN (SELECT OrderItem FROM base)
    AND NULLIF(TRIM(U_InsuranceProduct), '') IS NOT NULL
  GROUP BY U_OrderItem
  HAVING COUNT(DISTINCT U_InsuranceProduct) = 1
),
ip_strapi AS (
  SELECT i.human_id AS OrderItem, ANY_VALUE(RTRIM(SUBSTR(TRIM(REGEXP_REPLACE(TRIM(p.name), r'^\([^)]*\)\s*', '')), 1, 30))) AS ip
  FROM `pacific-plating-282708.careos.careos_order_items` i
  JOIN `pacific-plating-282708.careos.rf_strapi_prod_plans` p
    ON p.id = SAFE_CAST(REGEXP_EXTRACT(i.package, r'/packages/(\d+)_') AS INT64)
  WHERE i.human_id IN (SELECT OrderItem FROM base)
    AND NULLIF(TRIM(REGEXP_REPLACE(TRIM(p.name), r'^\([^)]*\)\s*', '')), '') IS NOT NULL
  GROUP BY i.human_id
  HAVING COUNT(DISTINCT RTRIM(SUBSTR(TRIM(REGEXP_REPLACE(TRIM(p.name), r'^\([^)]*\)\s*', '')), 1, 30))) = 1
)
SELECT base.* REPLACE (
  CASE
    WHEN base.InsuranceGroup = 'Motor'
      THEN IF(UPPER(TRIM(base.InsuranceProduct)) = 'MOTORBIKE', 'MotorBike', 'Motor')
    ELSE COALESCE(ip_sap.ip, ip_strapi.ip, base.InsuranceProduct)
  END AS InsuranceProduct
)
FROM base
LEFT JOIN ip_sap USING (OrderItem)
LEFT JOIN ip_strapi USING (OrderItem)
ORDER BY OrderID, OrderItem, Period, InvoiceNo
;


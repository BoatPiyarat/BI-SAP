-- Full source-only legacy root-fix proposal for:
--   pacific-plating-282708.sap_integration_v2.04_new order credit shell
-- Live-derived; one surgical RCB/RCL routing fix; no DDL and no deployment.

 -- 11/04/2024
 -- 09/12/2024 Haruethai Update Column 'InsuranceGroup', 'InsuranceType', 'InsuranceProduct' for order NONMOTOR on CareOs
 -- 16/03/2025 Piyarat excludes credit shell(new order from cancel change order) and correct ref.orders from CareOS

WITH

charges AS (
  SELECT * ,
    ROW_NUMBER() OVER (PARTITION BY transaction_id ORDER BY create_time) AS charge_rank
  FROM `pacific-plating-282708.careos.carepay_charges` 
  WHERE status = 'SUCCESSFUL' 
  AND service_provider <> 'RABBIT_LENDING'
), 
changes AS  (
  SELECT * FROM `pacific-plating-282708.careos.cancelled_change_orders` 
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

compu_detail AS (
  SELECT
    orders.human_id AS order_id,
    CASE
      WHEN order_items.gross_premium IS NULL THEN 0
      ELSE order_items.gross_premium
  END
    AS gross_premium
  FROM
    `pacific-plating-282708.careos.careos_order_items` order_items
  LEFT JOIN
    `pacific-plating-282708.careos.careos_orders` orders
  ON
    order_items.order_id = orders.id
  WHERE
    order_items.packagetype ='mandatoryPackages'
    AND orders.product = 'products/car-insurance'
    AND order_items.policy_start_date >= '2025-01-01' 
    ),

onetime_master AS (
  SELECT
    DISTINCT CAST(charges.amount AS FLOAT64) AS charges_amount,
    order_items.motor_item_type,
    order_items.packagetype,
    charges.service_provider,
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
  END
    AS TotalEIR,
    CASE
      WHEN transaction_snapshot_price_summaries.interest_amount IS NULL THEN 0
      ELSE ROUND(((ROUND((1 / 100) * transaction_snapshot_price_summaries.interest_amount,2) * 3.3) / 103.3),2)
  END
    AS TotalSBT,
    CASE
      WHEN transaction_snapshot_price_summaries.processing_fee_amount IS NULL THEN 0
      ELSE ROUND (ROUND((1 / 100) * transaction_snapshot_price_summaries.processing_fee_amount,2) * (100/107),2)
  END
    AS ProcessingFee_master,
    CASE
      WHEN transaction_snapshot_price_summaries.processing_fee_amount IS NULL THEN 0
      ELSE ROUND(ROUND((1 / 100) * transaction_snapshot_price_summaries.processing_fee_amount,2) - (ROUND((1 / 100) * transaction_snapshot_price_summaries.processing_fee_amount,2) * (100/107)),2)
  END
    AS ProcessingFeeVat_master,
    CASE
      WHEN transaction_snapshot_price_summaries.shipment_fee IS NULL THEN 0
      ELSE ROUND(ROUND((1 / 100) * transaction_snapshot_price_summaries.shipment_fee,2) * (100/107),2)
  END
    AS ShippingFee_master,
    CASE
      WHEN transaction_snapshot_price_summaries.shipment_fee IS NULL THEN 0
      ELSE ROUND(ROUND((1 / 100) * transaction_snapshot_price_summaries.shipment_fee,2) - ROUND((1 / 100) * transaction_snapshot_price_summaries.shipment_fee,2) * (100/107),2)
  END
    AS ShippingFeeVat_master,
    COALESCE(ROUND((1 / 100) * transaction_snapshot_price_summaries.discount_amount,2),0) AS Discount_master,
    charges.status AS TransactionStatus,
    order_items.submission_status AS SubmissionStatus,
    order_items.approval_status AS ApprovalStatus,
    transactions.status AS PaymentStatus,
    ROUND(((1 / 100) * charges.amount),2) AS ActualReceived_master, -- จำนวนเงินที่ลูกค้าจ่ายมาจริงๆ ห้ามเปลี่ยน 
    0 AS PrincipleThisPeriod,
    transaction_snapshot_price_summaries.interest_amount AS InterestEIRThisPeriod,
    0 AS PrincipleEIRThisPeriod,
    CASE WHEN sap.BatchRunDate is NOT NULL AND PARSE_TIMESTAMP('%d%m%Y', sap.BatchRunDate) >= TIMESTAMP(DATE_TRUNC(CURRENT_DATE(), MONTH)) 
      THEN PARSE_TIMESTAMP('%d%m%Y', sap.BatchRunDate)
      WHEN sap.BatchRunDate is NOT NULL AND PARSE_TIMESTAMP('%d%m%Y', sap.BatchRunDate) < TIMESTAMP(DATE_TRUNC(CURRENT_DATE(), MONTH))
      THEN TIMESTAMP(CURRENT_DATE())
      WHEN COALESCE(charges.payment_date, charges.update_time) < TIMESTAMP(DATE_TRUNC('2026-01-01', MONTH)) THEN TIMESTAMP(DATE_TRUNC('2026-01-01', MONTH))
      ELSE COALESCE(charges.payment_date, charges.update_time)
  END
    AS PaymentDate,
    charges.installment_number AS Period,
    1 AS TotalPeriods,
    0 AS PendingPayment,
    charges.create_time AS ExpectedDate,
    charges.id AS charges_id,
    CASE
      WHEN charges.third_party_id IS NULL AND charges.status = 'SUCCESSFUL' THEN CONCAT(charge_rank,"_",order_items.human_id)
      WHEN charges.third_party_id IS NULL
    AND charges.status <> 'SUCCESSFUL' THEN ''
      ELSE charges.third_party_id
  END
    AS InvoiceNo,
    order_items.insurer AS InsurerCode,
    order_items.product AS InsuranceGroup,
    order_items.motor_item_type AS InsuranceType,
    CASE
      WHEN JSON_VALUE(orders.data, '$.oicCode') IN ('TYPE_610', 'TYPE_620', 'TYPE_630') THEN 'MotorBike'
      WHEN JSON_VALUE(orders.data, '$.oicCode') IS NOT NULL THEN 'Motor'
      ELSE order_items.product
  END
    AS InsuranceProduct,
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
    CASE
      WHEN JSON_VALUE(orders.data, '$.policyHolder.isCompany') ='true' AND JSON_VALUE(orders.data, '$.policyHolder.companyTaxId') IS NULL THEN '-'
      WHEN JSON_VALUE(orders.data, '$.policyHolder.isCompany') ='true'
    AND JSON_VALUE(orders.data, '$.policyHolder.companyTaxId') IS NOT NULL THEN JSON_VALUE(orders.data, '$.policyHolder.companyTaxId')
      WHEN JSON_VALUE(orders.data, '$.idNumber') IS NULL OR JSON_VALUE(orders.data, '$.idNumber') IN ('', ' ') THEN '-'
      ELSE JSON_VALUE(orders.data, '$.idNumber')
  END
    AS InsuredID,
    JSON_VALUE(orders.data, '$.policyHolder.title') AS Title,
    COALESCE(JSON_VALUE(orders.data, '$.policyHolder.firstName'),JSON_VALUE(orders.data, '$.policyHolder.policyAddress.companyName')) AS FirstName,
    JSON_VALUE(orders.data, '$.policyHolder.lastName') AS LastName,
    0 AS RefundAmountBeforeFee,
    0 AS RefundAmountAfterFee,
    CASE
      WHEN JSON_VALUE(orders.data, '$.policyHolder.policyAddress.isBillingAddress') = 'true' THEN CONCAT( COALESCE(JSON_VALUE(orders.data, '$.policyHolder.policyAddress.fullName'),JSON_VALUE(orders.data, '$.policyHolder.policyAddress.companyName')), ', ', JSON_VALUE(orders.data, '$.policyHolder.policyAddress.address'), ', ', JSON_VALUE(orders.data, '$.policyHolder.policyAddress.subDistrict'), ', ', JSON_VALUE(orders.data, '$.policyHolder.policyAddress.district'), ', ', JSON_VALUE(orders.data, '$.policyHolder.policyAddress.province'), ', ', JSON_VALUE(orders.data, '$.policyHolder.policyAddress.postCode') )
      ELSE CONCAT( JSON_VALUE(orders.data, '$.policyHolder.billingAddress.fullName'), ', ', JSON_VALUE(orders.data, '$.policyHolder.billingAddress.address'), ', ', JSON_VALUE(orders.data, '$.policyHolder.billingAddress.subDistrict'), ', ', JSON_VALUE(orders.data, '$.policyHolder.billingAddress.district'), ', ', JSON_VALUE(orders.data, '$.policyHolder.billingAddress.province'), ', ', JSON_VALUE(orders.data, '$.policyHolder.billingAddress.postCode') )
  END
    AS BillingAddress,
    CURRENT_DATE() AS BatchRunDate,
    'RCB' AS CompanyDB,
    ch.old_human_id AS RefOrder,
    ROW_NUMBER() OVER (PARTITION BY order_items.human_id ORDER BY order_items.create_time,charges.create_time) AS cmi_rank
  FROM
    orders
  LEFT JOIN
    leads
  ON
    CONCAT('leads/',leads.id) = orders.lead
  LEFT JOIN
    transactions
  ON
    CONCAT('transactions/',transactions.id) = orders.payment
  LEFT JOIN
    follow_ups
  ON
    follow_ups.transaction_id = transactions.id
  LEFT JOIN
    charges
  ON
    charges.transaction_id = transactions.id
  LEFT JOIN
    order_items
  ON
    order_items.order_id = orders.id
  LEFT JOIN
    transaction_snapshots
  ON
    transaction_snapshots.transaction_id = transactions.id
  LEFT JOIN
    transaction_snapshot_price_summaries
  ON
    transaction_snapshot_price_summaries.snapshot_id = transaction_snapshots.id
  LEFT JOIN changes ch 
  ON ch.current_human_id = orders.human_id
  LEFT JOIN pacific-plating-282708.sap_integration_v2.SAP_LIVE_FULL sap 
  ON sap.U_OrderID = ch.old_human_id AND sap.U_InsuranceType <>'MOTOR_TYPE_COMPULSORY'

  WHERE
    charges.status = 'SUCCESSFUL'
    AND service_provider <> 'RABBIT_LENDING'
    -- Root fix: RABBIT_CARE_INSTALLMENT belongs to RCL, never the RCB CreditShell flow.
    AND transactions.payment_option != 'RABBIT_CARE_INSTALLMENT'
    AND orders.product = 'products/car-insurance'
    AND order_items.policy_start_date >= '2025-01-01' 
    AND ch.current_human_id IS NOT NULL
    ),

onetime_master_go AS (
  SELECT
    distinct *,
    CASE
      WHEN packagetype='mandatoryPackages' THEN 0
      ELSE WHT_master
  END
    AS WHT,
    CASE
      WHEN packagetype='mandatoryPackages' THEN 0
      ELSE ProcessingFee_master
  END
    AS ProcessingFee,
    CASE
      WHEN packagetype='mandatoryPackages' THEN 0
      ELSE ProcessingFeeVat_master
  END
    AS ProcessingFeeVat,
    CASE
      WHEN packagetype='mandatoryPackages' THEN 0
      ELSE ShippingFee_master
  END
    AS ShippingFee,
    CASE
      WHEN packagetype='mandatoryPackages' THEN 0
      ELSE ShippingFeeVat_master
  END
    AS ShippingFeeVat,
    CASE
      WHEN packagetype='mandatoryPackages' THEN TotalPremium
      ELSE ROUND((TotalPremium)+TotalEIR+TotalSBT+ProcessingFee_master+ProcessingFeeVat_master+ShippingFee_master+ShippingFeeVat_master,2)
  END
    AS TotalAmount,
    CASE
      WHEN packagetype='mandatoryPackages' THEN 0
      ELSE Discount_master
  END
    AS Discount,
    CASE
      WHEN packagetype='mandatoryPackages' THEN compu_detail.gross_premium
      WHEN charge_rank = 1 
        THEN ROUND((TotalPremium)+TotalEIR+TotalSBT+ProcessingFee_master+ProcessingFeeVat_master+ShippingFee_master+ShippingFeeVat_master-Discount_master,2)
      WHEN charge_rank  <> 1 
        THEN 0
  END AS ExpectedReceived,
    CASE
      WHEN packagetype='mandatoryPackages' THEN compu_detail.gross_premium
      WHEN packagetype <>'mandatoryPackages' AND charge_rank <> 1 THEN coalesce(ActualReceived_master, ROUND(0.01*TotalPremium,2))
      WHEN compu_detail.gross_premium IS NOT NULL AND packagetype <>'mandatoryPackages' AND charge_rank = 1 THEN ROUND(ActualReceived_master-compu_detail.gross_premium,2)
      ELSE coalesce(ActualReceived_master, ROUND(0.01*TotalPremium,2) )
  END AS ActualReceived,
    0 AS InterestThisPeriod
  FROM
    onetime_master
  LEFT JOIN
    compu_detail
  ON
    compu_detail.order_id=onetime_master.OrderID
  LEFT JOIN
    charges
  ON
    charges.id = onetime_master.charges_id
  LEFT JOIN changes ch on ch.current_human_id = onetime_master.OrderID
  WHERE 
      charges.status = 'SUCCESSFUL'
      AND charges.service_provider != 'ICOLLECTION'
      AND charges.service_provider <> 'RABBIT_LENDING' 
      AND NOT (cmi_rank <> 1 AND motor_item_type = 'MOTOR_TYPE_COMPULSORY')
AND onetime_master.OrderID IN (SELECT current_human_id FROM changes ) 
  )

select distinct
CompanyDB	,
OrderID	,
OrderItem	,
InvoiceNo	,
CAST(FORMAT_DATE('%d%m%Y', OrderDate) AS STRING) AS OrderDate,
InsuredID	,
CASE
WHEN Title = 'KHUN' THEN 'คุณ'
WHEN Title = 'MISS' THEN 'นางสาว'
WHEN Title = 'MR' THEN 'นาย'
WHEN Title = 'MRS' THEN 'นาง'
ELSE ''
END AS Title,
FirstName	,
LastName	, 
TRIM(InsurerCode,'insurer/') AS InsurerCode,

CASE 
  WHEN InsuranceGroup = 'products/car-insurance' THEN 'Motor'
  WHEN InsuranceGroup = 'products/health-insurance' THEN 'Health'
  WHEN InsuranceGroup = 'products/travel-insurance' THEN 'TA'
  ELSE InsuranceGroup
END AS InsuranceGroup,
------------------------
CASE 
  WHEN (InsuranceType IS NULL OR InsuranceType = ' ' ) AND InsuranceGroup = 'products/health-insurance' THEN 'Health'
  WHEN (InsuranceType IS NULL OR InsuranceType = ' ' ) AND InsuranceGroup = 'products/travel-insurance' THEN 'TA'
  ELSE InsuranceType
END AS InsuranceType,
--------------------
CASE
  WHEN InsuranceGroup = 'products/car-insurance' THEN 'Motor'
  WHEN InsuranceGroup = 'products/health-insurance' THEN 'Health'
  WHEN InsuranceGroup = 'products/travel-insurance' THEN 'TA'  
  ELSE InsuranceGroup
END AS InsuranceProduct,
--------------------
'Insurance' ProductType,
CASE
  WHEN PolicyType = 'LEAD_TYPE_RENEWAL' THEN 'R'
  ELSE 'N'
END AS PolicyType,
Endorse,
CAST(FORMAT_DATE('%d%m%Y', PolicyDate) AS STRING) AS PolicyDate,
PolicyNo	,
CAST(EndorsementNo AS STRING)	EndorsementNo,
ChassisNo	,
LicensePlate	,
FORMAT('%.2f',GrossPremium) GrossPremium	,
FORMAT('%.2f',StampDuty) StampDuty	,
FORMAT('%.2f',VAT) VAT	,
FORMAT('%.2f',TotalPremium) TotalPremium	,
FORMAT('%.2f',WHT) WHT,
FORMAT('%.2f',TotalEIR) TotalEIR	,
FORMAT('%.2f',TotalSBT)	TotalSBT,
FORMAT('%.2f',ProcessingFee) ProcessingFee,
FORMAT('%.2f',ProcessingFeeVat) ProcessingFeeVat,
FORMAT('%.2f',ShippingFee) ShippingFee,
FORMAT('%.2f',ShippingFeeVat)	ShippingFeeVat,
FORMAT('%.2f',TotalAmount) TotalAmount	,
FORMAT('%.2f',Discount)	Discount,
    CASE 
      WHEN TransactionStatus = 'SUCCESSFUL' THEN 'paid'
      WHEN TransactionStatus = 'PENDING' THEN 'pending'
      WHEN TransactionStatus = 'FOLLOWUP_STATUS_PAID' THEN 'paid'
      WHEN TransactionStatus = 'FOLLOWUP_STATUS_PENDING' THEN 'pending'
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
InterestThisPeriod	,
PrincipleThisPeriod	,
InterestEIRThisPeriod	,
PrincipleEIRThisPeriod	,
CAST(FORMAT_DATE('%d%m%Y', PaymentDate) AS STRING) AS PaymentDate,
Period	,
TotalPeriods	,
PendingPayment	,
CASE WHEN PaymentMethod ='DIRECT_PAYMENT'and PaymentChannel='SERVICE_PROVIDER_UNSPECIFIED' THEN 'DPM จ่ายตรงกับบริษัทประกัน' ELSE 'Credit Shell' END AS PaymentMethod	,
CASE WHEN PaymentMethod ='DIRECT_PAYMENT'and PaymentChannel='SERVICE_PROVIDER_UNSPECIFIED' THEN 'RCB-DIRECT PAYMENT' ELSE 'RCB-Credit Shell' END AS PaymentChannel	,
CAST(FORMAT_DATE('%d%m%Y', ExpectedDate) AS STRING) AS ExpectedDate,
ch.old_human_id as RefOrder,
RefundAmountBeforeFee	,
RefundAmountAfterFee	,
BillingAddress	,
CAST(FORMAT_DATE('%d%m%Y', BatchRunDate) AS STRING) AS BatchRunDate,
from onetime_master_go
--left join get_charges_ref on onetime_master_go.InvoiceNo=get_charges_ref.third_party_id and get_charges_ref.order_id != onetime_master_go.OrderID
LEFT JOIN changes ch on ch.current_human_id = onetime_master_go.OrderID 

where 1=1
AND OrderDate >= '2025-01-01'
AND OrderID in (SELECT current_human_id FROM changes)


CREATE OR REPLACE VIEW `pacific-plating-282708.sap_integration_v2.rcb_backup_20250705` AS
 -- 11/04/2024
 -- 09/12/2024 Haruethai Update Column 'InsuranceGroup', 'InsuranceType', 'InsuranceProduct' for order NONMOTOR on CareOs
 -- 16/03/2025 Piyarat excludes credit shell(new order from cancel change order) and correct ref.orders from CareOS
 -- 4/July/2025 Piyarat fixed the price after discount in snapshot price summary

WITH
get_charges_ref AS (
  select charges.third_party_id , orders.human_id as order_id , orders.payment 
  from `pacific-plating-282708.careos.carepay_charges` charges
  left join `pacific-plating-282708.careos.careos_orders` orders 
  on orders.payment =  CONCAT('transactions/',charges.transaction_id) 
  where  
   status = 'SUCCESSFUL' 
  and orders.human_id is not null
  AND orders.product = 'products/car-insurance'
  AND (service_provider <> 'RABBIT_LENDING' OR (service_provider IS NULL AND charges.payment_method = 'EDC'))
),

charges AS (
  SELECT * FROM `pacific-plating-282708.careos.carepay_charges`
  WHERE status = 'SUCCESSFUL' 
  AND (service_provider <> 'RABBIT_LENDING' OR (service_provider IS NULL AND payment_method = 'EDC'))
), 

follow_ups AS ( 
  SELECT * FROM `pacific-plating-282708.careos.carepay_follow_ups`
),
 
payment_options AS ( 
  SELECT * FROM `pacific-plating-282708.careos.carepay_payment_options`
),

payment_records AS ( 
  SELECT * FROM `pacific-plating-282708.careos.carepay_payment_records`
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
--14-Jun-2025 removed timee -- some of RCB orders missing--
charge_one as (
SELECT charges.id as charges_id , charges.transaction_id
FROM charges right join (
select charges.transaction_id as id --, min(charges.create_time) as timee
FROM orders 
LEFT JOIN transactions ON CONCAT('transactions/',transactions.id) = orders.payment
LEFT JOIN charges ON charges.transaction_id = transactions.id 
where charges.status = 'SUCCESSFUL' 
and (charges.service_provider != 'ICOLLECTION' OR (charges.service_provider IS NULL AND charges.payment_method = 'EDC'))
AND transactions.installments = 1
AND (charges.service_provider <> 'RABBIT_LENDING' OR (charges.service_provider IS NULL AND charges.payment_method = 'EDC'))
 -- group by charges.transaction_id
) as minn on minn.id = charges.transaction_id --and charges.create_time=minn.timee
)
,
check_order_items as (
select orders.human_id as OrderID , count(order_items) as no_items
FROM `pacific-plating-282708.careos.careos_order_items` order_items
LEFT JOIN `pacific-plating-282708.careos.careos_orders` orders
    ON order_items.order_id = orders.id
where orders.product = 'products/car-insurance'
AND policy_start_date >= '2025-01-01'
group by orders.human_id
),
compu_detail as (
SELECT 
orders.human_id as order_id,
case when order_items.gross_premium is null then 0 else order_items.gross_premium end as gross_premium
FROM `pacific-plating-282708.careos.careos_order_items` order_items
LEFT JOIN `pacific-plating-282708.careos.careos_orders` orders
    ON order_items.order_id = orders.id
where order_items.packagetype ='mandatoryPackages'
AND orders.product = 'products/car-insurance'
AND order_items.policy_start_date >= '2025-01-01'

),

onetime_master as (
select distinct
CAST(charges.amount AS FLOAT64) as charges_amount,
order_items.motor_item_type,
order_items.packagetype,
charges.service_provider, 
orders.create_time AS OrderDate,
charges.status ,
orders.human_id,
order_items.human_id as OrderItem ,
order_items.price price,
order_items.net_premium AS GrossPremium,
order_items.stamp_duty AS StampDuty,
order_items.vat_amount AS VAT,
order_items.gross_premium TotalPremium,
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
--CASE WHEN discount is not NULL AND transaction_snapshot_price_summaries.discount_amount IS NULL THEN ROUND(CAST(discount AS INT64),2)--add 01062025 ELSE 
ROUND((1 / 100) * transaction_snapshot_price_summaries.discount_amount,2) AS Discount_master,
charges.status AS TransactionStatus,
order_items.submission_status AS SubmissionStatus,
order_items.approval_status AS ApprovalStatus,
transactions.status AS PaymentStatus,
ROUND(((1 / 100) * charges.amount),2) AS ActualReceived_master, -- จำนวนเงินที่ลูกค้าจ่ายมาจริงๆ ห้ามเปลี่ยน
-- CASE WHEN packagetype = 'mandatoryPackages' THEN 0 ELSE ROUND((TotalEIR)/(TotalPeriods-1),2) END END AS InterestThisPeriod 
-- 0 as InterestThisPeriod,
0 AS PrincipleThisPeriod,
transaction_snapshot_price_summaries.interest_amount AS InterestEIRThisPeriod,
0 AS PrincipleEIRThisPeriod,
CASE 
  WHEN COALESCE(charges.payment_date, charges.update_time) < TIMESTAMP(DATE_TRUNC(CURRENT_DATE(), MONTH)) 
    THEN TIMESTAMP(DATE_TRUNC(CURRENT_DATE(), MONTH))
  ELSE COALESCE(charges.payment_date, charges.update_time) 
END AS PaymentDate,
charges.installment_number AS Period,
-- 1 AS TotalPeriods, --- transactions.installments ผ่อนผ่านบัตรแต่รูดจ่ายเต็มจะเป็นจำนวนที่ผ่อนกับบัตร
1 as TotalPeriods,
0 as PendingPayment,
charges.create_time as ExpectedDate	,
-- COALESCE(charges.due_date,charges.create_time) as ExpectedDate	,

charges.id as charges_id,
case 
  when charges.third_party_id is null AND charges.status = 'SUCCESSFUL' then order_items.human_id
  WHEN charges.third_party_id is null AND charges.status <> 'SUCCESSFUL' THEN ''
  else  charges.third_party_id 
end as InvoiceNo,
order_items.insurer AS InsurerCode,
order_items.product AS InsuranceGroup,
order_items.motor_item_type AS InsuranceType,
CASE WHEN JSON_VALUE(orders.data, '$.oicCode') in ('TYPE_610','TYPE_620', 'TYPE_630') THEN 'MotorBike'  
     WHEN JSON_VALUE(orders.data, '$.oicCode') is not null THEN 'Motor'
ELSE order_items.product
END AS InsuranceProduct,
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
WHEN JSON_VALUE(orders.data, '$.policyHolder.isCompany') ='true' AND JSON_VALUE(orders.data, '$.policyHolder.companyTaxId') is NULL then '-'
WHEN JSON_VALUE(orders.data, '$.policyHolder.isCompany') ='true' AND JSON_VALUE(orders.data, '$.policyHolder.companyTaxId') is NOT NULL then JSON_VALUE(orders.data, '$.policyHolder.companyTaxId') 
WHEN JSON_VALUE(orders.data, '$.idNumber') IS NULL OR JSON_VALUE(orders.data, '$.idNumber') in ('', ' ') THEN '-' ELSE JSON_VALUE(orders.data, '$.idNumber') end as InsuredID ,
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
where 
    charges.status = 'SUCCESSFUL'
AND (service_provider <> 'RABBIT_LENDING' OR (service_provider IS NULL AND charges.payment_method = 'EDC'))
AND orders.product = 'products/car-insurance'
AND order_items.policy_start_date >= '2025-01-01'
) , 

onetime_master_go as (
select * ,
case when packagetype='mandatoryPackages' then 0 else WHT_master end as WHT	, 
case when packagetype='mandatoryPackages' then 0 else ProcessingFee_master end	as	ProcessingFee	,
case when packagetype='mandatoryPackages' then 0 else ProcessingFeeVat_master end	as	ProcessingFeeVat	,
case when packagetype='mandatoryPackages' then 0 else ShippingFee_master end	as	ShippingFee	,
case when packagetype='mandatoryPackages' then 0 else ShippingFeeVat_master end	as	ShippingFeeVat ,
case when packagetype='mandatoryPackages' then TotalPremium else 
ROUND((TotalPremium)+TotalEIR+TotalSBT+ProcessingFee_master+ProcessingFeeVat_master+ShippingFee_master+ShippingFeeVat_master,2)	end as TotalAmount	,
--ROUND((TotalPremium-WHT_master)+TotalEIR+TotalSBT+ProcessingFee_master+ProcessingFeeVat_master+ShippingFee_master+ShippingFeeVat_master,2)	end as TotalAmount	, -- สูตรที่ถูก - แต่บน sap ผิด (เอา wht ออกเพื่อให้เข้า sap ได้)
case when packagetype='mandatoryPackages' then 0 else Discount_master end	as	Discount	, 
case when packagetype='mandatoryPackages' then compu_detail.gross_premium 
  else case when compu_detail.gross_premium is null then ActualReceived_master  else ROUND((TotalPremium)+TotalEIR+TotalSBT+ProcessingFee_master+ProcessingFeeVat_master+ShippingFee_master+ShippingFeeVat_master-Discount_master,2) end 
end as ExpectedReceived	,
case when packagetype='mandatoryPackages' then compu_detail.gross_premium 
  else case when compu_detail.gross_premium is null then ActualReceived_master  else ROUND(ActualReceived_master-compu_detail.gross_premium,2) end 
end as ActualReceived	,
-- CASE WHEN packagetype = 'mandatoryPackages' THEN 0 ELSE ROUND((TotalEIR)/(TotalPeriods-1),2) END AS InterestThisPeriod ,
0 as InterestThisPeriod  

from onetime_master 
left join compu_detail on compu_detail.order_id=onetime_master.human_id
left join check_order_items on check_order_items.OrderID = onetime_master.human_id 
where 1=1
and onetime_master.charges_id in (select distinct charges_id from charge_one) -- ชำระเต็มงวดแรก  -- งวด 2 ทำ sub query เพิ่ม 
AND onetime_master.human_id  not in (SELECT current_human_id FROM `pacific-plating-282708.careos.cancelled_change_orders`  )
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
InterestThisPeriod	,
PrincipleThisPeriod	,
InterestEIRThisPeriod	,
PrincipleEIRThisPeriod	,
CAST(FORMAT_DATE('%d%m%Y', PaymentDate) AS STRING) AS PaymentDate,
Period	,
TotalPeriods	,
PendingPayment	,
CASE
    WHEN PaymentMethod = 'EDC' THEN 'EDC EDC'
    WHEN PaymentMethod ='CASH'and PaymentChannel='SERVICE_PROVIDER_UNSPECIFIED' THEN 'TRF Transfer'
-- WHEN PaymentMethod ='CASH'and PaymentChannel='SERVICE_PROVIDER_UNSPECIFIED' THEN 'ดูใน carepay '
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
WHEN PaymentMethod ='QR_CODE'and PaymentChannel='OMISE' THEN 'OME Omise QR Prompt Pay'
WHEN PaymentMethod ='QR_CODE'and PaymentChannel='RABBIT_LENDING' THEN 'OME Omise QR Prompt Pay'
WHEN PaymentMethod ='QR_CODE'and PaymentChannel='RCB' THEN 'OME Omise QR Prompt Pay'
-- WHEN PaymentMethod ='DIRECT_PAYMENT'and PaymentChannel='SERVICE_PROVIDER_UNSPECIFIED' THEN 'TRF Transfer'
WHEN PaymentMethod ='EDC'and PaymentChannel='KRUNGTHAI' THEN 'EDC EDC'
WHEN PaymentMethod ='QR_CODE'and PaymentChannel='RABBIT_LENDING' THEN 'OME Omise QR Prompt Pay'
WHEN PaymentMethod ='all'and PaymentChannel='all' THEN 'RCL-CMI-channel'
ELSE   'TRF Transfer'
END AS PaymentMethod	,
CASE
    WHEN PaymentMethod = 'EDC' THEN `pacific-plating-282708.sap_integration_v3.fn_rcb_payment_mapping`('EDC', PaymentChannel).sap_payment_channel
    WHEN PaymentMethod ='CASH'and PaymentChannel='SERVICE_PROVIDER_UNSPECIFIED' THEN 'RCB-Transfer-อื่นๆ'
-- WHEN PaymentMethod ='CASH'and PaymentChannel='SERVICE_PROVIDER_UNSPECIFIED' THEN 'fix มือรอ list - Change Order RCL'
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
WHEN PaymentMethod ='QR_CODE'and PaymentChannel='OMISE' THEN 'RCB-Omise QR Prompt Pay-BAY'
WHEN PaymentMethod ='QR_CODE'and PaymentChannel='RABBIT_LENDING' THEN 'RCB-Omise QR Prompt Pay-BAY'
WHEN PaymentMethod ='QR_CODE'and PaymentChannel='RCB' THEN 'RCB-Omise QR Prompt Pay-BAY'
-- WHEN PaymentMethod ='DIRECT_PAYMENT'and PaymentChannel='SERVICE_PROVIDER_UNSPECIFIED' THEN 'RCL-Transfer-KTB'
-- WHEN PaymentMethod ='EDC'and PaymentChannel='KRUNGTHAI' THEN 'RCL-EDC-KTB'
WHEN PaymentMethod ='QR_CODE'and PaymentChannel='RABBIT_LENDING' THEN 'RCL-Omise QR Prompt Pay-BAY'
WHEN PaymentMethod ='all'and PaymentChannel='all' THEN 'RCL-CMI-channel'
ELSE 'RCB-Transfer-อื่นๆ'
END AS PaymentChannel	,
CAST(FORMAT_DATE('%d%m%Y', ExpectedDate) AS STRING) AS ExpectedDate,
ch.old_human_id as RefOrder,
RefundAmountBeforeFee	,
RefundAmountAfterFee	,
BillingAddress	,
CAST(FORMAT_DATE('%d%m%Y', BatchRunDate) AS STRING) AS BatchRunDate,
from onetime_master_go
left join get_charges_ref on onetime_master_go.InvoiceNo=get_charges_ref.third_party_id and get_charges_ref.order_id != onetime_master_go.OrderID
LEFT JOIN `pacific-plating-282708.careos.cancelled_change_orders`  ch on ch.current_human_id = onetime_master_go.OrderID
;

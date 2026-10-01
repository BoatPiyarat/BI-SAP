CREATE OR REPLACE VIEW `pacific-plating-282708.sap_data_engineer.sap_dashboard_carepay_cancelled` AS
 -- 11/04/2024
WITH
card_tokens AS (
  SELECT * FROM `pacific-plating-282708.careos.carepay_card_tokens`
),

charges AS (
  SELECT * FROM `pacific-plating-282708.careos.carepay_charges`
), 

contract_prices AS (
  SELECT * FROM `pacific-plating-282708.careos.carepay_contract_prices`
),

contract_records AS ( 
  SELECT * FROM `pacific-plating-282708.careos.carepay_contract_records`
),

contracts AS ( 
  SELECT id, lead_resource FROM `pacific-plating-282708.careos.carepay_contracts`
),

customer_tokens AS ( 
  SELECT * FROM `pacific-plating-282708.careos.carepay_customer_tokens`
),

follow_ups AS ( 
  SELECT * FROM `pacific-plating-282708.careos.carepay_follow_ups`
),

hydra_migrations AS ( 
  SELECT * FROM `pacific-plating-282708.careos.carepay_hydra_migrations`
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
charge_one as (
SELECT charges.id as charges_id , charges.transaction_id
FROM charges right join (
select charges.transaction_id as id , min(charges.create_time) as timee
FROM orders 
LEFT JOIN transactions ON CONCAT('transactions/',transactions.id) = orders.payment
LEFT JOIN charges ON charges.transaction_id = transactions.id 
where charges.status = 'SUCCESSFUL' 
and (charges.service_provider IS NULL OR charges.service_provider <> 'ICOLLECTION')
-- and orders.human_id = 'L77069632' 
group by charges.transaction_id
) as minn on minn.id = charges.transaction_id and charges.create_time=minn.timee
)
,
check_order_items as (
select orders.human_id as OrderID , count(order_items) as no_items
FROM `pacific-plating-282708.careos.careos_order_items` order_items
LEFT JOIN `pacific-plating-282708.careos.careos_orders` orders
    ON order_items.order_id = orders.id
where 1=1 
-- and order_items.is_cancelled is false
group by orders.human_id
-- group by order_items.order_id
),
compu_detail as (
SELECT 
orders.human_id as order_id,
-- order_items.human_id as OrderItem ,
case when order_items.gross_premium is null then 0 else order_items.gross_premium end as gross_premium
FROM `pacific-plating-282708.careos.careos_order_items` order_items
LEFT JOIN `pacific-plating-282708.careos.careos_orders` orders
    ON order_items.order_id = orders.id
where order_items.packagetype ='mandatoryPackages'
-- and order_items.is_cancelled is false
),
-- not_full_paid as (
--   SELECT 
-- -- o.is_fully_paid ,
-- o.human_id as order_id
-- --, c.*
-- FROM `pacific-plating-282708.careos.carepay_contracts` c
-- left join  `pacific-plating-282708.careos.careos_leads` l on CONCAT('leads/',l.id)=c.lead_resource
-- left join `pacific-plating-282708.careos.careos_orders` o  ON CONCAT('leads/',l.id) = o.lead
-- where c.status ='APPROVED'
-- and o.is_fully_paid is false
-- ),
onetime_master as (
select 
charges.amount as charges_amount,
-- orders.human_id ,
-- orders.create_time,
-- order_items.human_id ,
-- orders.is_fully_paid,
-- -- charges.service_provider,
-- -- charges.status ,
-- -- charges.amount,
-- -- orders.* 
-- -- transaction_snapshot_installment_details.add_ons,
-- order_items.price,
-- charges.installment_number as charges_installment_number,
-- transaction_snapshot_price_summaries.interest_amount,
-- charges.*,
-- follow_ups.*
------------------
order_items.motor_item_type,
order_items.packagetype,
charges.service_provider, 
orders.create_time AS OrderDate,
charges.status ,
-- charges.amount as receive_amount,
-- orders.* 
-- transaction_snapshot_installment_details.add_ons,
orders.human_id,
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
-- 'ROUND((TotalPremium-WHT)+TotalEIR+TotalSBT+ProcessingFee+ProcessingFeeVat+ShippingFee+ShippingFeeVat,2)' as TotalAmount,
-- ROUND((1 / 100) * transaction_snapshot_price_summaries.net_premium_amount,2) AS TotalAmount,
-- ROUND((TotalPremium-WHT)+TotalEIR+TotalSBT+ProcessingFee+ProcessingFeeVat+ShippingFee+ShippingFeeVat,2) AS TotalAmount,
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
COALESCE(charges.payment_date,charges.update_time) as PaymentDate	,
charges.installment_number AS Period,
-- 1 AS TotalPeriods, --- transactions.installments ผ่อนผ่านบัตรแต่รูดจ่ายเต็มจะเป็นจำนวนที่ผ่อนกับบัตร
1 as TotalPeriods,
0 as PendingPayment,
charges.create_time as ExpectedDate	,
-- COALESCE(charges.due_date,charges.create_time) as ExpectedDate	,

charges.id as charges_id,
case when charges.third_party_id is null then order_items.human_id else  charges.third_party_id end as InvoiceNo,
order_items.insurer AS InsurerCode,
order_items.product AS InsuranceGroup,
order_items.motor_item_type AS InsuranceType,
order_items.package AS InsuranceProduct,
leads.type AS PolicyType,
'N' AS Endorse,
order_items.policy_start_date AS PolicyDate,
order_items.policy_number AS PolicyNo,
NULL AS EndorsementNo, 
JSON_VALUE(orders.data, '$.chassisNumber') AS ChassisNo,
JSON_VALUE(orders.data, '$.carLicensePlate') AS LicensePlate,
charges.payment_method AS PaymentMethod,
charges.service_provider AS PaymentChannel,
-- JSON_VALUE(orders.data, '$.idNumber') AS InsuredID,
case when JSON_VALUE(orders.data, '$.policyHolder.isCompany') ='true' then 
JSON_VALUE(orders.data, '$.policyHolder.companyTaxId') else JSON_VALUE(orders.data, '$.idNumber') end as InsuredID ,
JSON_VALUE(orders.data, '$.policyHolder.title') AS Title,
COALESCE(JSON_VALUE(orders.data, '$.policyHolder.firstName'),JSON_VALUE(orders.data, '$.policyHolder.policyAddress.companyName')) AS FirstName,
JSON_VALUE(orders.data, '$.policyHolder.lastName') AS LastName, 
-- ROUND(refunds.amount * (100/107),2) AS RefundAmountBeforeFee,
-- refunds.amount AS RefundAmountAfterFee,
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
and follow_ups.id is null -- ไม่มีงวดต้องตาม = ไม่ผ่อน 
and (charges.service_provider IS NULL OR charges.service_provider <> 'ICOLLECTION')
-- and order_items.is_cancelled is false
---------- check installment
-- and installment_number > 1
-- and charges.service_provider = 'ICOLLECTION'
-- and installment_number = 2
-- and orders.human_id ='L77017526'
-- and orders.human_id IN ('L73722662','L73720932') 
-- and orders.human_id = 'L77017526' -- L77102544 fuck order 
-- and transaction_snapshot_price_summaries.interest_amount is not null -- มีดอก = ผ่อน
-- and transaction_snapshot_price_summaries.interest_amount > 0 -- มีดอก = ผ่อน
-- and orders.create_time > '2024-04-02'
-- and orders.create_time < '2024-04-03'
-- order by orders.create_time  desc   , follow_ups.id
-- limit 1888 
) , onetime_master_go as (
select * ,
case when packagetype='mandatoryPackages' then 0 else WHT_master end as WHT	, 
case when packagetype='mandatoryPackages' then 0 else ProcessingFee_master end	as	ProcessingFee	,
case when packagetype='mandatoryPackages' then 0 else ProcessingFeeVat_master end	as	ProcessingFeeVat	,
case when packagetype='mandatoryPackages' then 0 else ShippingFee_master end	as	ShippingFee	,
case when packagetype='mandatoryPackages' then 0 else ShippingFeeVat_master end	as	ShippingFeeVat ,
case when packagetype='mandatoryPackages' then TotalPremium else 
ROUND((TotalPremium)+TotalEIR+TotalSBT+ProcessingFee_master+ProcessingFeeVat_master+ShippingFee_master+ShippingFeeVat_master,2)	end as TotalAmount	,
-- ROUND((TotalPremium-WHT_master)+TotalEIR+TotalSBT+ProcessingFee_master+ProcessingFeeVat_master+ShippingFee_master+ShippingFeeVat_master,2)	end as TotalAmount	, -- สูตรที่ถูก - แต่บน sap ผิด (เอา wht ออกเพื่อให้เข้า sap ได้)

case when packagetype='mandatoryPackages' then 0 else Discount_master end	as	Discount	, 
case when packagetype='mandatoryPackages' then TotalPremium 
  else case when compu_detail.gross_premium is null then ActualReceived_master else ROUND(ActualReceived_master-compu_detail.gross_premium,2) end 
end as ActualReceived	,
-- CASE WHEN packagetype = 'mandatoryPackages' THEN 0 ELSE ROUND((TotalEIR)/(TotalPeriods-1),2) END AS InterestThisPeriod ,
0 as InterestThisPeriod  
------------------------------------------------------------------
-- ,compu_detail.*
-- (ActualReceived-compu_detail.gross_premium)	as	ActualReceived
-- ,charges_amount
-- check_order_items.no_items,
-- onetime_master.charges_id 
-- ,ROUND((1/100)*charges_amount,2) as charges_amount
from onetime_master 
left join compu_detail on compu_detail.order_id=onetime_master.human_id
left join check_order_items on check_order_items.OrderID = onetime_master.human_id 
where 1=1
and onetime_master.charges_id in (select distinct charges_id from charge_one) -- ชำระเต็มงวดแรก  -- งวด 2 ทำ sub query เพิ่ม 
-- and aaa.charges_id in ('849c9c3e-2b25-4097-8307-73455425229a') and aaa.human_id = 'L77069632' 
-- order by onetime_master.human_id 
-- limit 8;
) 
select 
CAST(FORMAT_DATE('%d%m%Y', order_items.cancel_time) AS STRING) AS cancel_time,
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
  ELSE InsuranceGroup
END AS InsuranceGroup,
InsuranceType	,
CASE
  WHEN InsuranceGroup = 'products/car-insurance' THEN 'Motor'
  ELSE InsuranceGroup
END AS InsuranceProduct,
CASE
  WHEN PolicyType = 'LEAD_TYPE_RENEWAL' THEN 'R'
  ELSE 'N'
END AS PolicyType,
Endorse,
CAST(FORMAT_DATE('%d%m%Y', PolicyDate) AS STRING) AS PolicyDate,
PolicyNo	,
EndorsementNo	,
ChassisNo	,
LicensePlate	,
GrossPremium	,
StampDuty	,
VAT	,
TotalPremium	,
WHT	,
TotalEIR	,
TotalSBT	,
ProcessingFee	,
ProcessingFeeVat	,
ShippingFee	,
ShippingFeeVat	,
TotalAmount	,
Discount	,
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
ActualReceived	,
InterestThisPeriod	,
PrincipleThisPeriod	,
InterestEIRThisPeriod	,
PrincipleEIRThisPeriod	,
CAST(FORMAT_DATE('%d%m%Y', PaymentDate) AS STRING) AS PaymentDate,
Period	,
TotalPeriods	,
PendingPayment	,
CASE WHEN PaymentMethod='CASH' AND PaymentChannel='SERVICE_PROVIDER_UNSPECIFIED' THEN '99' ELSE `pacific-plating-282708.sap_integration_v3.fn_rcb_payment_mapping`(PaymentMethod, PaymentChannel).sap_payment_method END AS PaymentMethod	,
CASE WHEN PaymentMethod='CASH' AND PaymentChannel='SERVICE_PROVIDER_UNSPECIFIED' THEN 'fix มือมี list ให้แล้ว' ELSE `pacific-plating-282708.sap_integration_v3.fn_rcb_payment_mapping`(PaymentMethod, PaymentChannel).sap_payment_channel END AS PaymentChannel	,
CAST(FORMAT_DATE('%d%m%Y', ExpectedDate) AS STRING) AS ExpectedDate,
RefOrder	,
RefundAmountBeforeFee	,
RefundAmountAfterFee	,
BillingAddress	,
CAST(FORMAT_DATE('%d%m%Y', BatchRunDate) AS STRING) AS BatchRunDate,
from onetime_master_go left join order_items on onetime_master_go.OrderItem=order_items.human_id
where PaymentMethod !='CASH'
-- CAST(FORMAT_DATE('%d%m%Y', OrderDate) AS STRING) ='10042024'
-- and OrderID = 'L74220356'
-- limit 100
;

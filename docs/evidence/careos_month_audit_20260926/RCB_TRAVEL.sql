WITH

get_charges_ref AS (

  select charges.third_party_id , orders.human_id as order_id , orders.payment

  from `pacific-plating-282708.careos.careos_orders` orders

  left join `pacific-plating-282708.careos.carepay_charges` charges

  on orders.payment =  CONCAT('transactions/',charges.transaction_id)

  WHERE product = 'products/travel-insurance'



),

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

and charges.service_provider != 'ICOLLECTION'

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



),



onetime_master as (

select

charges.amount as charges_amount,

order_items.motor_item_type,

order_items.packagetype,

charges.service_provider,

orders.create_time AS OrderDate,

charges.status ,

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

ROUND((1 / 100) * transaction_snapshot_price_summaries.discount_amount,2) AS Discount_master,

charges.status AS TransactionStatus,

order_items.submission_status AS SubmissionStatus,

order_items.approval_status AS ApprovalStatus,

transactions.status AS PaymentStatus,

ROUND(((1 / 100) * charges.amount),2) AS ActualReceived_master, -- จำนวนเงินที่ลูกค้าจ่ายมาจริงๆ ห้ามเปลี่ยน

0 AS PrincipleThisPeriod,

transaction_snapshot_price_summaries.interest_amount AS InterestEIRThisPeriod,

0 AS PrincipleEIRThisPeriod,

COALESCE(charges.payment_date,charges.update_time) as PaymentDate ,

charges.installment_number AS Period,

-- 1 AS TotalPeriods, --- transactions.installments ผ่อนผ่านบัตรแต่รูดจ่ายเต็มจะเป็นจำนวนที่ผ่อนกับบัตร

1 as TotalPeriods,

0 as PendingPayment,

charges.create_time as ExpectedDate ,

-- COALESCE(charges.due_date,charges.create_time) as ExpectedDate ,



charges.id as charges_id,

case

  when charges.third_party_id is null then order_items.human_id

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

'RCB-Omise QR Prompt Pay-2C2P' AS PaymentChannel,

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

) , onetime_master_go as (

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

left join compu_detail on compu_detail.order_id=onetime_master.human_id

left join check_order_items on check_order_items.OrderID = onetime_master.human_id

where 1=1

--and onetime_master.charges_id in (select distinct charges_id from charge_one) -- ชำระเต็มงวดแรก  -- งวด 2 ทำ sub query เพิ่ม



)

select

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

  WHEN InsuranceGroup = 'products/travel-insurance'

  THEN

  ----------------[Data Data Standardization For Healh Non-Motor]--------------

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

      WHEN InsurerCode = 'insurers/31' THEN 'N061'

      WHEN InsurerCode = 'insurers/33' THEN 'N011' --LMG--

      WHEN InsurerCode = 'insurers/34' THEN 'N079' --MSIG--

      WHEN InsurerCode = 'insurers/36' THEN 'N084'

      WHEN InsurerCode = 'insurers/37' THEN 'N083'

      WHEN InsurerCode = 'insurers/40' THEN 'N033'

      WHEN InsurerCode = 'insurers/42' THEN 'N064'

      WHEN InsurerCode = 'insurers/43' THEN 'N080'

      --WHEN InsurerCode = 'insurers/44' THEN 'N039'

      WHEN InsurerCode = 'insurers/44' THEN 'N081'

      ELSE InsurerCode

    END

  ELSE 'Not Travel'

END AS InsurerCode,

CASE

  WHEN InsuranceGroup = 'products/car-insurance' THEN 'Motor'

  WHEN InsuranceGroup = 'products/health-insurance' THEN 'Health'

  WHEN InsuranceGroup = 'products/travel-insurance' THEN 'Travel'

  ELSE InsuranceGroup

END AS InsuranceGroup,

------------------------

CASE

  WHEN InsuranceType IS NULL OR InsuranceType = ' ' THEN 'Travel'

  ELSE InsuranceType

END AS InsuranceType,

--------------------

CASE

  WHEN InsuranceGroup = 'products/car-insurance' THEN 'Motor'

  WHEN InsuranceGroup = 'products/health-insurance' THEN 'Health'

  WHEN InsuranceGroup = 'products/travel-insurance' THEN 'VFS'

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

'Omise QR Prompt Pay' AS PaymentMethod  ,

'RCB-Omise QR Prompt Pay-2C2P' AS PaymentChannel ,

CAST(FORMAT_DATE('%d%m%Y', ExpectedDate) AS STRING) AS ExpectedDate,

'' as RefOrder,

RefundAmountBeforeFee ,

RefundAmountAfterFee  ,

BillingAddress  ,

CAST(FORMAT_DATE('%d%m%Y', BatchRunDate) AS STRING) AS BatchRunDate,

from onetime_master_go



WHERE InsuranceGroup = 'products/travel-insurance'

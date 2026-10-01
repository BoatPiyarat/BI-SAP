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

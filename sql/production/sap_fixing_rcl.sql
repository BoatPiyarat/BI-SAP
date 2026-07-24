-- BASELINE CAPTURE 2026-07-24 -- pulled verbatim from live BigQuery view definition
-- Object: sap_data_engineer.sap_fixing_rcl
-- Boat: fix the same A2 NULL-safe bug here, leave everything else as-is (not
-- confirmed live/nightly production like the other 4 objects, but fixing anyway).
-- See docs/knowledge/30_SAP_CHANGELOG.md (2026-07-24 entry) for the bug.

WITH
get_charges_ref AS (
  SELECT 
    charges.third_party_id, 
    MIN(orders.human_id) AS order_id, 
    MIN(orders.payment)
  FROM 
    `pacific-plating-282708.careos.carepay_charges` charges
  LEFT JOIN 
    `pacific-plating-282708.careos.careos_orders` orders 
    ON orders.payment = CONCAT('transactions/', charges.transaction_id)
  WHERE 
    1=1 
    AND service_provider != 'ICOLLECTION'
    AND status = 'SUCCESSFUL'
    AND third_party_id IS NOT NULL 
    AND orders.human_id IS NOT NULL
  GROUP BY 
    charges.third_party_id 
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
)
,check_order_items as (
select orders.human_id as OrderID , count(order_items) as no_items
FROM `pacific-plating-282708.careos.careos_order_items` order_items
LEFT JOIN `pacific-plating-282708.careos.careos_orders` orders
    ON order_items.order_id = orders.id
where 1=1 and order_items.is_cancelled is false
group by orders.human_id
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
  WHERE transaction_snapshot_installment_details.period = 1 AND transaction_snapshot_installment_details.add_ons IS NOT NULL
),
--------------------------------------------------------------------------------------------------------

rcb_voluntary_installment_details AS (
  SELECT
    'rcb_voluntary_installment_details' AS CTE_source,
    'RCB' AS CompanyDB,
    orders.human_id AS OrderID,
    order_items.human_id AS OrderItem,
    case when charges.third_party_id is null then order_items.human_id else  charges.third_party_id end as InvoiceNo,
    orders.create_time AS OrderDate,
    JSON_VALUE(orders.data, '$.idNumber') AS InsuredID,
    JSON_VALUE(orders.data, '$.policyHolder.title') AS Title,
    COALESCE(JSON_VALUE(orders.data, '$.policyHolder.firstName'),JSON_VALUE(orders.data, '$.policyHolder.policyAddress.companyName')) AS FirstName,
    JSON_VALUE(orders.data, '$.policyHolder.lastName') AS LastName,
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
      ELSE ROUND (ROUND((1 / 100) * transaction_snapshot_price_summaries.processing_fee_amount,2) * (100/107),2)
    END AS ProcessingFee,
    CASE
      WHEN transaction_snapshot_price_summaries.processing_fee_amount IS NULL THEN 0
      ELSE ROUND(ROUND((1 / 100) * transaction_snapshot_price_summaries.processing_fee_amount,2) - (ROUND((1 / 100) * transaction_snapshot_price_summaries.processing_fee_amount,2) * (100/107)),2)
    END AS ProcessingFeeVat,
    CASE
      WHEN transaction_snapshot_price_summaries.shipment_fee IS NULL THEN 0
      ELSE ROUND(ROUND((1 / 100) * transaction_snapshot_price_summaries.shipment_fee,2) * (100/107),2)
    END AS ShippingFee,
    CASE
      WHEN transaction_snapshot_price_summaries.shipment_fee IS NULL THEN 0
      ELSE ROUND(ROUND((1 / 100) * transaction_snapshot_price_summaries.shipment_fee,2) - ROUND((1 / 100) * transaction_snapshot_price_summaries.shipment_fee,2) * (100/107),2)
    END AS ShippingFeeVat,
    CASE 
      WHEN takeaway_compulsary IS NOT NULL THEN ROUND((((1 / 100) * transaction_snapshot_price_summaries.net_premium_amount) - takeaway_compulsary.add_ons) + ((1 / 100) * transaction_snapshot_price_summaries.discount_amount),2)
      ELSE ROUND(((1 / 100) * transaction_snapshot_price_summaries.net_premium_amount) + ((1 / 100) * transaction_snapshot_price_summaries.discount_amount),2)
    END AS TotalAmount, 
    ROUND((1 / 100) * transaction_snapshot_price_summaries.discount_amount,2) AS Discount,
    follow_ups.status AS TransactionStatus,
    order_items.submission_status AS SubmissionStatus,
    order_items.approval_status AS ApprovalStatus,
    transactions.status AS PaymentStatus,
    CASE
      WHEN transaction_snapshot_installment_details.period = 1 THEN ROUND(ROUND((1 / 100) * transaction_snapshot_installment_details.payment_amount,2) - ROUND((1 / 100) * transaction_snapshot_installment_details.add_ons,2),2)
      ELSE ROUND((1 / 100) * transaction_snapshot_installment_details.payment_amount,2)
    END AS ActualReceived,
    CASE 
      WHEN transaction_snapshot_price_summaries.interest_amount = 0 OR transaction_snapshots.number_of_installment - 1 = 0 THEN 0
      WHEN transaction_snapshot_installment_details.period = 1 THEN 0
      ELSE ROUND((ROUND((1 / 100) * transaction_snapshot_price_summaries.interest_amount,2) - ((ROUND((1 / 100) * transaction_snapshot_price_summaries.interest_amount,2) * 3.3) / 103.3)) / (transaction_snapshots.number_of_installment - 1),2)
    END AS InterestThisPeriod,  
    CASE
      WHEN (transaction_snapshots.number_of_installment - 1) = 0 THEN 0
      WHEN transaction_snapshot_installment_details.period = 1 THEN ROUND((1 / 100) * transaction_snapshot_installment_details.principal,2)
      ELSE ROUND((ROUND((1/100)*transaction_snapshot_installment_details.payment_amount,2)) - ((ROUND((1/100)*transaction_snapshot_price_summaries.interest_amount,2) - ((ROUND((1/100)*transaction_snapshot_price_summaries.interest_amount,2)*3.3)/103.3))/(transaction_snapshots.number_of_installment-1)),2)
    END AS PrincipleThisPeriod,
    ROUND((1 / 100) * transaction_snapshot_installment_details.interest,2) AS InterestEIRThisPeriod,
    ROUND((1 / 100) * transaction_snapshot_installment_details.principal,2) AS PrincipleEIRThisPeriod,  
    charges.update_time AS PaymentDate,
    transaction_snapshot_installment_details.period AS Period,
    transaction_snapshots.number_of_installment AS TotalPeriods, --transactions.installments AS TotalPeriods,
    ROUND((1 / 100) * transaction_snapshot_installment_details.principal_balance,2) AS PendingPayment, -- Need to check
    charges.payment_method AS PaymentMethod,
    charges.service_provider AS PaymentChannel,
    follow_ups.due_date AS ExpectedDate,
    leads.reference AS RefOrder,
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
  LEFT JOIN order_items
    ON order_items.order_id = orders.id
  LEFT JOIN refunds
    ON refunds.transaction_id = transactions.id
  LEFT JOIN follow_ups
    ON follow_ups.transaction_id = transactions.id
    AND follow_ups.installment = transaction_snapshot_installment_details.period
  LEFT JOIN takeaway_compulsary
    ON takeaway_compulsary.transaction_snapshot_id = transaction_snapshots.id
  WHERE 
    transaction_snapshot_installment_details.id IS NOT NULL
    AND (order_items.motor_item_type != 'MOTOR_TYPE_COMPULSORY' OR order_items.motor_item_type IS NULL)  -- A2 fix 2026-07-24
    and (follow_ups.transaction_id is  null)
),
--------------------------------------------------------------------------------------------------------

rcl_voluntary_installment_details AS (
  SELECT
    'rcl_voluntary_installment_details' AS CTE_source,
    'RCB' AS CompanyDB,
    orders.human_id AS OrderID,
    order_items.human_id AS OrderItem,
    case when charges.third_party_id is null then order_items.human_id else  charges.third_party_id end as InvoiceNo,
    orders.create_time AS OrderDate,
    case when JSON_VALUE(orders.data, '$.policyHolder.isCompany') ='true' then 
    JSON_VALUE(orders.data, '$.policyHolder.companyTaxId') else JSON_VALUE(orders.data, '$.idNumber') end as InsuredID ,
    JSON_VALUE(orders.data, '$.policyHolder.title') AS Title,
    COALESCE(JSON_VALUE(orders.data, '$.policyHolder.firstName'),JSON_VALUE(orders.data, '$.policyHolder.policyAddress.companyName')) AS FirstName,
    JSON_VALUE(orders.data, '$.policyHolder.lastName') AS LastName,
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
      ELSE ROUND(ROUND((1 / 100) * transaction_snapshot_price_summaries.processing_fee_amount,2) - (ROUND((1 / 100) * transaction_snapshot_price_summaries.processing_fee_amount,2) * (100/103.3)),2)
    END AS ProcessingFeeVat,
    CASE
      WHEN transaction_snapshot_price_summaries.shipment_fee IS NULL THEN 0
      ELSE ROUND(ROUND((1 / 100) * transaction_snapshot_price_summaries.shipment_fee,2) * (100/107),2)
    END AS ShippingFee,
    CASE
      WHEN transaction_snapshot_price_summaries.shipment_fee IS NULL THEN 0
      ELSE ROUND(ROUND((1 / 100) * transaction_snapshot_price_summaries.shipment_fee,2) - ROUND((1 / 100) * transaction_snapshot_price_summaries.shipment_fee,2) * (100/107),2)
    END AS ShippingFeeVat,
    CASE 
      WHEN takeaway_compulsary IS NOT NULL THEN ROUND(((1 / 100) * transaction_snapshot_price_summaries.net_premium_amount - takeaway_compulsary.add_ons),2)
      ELSE ROUND((1 / 100) * transaction_snapshot_price_summaries.net_premium_amount,2)
    END AS TotalAmount,
    
    ROUND((1 / 100) * transaction_snapshot_price_summaries.discount_amount,2) AS Discount,
    follow_ups.status AS TransactionStatus,
    order_items.submission_status AS SubmissionStatus,
    order_items.approval_status AS ApprovalStatus,
    transactions.status AS PaymentStatus,
    CASE
      WHEN transaction_snapshot_installment_details.period = 1 THEN ROUND(ROUND((1 / 100) * transaction_snapshot_installment_details.payment_amount,2) - ROUND((1 / 100) * transaction_snapshot_installment_details.add_ons,2),2)
      ELSE ROUND((1 / 100) * transaction_snapshot_installment_details.payment_amount,2)
    END AS ActualReceived,
    CASE 
      WHEN transaction_snapshot_price_summaries.interest_amount = 0 OR transaction_snapshots.number_of_installment - 1 = 0 THEN 0
      WHEN transaction_snapshot_installment_details.period = 1 THEN 0
      ELSE ROUND((ROUND((1 / 100) * transaction_snapshot_price_summaries.interest_amount,2) - ((ROUND((1 / 100) * transaction_snapshot_price_summaries.interest_amount,2) * 3.3) / 103.3)) / (transaction_snapshots.number_of_installment - 1),2)
    END AS InterestThisPeriod,  
    CASE
      WHEN (transaction_snapshots.number_of_installment - 1) = 0 THEN 0
      WHEN transaction_snapshot_installment_details.period = 1 THEN ROUND((1 / 100) * transaction_snapshot_installment_details.principal,2)
      ELSE ROUND((ROUND((1/100)*transaction_snapshot_installment_details.payment_amount,2)) - ((ROUND((1/100)*transaction_snapshot_price_summaries.interest_amount,2) - ((ROUND((1/100)*transaction_snapshot_price_summaries.interest_amount,2)*3.3)/103.3))/(transaction_snapshots.number_of_installment-1)),2)
    END AS PrincipleThisPeriod,
    ROUND((1 / 100) * transaction_snapshot_installment_details.interest,2) AS InterestEIRThisPeriod,
    ROUND((1 / 100) * transaction_snapshot_installment_details.principal,2) AS PrincipleEIRThisPeriod,  
    charges.update_time AS PaymentDate,
    transaction_snapshot_installment_details.period AS Period,
    transaction_snapshots.number_of_installment AS TotalPeriods,
    ROUND((1 / 100) * transaction_snapshot_installment_details.principal_balance,2) AS PendingPayment,
    charges.payment_method AS PaymentMethod,
    charges.service_provider AS PaymentChannel,
    follow_ups.due_date AS ExpectedDate,
    leads.reference AS RefOrder,
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
  WHERE 
    transaction_snapshot_installment_details.id IS NOT NULL
    AND (order_items.motor_item_type != 'MOTOR_TYPE_COMPULSORY' OR order_items.motor_item_type IS NULL)  -- A2 fix 2026-07-24
    and (follow_ups.transaction_id is not null)
),
--------------------------------------------------------------------------------------------------------

voluntary_onetime_no_installment_details AS (
  SELECT
    'xxx_voluntary_onetime_no_installment_details' AS CTE_source, 
    'RCB' AS CompanyDB, 
    orders.human_id AS OrderID, 
    order_items.human_id AS OrderItem, 
    case when charges.third_party_id is null then order_items.human_id else  charges.third_party_id end as InvoiceNo,
    orders.create_time AS OrderDate, 
    JSON_VALUE(orders.data, '$.idNumber') AS InsuredID, 
    JSON_VALUE(orders.data, '$.policyHolder.title') AS Title, 
    COALESCE(JSON_VALUE(orders.data, '$.policyHolder.firstName'),JSON_VALUE(orders.data, '$.policyHolder.policyAddress.companyName')) AS FirstName, 
    JSON_VALUE(orders.data, '$.policyHolder.lastName') AS LastName, 
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
      ELSE ROUND (ROUND((1 / 100) * transaction_snapshot_price_summaries.processing_fee_amount,2) * (100/107),2)
    END AS ProcessingFee,
    CASE
      WHEN transaction_snapshot_price_summaries.processing_fee_amount IS NULL THEN 0
      ELSE ROUND(ROUND((1 / 100) * transaction_snapshot_price_summaries.processing_fee_amount,2)-(ROUND((1 / 100) * transaction_snapshot_price_summaries.processing_fee_amount,2) * (100/107)),2)
    END AS ProcessingFeeVat,
    CASE
      WHEN transaction_snapshot_price_summaries.shipment_fee IS NULL THEN 0
      ELSE ROUND(ROUND((1 / 100) * transaction_snapshot_price_summaries.shipment_fee,2) * (100/107),2)
    END AS ShippingFee,
    CASE
      WHEN transaction_snapshot_price_summaries.shipment_fee IS NULL THEN 0
      ELSE ROUND(ROUND((1 / 100) * transaction_snapshot_price_summaries.shipment_fee,2) - ROUND((1 / 100) * transaction_snapshot_price_summaries.shipment_fee,2) * (100/107),2)
    END AS ShippingFeeVat,
    ROUND((1 / 100) * transaction_snapshot_price_summaries.net_premium_amount,2) AS TotalAmount,
    ROUND((1 / 100) * transaction_snapshot_price_summaries.discount_amount,2) AS Discount,
    charges.status AS TransactionStatus,
    order_items.submission_status AS SubmissionStatus,
    order_items.approval_status AS ApprovalStatus,
    transactions.status AS PaymentStatus,
    case 
    when transaction_snapshot_installment_details.add_ons is null then ROUND((1 / 100) * charges.amount,2)
    when transaction_snapshot_installment_details.add_ons is not null then ROUND((1 / 100) * (charges.amount-transaction_snapshot_installment_details.add_ons),2)
    else ROUND((1 / 100) * charges.amount,2) end 
    as ActualReceived, 
    CASE 
      WHEN transaction_snapshot_price_summaries.interest_amount = 0 OR transaction_snapshots.number_of_installment - 1 = 0 THEN 0
      ELSE ROUND((ROUND((1 / 100) * transaction_snapshot_price_summaries.interest_amount,2) - ((ROUND((1 / 100) * transaction_snapshot_price_summaries.interest_amount,2) * 3.3) / 103.3)) / (transaction_snapshots.number_of_installment - 1),2)
    END AS InterestThisPeriod,
    0 AS PrincipleThisPeriod,
    transaction_snapshot_price_summaries.interest_amount AS InterestEIRThisPeriod,
    0 AS PrincipleEIRThisPeriod,
    charges.update_time AS PaymentDate,
    charges.installment_number AS Period,
    transactions.installments AS TotalPeriods,
    CASE
      WHEN transactions.status = 'SUCCESSFUL' THEN 0
      ELSE ROUND((1 / 100) * transactions.amount,2)
    END AS PendingPayment,
    charges.payment_method AS PaymentMethod,
    charges.service_provider AS PaymentChannel,
    charges.update_time AS ExpectedDate,
    leads.reference AS RefOrder,
    NULL AS RefundAmountBeforeFee,
    NULL AS RefundAmountAfterFee,
    CASE
      WHEN JSON_VALUE(orders.data, '$.policyHolder.policyAddress.isBillingAddress') = 'true' 
        THEN CONCAT(
          COALESCE(JSON_VALUE(orders.data, '$.policyHolder.policyAddress.fullName'),JSON_VALUE(orders.data, '$.policyHolder.policyAddress.companyName')), ', ',
          JSON_VALUE(orders.data, '$.policyHolder.policyAddress.address'), ' ',
          JSON_VALUE(orders.data, '$.policyHolder.policyAddress.subDistrict'), ' ',
          JSON_VALUE(orders.data, '$.policyHolder.policyAddress.district'), ' ',
          JSON_VALUE(orders.data, '$.policyHolder.policyAddress.province'), ' ',  
          JSON_VALUE(orders.data, '$.policyHolder.policyAddress.postCode')
        )
        ELSE CONCAT(
          JSON_VALUE(orders.data, '$.policyHolder.billingAddress.fullName'), ' ',
          JSON_VALUE(orders.data, '$.policyHolder.billingAddress.address'), ' ',
          JSON_VALUE(orders.data, '$.policyHolder.billingAddress.subDistrict'), ' ',
          JSON_VALUE(orders.data, '$.policyHolder.billingAddress.district'), ' ',
          JSON_VALUE(orders.data, '$.policyHolder.billingAddress.province'), ' ',
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
  LEFT JOIN order_items
    ON order_items.order_id = orders.id
  LEFT JOIN refunds
    ON refunds.transaction_id = transactions.id
  LEFT JOIN follow_ups
    ON follow_ups.transaction_id = transactions.id
  WHERE 
    transaction_snapshot_installment_details.id IS NULL
    AND transaction_snapshot_price_summaries.id IS NOT NULL
    AND (order_items.motor_item_type != 'MOTOR_TYPE_COMPULSORY' OR order_items.motor_item_type IS NULL)  -- A2 fix 2026-07-24
    AND orders.create_time >= "2024-03-28"
    AND transactions.installments = 1
    AND transactions.status = 'SUCCESSFUL'
    AND charges.status = 'SUCCESSFUL'
),
--------------------------------------------------------------------------------------------------------

compulsary_installment_details AS (
  SELECT
    'compulsary_installment_details' AS CTE_source, 
    'RCB' AS CompanyDB,
    orders.human_id AS OrderID,
    order_items.human_id AS OrderItem,
    case when charges.third_party_id is null then order_items.human_id else  charges.third_party_id end as InvoiceNo,
    orders.create_time AS OrderDate,
    case when JSON_VALUE(orders.data, '$.policyHolder.isCompany') ='true' then 
    JSON_VALUE(orders.data, '$.policyHolder.companyTaxId') else JSON_VALUE(orders.data, '$.idNumber') end as InsuredID ,
    JSON_VALUE(orders.data, '$.policyHolder.title') AS Title,
    COALESCE(JSON_VALUE(orders.data, '$.policyHolder.firstName'),JSON_VALUE(orders.data, '$.policyHolder.policyAddress.companyName')) AS FirstName,
    JSON_VALUE(orders.data, '$.policyHolder.lastName') AS LastName,
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
    order_items.gross_premium  as TotalAmount,
    0 AS Discount,
    charges.status AS TransactionStatus,
    order_items.submission_status AS SubmissionStatus,
    order_items.approval_status AS ApprovalStatus,
    transactions.status AS PaymentStatus,
    order_items.gross_premium  as ActualReceived,
    0 AS InterestThisPeriod,
    0 AS PrincipleThisPeriod,
    0 AS InterestEIRThisPeriod,
    0 AS PrincipleEIRThisPeriod,
    charges.update_time AS PaymentDate,
    transaction_snapshot_installment_details.period AS Period,
    transaction_snapshot_installment_details.period AS TotalPeriods,
    0 as PendingPayment,
    charges.payment_method AS PaymentMethod,
    charges.service_provider AS PaymentChannel,
    follow_ups.due_date AS ExpectedDate,
    leads.reference AS RefOrder,
    NULL AS RefundAmountBeforeFee,
    NULL AS RefundAmountAfterFee,
    CASE
      WHEN JSON_VALUE(orders.data, '$.policyHolder.policyAddress.isBillingAddress') = 'true' 
        THEN CONCAT(
          COALESCE(JSON_VALUE(orders.data, '$.policyHolder.policyAddress.fullName'),JSON_VALUE(orders.data, '$.policyHolder.policyAddress.companyName')), ', ',
          JSON_VALUE(orders.data, '$.policyHolder.policyAddress.address'), ' ',
          JSON_VALUE(orders.data, '$.policyHolder.policyAddress.subDistrict'), ' ',
          JSON_VALUE(orders.data, '$.policyHolder.policyAddress.district'), ' ',
          JSON_VALUE(orders.data, '$.policyHolder.policyAddress.province'), ' ',  
          JSON_VALUE(orders.data, '$.policyHolder.policyAddress.postCode')
        )
        ELSE CONCAT(
          JSON_VALUE(orders.data, '$.policyHolder.billingAddress.fullName'), ' ',
          JSON_VALUE(orders.data, '$.policyHolder.billingAddress.address'), ' ',
          JSON_VALUE(orders.data, '$.policyHolder.billingAddress.subDistrict'), ' ',
          JSON_VALUE(orders.data, '$.policyHolder.billingAddress.district'), ' ',
          JSON_VALUE(orders.data, '$.policyHolder.billingAddress.province'), ' ',
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
  WHERE 
    order_items.motor_item_type = 'MOTOR_TYPE_COMPULSORY'
    AND charges.status NOT IN ('FAILED','PENDING')
    AND transaction_snapshot_installment_details.period = 1
),
--------------------------------------------------------------------------------------------------------

compulsary_onetime_no_installment_details AS (
  SELECT
    'xxx_compulsary_onetime_no_installment_details' AS CTE_source, 
    'RCB' AS CompanyDB,
    orders.human_id AS OrderID,
    order_items.human_id AS OrderItem,
    case when charges.third_party_id is null then order_items.human_id else  charges.third_party_id end as InvoiceNo,
    orders.create_time AS OrderDate,
    JSON_VALUE(orders.data, '$.idNumber') AS InsuredID,
    JSON_VALUE(orders.data, '$.policyHolder.title') AS Title,
    COALESCE(JSON_VALUE(orders.data, '$.policyHolder.firstName'),JSON_VALUE(orders.data, '$.policyHolder.policyAddress.companyName')) AS FirstName,
    JSON_VALUE(orders.data, '$.policyHolder.lastName') AS LastName,
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
    order_items.price AS TotalAmount,
    0 AS Discount,
    charges.status AS TransactionStatus,
    order_items.submission_status AS SubmissionStatus,
    order_items.approval_status AS ApprovalStatus,
    transactions.status AS PaymentStatus,
    order_items.price AS ActualReceived,
    0 AS InterestThisPeriod,
    0 AS PrincipleThisPeriod,
    0 AS InterestEIRThisPeriod,
    0 AS PrincipleEIRThisPeriod,
    charges.update_time AS PaymentDate,
    charges.installment_number AS Period,
    transactions.installments AS TotalPeriods,
    0 AS PendingPayment,
    charges.payment_method AS PaymentMethod,
    charges.service_provider AS PaymentChannel,
    charges.update_time AS ExpectedDate,
    leads.reference AS RefOrder,
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
  LEFT JOIN order_items
    ON order_items.order_id = orders.id
  LEFT JOIN refunds
    ON refunds.transaction_id = transactions.id
  LEFT JOIN follow_ups
    ON follow_ups.transaction_id = transactions.id

  WHERE 
    transaction_snapshot_installment_details.id IS NULL
    AND order_items.motor_item_type = 'MOTOR_TYPE_COMPULSORY'
    AND orders.create_time >= "2024-03-25"
    AND transactions.installments = 1
    AND transactions.status = 'SUCCESSFUL'
    AND charges.status = 'SUCCESSFUL'
),
--------------------------------------------------------------------------------------------------------

combine AS (
  SELECT * FROM rcb_voluntary_installment_details
  UNION ALL
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
    CASE 
      WHEN InvoiceNo IS NULL AND TransactionStatus = 'SUCCESSFUL' THEN '' 
      ELSE InvoiceNo 
    END AS InvoiceNo,
    CAST(FORMAT_DATE('%d%m%Y', OrderDate) AS STRING) AS OrderDate,
    CASE 
      WHEN InsuredID = '' THEN '-' 
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
    TRIM(InsurerCode, 'insurer/') AS InsurerCode,
    CASE
      WHEN InsuranceGroup = 'products/car-insurance' THEN 'Motor'
      ELSE InsuranceGroup
    END AS InsuranceGroup,
    InsuranceType,
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
    PolicyNo,
    EndorsementNo,
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
    ROUND((TotalPremium + TotalEIR + TotalSBT + ProcessingFee + ProcessingFeeVat + ShippingFee + ShippingFeeVat), 2) AS TotalAmount,
    Discount,
    CASE 
      WHEN TransactionStatus = 'FOLLOWUP_STATUS_CANCELLED' THEN 'pending'
      WHEN TransactionStatus = 'FOLLOWUP_STATUS_OVERDUE' THEN 'pending'
      WHEN TransactionStatus = 'FOLLOWUP_STATUS_PAID' THEN 'paid'
      WHEN TransactionStatus = 'FOLLOWUP_STATUS_PENDING' THEN 'pending'
      WHEN TransactionStatus = 'SUCCESSFUL' THEN 'paid'
      WHEN TransactionStatus = 'PENDING' THEN 'pending'
      WHEN TransactionStatus IS NULL THEN 'pending'
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
      WHEN PaymentStatus = 'SUCCESSFUL' THEN 'fully paid'
      WHEN PaymentStatus = 'PENDING' THEN 'Not fully paid'
      ELSE PaymentStatus
    END AS PaymentStatus,
    ActualReceived,
    InterestThisPeriod,
    PrincipleThisPeriod,
    InterestEIRThisPeriod,
    PrincipleEIRThisPeriod,
    CAST(FORMAT_DATE('%d%m%Y', PaymentDate) AS STRING) AS PaymentDate,
    Period,
    TotalPeriods,
    ROUND(((((TotalPremium + TotalEIR + TotalSBT + ProcessingFee + ProcessingFeeVat + ShippingFee + ShippingFeeVat) - Discount) - Discount) / TotalPeriods) * (TotalPeriods - Period), 2) AS PendingPayment,
    CASE 
      WHEN InsuranceType = 'MOTOR_TYPE_COMPULSORY' THEN 'RCL-CMI-channel'
      WHEN PaymentMethod = 'CASH' THEN 'TRF Transfer'
      WHEN PaymentMethod = 'QR_CODE' THEN 'OME Omise QR Prompt Pay'
      WHEN PaymentMethod = 'DIRECT_PAYMENT' AND PaymentChannel = 'SERVICE_PROVIDER_UNSPECIFIED' THEN 'DPM จ่ายตรงกับบริษัทประกัน'
      ELSE PaymentMethod 
    END AS PaymentMethod,
    CASE 
      WHEN InsuranceType = 'MOTOR_TYPE_COMPULSORY' THEN 'RCL-CMI-channel'
      WHEN PaymentMethod = 'CASH' THEN 'RCL-Transfer-อื่นๆ'
      WHEN PaymentMethod = 'QR_CODE' AND PaymentChannel = 'RABBIT_LENDING' THEN 'RCL-Omise QR Prompt Pay-BAY'
      WHEN PaymentMethod = 'DIRECT_PAYMENT' AND PaymentChannel = 'SERVICE_PROVIDER_UNSPECIFIED' THEN 'RCL-DIRECT PAYMENT - Installment'
      ELSE PaymentChannel 
    END AS PaymentChannel,
    CAST(FORMAT_DATE('%d%m%Y', ExpectedDate) AS STRING) AS ExpectedDate,
    RefOrder,
    RefundAmountBeforeFee,
    RefundAmountAfterFee,
    BillingAddress,
    CAST(FORMAT_DATE('%d%m%Y', BatchRunDate) AS STRING) AS BatchRunDate
  FROM 
    combine
),
--------------------------------------------------------------------------------------------------------

transformation_xxx AS (
    SELECT 
        CTE_source, 
        CompanyDB, 
        OrderID,
        OrderItem,
        CASE 
            WHEN TransactionStatus = 'paid' THEN InvoiceNo 
            ELSE '' 
        END AS InvoiceNo,
        OrderDate,
        InsuredID,
        Title,
        FirstName,
        LastName,
        InsurerCode,
        InsuranceGroup,
        InsuranceType,
        InsuranceProduct,
        PolicyType,
        Endorse,
        PolicyDate,
        CASE 
            WHEN PolicyNo IS NULL THEN '' 
            ELSE PolicyNo 
        END AS PolicyNo,
        EndorsementNo,
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
        TotalAmount,
        Discount,
        TransactionStatus,
        SubmissionStatus,
        ApprovalStatus,
        PaymentStatus,
        ActualReceived,
        InterestThisPeriod,
        PrincipleThisPeriod,
        InterestEIRThisPeriod,
        PrincipleEIRThisPeriod,
        CASE 
            WHEN PaymentDate IS NULL THEN '' 
            ELSE PaymentDate 
        END AS PaymentDate,
        Period,
        TotalPeriods,
        PendingPayment,
        IFNULL(PaymentMethod, ' ') AS PaymentMethod,
        IFNULL(PaymentChannel, ' ') AS PaymentChannel,
        ExpectedDate,
        get_charges_ref.order_id AS RefOrder,
        RefundAmountBeforeFee,
        RefundAmountAfterFee,
        BillingAddress,
        BatchRunDate
    FROM 
        transformation 
    LEFT JOIN 
        get_charges_ref ON transformation.InvoiceNo = get_charges_ref.third_party_id 
        AND get_charges_ref.order_id != transformation.OrderID
)
------------------------------------------------------------------------------------------------------------
SELECT 
    transformation_xxx.* 
    EXCEPT (CTE_source) 
FROM 
    transformation_xxx 
    LEFT JOIN check_order_items ON transformation_xxx.OrderID = check_order_items.OrderID
WHERE 
    1=1 
ORDER BY 
    OrderID,
    TotalPeriods,
    Period

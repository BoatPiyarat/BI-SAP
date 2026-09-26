-- SOURCE-ONLY LEGACY PROPOSAL — DO NOT DEPLOY

-- Object: pacific-plating-282708.sap_data_engineer.RCL_HEALTH

-- Live definition last modified: 2026-08-29 02:21:39 +00:00

-- Captured live query SHA256: 0f41e474e2ffeadbe3b8c11087af7763cd732823ffde6604227ec8658f358606

-- Scope: one surgical status-precedence fix; every other live query byte is preserved.

-- Deployment is blocked by docs/AGENT_RULES.md unless Boat grants a scoped legacy exception

-- and the exact reviewed artifact receives Class-A PASS plus explicit deploy approval.

-- RCB NonMotor installment (RCL / RABBIT_LENDING) -- FIXED & TUNED VERSION

-- Fixed & tuned: 2026-08-28 (Boat review)

-- Changes:

--  1. FIX (correctness, major -- this is what Boat flagged): the charges

--     JOIN had NO service_provider filter at all, so any matched charge

--     (including EDC card-installment charges) could populate

--     ActualReceived/PaymentDate/PaymentMethod for a period. Added

--     `AND charges.service_provider = 'RABBIT_LENDING'` to the JOIN's ON

--     clause (not WHERE -- keeps unmatched/pending periods surviving the

--     LEFT JOIN, same pattern as the Motor RCL installment fix).

--  2. FIX (correctness, major): added `transactions.payment_option IS

--     DISTINCT FROM 'CREDIT_CARD_INSTALLMENT'` on the `transactions` CTE --

--     same EDC-installment guard confirmed for Motor. NULL-safe (payment_

--     option can be NULL for other transaction types).

--  3. FIX (correctness, confirmed with Boat -- same fix already applied to

--     the Motor RCL installment query): credit-shell orders are now fully

--     EXCLUDED, not just relabeled. `change` CTE moved earlier; `orders`

--     CTE filtered `human_id NOT IN (SELECT human_id FROM change)`. The

--     existing PaymentMethod/PaymentChannel "RCL-Credit Shell" CASE

--     branches are left in place (same reasoning as Motor: after this

--     exclusion they can never match again since cancelled_change_orders

--     is small, and rewriting those CASE blocks to remove the dead

--     branches risked a typo for no real gain).

--  4. FIX (correctness, confirmed with Boat): `AND (follow_ups.

--     transaction_id IS NOT NULL)` in the main WHERE silently turned the

--     LEFT JOIN follow_ups into an effective INNER JOIN, dropping any

--     period that doesn't yet have a follow-up row -- the exact same bug

--     Motor's RCL installment query already had commented out, with the

--     same root cause. Commented out here too. This query's own

--     PaymentMethod/PaymentChannel CASE logic already anticipates pending

--     periods with no charge yet (`WHEN charges.payment_date IS NULL THEN

--     NULL`), so this fix makes the query consistent with its own design.

--  5. FIX (correctness, confirmed with Boat): the `refunds` join had NO

--     period-scoping at all (`ON refunds.transaction_id = transactions.

--     id`) -- a single refund amount was showing up duplicated on EVERY

--     installment period row of that transaction, and a transaction with

--     more than one refund row would have duplicated the period rows

--     themselves. Refunds are now pre-aggregated to one row per

--     transaction_id (SUM), and shown ONLY on Period = 1 (0 on every

--     other period) -- matching the convention this query already uses

--     elsewhere for period-1-only attribution (charge_rank = 1,

--     takeaway_compulsary).

--  6. FIX (dead code): removed 10 CTEs that were declared but never

--     referenced anywhere in the query: card_tokens, contract_prices,

--     contract_records, contracts, customer_tokens, hydra_migrations,

--     payment_options, payment_records, prices, check_order_items (and

--     check_order_items' now-pointless LEFT JOIN in the final SELECT --

--     it never contributed any output column since the final SELECT is

--     explicitly `transformation_xxx.*`, not a bare `*`).

-- NOT changed: all financial calculations, the InsurerCode health-mapping

--     table, InsuranceType/Group/Product logic, PaymentMethod/

--     PaymentChannel mapping, and every other CASE expression are

--     byte-identical to the original.

-- ============================================================



WITH

get_charges_ref AS (

  SELECT charges.third_party_id,

  MIN(orders.human_id) AS order_id,

  MIN(orders.payment) --, charges.*



  FROM `pacific-plating-282708.careos.carepay_charges` charges

  LEFT JOIN `pacific-plating-282708.careos.careos_orders` orders

    on orders.payment =  CONCAT('transactions/',charges.transaction_id)

  WHERE 1=1

  AND service_provider != 'ICOLLECTION'

  AND status = 'SUCCESSFUL'

  AND third_party_id IS NOT NULL AND orders.human_id IS NOT NULL

  GROUP BY charges.third_party_id

),



charges AS (

  SELECT * ,

  ROW_NUMBER() OVER (PARTITION BY transaction_id, installment_number ORDER BY create_time) AS charge_rank

  FROM `pacific-plating-282708.careos.carepay_charges`

  WHERE status = 'SUCCESSFUL'

),



follow_ups AS (

  SELECT * FROM `pacific-plating-282708.careos.carepay_follow_ups`

),



-- FIX 5: pre-aggregated to one row per transaction_id -- attributed to

-- Period 1 only in the main SELECT below (see FIX 5 note there).

refunds AS (

  SELECT transaction_id, SUM(amount) AS amount

  FROM `pacific-plating-282708.careos.carepay_refunds`

  GROUP BY transaction_id

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



-- FIX 2: EDC-installment guard, same as Motor.

transactions AS (

  SELECT * FROM `pacific-plating-282708.careos.carepay_transactions`

  WHERE payment_option IS DISTINCT FROM 'CREDIT_CARD_INSTALLMENT'

),



change AS (SELECT current_human_id human_id, old_human_id

FROM pacific-plating-282708.careos.cancelled_change_orders ),



-- FIX 3: credit-shell exclusion, same pattern as Motor RCL installment.

orders AS (

  SELECT * FROM `pacific-plating-282708.careos.careos_orders`

  WHERE human_id NOT IN (SELECT human_id FROM change)

),



order_items AS (

  SELECT * FROM `pacific-plating-282708.careos.careos_order_items`

),



leads AS (

  SELECT * FROM `pacific-plating-282708.careos.careos_leads`

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

    CASE

      WHEN charges.third_party_id IS NULL THEN order_items.human_id

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

    order_items.package AS InsuranceProduct,

    'Insurance' AS ProductType,

    leads.type AS PolicyType,

    'N' AS Endorse,

    order_items.policy_start_date AS PolicyDate,

    order_items.policy_number AS PolicyNo,

    CAST('' AS STRING) AS EndorsementNo,

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

    CASE

      WHEN takeaway_compulsary IS NOT NULL THEN ROUND(((1 / 100) * transaction_snapshot_price_summaries.net_premium_amount - takeaway_compulsary.add_ons),2)

      ELSE ROUND((1 / 100) * transaction_snapshot_price_summaries.net_premium_amount,2)

    END AS TotalAmount,

    ROUND((1 / 100) * transaction_snapshot_price_summaries.discount_amount,2) AS Discount,

    -- ROOT FIX 2026-09-01: a matched RABBIT_LENDING charge in this CTE is already

    -- restricted to SUCCESSFUL. Charge truth must win over a stale/pending follow-up;

    -- otherwise a paid period is mislabeled pending while retaining payment fields.

    CASE

      WHEN charges.status = 'SUCCESSFUL' THEN 'SUCCESSFUL'

      ELSE follow_ups.status

    END AS TransactionStatus,

    order_items.submission_status AS SubmissionStatus,

    order_items.approval_status AS ApprovalStatus,

    transactions.status AS PaymentStatus,

    CASE WHEN charge_rank <> 1 THEN 0

      WHEN transaction_snapshot_installment_details.period = 1 THEN ROUND(ROUND((1 / 100) * transaction_snapshot_installment_details.payment_amount,2) - ROUND((1 / 100) * transaction_snapshot_installment_details.add_ons,2),2)

      ELSE ROUND((1 / 100) * transaction_snapshot_installment_details.payment_amount,2)

    END AS ExpectedReceived,

 CASE WHEN charge_rank = 1 THEN ROUND(ROUND((1 / 100) * charges.amount,2)- ROUND((1 / 100) * transaction_snapshot_installment_details.add_ons,2),2)

 ELSE ROUND((1 / 100) * COALESCE(charges.amount,transaction_snapshot_installment_details.payment_amount),2) END AS ActualReceived,

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

CASE

  WHEN DATE(payment_date) < DATE_TRUNC(CURRENT_DATE(), MONTH)

       AND CURRENT_DATE() > DATE_ADD(

             LAST_DAY(DATE_SUB(CURRENT_DATE(), INTERVAL 1 MONTH)),

             INTERVAL 3 DAY

           )

  THEN  DATE_TRUNC(CURRENT_DATE(), MONTH)



  ELSE  DATE(payment_date)

END AS PaymentDate,

    transaction_snapshot_installment_details.period AS Period,

    transaction_snapshots.number_of_installment AS TotalPeriods, --transactions.installments AS TotalPeriods,

    ROUND((1 / 100) * transaction_snapshot_installment_details.principal_balance,2) AS PendingPayment, -- Need to check

    CASE WHEN charges.payment_date IS NULL THEN NULL

      WHEN transaction_snapshot_installment_details.period = 1 AND change.human_id IS NOT NULL AND charges.payment_method <> 'DIRECT_PAYMENT' THEN "RCL-Credit Shell"

      WHEN change.human_id IS NOT NULL AND charges.payment_method = 'DIRECT_PAYMENT' THEN 'DIRECT_PAYMENT'

      ELSE charges.payment_method END AS PaymentMethod,

    CASE WHEN charges.payment_date IS NULL THEN NULL

      WHEN transaction_snapshot_installment_details.period = 1 AND change.human_id IS NOT NULL AND charges.payment_method <> 'DIRECT_PAYMENT' THEN "RCL-Credit Shell"

      WHEN change.human_id IS NOT NULL AND charges.payment_method = 'DIRECT_PAYMENT' THEN 'RCL-DIRECT PAYMENT'

      ELSE charges.service_provider END AS PaymentChannel,

    follow_ups.due_date AS ExpectedDate,

    leads.reference AS RefOrder,

    -- FIX 5: refunds now pre-aggregated to one row per transaction; shown

    -- on Period 1 only (0 elsewhere) instead of duplicated on every period.

    CASE WHEN transaction_snapshot_installment_details.period = 1 THEN ROUND(refunds.amount * (100/107),2) ELSE 0 END AS RefundAmountBeforeFee,

    CASE WHEN transaction_snapshot_installment_details.period = 1 THEN refunds.amount ELSE 0 END AS RefundAmountAfterFee,

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

    AND charges.service_provider = 'RABBIT_LENDING'  -- FIX 1: this is the actual bug Boat flagged

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

    transaction_snapshot_installment_details.id IS NOT NULL

    AND order_items.motor_item_type IS NULL

    -- FIX 4: commented out, same reason and same fix as Motor RCL installment --

    -- this silently turned the follow_ups LEFT JOIN into an INNER JOIN and

    -- dropped periods with no follow-up row yet (pending periods this query's

    -- own PaymentMethod/PaymentChannel logic already anticipates).

    -- AND (follow_ups.transaction_id IS NOT NULL)

),

--------------------------------------------------------------------------------------------------------





--------------------------------------------------------------------------------------------------------



combine AS (

  --SELECT * FROM rcb_voluntary_installment_details

  --UNION ALL

  SELECT * FROM rcl_voluntary_installment_details

  --UNION ALL

  --SELECT * FROM compulsary_installment_details

  -- UNION ALL SELECT * FROM voluntary_onetime_no_installment_details

  -- UNION ALL SELECT * FROM compulsary_onetime_no_installment_details

),

--------------------------------------------------------------------------------------------------------



transformation AS (

  SELECT

    CTE_source,

    CompanyDB,

    OrderID,

    OrderItem,

    CASE WHEN InvoiceNo IS NULL AND TransactionStatus = 'SUCCESSFUL' THEN '' ELSE InvoiceNo END AS InvoiceNo,

    CAST(FORMAT_DATE('%d%m%Y', OrderDate) AS STRING) AS OrderDate,

    case

      WHEN InsuredID='' THEN '-'

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

    CASE

  WHEN InsuranceGroup = 'products/health-insurance'

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

      WHEN InsurerCode = 'insurers/30' THEN 'N30'--Generali--

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

      WHEN TransactionStatus = 'FOLLOWUP_STATUS_CANCELLED' THEN 'pending'

      WHEN TransactionStatus = 'FOLLOWUP_STATUS_OVERDUE' THEN 'pending'

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

      WHEN PaymentStatus = 'SUCCESSFUL' THEN 'fully paid'

      WHEN PaymentStatus = 'PENDING' THEN 'Not fully paid'

      ELSE PaymentStatus

    END AS PaymentStatus,

    ExpectedReceived,

    ActualReceived,

  InterestThisPeriod,

  PrincipleThisPeriod,

  InterestEIRThisPeriod,

  PrincipleEIRThisPeriod,

  CAST(FORMAT_DATE('%d%m%Y', PaymentDate) AS STRING) AS PaymentDate,

  Period,

  TotalPeriods,



  ROUND(((((TotalPremium+TotalEIR+TotalSBT+ProcessingFee+ProcessingFeeVat+ShippingFee+ShippingFeeVat)-Discount)-Discount)/TotalPeriods)*(TotalPeriods-Period),2) as PendingPayment,

  CASE

    WHEN PaymentDate IS NULL THEN NULL

    --WHEN InsuranceGroup = 'products/health-insurance' THEN 'OME Omise QR Prompt Pay'

    WHEN PaymentMethod = 'CASH' AND InsuranceGroup = 'products/health-insurance' THEN 'TRF Transfer'

    WHEN PaymentMethod = 'QR_CODE' AND InsuranceGroup = 'products/health-insurance' THEN 'OME Omise QR Prompt Pay'

    WHEN PaymentDate IS NULL THEN NULL

    ELSE PaymentMethod

  END AS PaymentMethod,

  CASE

    WHEN PaymentDate IS NULL THEN NULL

    --WHEN InsuranceGroup = 'products/health-insurance' THEN 'RCL-Omise QR Prompt Pay-Health'

    WHEN PaymentMethod = 'CASH' AND InsuranceGroup = 'products/health-insurance' THEN 'RCL-Transfer-อื่นๆ'

    WHEN PaymentMethod = 'QR_CODE' AND PaymentChannel = 'RABBIT_LENDING' AND InsuranceGroup = 'products/health-insurance' THEN 'RCL-Omise QR Prompt Pay-Health'

    WHEN PaymentMethod = 'DIRECT_PAYMENT' THEN 'RCL-DIRECT PAYMENT'

    WHEN PaymentMethod = 'DIRECT_DEBIT' AND PaymentChannel = 'RABBIT_LENDING' AND InsuranceGroup = 'products/health-insurance' THEN 'RCL-Direct Debit-Health'

    ELSE PaymentChannel

  END AS PaymentChannel,



CAST(FORMAT_DATE('%d%m%Y', ExpectedDate) AS STRING) AS ExpectedDate,

    RefOrder,

    RefundAmountBeforeFee,

    RefundAmountAfterFee,

    BillingAddress,

    CAST(FORMAT_DATE('%d%m%Y', BatchRunDate) AS STRING) AS BatchRunDate,

  FROM combine

  -- where PaymentMethod !='CASH'

),

--------------------------------------------------------------------------------------------------------



transformation_xxx as (

SELECT

  CTE_source,

  CompanyDB,

  OrderID,

  OrderItem	,

  CASE

    WHEN LOWER(TransactionStatus) = 'paid' THEN InvoiceNo

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

  ProductType,

  PolicyType,

  Endorse,

  PolicyDate,

  CASE

    WHEN PolicyNo IS NULL THEN ''

    ELSE PolicyNo

  END AS PolicyNo,

  CAST('' AS STRING) AS EndorsementNo,

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

  ExpectedReceived,

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

  IFNULL(PaymentMethod, '') AS PaymentMethod,

  IFNULL(PaymentChannel, '') AS PaymentChannel,

  ExpectedDate,

  get_charges_ref.order_id AS RefOrder,

  -- FLAGGED, NOT CHANGED: this hardcodes '' regardless of the RefundAmount

  -- fix upstream (FIX 5 in the header) -- pre-existing in the original

  -- query, not introduced by this edit. Confirm with Boat whether refunds

  -- are intentionally blanked out for installment plans (handled by a

  -- separate flow) before removing this override.

  '' AS RefundAmountBeforeFee,

  '' AS  RefundAmountAfterFee,

  BillingAddress,

  BatchRunDate



FROM transformation

LEFT JOIN get_charges_ref

  ON transformation.InvoiceNo=get_charges_ref.third_party_id

  AND get_charges_ref.order_id != transformation.OrderID

)



SELECT

  transformation_xxx.* EXCEPT(CTE_source)

FROM transformation_xxx



WHERE 1=1

ORDER BY OrderID,	TotalPeriods ,Period

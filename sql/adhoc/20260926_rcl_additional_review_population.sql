CREATE TEMP TABLE evidence_sap AS SELECT `DocEntry`, `CompanyDB`, `U_OrderID`, `U_OrderItem`, `U_InvoiceNo`, `OrderDate`, `U_InsuredID`, `U_Title`, `U_FirstName`, `U_LastName`, `U_InsurerCode`, `U_InsuranceGroup`, `U_InsuranceType`, `U_InsuranceProduct`, `U_ProductType`, `U_PolicyType`, `U_Endorse`, `PolicyDate`, `U_PolicyNo`, `EndorsementNo`, `U_ChassisNo`, `U_LicensePlate`, `GrossPremium`, `StampDuty`, `VAT`, `TotalPremium`, `WHT`, `TotalEIR`, `TotalSBT`, `U_ProcessingFee`, `U_ProcessingFeeVat`, `U_ShippingFee`, `U_ShippingFeeVat`, `U_TotalAmount`, `U_Discount`, `TransactionStatus`, `U_SubmissionStatus`, `U_ApprovalStatus`, `U_PaymentStatus`, `ExpectedReceived`, `U_ActualReceived`, `U_InterestThisPeriod`, `U_PrincipleThisPeriod`, `U_InterestEIRThisPeriod`, `U_PrincipleEIRThisPeriod`, `PaymentDate`, `U_Period`, `TotalPeriods`, `PendingPayment`, `PaymentMethod`, `PaymentChannel`, `ExpectedDate`, `RefOrder`, `RefundAmountBeforeFee`, `RefundAmountAfterFee`, `BillingAddress`, `BatchRunDate`, `UpdateDate` FROM `pacific-plating-282708.sap_integration_v2.SAP_LIVE_FULL`;
CREATE TEMP TABLE candidate_dashboard AS -- 2026-09-26 same-period payment correction. Source only; not deployed.
-- sap_dashboard_carepay_installment -- FIXED & TUNED VERSION
-- Fixed & tuned: 2026-08-28 (Boat review)
-- Changes:
--  1. FIX (bug, not just perf): removed unused `refunds` LEFT JOIN in
--     rcl_voluntary_installment_details. No refunds column was ever used
--     (RefundAmountBeforeFee/AfterFee are hardcoded 0), but the join could
--     silently DUPLICATE every installment period row for a transaction
--     that has more than one refund record. Zero output benefit, real
--     duplication risk. Removed the join and the now-unused `refunds` CTE.
--  2. FIX (logic, confirmed with Boat): credit-shell orders are now fully
--     EXCLUDED (not just relabeled), same pattern as sap_dashboard_carepay_
--     fully_paid: `orders.human_id NOT IN (SELECT human_id FROM change)`,
--     pushed into the `orders` CTE so it applies to both
--     rcl_voluntary_installment_details and compulsary_installment_details.
--     NOTE: the existing `LEFT JOIN change ... ` and its PaymentMethod/
--     RefOrder CASE branches were intentionally LEFT IN PLACE. After this
--     exclusion, that join can never match (any surviving order's human_id
--     is by construction absent from `change`), so those branches are now
--     dead code -- but `cancelled_change_orders` is a small table, the cost
--     of keeping a permanently-empty join is negligible, and rewriting the
--     CASE logic across the query to remove it risked a typo for no real
--     gain. Result is identical either way.
--  3. FIX (logic, confirmed with Boat): removed the `OR transactions.
--     installments > 1` fallback in rcl_voluntary_installment_details'
--     WHERE. This fallback was independent of the transaction_snapshots
--     number_of_installment>1 filter and could let a transaction that is
--     actually a one-time payment (mismatched/stale `installments` config
--     value) through as "installment". Structural check only now:
--     `transaction_snapshot_installment_details.id IS NOT NULL` --
--     this predicate is ALREADY guaranteed to imply number_of_installment>1,
--     because transaction_snapshot_installment_details only joins through
--     the pre-filtered transaction_snapshots CTE (see that CTE's WHERE).
--  4. FIX (logic, confirmed with Boat): EDC-installment orders are now
--     EXCLUDED. Confirmed signal: transactions.payment_option =
--     'CREDIT_CARD_INSTALLMENT' (charges.payment_method = 'EDC' at the
--     charge level, consistent with this). Filtered in the `transactions`
--     CTE using IS DISTINCT FROM (NULL-safe -- see note at that CTE).
--  5. Removed unused CTEs: `payment_options`, `prices` (declared, never
--     joined/referenced anywhere -- dead code).
--  6. Removed dead CTE chain: `check_order_items` -> `old_final` (declared,
--     but old_final is never referenced downstream -- the real pipeline is
--     transformation -> arrange -> finish -> arrange_again -> finish_2).
--  7. Removed intermediate `ORDER BY` inside CTEs `finish` and `finish_2`
--     (each gets joined/aggregated again afterward, so any sort there is
--     discarded and paid for twice). The final SELECT already has its own
--     ORDER BY -- same output, less sort cost.
-- NOT changed: all calculations, CASE logic, and the final SELECT/column
--     list are otherwise byte-identical to the original.
-- ============================================================

WITH
charges AS (
  SELECT * ,
  ROW_NUMBER() OVER (PARTITION BY transaction_id, installment_number ORDER BY create_time, id) AS charge_rank
  FROM `pacific-plating-282708.careos.carepay_charges`
  WHERE status = 'SUCCESSFUL'
  AND service_provider = 'RABBIT_LENDING'
),

follow_ups AS (
  SELECT * FROM `pacific-plating-282708.careos.carepay_follow_ups`
),

follow_up_first_due_dates AS (
  SELECT
    transaction_id,
    MIN(DATE(due_date)) AS first_due_date
  FROM follow_ups
  WHERE due_date IS NOT NULL
  GROUP BY transaction_id
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
  SELECT * EXCEPT(snapshot_rank)
  FROM (
    SELECT
      *,
      ROW_NUMBER() OVER (
        PARTITION BY transaction_id
        ORDER BY update_time DESC, id DESC
      ) AS snapshot_rank
    FROM `pacific-plating-282708.careos.carepay_transaction_snapshots`
  )
  WHERE snapshot_rank = 1
    AND number_of_installment > 1
),

installment_periods AS (
  SELECT
    transaction_snapshots.id AS snapshot_id,
    transaction_snapshots.transaction_id,
    transaction_snapshots.number_of_installment,
    period
  FROM transaction_snapshots
  CROSS JOIN UNNEST(
    GENERATE_ARRAY(1, transaction_snapshots.number_of_installment)
  ) AS period
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
    COALESCE(charges.charge_rank > 1, FALSE) AS is_additional_receipt,
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
      WHEN installment_periods.period = 1 THEN ROUND(ROUND((1 / 100) * transaction_snapshot_installment_details.payment_amount,2) - ROUND((1 / 100) * transaction_snapshot_installment_details.add_ons,2),2)
      ELSE ROUND((1 / 100) * transaction_snapshot_installment_details.payment_amount,2)
    END AS ExpectedReceived,
    CASE
      WHEN charge_rank IS NULL THEN 0  -- FIX #1: no charge yet for this period -> nothing actually received
      WHEN charge_rank = 1 THEN ROUND(ROUND((1 / 100) * charges.amount,2)- ROUND((1 / 100) * transaction_snapshot_installment_details.add_ons,2),2)
      ELSE ROUND((1 / 100) * COALESCE(charges.amount,transaction_snapshot_installment_details.payment_amount),2)
    END AS ActualReceived,
    CASE WHEN charge_rank <> 1 THEN 0
      WHEN transaction_snapshot_price_summaries.interest_amount = 0 OR transaction_snapshots.number_of_installment - 1 = 0 THEN 0
      WHEN installment_periods.period = 1 THEN 0
      ELSE ROUND((ROUND((1 / 100) * transaction_snapshot_price_summaries.interest_amount,2) - ((ROUND((1 / 100) * transaction_snapshot_price_summaries.interest_amount,2) * 3.3) / 103.3)) / (transaction_snapshots.number_of_installment - 1),2)
    END AS InterestThisPeriod,
    CASE
      WHEN (transaction_snapshots.number_of_installment - 1) = 0 THEN 0
      WHEN installment_periods.period = 1 AND charge_rank = 1 THEN ROUND((1 / 100) * charges.amount- ROUND((1 / 100) * transaction_snapshot_installment_details.add_ons,2),2)
      WHEN installment_periods.period = 1 AND charge_rank <> 1 THEN ROUND((1 / 100) * charges.amount,2)
      ELSE ROUND((ROUND((1/100)*transaction_snapshot_installment_details.payment_amount,2)) - ((ROUND((1/100)*transaction_snapshot_price_summaries.interest_amount,2) - ((ROUND((1/100)*transaction_snapshot_price_summaries.interest_amount,2)*3.3)/103.3))/(transaction_snapshots.number_of_installment-1)),2)
    END AS PrincipleThisPeriod,
    CASE WHEN charge_rank <> 1 THEN 0 ELSE ROUND((1 / 100) * transaction_snapshot_installment_details.interest,2) END AS InterestEIRThisPeriod,
    CASE WHEN (transaction_snapshots.number_of_installment - 1) = 0 THEN 0
      WHEN installment_periods.period = 1 AND charge_rank = 1 THEN ROUND((1 / 100) * charges.amount- ROUND((1 / 100) * transaction_snapshot_installment_details.add_ons,2),2)
      WHEN installment_periods.period = 1 AND charge_rank <> 1 THEN ROUND((1 / 100) * charges.amount,2)
      ELSE ROUND((1 / 100) * transaction_snapshot_installment_details.principal,2) END AS PrincipleEIRThisPeriod,
    charges.update_time AS PaymentDate,
    installment_periods.period AS Period,
    transaction_snapshots.number_of_installment AS TotalPeriods,
    CASE WHEN charge_rank <> 1 THEN 0 ELSE ROUND((1 / 100) * transaction_snapshot_installment_details.principal_balance,2) END AS PendingPayment, -- Need to check
    CASE WHEN installment_periods.period = 1 AND change.human_id IS NOT NULL AND charges.payment_method <> 'DIRECT_PAYMENT' THEN "RCL-Credit Shell"
      WHEN change.human_id IS NOT NULL AND charges.payment_method = 'DIRECT_PAYMENT' THEN 'DIRECT_PAYMENT'
      ELSE charges.payment_method END AS PaymentMethod,
    CASE WHEN installment_periods.period = 1 AND change.human_id IS NOT NULL AND charges.payment_method <> 'DIRECT_PAYMENT' THEN "RCL-Credit Shell"
      WHEN change.human_id IS NOT NULL AND charges.payment_method = 'DIRECT_PAYMENT' THEN 'RCL-DIRECT PAYMENT'
      ELSE charges.service_provider END AS PaymentChannel,
    COALESCE(
      DATE(follow_ups.due_date),
      DATE_ADD(
        follow_up_first_due_dates.first_due_date,
        INTERVAL installment_periods.period - 1 MONTH
      )
    ) AS ExpectedDate,
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
  LEFT JOIN installment_periods
    ON installment_periods.snapshot_id = transaction_snapshots.id
  LEFT JOIN transaction_snapshot_price_summaries
    ON transaction_snapshot_price_summaries.snapshot_id = transaction_snapshots.id
  LEFT JOIN transaction_snapshot_installment_details
    ON transaction_snapshot_installment_details.snapshot_id = transaction_snapshots.id
    AND transaction_snapshot_installment_details.period = installment_periods.period
  LEFT JOIN charges
    ON charges.transaction_id = transactions.id
    AND charges.installment_number = installment_periods.period
    AND charges.status NOT IN ('FAILED','PENDING')
    AND charges.service_provider = 'RABBIT_LENDING'  -- FIX #1: moved from WHERE so unmatched periods still survive the LEFT JOIN
  LEFT JOIN order_items
    ON order_items.order_id = orders.id
  LEFT JOIN refunds
    ON refunds.transaction_id = transactions.id
  LEFT JOIN follow_ups
    ON follow_ups.transaction_id = transactions.id
    AND follow_ups.installment = installment_periods.period
  LEFT JOIN follow_up_first_due_dates
    ON follow_up_first_due_dates.transaction_id = transactions.id
  LEFT JOIN takeaway_compulsary
    ON takeaway_compulsary.transaction_snapshot_id = transaction_snapshots.id
  LEFT JOIN change on change.human_id = orders.human_id
 WHERE
  installment_periods.period IS NOT NULL
   AND order_items.product = 'products/car-insurance'
   AND order_items.motor_item_type <> 'MOTOR_TYPE_COMPULSORY'
   -- Keep every successful charge; rank > 1 has ExpectedReceived = 0.
    -- one row per period, including unpaid periods
   --AND (follow_ups.transaction_id IS NOT NULL)
   -- FIX #1: removed "AND charges.service_provider = 'RABBIT_LENDING'" here — it was on the joined (nullable)
   -- table, which silently turned the LEFT JOIN charges above into an INNER JOIN and dropped every period
   -- that didn't yet have a SUCCESSFUL charge (e.g. unpaid periods 2-6 of a 6-installment plan).
),
--------------------------------------------------------------------------------------------------------
--------------------------------------------------------------------------------------------------------

compulsary_installment_details AS (
  SELECT
    'compulsary_installment_details' AS CTE_source,
    FALSE AS is_additional_receipt,
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
    COALESCE(
      DATE(follow_ups.due_date),
      DATE_ADD(
        follow_up_first_due_dates.first_due_date,
        INTERVAL transaction_snapshot_installment_details.period - 1 MONTH
      )
    ) AS ExpectedDate,
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
    AND charges.service_provider = 'RABBIT_LENDING'
  LEFT JOIN leads
    ON CONCAT('leads/',leads.id) = orders.lead
  LEFT JOIN follow_ups
    ON follow_ups.transaction_id = transactions.id
    AND follow_ups.installment = transaction_snapshot_installment_details.period
  LEFT JOIN follow_up_first_due_dates
    ON follow_up_first_due_dates.transaction_id = transactions.id
  LEFT JOIN change on change.human_id = orders.human_id
  WHERE
    order_items.motor_item_type = 'MOTOR_TYPE_COMPULSORY'
    AND transaction_snapshot_installment_details.id IS NOT NULL
    AND transaction_snapshot_installment_details.period = 1
    AND charges.charge_rank = 1
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
    is_additional_receipt,
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
    ROUND(
        COALESCE(TotalPremium, 0)
      + COALESCE(TotalEIR, 0)
      + COALESCE(TotalSBT, 0)
      + COALESCE(ProcessingFee, 0)
      + COALESCE(ProcessingFeeVat, 0)
      + COALESCE(ShippingFee, 0)
      + COALESCE(ShippingFeeVat, 0),
      2
    ) AS TotalAmount,
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
  WHEN PaymentDate IS NULL THEN NULL
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
  ROUND(
    SAFE_DIVIDE(
        COALESCE(TotalPremium, 0)
      + COALESCE(TotalEIR, 0)
      + COALESCE(TotalSBT, 0)
      + COALESCE(ProcessingFee, 0)
      + COALESCE(ProcessingFeeVat, 0)
      + COALESCE(ShippingFee, 0)
      + COALESCE(ShippingFeeVat, 0)
      - COALESCE(Discount, 0),
      NULLIF(TotalPeriods, 0)
    ) * (TotalPeriods - Period),
    2
  ) AS PendingPayment,
  CASE WHEN COALESCE(TransactionStatus, '') <> 'SUCCESSFUL' THEN ''
    WHEN PaymentMethod ='DIRECT_PAYMENT'and PaymentChannel ='SERVICE_PROVIDER_UNSPECIFIED' THEN 'DPM จ่ายตรงกับบริษัทประกัน'
    WHEN InsuranceType = 'MOTOR_TYPE_COMPULSORY' THEN 'RCL-CMI-channel'
    WHEN PaymentMethod = 'CASH' THEN 'TRF Transfer'
    WHEN PaymentMethod = 'QR_CODE' THEN 'OME Omise QR Prompt Pay'
    WHEN PaymentMethod = 'BANK_TRANSFER' THEN 'TRF Transfer'
    ELSE PaymentMethod
  END AS PaymentMethod,
  CASE WHEN COALESCE(TransactionStatus, '') <> 'SUCCESSFUL' THEN ''
    WHEN PaymentMethod ='DIRECT_PAYMENT'and PaymentChannel ='SERVICE_PROVIDER_UNSPECIFIED' THEN 'RCL-DIRECT PAYMENT'
    WHEN InsuranceType = 'MOTOR_TYPE_COMPULSORY' THEN 'RCL-CMI-channel'
    WHEN InsuranceGroup != 'products/car-insurance' AND PaymentMethod = 'QR_CODE' THEN 'RCL-Omise QR Prompt Pay-Health'  -- FIX #2 (Root Cause 8)
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
  transformation.is_additional_receipt,
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
    WHEN transformation.is_additional_receipt THEN 0
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
    WHEN finish.is_additional_receipt THEN 0
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
ORDER BY OrderItem, Period;
CREATE TEMP TABLE candidate_newpayment AS -- 2026-09-26 same-period payment correction. Source only; not deployed.
-- SELECT-only replacement for sap_integration_v2.RCL 05_newpayment.
-- Ordinary periods keep the existing paid-period exclusion.
-- Additional payments use immutable event identity, including the established
-- raw/2_ invoice alias for installment 1. No SAP values are rewritten.
WITH
  sap_paid_periods AS (
    SELECT DISTINCT U_OrderItem AS order_item, SAFE_CAST(U_Period AS INT64) AS period
    FROM evidence_sap
    WHERE TransactionStatus IN ('Paid', 'paid')
  ),
  sap_terminal_events AS (
    SELECT DISTINCT U_OrderItem AS order_item, SAFE_CAST(U_Period AS INT64) AS period,
      U_InvoiceNo AS invoice_no
    FROM evidence_sap
    WHERE LOWER(TRIM(TransactionStatus)) IN
      ('paid', 'cancelled', 'cancelled (change order / rejected)')
      AND NULLIF(TRIM(U_InvoiceNo), '') IS NOT NULL
      AND UPPER(TRIM(U_InvoiceNo)) != 'NULL'
  ),
  source_receipts AS (
    SELECT id, transaction_id, installment_number, third_party_id, create_time, update_time,
      ROW_NUMBER() OVER (PARTITION BY transaction_id, installment_number ORDER BY create_time, id) AS source_charge_rank,
      COUNT(*) OVER (PARTITION BY id) AS charge_id_rows,
      COUNT(*) OVER (PARTITION BY transaction_id, installment_number, third_party_id) AS invoice_rows,
      COUNT(*) OVER (PARTITION BY transaction_id, installment_number, create_time) AS timestamp_rows
    FROM `pacific-plating-282708.careos.carepay_charges`
    WHERE status = 'SUCCESSFUL' AND service_provider = 'RABBIT_LENDING'
  ),
  source_receipt_events AS (
    -- Preserve rank lineage even when additional-receipt eligibility fails.
    -- The fallback mirrors dashboard identity ONLY for classification; it is
    -- never accepted as a new additional receipt's invoice identity.
    SELECT oi.human_id AS order_item, c.installment_number AS period,
      CASE WHEN c.installment_number = 1 THEN CONCAT('2_', COALESCE(c.third_party_id, oi.human_id))
        ELSE COALESCE(c.third_party_id, oi.human_id) END AS invoice_no,
      MIN(c.update_time) AS raw_update_time,
      CASE WHEN COUNT(*) = 1 THEN MIN(c.source_charge_rank) END AS source_charge_rank,
      COUNT(*) AS source_event_rows,
      COUNT(*) = 1 AND COUNTIF(
        NULLIF(TRIM(c.id), '') IS NULL
        OR NULLIF(TRIM(c.third_party_id), '') IS NULL
        OR UPPER(TRIM(c.third_party_id)) = 'NULL'
        OR c.charge_id_rows != 1 OR c.invoice_rows != 1 OR c.timestamp_rows != 1
      ) = 0 AS additional_identity_valid
    FROM source_receipts c
    JOIN `pacific-plating-282708.careos.careos_orders` o
      ON o.payment = CONCAT('transactions/', c.transaction_id)
    JOIN `pacific-plating-282708.careos.careos_order_items` oi
      ON oi.order_id = o.id
    WHERE NULLIF(TRIM(oi.human_id), '') IS NOT NULL
    GROUP BY order_item, period, invoice_no
  ),
  interface AS (
    SELECT
      d.CompanyDB,
      d.OrderID,
      d.OrderItem,
      d.InvoiceNo,
      d.OrderDate,
      d.InsuredID,
      d.Title,
      d.FirstName,
      d.LastName,
      d.InsurerCode,
      d.InsuranceGroup,
      d.InsuranceType,
      d.InsuranceProduct,
      d.ProductType,
      d.PolicyType,
      d.Endorse,
      d.PolicyDate,
      d.PolicyNo,
      d.EndorsementNo,
      d.ChassisNo,
      d.LicensePlate,
      d.GrossPremium,
      d.StampDuty,
      d.VAT,
      d.TotalPremium,
      d.WHT,
      d.TotalEIR,
      d.TotalSBT,
      d.ProcessingFee,
      d.ProcessingFeeVat,
      d.ShippingFee,
      d.ShippingFeeVat,
      d.TotalAmount,
      d.Discount,
      d.TransactionStatus,
      d.SubmissionStatus,
      d.ApprovalStatus,
      d.PaymentStatus,
      d.ExpectedReceived,
      d.ActualReceived,
      d.InterestThisPeriod,
      d.PrincipleThisPeriod,
      d.InterestEIRThisPeriod,
      d.PrincipleEIRThisPeriod,
      d.PaymentDate,
      d.Period,
      d.TotalPeriods,
      d.PendingPayment,
      d.PaymentMethod,
      d.PaymentChannel,
      d.ExpectedDate,
      d.RefOrder,
      CAST(d.RefundAmountBeforeFee AS FLOAT64) AS RefundAmountBeforeFee,
      CAST(d.RefundAmountAfterFee AS FLOAT64) AS RefundAmountAfterFee,
      d.BillingAddress,
      d.BatchRunDate,
      SAFE_CAST(d.Period AS INT64) AS careos_installment,
      v.source_charge_rank, v.source_event_rows, v.additional_identity_valid,
      COALESCE(ExpectedReceived = 0, FALSE)
        AND COALESCE(ActualReceived, 0) > 0
        AND LOWER(TRIM(COALESCE(TransactionStatus, ''))) = 'paid'
        AS has_additional_shape
    FROM candidate_dashboard d
    LEFT JOIN source_receipt_events v ON v.order_item=d.OrderItem
      AND v.period=SAFE_CAST(d.Period AS INT64) AND v.invoice_no=d.InvoiceNo
  )
SELECT DISTINCT
  interface.CompanyDB,
  interface.OrderID,
  interface.OrderItem,
  interface.InvoiceNo,
  interface.OrderDate,
  interface.InsuredID,
  interface.Title,
  interface.FirstName,
  interface.LastName,
  interface.InsurerCode,
  interface.InsuranceGroup,
  interface.InsuranceType,
  interface.InsuranceProduct,
  interface.ProductType,
  interface.PolicyType,
  interface.Endorse,
  interface.PolicyDate,
  interface.PolicyNo,
  interface.EndorsementNo,
  interface.ChassisNo,
  interface.LicensePlate,
  interface.GrossPremium,
  interface.StampDuty,
  interface.VAT,
  interface.TotalPremium,
  interface.WHT,
  interface.TotalEIR,
  interface.TotalSBT,
  interface.ProcessingFee,
  interface.ProcessingFeeVat,
  interface.ShippingFee,
  interface.ShippingFeeVat,
  interface.TotalAmount,
  interface.Discount,
  interface.TransactionStatus,
  interface.SubmissionStatus,
  interface.ApprovalStatus,
  interface.PaymentStatus,
  interface.ExpectedReceived,
  interface.ActualReceived,
  interface.InterestThisPeriod,
  interface.PrincipleThisPeriod,
  interface.InterestEIRThisPeriod,
  interface.PrincipleEIRThisPeriod,
  interface.PaymentDate,
  interface.Period,
  interface.TotalPeriods,
  interface.PendingPayment,
  interface.PaymentMethod,
  interface.PaymentChannel,
  interface.ExpectedDate,
  interface.RefOrder,
  interface.RefundAmountBeforeFee,
  interface.RefundAmountAfterFee,
  interface.BillingAddress,
  interface.BatchRunDate
FROM interface
WHERE interface.careos_installment IS NOT NULL
  AND (
    (
      (
        interface.source_charge_rank = 1
        OR (interface.source_event_rows IS NULL AND COALESCE(interface.ActualReceived, 0) = 0)
      )
      AND NOT EXISTS (
        SELECT 1 FROM sap_paid_periods p
        WHERE p.order_item = interface.OrderItem
          AND p.period = interface.careos_installment
      )
    )
    OR (
      interface.source_charge_rank > 1
      AND interface.has_additional_shape
      AND interface.additional_identity_valid
      AND NULLIF(TRIM(interface.InvoiceNo), '') IS NOT NULL
      AND UPPER(TRIM(interface.InvoiceNo)) != 'NULL'
      AND NOT EXISTS (
        SELECT 1 FROM sap_terminal_events e
        WHERE e.order_item = interface.OrderItem
          AND e.period = interface.careos_installment
          AND (
            e.invoice_no = interface.InvoiceNo
            OR (
              interface.careos_installment = 1
              AND STARTS_WITH(interface.InvoiceNo, '2_')
              AND e.invoice_no = SUBSTR(interface.InvoiceNo, 3)
            )
          )
      )
    )
  )
ORDER BY interface.OrderItem, interface.Period
;
CREATE TEMP TABLE candidate_gate AS -- 2026-09-26 same-period payment correction. Source only; not deployed.
-- RCL 05_paid by period -- FIXED & CREATED 2026-08-29 (Boat review)
-- Previously this logic lived (mislabeled) under `RCL 05_newpayment`.
-- Bug fixed here: original version joined `sap` to `charges` (ALL periods
-- ever paid) instead of `charges_ranking` (latest period only), then
-- relied on DISTINCT to collapse -- this let orders where an OLD period
-- was still missing from SAP mask the fact that the LATEST period was
-- already Paid+Paid, producing false "qualified" rows
-- (e.g. "1/10 CareOS paid, SAP paid" wrongly surfaced).
-- Fix: NOT EXISTS check scoped to charges_ranking.installment_number
-- (the actual latest period) plus OrderItem-level join key (was OrderID-only).
WITH charges AS (
  SELECT *
  FROM `pacific-plating-282708.careos.carepay_charges`
  WHERE status = 'SUCCESSFUL'
),

charges_ranking AS (
  SELECT *,
    ROW_NUMBER() OVER (PARTITION BY transaction_id ORDER BY installment_number DESC) AS rank
  FROM charges
  QUALIFY rank = 1
),

sap_paid_periods AS (
  -- exact per-(OrderItem, Period) existence check -- NOT a MAX watermark, NOT an all-period fan-out
  SELECT DISTINCT
    U_OrderItem AS order_item,
    SAFE_CAST(U_Period AS INT64) AS period
  FROM evidence_sap
  WHERE TransactionStatus IN ('Paid', 'paid')
)
,
additional_items AS (
  -- Only genuinely unsent additional events can reopen an already-paid item.
  SELECT DISTINCT OrderItem
  FROM candidate_newpayment n
  JOIN `pacific-plating-282708.careos.careos_order_items` oi ON oi.human_id = n.OrderItem
  JOIN `pacific-plating-282708.careos.careos_orders` o ON o.id = oi.order_id
  JOIN (
    SELECT transaction_id, installment_number, third_party_id, update_time,
      ROW_NUMBER() OVER (PARTITION BY transaction_id, installment_number ORDER BY create_time, id) AS source_charge_rank
    FROM `pacific-plating-282708.careos.carepay_charges`
    WHERE status='SUCCESSFUL' AND service_provider='RABBIT_LENDING'
  ) c
    ON o.payment = CONCAT('transactions/', c.transaction_id)
    AND c.installment_number = SAFE_CAST(n.Period AS INT64)
    AND n.InvoiceNo = CASE WHEN c.installment_number = 1
      THEN CONCAT('2_', c.third_party_id) ELSE c.third_party_id END
    AND c.source_charge_rank > 1
  WHERE ExpectedReceived = 0
    AND ActualReceived > 0
    AND LOWER(TRIM(TransactionStatus)) = 'paid'
    AND NULLIF(TRIM(InvoiceNo), '') IS NOT NULL
    AND UPPER(TRIM(InvoiceNo)) != 'NULL'
    AND DATE(c.update_time)
      BETWEEN DATE_TRUNC(DATE_SUB(CURRENT_DATE(), INTERVAL 2 MONTH), MONTH)
      AND CURRENT_DATE()
)

SELECT DISTINCT
  orders.human_id,
  oi.human_id AS order_item,
  orders.create_time AS order_create_time,
  orders.update_time AS order_update_time,
  orders.is_fully_paid,
  orders.is_cancelled,
  transactions.payment_option,
  charges_ranking.installment_number,
  orders.cancel_time,
  charges_ranking.update_time AS charges_update_time,
  CASE
    WHEN orders.create_time < '2024-03-28' THEN 'icollection'
    ELSE 'carepay'
  END AS sql_view_using,
  orders.product,
  oi.motor_item_type AS InsuranceType
FROM `pacific-plating-282708.careos.careos_orders` AS orders
LEFT JOIN `pacific-plating-282708.careos.careos_order_items` AS oi
  ON orders.id = oi.order_id
LEFT JOIN `pacific-plating-282708.careos.carepay_transactions` AS transactions
  ON CONCAT('transactions/', transactions.id) = orders.payment
LEFT JOIN charges_ranking
  ON charges_ranking.transaction_id = transactions.id
LEFT JOIN additional_items AS additional
  ON additional.OrderItem = oi.human_id
WHERE 1=1
  AND charges_ranking.installment_number IS NOT NULL
  AND (
    DATE(charges_ranking.update_time)
      BETWEEN DATE_TRUNC(DATE_SUB(CURRENT_DATE(), INTERVAL 2 MONTH), MONTH)
      AND CURRENT_DATE()
    OR additional.OrderItem IS NOT NULL
  )
  AND transactions.payment_option = 'RABBIT_CARE_INSTALLMENT'
  AND (
    NOT EXISTS (
      SELECT 1
      FROM sap_paid_periods p
      WHERE p.order_item = oi.human_id
        AND p.period = charges_ranking.installment_number
    )
    OR additional.OrderItem IS NOT NULL
  )
ORDER BY orders.create_time ASC;
CREATE TEMP TABLE evidence_paid AS -- RCL 05_paid -- FIXED & TUNED VERSION

-- Fixed & tuned: 2026-08-28 (Boat review)

-- Changes:

--  1. FIX (crash risk): SPLIT(...)[OFFSET(1)] -> SAFE_OFFSET(1). OFFSET

--     throws a hard runtime error if U_InsurerCode has no '-'; SAFE_OFFSET

--     returns NULL instead. No behavior change for well-formed data.

--  2. FIX (perf + clarity): removed the `newpayment` CTE (MAX(Period) WHERE

--     Paid, GROUP BY OrderItem) and its JOIN + `Period <= pp` condition.

--     This was NOT a real watermark bug here (unlike 05_newpayment) --

--     since the main WHERE already requires TransactionStatus IN

--     ('Paid','paid'), any surviving row's own period is BY DEFINITION <=

--     the max paid period for its OrderItem (it's part of the set being

--     maxed). The condition was tautological for every row that passes.

--     Its only real effect: SAFE_CAST(Period AS INT64) returning NULL for

--     non-numeric Period values made `NULL <= pp` evaluate NULL, silently

--     dropping those rows. That guard is now explicit and direct below,

--     without paying for a full-table GROUP BY over SAP_LIVE_FULL to get it.

--  3. NOT changed (confirmed with Boat, keep as-is): the TransactionStatus

--     override (any row with a non-null InvoiceNo not starting with 'L'

--     gets forced to 'Paid') -- known legacy workaround, intentional.

--  4. NOT changed (flagged, not yet confirmed): `cmi` CTE's date cutoff

--     (create_time < start of this month) means CMI order items created

--     THIS month are not excluded and can still pass through. Flagging

--     only -- not changed since not explicitly confirmed either way.

-- ============================================================



WITH

  sap AS (

  SELECT

    DISTINCT CompanyDB,

    U_OrderID OrderID,

    U_OrderItem OrderItem,

    U_InvoiceNo InvoiceNo,

    OrderDate AS OrderDate,

    U_InsuredID InsuredID,

    U_Title Title,

    U_FirstName FirstName,

    U_LastName LastName,

    SPLIT(U_InsurerCode, '-')[SAFE_OFFSET(1)] AS InsurerCode,

    U_InsuranceGroup InsuranceGroup,

    U_InsuranceType InsuranceType,

    U_InsuranceProduct InsuranceProduct,

    CASE

      WHEN U_ProductType = 'NULL' THEN 'Insurance'

      ELSE U_ProductType

    END

    AS ProductType,

    U_PolicyType PolicyType,

    'N' Endorse,

    PolicyDate AS PolicyDate,

    U_PolicyNo PolicyNo,

    EndorsementNo EndorsementNo,

    U_ChassisNo ChassisNo,

    U_LicensePlate LicensePlate,

    GrossPremium GrossPremium,

    StampDuty StampDuty,

    VAT VAT,

    TotalPremium TotalPremium,

    WHT WHT,

    TotalEIR TotalEIR,

    TotalSBT TotalSBT,

    U_ProcessingFee ProcessingFee,

    U_ProcessingFeeVat ProcessingFeeVat,

    U_ShippingFee ShippingFee,

    U_ShippingFeeVat ShippingFeeVat,

    U_TotalAmount TotalAmount,

    U_Discount Discount,

    --CASE WHEN change.old_human_id IS NOT NULL THEN 'Cancelled (Change order / Rejected)' ELSE 'Cancelled'END AS TransactionStatus,

    -- NOT changed (confirmed with Boat, 2026-08-28): keep this override as-is.

    CASE WHEN TransactionStatus NOT IN ('Paid', 'paid') AND U_InvoiceNo IS NOT NULL AND U_InvoiceNo NOT LIKE 'L%'

    THEN 'Paid' ELSE TransactionStatus END AS TransactionStatus,

    U_SubmissionStatus SubmissionStatus,

    U_ApprovalStatus ApprovalStatus,

    U_PaymentStatus PaymentStatus,

    ExpectedReceived,

    U_ActualReceived ActualReceived,

    U_InterestThisPeriod InterestThisPeriod,

    U_PrincipleThisPeriod PrincipleThisPeriod,

    U_InterestEIRThisPeriod InterestEIRThisPeriod,

    U_PrincipleEIRThisPeriod PrincipleEIRThisPeriod,

    CASE

      WHEN PaymentDate = 'NULL' THEN ''

      ELSE PaymentDate

  END

    AS PaymentDate,

    U_Period Period,

    TotalPeriods TotalPeriods,

    PendingPayment PendingPayment,

    CASE

      WHEN PaymentMethod = 'NULL' THEN ''

      ELSE PaymentMethod

  END

    AS PaymentMethod,

    CASE

      WHEN PaymentChannel = 'NULL' THEN ''

      ELSE PaymentChannel

  END

    AS PaymentChannel,

    ExpectedDate AS ExpectedDate,

    RefOrder RefOrder,

    RefundAmountBeforeFee RefundAmountBeforeFee,

    RefundAmountAfterFee RefundAmountAfterFee,

    BillingAddress BillingAddress,

    CAST(FORMAT_DATE('%d%m%Y', CURRENT_DATE()) AS STRING) AS BatchRunDate



  FROM

    evidence_sap

    WHERE PaymentChannel LIKE '%RCL%'),



  cancelled AS (  SELECT distinct U_OrderItem

  FROM evidence_sap

  WHERE (U_OrderID like '%C%'

  OR TransactionStatus in ('Cancelled','Cancelled (Change order / Rejected)'))

  AND PaymentChannel LIKE '%RCL%'

),



  cmi AS (SELECT human_id order_item,*

  FROM `pacific-plating-282708.careos.careos_order_items`

  WHERE DATE(create_time) < DATE(DATE_TRUNC(CURRENT_DATE(), MONTH))

  AND motor_item_type = 'MOTOR_TYPE_COMPULSORY'

  )



SELECT DISTINCT

  sap.*

FROM sap

LEFT JOIN cancelled

  ON cancelled.U_OrderItem = sap.OrderItem

LEFT JOIN cmi

  ON cmi.order_item = sap.OrderItem

WHERE

SAFE_CAST(sap.Period AS INT64) IS NOT NULL  -- FIX 2: direct guard, replaces the removed MAX-watermark join

AND OrderID NOT LIKE '%_X%'

AND cancelled.U_OrderItem IS NULL

AND cmi.order_item IS NULL

AND sap.InvoiceNo IS NOT NULL

AND sap.TransactionStatus in ('Paid', 'paid')



Order by OrderID, Period;
CREATE TEMP TABLE candidate_wrapper AS -- Full source-only legacy root-fix proposal for:
--   pacific-plating-282708.sap_view.RCL_Motor_process_2_newpayment
--
-- Root fixes:
--   1. Route only products/car-insurance into this Motor interface.
--   2. Exclude an OrderItem when the canonical CareOS item is cancelled. This keeps the
--      whole cancelled schedule out of new-payment instead of mixing current pending rows
--      with historical SAP Paid rows removed by RCL 05_paid.
--   3. Preserve legitimate same-period additional-payment rows. ExpectedReceived = 0 rows
--      are deduplicated by InvoiceNo (or their existing deterministic fallback), while a
--      normal scheduled row remains one row per OrderItem/Period.
--
-- SELECT only: this file does not replace or deploy the legacy view.

WITH
  interface AS (
    SELECT *
    FROM evidence_paid

    UNION ALL

    SELECT *
    FROM candidate_newpayment
  ),

  eligible_newpayment_items AS (
    SELECT DISTINCT
      paid_by_period.order_item
    FROM candidate_gate AS paid_by_period
    JOIN `pacific-plating-282708.careos.careos_order_items` AS order_item
      ON order_item.human_id = paid_by_period.order_item
    WHERE paid_by_period.product = 'products/car-insurance'
      AND paid_by_period.InsuranceType != 'MOTOR_TYPE_COMPULSORY'
      AND order_item.is_cancelled IS NOT TRUE
      AND order_item.cancel_time IS NULL
  ),

  source AS (
    SELECT DISTINCT
      interface.*
    FROM interface
    JOIN eligible_newpayment_items
      ON eligible_newpayment_items.order_item = interface.OrderItem
    WHERE SAFE.PARSE_DATE('%d%m%Y', interface.OrderDate) >= DATE '2026-01-01'
      -- Fail closed against RCB/RCL and NonMotor routing leakage.
      AND interface.InsuranceGroup = 'Motor'
      AND interface.InsuranceType != 'MOTOR_TYPE_COMPULSORY'
  ),

  classified AS (
    SELECT
      source.*,
      CASE
        WHEN COALESCE(source.ExpectedReceived, 0) = 0
          AND COALESCE(source.ActualReceived, 0) > 0
        THEN 1
        ELSE 0
      END AS is_additional_payment,
      ROW_NUMBER() OVER (
        PARTITION BY
          source.OrderItem,
          source.Period,
          CASE
            WHEN COALESCE(source.ExpectedReceived, 0) = 0
              AND COALESCE(source.ActualReceived, 0) > 0
            THEN COALESCE(
              NULLIF(source.InvoiceNo, ''),
              CONCAT(
                'additional_',
                CAST(source.ActualReceived AS STRING),
                '_',
                COALESCE(source.PaymentDate, '')
              )
            )
            ELSE 'normal_period_row'
          END
        ORDER BY
          CASE
            WHEN source.InvoiceNo IS NOT NULL
              AND source.InvoiceNo NOT IN ('', 'null', 'NULL')
            THEN 1 ELSE 2
          END,
          CASE
            WHEN source.PolicyNo IS NOT NULL
              AND source.PolicyNo NOT IN ('', 'null', 'NULL')
            THEN 1 ELSE 2
          END,
          CASE
            WHEN source.PaymentDate IS NOT NULL
              AND source.PaymentDate NOT IN ('', 'null', 'NULL')
            THEN 1 ELSE 2
          END,
          source.PaymentDate DESC
      ) AS rn
    FROM source
  )

SELECT
  * EXCEPT (is_additional_payment, rn)
FROM classified
WHERE rn = 1
ORDER BY OrderID, OrderItem, Period;
CREATE TEMP TABLE baseline_dashboard AS -- sap_dashboard_carepay_installment -- FIXED & TUNED VERSION
-- Fixed & tuned: 2026-08-28 (Boat review)
-- Changes:
--  1. FIX (bug, not just perf): removed unused `refunds` LEFT JOIN in
--     rcl_voluntary_installment_details. No refunds column was ever used
--     (RefundAmountBeforeFee/AfterFee are hardcoded 0), but the join could
--     silently DUPLICATE every installment period row for a transaction
--     that has more than one refund record. Zero output benefit, real
--     duplication risk. Removed the join and the now-unused `refunds` CTE.
--  2. FIX (logic, confirmed with Boat): credit-shell orders are now fully
--     EXCLUDED (not just relabeled), same pattern as sap_dashboard_carepay_
--     fully_paid: `orders.human_id NOT IN (SELECT human_id FROM change)`,
--     pushed into the `orders` CTE so it applies to both
--     rcl_voluntary_installment_details and compulsary_installment_details.
--     NOTE: the existing `LEFT JOIN change ... ` and its PaymentMethod/
--     RefOrder CASE branches were intentionally LEFT IN PLACE. After this
--     exclusion, that join can never match (any surviving order's human_id
--     is by construction absent from `change`), so those branches are now
--     dead code -- but `cancelled_change_orders` is a small table, the cost
--     of keeping a permanently-empty join is negligible, and rewriting the
--     CASE logic across the query to remove it risked a typo for no real
--     gain. Result is identical either way.
--  3. FIX (logic, confirmed with Boat): removed the `OR transactions.
--     installments > 1` fallback in rcl_voluntary_installment_details'
--     WHERE. This fallback was independent of the transaction_snapshots
--     number_of_installment>1 filter and could let a transaction that is
--     actually a one-time payment (mismatched/stale `installments` config
--     value) through as "installment". Structural check only now:
--     `transaction_snapshot_installment_details.id IS NOT NULL` --
--     this predicate is ALREADY guaranteed to imply number_of_installment>1,
--     because transaction_snapshot_installment_details only joins through
--     the pre-filtered transaction_snapshots CTE (see that CTE's WHERE).
--  4. FIX (logic, confirmed with Boat): EDC-installment orders are now
--     EXCLUDED. Confirmed signal: transactions.payment_option =
--     'CREDIT_CARD_INSTALLMENT' (charges.payment_method = 'EDC' at the
--     charge level, consistent with this). Filtered in the `transactions`
--     CTE using IS DISTINCT FROM (NULL-safe -- see note at that CTE).
--  5. Removed unused CTEs: `payment_options`, `prices` (declared, never
--     joined/referenced anywhere -- dead code).
--  6. Removed dead CTE chain: `check_order_items` -> `old_final` (declared,
--     but old_final is never referenced downstream -- the real pipeline is
--     transformation -> arrange -> finish -> arrange_again -> finish_2).
--  7. Removed intermediate `ORDER BY` inside CTEs `finish` and `finish_2`
--     (each gets joined/aggregated again afterward, so any sort there is
--     discarded and paid for twice). The final SELECT already has its own
--     ORDER BY -- same output, less sort cost.
-- NOT changed: all calculations, CASE logic, and the final SELECT/column
--     list are otherwise byte-identical to the original.
-- ============================================================

WITH
charges AS (
  SELECT * ,
  ROW_NUMBER() OVER (PARTITION BY transaction_id, installment_number ORDER BY create_time) AS charge_rank
  FROM `pacific-plating-282708.careos.carepay_charges`
  WHERE status = 'SUCCESSFUL'
  AND service_provider = 'RABBIT_LENDING'
),

follow_ups AS (
  SELECT * FROM `pacific-plating-282708.careos.carepay_follow_ups`
),

follow_up_first_due_dates AS (
  SELECT
    transaction_id,
    MIN(DATE(due_date)) AS first_due_date
  FROM follow_ups
  WHERE due_date IS NOT NULL
  GROUP BY transaction_id
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
  SELECT * EXCEPT(snapshot_rank)
  FROM (
    SELECT
      *,
      ROW_NUMBER() OVER (
        PARTITION BY transaction_id
        ORDER BY update_time DESC, id DESC
      ) AS snapshot_rank
    FROM `pacific-plating-282708.careos.carepay_transaction_snapshots`
  )
  WHERE snapshot_rank = 1
    AND number_of_installment > 1
),

installment_periods AS (
  SELECT
    transaction_snapshots.id AS snapshot_id,
    transaction_snapshots.transaction_id,
    transaction_snapshots.number_of_installment,
    period
  FROM transaction_snapshots
  CROSS JOIN UNNEST(
    GENERATE_ARRAY(1, transaction_snapshots.number_of_installment)
  ) AS period
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
      WHEN installment_periods.period = 1 THEN ROUND(ROUND((1 / 100) * transaction_snapshot_installment_details.payment_amount,2) - ROUND((1 / 100) * transaction_snapshot_installment_details.add_ons,2),2)
      ELSE ROUND((1 / 100) * transaction_snapshot_installment_details.payment_amount,2)
    END AS ExpectedReceived,
    CASE
      WHEN charge_rank IS NULL THEN 0  -- FIX #1: no charge yet for this period -> nothing actually received
      WHEN charge_rank = 1 THEN ROUND(ROUND((1 / 100) * charges.amount,2)- ROUND((1 / 100) * transaction_snapshot_installment_details.add_ons,2),2)
      ELSE ROUND((1 / 100) * COALESCE(charges.amount,transaction_snapshot_installment_details.payment_amount),2)
    END AS ActualReceived,
    CASE WHEN charge_rank <> 1 THEN 0
      WHEN transaction_snapshot_price_summaries.interest_amount = 0 OR transaction_snapshots.number_of_installment - 1 = 0 THEN 0
      WHEN installment_periods.period = 1 THEN 0
      ELSE ROUND((ROUND((1 / 100) * transaction_snapshot_price_summaries.interest_amount,2) - ((ROUND((1 / 100) * transaction_snapshot_price_summaries.interest_amount,2) * 3.3) / 103.3)) / (transaction_snapshots.number_of_installment - 1),2)
    END AS InterestThisPeriod,
    CASE
      WHEN (transaction_snapshots.number_of_installment - 1) = 0 THEN 0
      WHEN installment_periods.period = 1 AND charge_rank = 1 THEN ROUND((1 / 100) * charges.amount- ROUND((1 / 100) * transaction_snapshot_installment_details.add_ons,2),2)
      WHEN installment_periods.period = 1 AND charge_rank <> 1 THEN ROUND((1 / 100) * charges.amount,2)
      ELSE ROUND((ROUND((1/100)*transaction_snapshot_installment_details.payment_amount,2)) - ((ROUND((1/100)*transaction_snapshot_price_summaries.interest_amount,2) - ((ROUND((1/100)*transaction_snapshot_price_summaries.interest_amount,2)*3.3)/103.3))/(transaction_snapshots.number_of_installment-1)),2)
    END AS PrincipleThisPeriod,
    CASE WHEN charge_rank <> 1 THEN 0 ELSE ROUND((1 / 100) * transaction_snapshot_installment_details.interest,2) END AS InterestEIRThisPeriod,
    CASE WHEN (transaction_snapshots.number_of_installment - 1) = 0 THEN 0
      WHEN installment_periods.period = 1 AND charge_rank = 1 THEN ROUND((1 / 100) * charges.amount- ROUND((1 / 100) * transaction_snapshot_installment_details.add_ons,2),2)
      WHEN installment_periods.period = 1 AND charge_rank <> 1 THEN ROUND((1 / 100) * charges.amount,2)
      ELSE ROUND((1 / 100) * transaction_snapshot_installment_details.principal,2) END AS PrincipleEIRThisPeriod,
    charges.update_time AS PaymentDate,
    installment_periods.period AS Period,
    transaction_snapshots.number_of_installment AS TotalPeriods,
    CASE WHEN charge_rank <> 1 THEN 0 ELSE ROUND((1 / 100) * transaction_snapshot_installment_details.principal_balance,2) END AS PendingPayment, -- Need to check
    CASE WHEN installment_periods.period = 1 AND change.human_id IS NOT NULL AND charges.payment_method <> 'DIRECT_PAYMENT' THEN "RCL-Credit Shell"
      WHEN change.human_id IS NOT NULL AND charges.payment_method = 'DIRECT_PAYMENT' THEN 'DIRECT_PAYMENT'
      ELSE charges.payment_method END AS PaymentMethod,
    CASE WHEN installment_periods.period = 1 AND change.human_id IS NOT NULL AND charges.payment_method <> 'DIRECT_PAYMENT' THEN "RCL-Credit Shell"
      WHEN change.human_id IS NOT NULL AND charges.payment_method = 'DIRECT_PAYMENT' THEN 'RCL-DIRECT PAYMENT'
      ELSE charges.service_provider END AS PaymentChannel,
    COALESCE(
      DATE(follow_ups.due_date),
      DATE_ADD(
        follow_up_first_due_dates.first_due_date,
        INTERVAL installment_periods.period - 1 MONTH
      )
    ) AS ExpectedDate,
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
  LEFT JOIN installment_periods
    ON installment_periods.snapshot_id = transaction_snapshots.id
  LEFT JOIN transaction_snapshot_price_summaries
    ON transaction_snapshot_price_summaries.snapshot_id = transaction_snapshots.id
  LEFT JOIN transaction_snapshot_installment_details
    ON transaction_snapshot_installment_details.snapshot_id = transaction_snapshots.id
    AND transaction_snapshot_installment_details.period = installment_periods.period
  LEFT JOIN charges
    ON charges.transaction_id = transactions.id
    AND charges.installment_number = installment_periods.period
    AND charges.status NOT IN ('FAILED','PENDING')
    AND charges.service_provider = 'RABBIT_LENDING'  -- FIX #1: moved from WHERE so unmatched periods still survive the LEFT JOIN
  LEFT JOIN order_items
    ON order_items.order_id = orders.id
  LEFT JOIN refunds
    ON refunds.transaction_id = transactions.id
  LEFT JOIN follow_ups
    ON follow_ups.transaction_id = transactions.id
    AND follow_ups.installment = installment_periods.period
  LEFT JOIN follow_up_first_due_dates
    ON follow_up_first_due_dates.transaction_id = transactions.id
  LEFT JOIN takeaway_compulsary
    ON takeaway_compulsary.transaction_snapshot_id = transaction_snapshots.id
  LEFT JOIN change on change.human_id = orders.human_id
 WHERE
  installment_periods.period IS NOT NULL
   AND order_items.product = 'products/car-insurance'
   AND order_items.motor_item_type <> 'MOTOR_TYPE_COMPULSORY'
   AND (charges.charge_rank = 1 OR charges.charge_rank IS NULL) -- one row per period, including unpaid periods
   --AND (follow_ups.transaction_id IS NOT NULL)
   -- FIX #1: removed "AND charges.service_provider = 'RABBIT_LENDING'" here — it was on the joined (nullable)
   -- table, which silently turned the LEFT JOIN charges above into an INNER JOIN and dropped every period
   -- that didn't yet have a SUCCESSFUL charge (e.g. unpaid periods 2-6 of a 6-installment plan).
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
    COALESCE(
      DATE(follow_ups.due_date),
      DATE_ADD(
        follow_up_first_due_dates.first_due_date,
        INTERVAL transaction_snapshot_installment_details.period - 1 MONTH
      )
    ) AS ExpectedDate,
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
    AND charges.service_provider = 'RABBIT_LENDING'
  LEFT JOIN leads
    ON CONCAT('leads/',leads.id) = orders.lead
  LEFT JOIN follow_ups
    ON follow_ups.transaction_id = transactions.id
    AND follow_ups.installment = transaction_snapshot_installment_details.period
  LEFT JOIN follow_up_first_due_dates
    ON follow_up_first_due_dates.transaction_id = transactions.id
  LEFT JOIN change on change.human_id = orders.human_id
  WHERE
    order_items.motor_item_type = 'MOTOR_TYPE_COMPULSORY'
    AND transaction_snapshot_installment_details.id IS NOT NULL
    AND transaction_snapshot_installment_details.period = 1
    AND charges.charge_rank = 1
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
    ROUND(
        COALESCE(TotalPremium, 0)
      + COALESCE(TotalEIR, 0)
      + COALESCE(TotalSBT, 0)
      + COALESCE(ProcessingFee, 0)
      + COALESCE(ProcessingFeeVat, 0)
      + COALESCE(ShippingFee, 0)
      + COALESCE(ShippingFeeVat, 0),
      2
    ) AS TotalAmount,
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
  WHEN PaymentDate IS NULL THEN NULL
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
  ROUND(
    SAFE_DIVIDE(
        COALESCE(TotalPremium, 0)
      + COALESCE(TotalEIR, 0)
      + COALESCE(TotalSBT, 0)
      + COALESCE(ProcessingFee, 0)
      + COALESCE(ProcessingFeeVat, 0)
      + COALESCE(ShippingFee, 0)
      + COALESCE(ShippingFeeVat, 0)
      - COALESCE(Discount, 0),
      NULLIF(TotalPeriods, 0)
    ) * (TotalPeriods - Period),
    2
  ) AS PendingPayment,
  CASE WHEN COALESCE(TransactionStatus, '') <> 'SUCCESSFUL' THEN ''
    WHEN PaymentMethod ='DIRECT_PAYMENT'and PaymentChannel ='SERVICE_PROVIDER_UNSPECIFIED' THEN 'DPM จ่ายตรงกับบริษัทประกัน'
    WHEN InsuranceType = 'MOTOR_TYPE_COMPULSORY' THEN 'RCL-CMI-channel'
    WHEN PaymentMethod = 'CASH' THEN 'TRF Transfer'
    WHEN PaymentMethod = 'QR_CODE' THEN 'OME Omise QR Prompt Pay'
    WHEN PaymentMethod = 'BANK_TRANSFER' THEN 'TRF Transfer'
    ELSE PaymentMethod
  END AS PaymentMethod,
  CASE WHEN COALESCE(TransactionStatus, '') <> 'SUCCESSFUL' THEN ''
    WHEN PaymentMethod ='DIRECT_PAYMENT'and PaymentChannel ='SERVICE_PROVIDER_UNSPECIFIED' THEN 'RCL-DIRECT PAYMENT'
    WHEN InsuranceType = 'MOTOR_TYPE_COMPULSORY' THEN 'RCL-CMI-channel'
    WHEN InsuranceGroup != 'products/car-insurance' AND PaymentMethod = 'QR_CODE' THEN 'RCL-Omise QR Prompt Pay-Health'  -- FIX #2 (Root Cause 8)
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
ORDER BY OrderItem, Period;
CREATE TEMP TABLE baseline_newpayment AS -- RCL 05_newpayment -- FIXED & TUNED VERSION

-- Fixed & tuned: 2026-08-28 (Boat review)

-- Changes:

--  1. FIX (dead code / perf): removed the `sap` CTE (a full transform of

--     all of SAP_LIVE_FULL) and the `cancelled` CTE -- neither was

--     referenced anywhere in the final SELECT (only `newpayment` and

--     `interface` were used). That was a full-table scan+transform paid

--     for nothing.

--  2. FIX (correctness, confirmed with Boat -- same root cause suspected

--     for Chain 3 / DDL 043): replaced the MAX(Period)-per-OrderItem

--     "watermark" with a genuine PER-PERIOD existence check. The old logic

--     (`careos_installment > MAX(paid period)`) assumed periods are paid

--     strictly in sequence with no gaps -- if period 2 was skipped but

--     period 3 got marked Paid, period 2 would be wrongly treated as

--     "already covered" forever and never surface as missing/new. The new

--     logic checks, for each exact (OrderItem, Period) pair CareOS says

--     should exist, whether THAT SPECIFIC period is already Paid in SAP --

--     no assumption of contiguous sequence.

-- ============================================================

-- RCL 05_newpayment -- FIXED & TUNED VERSION

-- Fixed & tuned: 2026-08-28 (Boat review)

-- Redeployed 2026-08-29: previous live definition under this name was

-- actually the 13-col `RCL 05_paid by period` logic (careos_orders join) --

-- wrong definition, root cause of UNION ALL column-count mismatch in

-- 06_02. This corrects it to the intended 56-col, schema-matched-to-

-- RCL-05_paid definition.



-- RCL 05_newpayment -- FIXED & TUNED VERSION

-- Redeployed 2026-08-29 (Boat review): previous live definition under

-- this name was actually the 13-col `RCL 05_paid by period` logic --

-- wrong definition, root cause of UNION ALL column-count mismatch

-- (56 vs 13) in 06_02. Corrected to the intended 56-col definition,

-- schema-matched to RCL 05_paid via sap_dashboard_carepay_installment.

-- Also explicitly casts RefundAmountBeforeFee/AfterFee to FLOAT64

-- (source has them as INT64; RCL 05_paid has them as FLOAT64 --

-- BigQuery would implicit-coerce in UNION ALL, but made explicit here

-- to avoid relying on that behavior silently).

WITH

  sap_paid_periods AS (

    -- exact per-(OrderItem, Period) existence check -- NOT a MAX watermark, NOT an all-period fan-out

    SELECT DISTINCT

      U_OrderItem AS order_item,

      SAFE_CAST(U_Period AS INT64) AS period

    FROM evidence_sap

    WHERE TransactionStatus IN ('Paid', 'paid')

  ),



  interface AS (

    SELECT

      * REPLACE (

        CAST(RefundAmountBeforeFee AS FLOAT64) AS RefundAmountBeforeFee,

        CAST(RefundAmountAfterFee AS FLOAT64) AS RefundAmountAfterFee

      ),

      SAFE_CAST(Period AS INT64) AS careos_installment

    FROM baseline_dashboard

  )



SELECT DISTINCT

  interface.* EXCEPT(careos_installment)

FROM interface

WHERE

  interface.careos_installment IS NOT NULL

  AND NOT EXISTS (

    SELECT 1

    FROM sap_paid_periods p

    WHERE p.order_item = interface.OrderItem

      AND p.period = interface.careos_installment

  )



ORDER BY interface.OrderItem, careos_installment;
CREATE TEMP TABLE baseline_gate AS -- RCL 05_paid by period -- FIXED & CREATED 2026-08-29 (Boat review)

-- Previously this logic lived (mislabeled) under `RCL 05_newpayment`.

-- Bug fixed here: original version joined `sap` to `charges` (ALL periods

-- ever paid) instead of `charges_ranking` (latest period only), then

-- relied on DISTINCT to collapse -- this let orders where an OLD period

-- was still missing from SAP mask the fact that the LATEST period was

-- already Paid+Paid, producing false "qualified" rows

-- (e.g. "1/10 CareOS paid, SAP paid" wrongly surfaced).

-- Fix: NOT EXISTS check scoped to charges_ranking.installment_number

-- (the actual latest period) plus OrderItem-level join key (was OrderID-only).

WITH charges AS (

  SELECT *

  FROM `pacific-plating-282708.careos.carepay_charges`

  WHERE status = 'SUCCESSFUL'

),



charges_ranking AS (

  SELECT *,

    ROW_NUMBER() OVER (PARTITION BY transaction_id ORDER BY installment_number DESC) AS rank

  FROM charges

  QUALIFY rank = 1

),



sap_paid_periods AS (

  -- exact per-(OrderItem, Period) existence check -- NOT a MAX watermark, NOT an all-period fan-out

  SELECT DISTINCT

    U_OrderItem AS order_item,

    SAFE_CAST(U_Period AS INT64) AS period

  FROM evidence_sap

  WHERE TransactionStatus IN ('Paid', 'paid')

)



SELECT DISTINCT

  orders.human_id,

  oi.human_id AS order_item,

  orders.create_time AS order_create_time,

  orders.update_time AS order_update_time,

  orders.is_fully_paid,

  orders.is_cancelled,

  transactions.payment_option,

  charges_ranking.installment_number,

  orders.cancel_time,

  charges_ranking.update_time AS charges_update_time,

  CASE

    WHEN orders.create_time < '2024-03-28' THEN 'icollection'

    ELSE 'carepay'

  END AS sql_view_using,

  orders.product,

  oi.motor_item_type AS InsuranceType

FROM `pacific-plating-282708.careos.careos_orders` AS orders

LEFT JOIN `pacific-plating-282708.careos.careos_order_items` AS oi

  ON orders.id = oi.order_id

LEFT JOIN `pacific-plating-282708.careos.carepay_transactions` AS transactions

  ON CONCAT('transactions/', transactions.id) = orders.payment

LEFT JOIN charges_ranking

  ON charges_ranking.transaction_id = transactions.id

WHERE 1=1

  AND charges_ranking.installment_number IS NOT NULL

  AND DATE(charges_ranking.update_time)

      BETWEEN DATE_TRUNC(DATE_SUB(CURRENT_DATE(), INTERVAL 2 MONTH), MONTH)

      AND CURRENT_DATE()

  AND transactions.payment_option = 'RABBIT_CARE_INSTALLMENT'

  AND NOT EXISTS (

    SELECT 1

    FROM sap_paid_periods p

    WHERE p.order_item = oi.human_id

      AND p.period = charges_ranking.installment_number

  )

ORDER BY orders.create_time ASC;
CREATE TEMP TABLE baseline_wrapper AS -- Full source-only legacy root-fix proposal for:
--   pacific-plating-282708.sap_view.RCL_Motor_process_2_newpayment
--
-- Root fixes:
--   1. Route only products/car-insurance into this Motor interface.
--   2. Exclude an OrderItem when the canonical CareOS item is cancelled. This keeps the
--      whole cancelled schedule out of new-payment instead of mixing current pending rows
--      with historical SAP Paid rows removed by RCL 05_paid.
--   3. Preserve legitimate same-period additional-payment rows. ExpectedReceived = 0 rows
--      are deduplicated by InvoiceNo (or their existing deterministic fallback), while a
--      normal scheduled row remains one row per OrderItem/Period.
--
-- SELECT only: this file does not replace or deploy the legacy view.

WITH
  interface AS (
    SELECT *
    FROM evidence_paid

    UNION ALL

    SELECT *
    FROM baseline_newpayment
  ),

  eligible_newpayment_items AS (
    SELECT DISTINCT
      paid_by_period.order_item
    FROM baseline_gate AS paid_by_period
    JOIN `pacific-plating-282708.careos.careos_order_items` AS order_item
      ON order_item.human_id = paid_by_period.order_item
    WHERE paid_by_period.product = 'products/car-insurance'
      AND paid_by_period.InsuranceType != 'MOTOR_TYPE_COMPULSORY'
      AND order_item.is_cancelled IS NOT TRUE
      AND order_item.cancel_time IS NULL
  ),

  source AS (
    SELECT DISTINCT
      interface.*
    FROM interface
    JOIN eligible_newpayment_items
      ON eligible_newpayment_items.order_item = interface.OrderItem
    WHERE SAFE.PARSE_DATE('%d%m%Y', interface.OrderDate) >= DATE '2026-01-01'
      -- Fail closed against RCB/RCL and NonMotor routing leakage.
      AND interface.InsuranceGroup = 'Motor'
      AND interface.InsuranceType != 'MOTOR_TYPE_COMPULSORY'
  ),

  classified AS (
    SELECT
      source.*,
      CASE
        WHEN COALESCE(source.ExpectedReceived, 0) = 0
          AND COALESCE(source.ActualReceived, 0) > 0
        THEN 1
        ELSE 0
      END AS is_additional_payment,
      ROW_NUMBER() OVER (
        PARTITION BY
          source.OrderItem,
          source.Period,
          CASE
            WHEN COALESCE(source.ExpectedReceived, 0) = 0
              AND COALESCE(source.ActualReceived, 0) > 0
            THEN COALESCE(
              NULLIF(source.InvoiceNo, ''),
              CONCAT(
                'additional_',
                CAST(source.ActualReceived AS STRING),
                '_',
                COALESCE(source.PaymentDate, '')
              )
            )
            ELSE 'normal_period_row'
          END
        ORDER BY
          CASE
            WHEN source.InvoiceNo IS NOT NULL
              AND source.InvoiceNo NOT IN ('', 'null', 'NULL')
            THEN 1 ELSE 2
          END,
          CASE
            WHEN source.PolicyNo IS NOT NULL
              AND source.PolicyNo NOT IN ('', 'null', 'NULL')
            THEN 1 ELSE 2
          END,
          CASE
            WHEN source.PaymentDate IS NOT NULL
              AND source.PaymentDate NOT IN ('', 'null', 'NULL')
            THEN 1 ELSE 2
          END,
          source.PaymentDate DESC
      ) AS rn
    FROM source
  )

SELECT
  * EXCEPT (is_additional_payment, rn)
FROM classified
WHERE rn = 1
ORDER BY OrderID, OrderItem, Period;
SELECT CURRENT_TIMESTAMP() AS checked_at_utc,
 (SELECT COUNT(*) FROM candidate_wrapper) AS candidate_rows,
 (SELECT COUNT(DISTINCT OrderItem) FROM candidate_wrapper) AS candidate_items,
 (SELECT COUNT(*) FROM candidate_wrapper WHERE ExpectedReceived=0 AND ActualReceived>0) AS additional_rows,
 (SELECT COUNT(*) FROM (SELECT OrderItem,Period,InvoiceNo FROM candidate_wrapper GROUP BY 1,2,3 HAVING COUNT(*)>1)) AS duplicate_event_keys,
 (SELECT COUNT(*) FROM (SELECT OrderItem FROM candidate_wrapper GROUP BY OrderItem HAVING MIN(SAFE_CAST(Period AS INT64))!=1 OR MAX(SAFE_CAST(Period AS INT64))!=MAX(SAFE_CAST(TotalPeriods AS INT64)) OR COUNT(DISTINCT SAFE_CAST(Period AS INT64))!=MAX(SAFE_CAST(TotalPeriods AS INT64)) OR COUNT(DISTINCT TotalPeriods)!=1)) AS incomplete_spines,
 (SELECT COUNT(*) FROM (SELECT OrderItem,Period FROM candidate_wrapper GROUP BY 1,2 HAVING COUNTIF(COALESCE(ExpectedReceived,0)!=0)>1)) AS repeated_expected_periods,
 (SELECT COUNT(*) FROM candidate_wrapper WHERE ExpectedReceived=0 AND ActualReceived>0 AND (NULLIF(TRIM(InvoiceNo),'') IS NULL OR UPPER(TRIM(InvoiceNo))='NULL')) AS blank_additional_invoices,
 (SELECT COUNT(*) FROM (SELECT OrderItem,Period,InvoiceNo,TransactionStatus,ExpectedReceived,ActualReceived,PaymentDate,PaymentMethod,PaymentChannel FROM baseline_wrapper EXCEPT DISTINCT SELECT OrderItem,Period,InvoiceNo,TransactionStatus,ExpectedReceived,ActualReceived,PaymentDate,PaymentMethod,PaymentChannel FROM candidate_wrapper)) AS existing_rows_removed_or_changed,
 ARRAY(SELECT AS STRUCT TransactionStatus,COUNT(*) AS row_count FROM candidate_wrapper GROUP BY TransactionStatus) AS status_distribution;


SELECT CURRENT_TIMESTAMP() AS checked_at_utc,
 (SELECT COUNT(*) FROM (SELECT TO_JSON_STRING(b) FROM baseline_wrapper b EXCEPT DISTINCT SELECT TO_JSON_STRING(c) FROM candidate_wrapper c)) AS full_payload_old_rows_removed,
 (SELECT COUNT(*) FROM (SELECT TO_JSON_STRING(b) FROM baseline_dashboard b EXCEPT DISTINCT SELECT TO_JSON_STRING(c) FROM candidate_dashboard c)) AS dashboard_old_rows_removed;

CREATE TEMP TABLE added_wrapper_rows AS
SELECT c.* FROM candidate_wrapper c WHERE NOT EXISTS (
 SELECT 1 FROM baseline_wrapper b WHERE TO_JSON_STRING(b)=TO_JSON_STRING(c));
SELECT CURRENT_TIMESTAMP() AS checked_at_utc,TransactionStatus,
 CASE WHEN ExpectedReceived=0 AND ActualReceived>0 THEN 'additional_shape' ELSE 'normal_spine' END AS row_kind,
 COUNT(*) AS row_count,COUNT(DISTINCT OrderItem) AS items,ROUND(SUM(ActualReceived),2) AS actual_thb
FROM added_wrapper_rows GROUP BY 2,3;
SELECT CURRENT_TIMESTAMP() AS checked_at_utc, OrderID,OrderItem,Period,InvoiceNo,ExpectedReceived,ActualReceived
FROM candidate_wrapper WHERE OrderID IN ('L80570054','L79109956') ORDER BY OrderItem,Period,InvoiceNo;
CREATE TEMP TABLE dependent_baseline AS
SELECT * FROM baseline_dashboard

WHERE OrderID not in (SELECT human_id FROM `pacific-plating-282708.temp.2025-03 new order from cancel change order credit shell` )

AND OrderID in (

  'L74256408',

'L74300166',

'L74340842',

'L74343536',

'L74402254',

'L74405784',

'L74427081',

'L74427712',

'L74430507',

'L74438979',

'L74440536',

'L74442869',

'L74453733',

'L74468069',

'L74493645',

'L74494145',

'L74510143',

'L74512746',

'L74520278',

'L74590996',

'L74623408',

'L74624257',

'L74663899',

'L74692981',

'L74768487',

'L74770301',

'L76362624',

'L76381553',

'L76386664',

'L77178953',

'L77311432',

'L77334959',

'L77401037',

'L77423021',

'L77423955',

'L77424504',

'L77437401',

'L77439533',

'L77441582',

'L77443853',

'L77444482',

'L77444681',

'L77445015',

'L77446119',

'L77447067',

'L77447717',

'L77449244',

'L77450551',

'L77458596',

'L77459765',

'L77460002',

'L77465633',

'L77473102',

'L77473637',

'L77474424',

'L73724413',

'L73732471',

'L73910039',

'L73925659',

'L74093732',

'L75280487',

'L77032552',

'L77051000',

'L77076863',

'L77085743',

'L77102636',

'L77105258',

'L77110037',

'L77127267',

'L77127764',

'L77128891',

'L77133830',

'L77136477',

'L77136812',

'L77137046',

'L77139568',

'L77139576',

'L77141259',

'L77144908',

'L77145970',

'L77146702',

'L77147324',

'L77148332',

'L77148824',

'L77148990',

'L77152178',

'L77152594',

'L77152669',

'L77152993',

'L77153011',

'L77153355',

'L77153913',

'L77154875',

'L77158848',

'L77165282',

'L77169952',

'L77172861',

'L77174075',

'L77175455',

'L77176331',

'L77176635',

'L77177754',

'L77178009',

'L77180520',

'L77184251',

'L77184386',

'L77184418',

'L77185233',

'L77190845',

'L77191202',

'L77193042',

'L77194369',

'L77194390',

'L77194782',

'L77195812',

'L77198016',

'L77198191',

'L77199218',

'L77200407',

'L77202025',

'L77202152',

'L77202486',

'L77205144',

'L77205429',

'L77205458',

'L77206258',

'L77208128',

'L77208229',

'L77208499',

'L77208667',

'L77208930',

'L77209484',

'L77209895',

'L77210360',

'L77210654',

'L77210882',

'L77212092',

'L77212473',

'L77212527',

'L77212621',

'L77212687',

'L77212887',

'L77212950',

'L77212990',

'L77213229',

'L77213320',

'L77213486',

'L77213792',

'L77213979',

'L77214023',

'L77214037',

'L77214096',

'L77215448',

'L77216352',

'L77216452',

'L77216713',

'L77216715',

'L77216817',

'L77216874',

'L77216875',

'L77217390',

'L77217399',

'L77218205',

'L77218478',

'L77218532',

'L77218541',

'L77218650',

'L77218667',

'L77218735',

'L77218739',

'L77218743',

'L77218763',

'L77218782',

'L77219002',

'L77219132',

'L77219393',

'L77219524',

'L77219525',

'L77219549',

'L77221329',

'L77222538',

'L77222736',

'L77222948',

'L77222962',

'L77223019',

'L77223803',

'L77223804',

'L77223815',

'L77223837',

'L77223870',

'L77223950',

'L77224836',

'L77225966',

'L77229000',

'L77229017',

'L77229027',

'L77229058',

'L77229103',

'L77229132',

'L77229194',

'L77229227',

'L77229286',

'L77229404',

'L77229467',

'L77229645',

'L77229658',

'L77229804',

'L77229810',

'L77229857',

'L77229893',

'L77229912',

'L77230017',

'L77230021',

'L77230169',

'L77230307',

'L77230313',

'L77230600',

'L77231225',

'L77231526',

'L77231958',

'L77231979',

'L77232990',

'L77233036',

'L77233038',

'L77233055',

'L77233056',

'L77233628',

'L77233676',

'L77233918',

'L77234002',

'L77234099',

'L77234216',

'L77234406',

'L77234422',

'L77234524',

'L77234638',

'L77237853',

'L77238062',

'L77238093',

'L77238163',

'L77238188',

'L77238201',

'L77238335',

'L77238345',

'L77238723',

'L77238756',

'L77240625',

'L77241105',

'L77241139',

'L77241202',

'L77241264',

'L77241329',

'L77241334',

'L77241451',

'L77242398',

'L77242425',

'L77242573',

'L77247024',

'L77247698',

'L77247799',

'L77247915',

'L77248016',

'L77248048',

'L77248281',

'L77248435',

'L77250792',

'L77252691',

'L77252711',

'L77252799',

'L77252906',

'L77254462',

'L77255650',

'L77255767',

'L77255887',

'L77256507',

'L77256551',

'L77256614',

'L77257562',

'L77257815',

'L77258936',

'L77259209',

'L77259249',

'L77259409',

'L77259786',

'L77261965',

'L77262744',

'L77263284',

'L77264170',

'L77264227',

'L77267136',

'L77270447',

'L77270485',

'L77270767',

'L77271411',

'L77272567',

'L77272745',

'L77274365',

'L77276306',

'L77276539',

'L77277778',

'L77278093',

'L77278567',

'L77278599',

'L77278607',

'L77278707',

'L77279034',

'L77279233',

'L77279381',

'L77279529',

'L77282602',

'L77282652',

'L77282653',

'L77282723',

'L77283276',

'L77283552',

'L77283685',

'L77283726',

'L77283859',

'L77286585',

'L77287430',

'L77287643',

'L77287777',

'L77289513',

'L77289531',

'L77291619',

'L77292060',

'L77292120',

'L77292678',

'L77294026',

'L77294047',

'L77294131',

'L77294278',

'L77294284',

'L77295635',

'L77295814',

'L77297352',

'L77298446',

'L77298483',

'L77298558',

'L77298711',

'L77298726',

'L77299851',

'L77300129',

'L77300246',

'L77300381',

'L77303891',

'L77305416',

'L77306947',

'L77307192',

'L77307279',

'L77307460',

'L77308057',

'L77310266',

'L77317220',

'L77318532',

'L77320690',

'L77320878',

'L77322044',

'L77322547',

'L77322548',

'L77322759',

'L77325006',

'L77326458',

'L77328676',

'L77331652',

'L77336150',

'L77336340',

'L77337851',

'L77339334',

'L77341069',

'L77353141',

'L77356606',

'L77356992',

'L77359366',

'L77362585',

'L77429492',

'L77437282',

'L77449310',

'L77458803',

'L77514480',

'L77759837',

'L77781746',

'L77826089',

'L77851893',

'L78041242',

'L78061821',

'L78179246',

'L78224194',

'L78247030',

'L78260856',

'L78273370',

'L78279786',

'L78291382',

'L78291805',

'L78293097',

'L78293100',

'L78294951',

'L78297629',

'L78300917',

'L78301072',

'L78301686',

'L78303282',

'L78309063',

'L78309132',

'L78309686',

'L78309702',

'L78312550',

'L78315011',

'L78315012',

'L78318145',

'L78318797',

'L78320378',

'L78321434',

'L78321723',

'L78322105',

'L78325383',

'L78326034',

'L78326453',

'L78326614',

'L78330003',

'L78330420',

'L78331218',

'L78339673',

'L78340106',

'L78340870',

'L78340933',

'L78341661',

'L78344609',

'L78346392',

'L78346966',

'L78348506',

'L78349202',

'L78349699',

'L78350109',

'L78350285',

'L78350417',

'L78350884',

'L78351432',

'L78351618',

'L78351643',

'L78353169',

'L78354098',

'L78354185',

'L78354426',

'L78355657',

'L78355891',

'L78356643',

'L78356675',

'L78356865',

'L78357034',

'L78357197',

'L78358079',

'L78358718',

'L78358867',

'L78358998',

'L78359581',

'L78359624',

'L78359956',

'L78360224',

'L78360731',

'L78360868',

'L78360932',

'L78360990',

'L78361269',

'L78362383',

'L78362407',

'L78363028',

'L78363036',

'L78363159',

'L78363160',

'L78363471',

'L78363859',

'L78363868',

'L78364108',

'L78364299',

'L78370853',

'L78371247',

'L78372223',

'L78372345',

'L78372369',

'L78372666',

'L78383218',

'L78383609',

'L78383851',

'L78385010',

'L78385353',

'L78385700',

'L78386370',

'L78386453',

'L78386539',

'L78386789',

'L78386946',

'L78387064',

'L72651220',

'L73707169',

'L73875165',

'L75446127',

'L76853344',

'L76958584',

'L76968514',

'L76981184',

'L76982197',

'L76999192',

'L77008110',

'L77018043',

'L77025337',

'L77027850',

'L77029561',

'L77034676',

'L77041221',

'L77047541',

'L77049836',

'L77050000',

'L77052262',

'L77057239',

'L77058749',

'L77065180',

'L77072924',

'L77075290',

'L77086015',

'L77087901',

'L77091196',

'L77098880',

'L77098905',

'L77099208',

'L77099442',

'L77101678',

'L77101681',

'L77102742',

'L77102941',

'L77104293',

'L77104606',

'L77104860',

'L77104923',

'L77105880',

'L77106462',

'L77109519',

'L77110116',

'L77113511',

'L77113682',

'L77114170',

'L77114223',

'L77116123',

'L77116138',

'L77119137',

'L77123767',

'L77124374',

'L77124810',

'L77125555',

'L77126799',

'L77126827',

'L77127209',

'L77131359',

'L77133595',

'L77133683',

'L77133735',

'L77133938',

'L77134760',

'L77134772',

'L77136278',

'L77136546',

'L77139035',

'L77139142',

'L77139286',

'L77139592',

'L77139701',

'L77139826',

'L77140218',

'L77141264',

'L77141560',

'L77141704',

'L77143283',

'L77143837',

'L77144817',

'L77144930',

'L77144944',

'L77145081',

'L77145151',

'L77145714',

'L77145808',

'L77146200',

'L77146632',

'L77146921',

'L77147303',

'L77147574',

'L77148652',

'L77148814',

'L77148883',

'L77149148',

'L77149437',

'L77150602',

'L77151719',

'L77152724',

'L77152765',

'L77153294',

'L77153492',

'L77153544',

'L77153923',

'L77154066',

'L77155283',

'L77155871',

'L77155917',

'L77155966',

'L77158665',

'L77160267',

'L77161050',

'L77163999',

'L77164149',

'L77165784',

'L77166849',

'L77166852',

'L77167118',

'L77167126',

'L77167321',

'L77169632',

'L77170105',

'L77170646',

'L77173557',

'L77174245',

'L77174372',

'L77174390',

'L77177210',

'L77177659',

'L77180779',

'L77181595',

'L77181820',

'L77184571',

'L77185364',

'L77187279',

'L77187322',

'L77191195',

'L77192334',

'L77192340',

'L77194135',

'L77198106',

'L77199221',

'L77203806',

'L77206850',

'L77208133',

'L77208474',

'L77208583',

'L77210549',

'L77212861',

'L77212948',

'L77213349',

'L77214161',

'L77216121',

'L77218762',

'L77219375',

'L77230429',

'L77231496',

'L77238136',

'L77242437',

'L77264456',

'L77283492',

'L77292752',

'L77372225',

'L77759186',

'L77778887',

'L77784301',

'L77790969',

'L77805438',

'L77829701',

'L77844033',

'L77872531',

'L77882359',

'L77883070',

'L77918154',

'L77967640',

'L77968408',

'L78009531',

'L78030077',

'L78059264',

'L78074791',

'L78079340',

'L78083612',

'L78105836',

'L78113757',

'L78128334',

'L78143043',

'L78144429',

'L78145395',

'L78146194',

'L78150429',

'L78152111',

'L78156452',

'L78162765',

'L78166372',

'L78170300',

'L78173613',

'L78175093',

'L78175110',

'L78176209',

'L78177237',

'L78177542',

'L78178719',

'L78182076',

'L78182316',

'L78188524',

'L78197759',

'L78199631',

'L78202870',

'L78204546',

'L78204965',

'L78207619',

'L78208582',

'L78208941',

'L78209767',

'L78212807',

'L78212815',

'L78213346',

'L78214772',

'L78214921',

'L78215303',

'L78218053',

'L78218545',

'L78223030',

'L78223440',

'L78225177',

'L78226256',

'L78226833',

'L78228195',

'L78229855',

'L78229861',

'L78232518',

'L78232871',

'L78233639',

'L78234280',

'L78234933',

'L78235818',

'L78238065',

'L78239097',

'L78239830',

'L78241186',

'L78243146',

'L78244444',

'L78245263',

'L78245700',

'L78245749',

'L78245940',

'L78245957',

'L78245976',

'L78246313',

'L78246467',

'L78246482',

'L78248070',

'L78248856',

'L78249597',

'L78251120',

'L78251598',

'L78252312',

'L78252538',

'L78253337',

'L78253967',

'L78254073',

'L78254227',

'L78256100',

'L78256227',

'L78256813',

'L78258916',

'L78260960',

'L78262447',

'L78263793',

'L78264325',

'L78266003',

'L78266713',

'L78267314',

'L78268000',

'L78268488',

'L78270453',

'L78270858',

'L78271062',

'L78272592',

'L78273997',

'L78278144',

'L78279054',

'L78279359',

'L78281587',

'L78288298',

'L78296185',

'L73283282',

'L73393947',

'L73478141',

'L73716020',

'L75275234',

'L75295225',

'L76871093',

'L76880153',

'L76908179',

'L76924485',

'L76927769',

'L76934924',

'L76951192',

'L76955786',

'L76956366',

'L76964132',

'L76966521',

'L76972734',

'L76975698',

'L76976785',

'L76979612',

'L76981436',

'L76982233',

'L76985594',

'L76990197',

'L76991110',

'L76991147',

'L76991742',

'L76993600',

'L76999033',

'L77009089',

'L77011883',

'L77012087',

'L77015594',

'L77018315',

'L77018902',

'L77020578',

'L77021447',

'L77021974',

'L77024335',

'L77024424',

'L77026257',

'L77030146',

'L77031276',

'L77031677',

'L77032399',

'L77032984',

'L77034796',

'L77037662',

'L77040819',

'L77041526',

'L77043523',

'L77043595',

'L77043622',

'L77044041',

'L77044056',

'L77044125',

'L77044734',

'L77045381',

'L77047111',

'L77047114',

'L77047273',

'L77049680',

'L77049790',

'L77049818',

'L77050049',

'L77050831',

'L77050883',

'L77050899',

'L77050926',

'L77050960',

'L77051212',

'L77051446',

'L77051959',

'L77052260',

'L77052280',

'L77052394',

'L77052407',

'L77052965',

'L77053027',

'L77053115',

'L77053666',

'L77054770',

'L77056979',

'L77057073',

'L77057588',

'L77058662',

'L77058909',

'L77060005',

'L77060444',

'L77060472',

'L77060565',

'L77060894',

'L77061011',

'L77061290',

'L77061311',

'L77062353',

'L77062518',

'L77064685',

'L77065137',

'L77065258',

'L77065321',

'L77065928',

'L77066711',

'L77068178',

'L77068282',

'L77068546',

'L77068866',

'L77069511',

'L77069539',

'L77069556',

'L77069753',

'L77069894',

'L77069967',

'L77069986',

'L77071515',

'L77071764',

'L77073173',

'L77073180',

'L77073190',

'L77073400',

'L77073735',

'L77073757',

'L77073890',

'L77073891',

'L77073957',

'L77074064',

'L77074157',

'L77074367',

'L77075383',

'L77075392',

'L77075515',

'L77075808',

'L77075812',

'L77075844',

'L77075892',

'L77075915',

'L77076902',

'L77076923',

'L77077122',

'L77077186',

'L77078380',

'L77078886',

'L77079110',

'L77079699',

'L77079924',

'L77080205',

'L77081779',

'L77081898',

'L77084251',

'L77084277',

'L77084319',

'L77084383',

'L77084391',

'L77084472',

'L77084511',

'L77084588',

'L77084826',

'L77085190',

'L77085432',

'L77085737',

'L77085949',

'L77086329',

'L77088227',

'L77088575',

'L77088993',

'L77089422',

'L77090691',

'L77090809',

'L77090903',

'L77094570',

'L77095042',

'L77095728',

'L77096638',

'L77096902',

'L77096954',

'L77097121',

'L77098939',

'L77098978',

'L77099325',

'L77099828',

'L77101593',

'L77101662',

'L77102116',

'L77102145',

'L77102209',

'L77102215',

'L77102260',

'L77102855',

'L77102966',

'L77104080',

'L77104295',

'L77104318',

'L77104542',

'L77104560',

'L77104581',

'L77104861',

'L77105060',

'L77105704',

'L77105940',

'L77106271',

'L77106418',

'L77106445',

'L77108897',

'L77108898',

'L77109068',

'L77109573',

'L77109609',

'L77110383',

'L77110545',

'L77111100',

'L77112055',

'L77112061',

'L77112070',

'L77112196',

'L77112267',

'L77112360',

'L77112384',

'L77112536',

'L77113484',

'L77113615',

'L77115498',

'L77115515',

'L77115601',

'L77116032',

'L77116135',

'L77116171',

'L77116490',

'L77119194',

'L77119575',

'L77119876',

'L77120345',

'L77120376',

'L77123476',

'L77123482',

'L77124094',

'L77124207',

'L77124368',

'L77124371',

'L77124472',

'L77124849',

'L77124968',

'L77125038',

'L77125120',

'L77125177',

'L77125503',

'L77127153',

'L77127193',

'L77128159',

'L77128505',

'L77128508',

'L77129567',

'L77129876',

'L77130936',

'L77131211',

'L77132031',

'L77132546',

'L77132551',

'L77133634',

'L77133677',

'L77134040',

'L77134257',

'L77134528',

'L77134546',

'L77134662',

'L77134833',

'L77134884',

'L77135769',

'L77135850',

'L77135893',

'L77138679',

'L77139139',

'L77139181',

'L77139219',

'L77139600',

'L77139964',

'L77141289',

'L77141482',

'L77142861',

'L77143842',

'L77144051',

'L77145032',

'L77145183',

'L77145465',

'L77146122',

'L77146259',

'L77146588',

'L77147317',

'L77148525',

'L77148744',

'L77149242',

'L77150143',

'L77150188',

'L77150486',

'L77152232',

'L77152333',

'L77152402',

'L77152574',

'L77152860',

'L77152940',

'L77152999',

'L77153578',

'L77154006',

'L77154050',

'L77154076',

'L77154483',

'L77155747',

'L77156954',

'L77159948',

'L77162509',

'L77164926',

'L77165779',

'L77173513',

'L77174546',

'L77175514',

'L77177233',

'L77177378',

'L77177455',

'L77180549',

'L77187302',

'L77187305',

'L77191842',

'L77194941',

'L77198936',

'L77218665',

'L77285695',

'L77299734',

'L77444692',

'L77450942',

'L77540230',

'L77613172',

'L77724951',

'L77783851',

'L77825281',

'L77872529',

'L77897197',

'L77924918',

'L77938003',

'L77938297',

'L77938976',

'L77954482',

'L77960094',

'L77980012',

'L78011058',

'L78014120',

'L78031958',

'L78036423',

'L78037947',

'L78044348',

'L78044366',

'L78047041',

'L78047739',

'L78053360',

'L78064271',

'L78064294',

'L78070303',

'L78075235',

'L78075239',

'L78075655',

'L78080847',

'L78081554',

'L78082791',

'L78087251',

'L78087838',

'L78089392',

'L78089676',

'L78090024',

'L78094440',

'L78096197',

'L78096949',

'L78097049',

'L78098543',

'L78098948',

'L78101965',

'L78102881',

'L78106321',

'L78106387',

'L78106577',

'L78110550',

'L78111187',

'L78113222',

'L78115555',

'L78115574',

'L78117522',

'L78117803',

'L78118596',

'L78119070',

'L78119746',

'L78123326',

'L78123857',

'L78123871',

'L78124192',

'L78124913',

'L78127644',

'L78127913',

'L78128201',

'L78128570',

'L78129431',

'L78129988',

'L78130170',

'L78130579',

'L78131039',

'L78131804',

'L78132174',

'L78132246',

'L78133601',

'L78134500',

'L78135002',

'L78136619',

'L78137568',

'L78139223',

'L78139243',

'L78140409',

'L78142204',

'L78142307',

'L78143568',

'L78144209',

'L78144304',

'L78145137',

'L78145258',

'L78145400',

'L78145592',

'L78145616',

'L78145929',

'L78145958',

'L78146726',

'L78146742',

'L78146849',

'L78146940',

'L78147280',

'L78147282',

'L78147441',

'L78148331',

'L78148554',

'L78148628',

'L78149417',

'L78150144',

'L78151408',

'L78151413',

'L78151484',

'L78151976',

'L78152288',

'L78153180',

'L78153338',

'L78153527',

'L78153550',

'L78154455',

'L78155045',

'L78155062',

'L78155076',

'L78155217',

'L78155472',

'L78155602',

'L78155623',

'L78156128',

'L78156202',

'L78156204',

'L78156228',

'L78156602',

'L78156638',

'L78156646',

'L78158615',

'L78158784',

'L78158989',

'L78159000',

'L78159429',

'L78161724',

'L78161959',

'L78164560',

'L78164569',

'L78165086',

'L78166249',

'L78168224',

'L78168625',

'L78168873',

'L78168906',

'L78174118',

'L78177041',

'L78212480',

'L78226914',

'L78247029',

'L78268488',

'L78278144',

'L78296185',

'L73071799',

'L73355971',

'L74806026',

'L75279916',

'L75305359',

'L76833238',

'L76853781',

'L76875776',

'L76879223',

'L76896738',

'L76899855',

'L76901439',

'L76903624',

'L76905878',

'L76908570',

'L76908628',

'L76914603',

'L76914651',

'L76916142',

'L76918356',

'L76918702',

'L76921585',

'L76921879',

'L76922409',

'L76922537',

'L76927356',

'L76927380',

'L76928560',

'L76928998',

'L76935315',

'L76935442',

'L76937144',

'L76937415',

'L76937768',

'L76942513',

'L76944427',

'L76945187',

'L76947082',

'L76947446',

'L76947897',

'L76948536',

'L76950320',

'L76950827',

'L76950830',

'L76953194',

'L76953487',

'L76953493',

'L76954715',

'L76955677',

'L76956525',

'L76956535',

'L76956598',

'L76957614',

'L76957986',

'L76959124',

'L76960446',

'L76960735',

'L76960740',

'L76961792',

'L76963700',

'L76964737',

'L76965191',

'L76967224',

'L76968060',

'L76972054',

'L76972533',

'L76972900',

'L76973795',

'L76973821',

'L76974075',

'L76975750',

'L76976146',

'L76976188',

'L76976359',

'L76976585',

'L76976947',

'L76977494',

'L76978273',

'L76978955',

'L76979687',

'L76980912',

'L76981271',

'L76981896',

'L76981985',

'L76982236',

'L76982274',

'L76983357',

'L76983497',

'L76983548',

'L76983799',

'L76984489',

'L76984571',

'L76984640',

'L76984725',

'L76984780',

'L76987592',

'L76987707',

'L76987828',

'L76989661',

'L76989851',

'L76989947',

'L76990008',

'L76990012',

'L76990017',

'L76990122',

'L76990190',

'L76990422',

'L76990923',

'L76991049',

'L76991328',

'L76991580',

'L76991662',

'L76993712',

'L76994007',

'L76994108',

'L76994124',

'L76994169',

'L76995425',

'L76995621',

'L76995808',

'L76995954',

'L76999046',

'L76999227',

'L76999453',

'L76999622',

'L77001758',

'L77001818',

'L77003428',

'L77004410',

'L77004774',

'L77007681',

'L77008479',

'L77008485',

'L77008611',

'L77011975',

'L77011997',

'L77012109',

'L77013546',

'L77013547',

'L77015405',

'L77015447',

'L77015667',

'L77015728',

'L77015831',

'L77016048',

'L77016304',

'L77017835',

'L77019250',

'L77019305',

'L77020384',

'L77020486',

'L77024642',

'L77025940',

'L77026068',

'L77026300',

'L77028253',

'L77028304',

'L77029221',

'L77029493',

'L77029602',

'L77029817',

'L77029994',

'L77030004',

'L77031393',

'L77032997',

'L77034554',

'L77035826',

'L77038470',

'L77041432',

'L77044350',

'L77044468',

'L77044858',

'L77045846',

'L77047608',

'L77049326',

'L77049675',

'L77050786',

'L77050888',

'L77050954',

'L77051290',

'L77051496',

'L77051604',

'L77052183',

'L77053131',

'L77054773',

'L77057281',

'L77058217',

'L77058222',

'L77064854',

'L77069704',

'L77070026',

'L77070098',

'L77072351',

'L77073251',

'L77073853',

'L77074203',

'L77074313',

'L77075271',

'L77075390',

'L77075516',

'L77076484',

'L77077191',

'L77079067',

'L77081901',

'L77085989',

'L77090957',

'L77090958',

'L77090959',

'L77091513',

'L77095102',

'L77096688',

'L77098964',

'L77101855',

'L77102723',

'L77109393',

'L77110542',

'L77112048',

'L77123963',

'L77124472',

'L77125245',

'L77131192',

'L77132432',

'L77133258',

'L77143116',

'L77152999',

'L77212814',

'L77218665',

'L77239525',

'L77717918',

'L77746820',

'L77774286',

'L77781001',

'L77870896',

'L77874466',

'L77885525',

'L77894111',

'L77899001',

'L77904993',

'L77907743',

'L77910088',

'L77927162',

'L77927701',

'L77936480',

'L77938737',

'L77938744',

'L77941385',

'L77943340',

'L77953584',

'L77957860',

'L77961066',

'L77961552',

'L77965666',

'L77966217',

'L77972632',

'L77974573',

'L77976341',

'L77981348',

'L77982359',

'L77984003',

'L77995253',

'L77995445',

'L77997752',

'L77999514',

'L77999798',

'L78003884',

'L78003891',

'L78004818',

'L78009280',

'L78010442',

'L78012908',

'L78013239',

'L78020280',

'L78022009',

'L78022678',

'L78024551',

'L78025907',

'L78026797',

'L78029195',

'L78029600',

'L78030479',

'L78032216',

'L78033000',

'L78033013',

'L78035055',

'L78036517',

'L78036690',

'L78038595',

'L78039447',

'L78039450',

'L78039498',

'L78039661',

'L78040169',

'L78040726',

'L78040797',

'L78041527',

'L78041747',

'L78042029',

'L78042519',

'L78045033',

'L78047313',

'L78047744',

'L78049965',

'L78050021',

'L78050654',

'L78055952',

'L78056858',

'L78060552',

'L78061399',

'L78064702',

'L78064872',

'L78069167',

'L78072980',

'L78268488',

'L73008308',

'L73320287',

'L73386683',

'L74253681',

'L74759041',

'L74806763',

'L74807170',

'L75116263',

'L75301675',

'L75310817',

'L75488177',

'L75798611',

'L76075484',

'L76184048',

'L76341785',

'L76346556',

'L76347829',

'L76350218',

'L76350913',

'L76354556',

'L76361766',

'L76386094',

'L76419286',

'L76452783',

'L76481644',

'L76510125',

'L76619737',

'L76761120',

'L76820241',

'L76821556',

'L76822331',

'L76823215',

'L76825137',

'L76831155',

'L76831431',

'L76831519',

'L76832406',

'L76832890',

'L76832978',

'L76833132',

'L76835389',

'L76835833',

'L76838393',

'L76840262',

'L76840588',

'L76840592',

'L76840694',

'L76840899',

'L76840913',

'L76841399',

'L76842805',

'L76851443',

'L76854087',

'L76855925',

'L76855939',

'L76856687',

'L76857011',

'L76857725',

'L76860765',

'L76860926',

'L76861150',

'L76861262',

'L76863180',

'L76863674',

'L76864894',

'L76864979',

'L76865314',

'L76865416',

'L76865431',

'L76865795',

'L76868995',

'L76869402',

'L76869694',

'L76870920',

'L76873139',

'L76874770',

'L76875197',

'L76876968',

'L76878292',

'L76878487',

'L76878517',

'L76878588',

'L76879202',

'L76879403',

'L76879462',

'L76882038',

'L76882398',

'L76886467',

'L76886538',

'L76887055',

'L76892595',

'L76892664',

'L76892688',

'L76893958',

'L76894510',

'L76894750',

'L76896219',

'L76896227',

'L76896265',

'L76896388',

'L76896549',

'L76896763',

'L76897488',

'L76897829',

'L76898317',

'L76898462',

'L76899135',

'L76899936',

'L76900193',

'L76900208',

'L76900658',

'L76900717',

'L76900760',

'L76901075',

'L76901257',

'L76901278',

'L76901388',

'L76901516',

'L76901714',

'L76903277',

'L76903575',

'L76903946',

'L76903991',

'L76904284',

'L76904475',

'L76904747',

'L76908385',

'L76908389',

'L76908440',

'L76908479',

'L76908527',

'L76908528',

'L76908832',

'L76908860',

'L76909032',

'L76909112',

'L76909129',

'L76913172',

'L76913434',

'L76913461',

'L76914551',

'L76915197',

'L76916001',

'L76917070',

'L76917258',

'L76917264',

'L76918389',

'L76919099',

'L76919288',

'L76920392',

'L76920405',

'L76920706',

'L76921595',

'L76921642',

'L76921881',

'L76922126',

'L76922128',

'L76922416',

'L76922735',

'L76922770',

'L76924269',

'L76924367',

'L76925903',

'L76925928',

'L76926085',

'L76927505',

'L76927595',

'L76927660',

'L76927666',

'L76928206',

'L76928548',

'L76928690',

'L76931027',

'L76931086',

'L76931331',

'L76931565',

'L76931567',

'L76933417',

'L76933591',

'L76933986',

'L76934922',

'L76935320',

'L76937140',

'L76937559',

'L76938865',

'L76938921',

'L76938973',

'L76941579',

'L76941603',

'L76941758',

'L76944440',

'L76945426',

'L76947167',

'L76947445',

'L76947613',

'L76947994',

'L76948597',

'L76948872',

'L76948924',

'L76950121',

'L76950600',

'L76951145',

'L76951250',

'L76953044',

'L76953092',

'L76953133',

'L76953613',

'L76954084',

'L76957185',

'L76957195',

'L76957955',

'L76958849',

'L76960908',

'L76961070',

'L76961892',

'L76961957',

'L76964190',

'L76966788',

'L76968096',

'L76968518',

'L76975255',

'L76975701',

'L76976160',

'L76976585',

'L76977008',

'L76978291',

'L76978570',

'L76978649',

'L76979973',

'L76980849',

'L76981066',

'L76983509',

'L76984193',

'L76984519',

'L76990024',

'L76990858',

'L76991639',

'L76992753',

'L76995652',

'L76995744',

'L76995761',

'L76996436',

'L76996553',

'L76998955',

'L76998982',

'L76998989',

'L76999696',

'L77009427',

'L77009535',

'L77009581',

'L77009874',

'L77011775',

'L77016325',

'L77020504',

'L77024834',

'L77026271',

'L77026281',

'L77027930',

'L77029280',

'L77029768',

'L77031620',

'L77031672',

'L77044799',

'L77052908',

'L77054804',

'L77088983',

'L77101739',

'L77124472',

'L77152999',

'L77165469',

'L77218665',

'L77575844',

'L77696290',

'L77701507',

'L77711753',

'L77718082',

'L77725472',

'L77737350',

'L77746741',

'L77756102',

'L77773547',

'L77785225',

'L77802847',

'L77817321',

'L77824932',

'L77827561',

'L77831283',

'L77833588',

'L77834099',

'L77835754',

'L77839336',

'L77839669',

'L77840161',

'L77840713',

'L77840736',

'L77840812',

'L77840927',

'L77842353',

'L77843127',

'L77843732',

'L77846587',

'L77847359',

'L77847958',

'L77850526',

'L77852091',

'L77852102',

'L77854534',

'L77855387',

'L77857920',

'L77857977',

'L77860377',

'L77860449',

'L77861423',

'L77861698',

'L77863932',

'L77864422',

'L77864457',

'L77864710',

'L77866861',

'L77867247',

'L77867482',

'L77870372',

'L77871295',

'L77872900',

'L77873853',

'L77874196',

'L77874322',

'L77875602',

'L77877179',

'L77877302',

'L77877419',

'L77883494',

'L77884075',

'L77887162',

'L77887381',

'L77887502',

'L77888394',

'L77888891',

'L77889847',

'L77890723',

'L77891003',

'L77893442',

'L77894041',

'L77895200',

'L77896199',

'L77896253',

'L77897111',

'L77897833',

'L77902866',

'L77903422',

'L77905712',

'L77906048',

'L77906273',

'L77906827',

'L77907708',

'L77908218',

'L77908524',

'L77908687',

'L77909217',

'L77909654',

'L77910615',

'L77911425',

'L77911474',

'L77914439',

'L77914445',

'L77916147',

'L77916555',

'L77916952',

'L77917368',

'L77917372',

'L77920263',

'L77920459',

'L77921023',

'L77921054',

'L77921130',

'L77921344',

'L77921452',

'L77922344',

'L77923401',

'L77924608',

'L77924701',

'L77925030',

'L77926198',

'L77926693',

'L77927405',

'L77931696',

'L77932345',

'L77932492',

'L77933350',

'L77935918',

'L77936181',

'L77936926',

'L77937385',

'L77937532',

'L77937966',

'L77941385',

'L77941418',

'L77942505',

'L77943378',

'L77944365',

'L77944735',

'L78004754',

'L78009353',

'L78268488',

'L72801367',

'L73083336',

'L73187283',

'L73310847',

'L73316548',

'L74400722',

'L74512589',

'L74715718',

'L74728702',

'L74752170',

'L74752222',

'L74768215',

'L74773684',

'L74782669',

'L74787898',

'L74790263',

'L74795895',

'L74801189',

'L74801780',

'L74803046',

'L74803817',

'L74805683',

'L74805811',

'L74806132',

'L74806201',

'L74807423',

'L74811275',

'L74817822',

'L74818434',

'L74821080',

'L74839523',

'L75097396',

'L75271519',

'L75272400',

'L75276079',

'L75276243',

'L75276675',

'L75279035',

'L75279510',

'L75279598',

'L75283605',

'L75284043',

'L75284704',

'L75286046',

'L75286250',

'L75286308',

'L75286378',

'L75287751',

'L75293189',

'L75293498',

'L75296123',

'L75296921',

'L75297016',

'L75302089',

'L75309355',

'L75310577',

'L75310824',

'L75321458',

'L75321793',

'L75368237',

'L75445274',

'L75445322',

'L75452521',

'L75748532',

'L75774760',

'L76059491',

'L76087617',

'L76147726',

'L76343096',

'L76343105',

'L76344235',

'L76344936',

'L76344939',

'L76346858',

'L76347798',

'L76348086',

'L76348179',

'L76348189',

'L76348439',

'L76349812',

'L76350114',

'L76350232',

'L76350362',

'L76350364',

'L76350396',

'L76350968',

'L76352084',

'L76353048',

'L76353097',

'L76353599',

'L76353752',

'L76354723',

'L76360404',

'L76360474',

'L76361593',

'L76361671',

'L76365506',

'L76366762',

'L76367065',

'L76368069',

'L76368496',

'L76368563',

'L76368595',

'L76408098',

'L76408610',

'L76410216',

'L76451016',

'L76453849',

'L76454412',

'L76455348',

'L76487321',

'L76491024',

'L76492531',

'L76492546',

'L76500889',

'L76504095',

'L76506518',

'L76506739',

'L76511501',

'L76515306',

'L76518043',

'L76522260',

'L76522374',

'L76522777',

'L76522987',

'L76523037',

'L76523222',

'L76524140',

'L76610650',

'L76611250',

'L76614208',

'L76616795',

'L76619905',

'L76621117',

'L76621684',

'L76624539',

'L76632967',

'L76636931',

'L76641557',

'L76645875',

'L76651035',

'L76668766',

'L76703505',

'L76761047',

'L76764726',

'L76767423',

'L76770434',

'L76778609',

'L76782357',

'L76782969',

'L76783293',

'L76789584',

'L76820939',

'L76821376',

'L76821399',

'L76821436',

'L76821454',

'L76821558',

'L76821934',

'L76822043',

'L76822100',

'L76822375',

'L76822584',

'L76822591',

'L76824360',

'L76824483',

'L76824510',

'L76825146',

'L76828259',

'L76828957',

'L76829014',

'L76830447',

'L76831136',

'L76831210',

'L76831347',

'L76832543',

'L76832546',

'L76832958',

'L76833183',

'L76833995',

'L76835383',

'L76835965',

'L76838878',

'L76839307',

'L76840123',

'L76840242',

'L76840254',

'L76842647',

'L76842862',

'L76843014',

'L76851843',

'L76853691',

'L76855606',

'L76855863',

'L76856635',

'L76856689',

'L76857938',

'L76860577',

'L76861027',

'L76861893',

'L76862842',

'L76863041',

'L76863089',

'L76863609',

'L76865220',

'L76865295',

'L76869439',

'L76869481',

'L76869788',

'L76870490',

'L76873431',

'L76873944',

'L76875675',

'L76886236',

'L76892822',

'L76893003',

'L76893056',

'L76893120',

'L76896433',

'L76899791',

'L76901705',

'L76903966',

'L76907134',

'L76907399',

'L76908805',

'L76913163',

'L76918345',

'L76918469',

'L76919219',

'L76937785',

'L76953232',

'L76953600',

'L76965029',

'L76969859',

'L76976585',

'L76979680',

'L76984519',

'L76990104',

'L77051465',

'L77053383',

'L77113160',

'L77124472',

'L77152999',

'L77218665',

'L77286989',

'L77439110',

'L77550642',

'L77565242',

'L77641708',

'L77643764',

'L77646144',

'L77682901',

'L77683214',

'L77690309',

'L77700915',

'L77712843',

'L77715783',

'L77717601',

'L77717738',

'L77723478',

'L77727151',

'L77728409',

'L77740261',

'L77740617',

'L77740789',

'L77745436',

'L77749708',

'L77753083',

'L77754774',

'L77755045',

'L77755341',

'L77755667',

'L77756589',

'L77757129',

'L77757614',

'L77757677',

'L77758084',

'L77759515',

'L77762672',

'L77763132',

'L77770449',

'L77771250',

'L77772470',

'L77773451',

'L77774888',

'L77776843',

'L77781233',

'L77781542',

'L77784032',

'L77784042',

'L77784102',

'L77786554',

'L77787053',

'L77788516',

'L77790544',

'L77791589',

'L77794070',

'L77794212',

'L77795244',

'L77795577',

'L77795968',

'L77800081',

'L77800632',

'L77802260',

'L77802581',

'L77803256',

'L77803379',

'L77804752',

'L77805306',

'L77805537',

'L77806470',

'L77806640',

'L77806715',

'L77807301',

'L77808245',

'L77809334',

'L77809478',

'L77810013',

'L77810163',

'L77810305',

'L77812889',

'L77813555',

'L77813590',

'L77814584',

'L77815392',

'L77816130',

'L77816354',

'L77816362',

'L77816455',

'L77816797',

'L77816806',

'L77816842',

'L77817301',

'L77817670',

'L77817847',

'L77817851',

'L77819045',

'L77819218',

'L77819323',

'L77820280',

'L77820384',

'L77821710',

'L77821730',

'L77821882',

'L77822856',

'L77823853',

'L77824104',

'L77825297',

'L77825574',

'L77825602',

'L77826012',

'L77827268',

'L77827338',

'L77827905',

'L77828341',

'L77828458',

'L77830506',

'L77830707',

'L77830715',

'L77830717',

'L77831596',

'L77831925',

'L77838393',

'L77839739',

'L77937966',

'L77941385',

'L78268488',

'L74724350',

'L74731777',

'L74745898',

'L74775718',

'L74775951',

'L74778236',

'L74779128',

'L74779976',

'L74780559',

'L74787193',

'L74804246',

'L74807445',

'L74811654',

'L74982286',

'L75274650',

'L75277943',

'L75444696',

'L75727817',

'L76362231',

'L76367520',

'L76414786',

'L76416002',

'L76788912',

'L76921885',

'L77152999',

'L77218665',

'L77528562',

'L77675096',

'L77680691',

'L77683666',

'L77689773',

'L77711772',

'L77717662',

'L77718799',

'L77720003',

'L77726984',

'L77727310',

'L77728123',

'L77733145',

'L77737869',

'L77745735',

'L77775300',

'L77941385',

'L77983426',

'L74445963',

'L74623168',

'L74624259',

'L74647111',

'L74660647',

'L74694951',

'L74711757',

'L74714501',

'L74723851',

'L74727213',

'L74729155',

'L74747179',

'L74756133',

'L74768335',

'L74771234',

'L74798520',

'L74803327',

'L75272922',

'L76392443',

'L76415057',

'L76523550',

'L76769749',

'L77152999',

'L77218665',

'L77373010',

'L77436630',

'L77576143',

'L77576168',

'L77594173',

'L77599298',

'L77610313',

'L77617049',

'L77618112',

'L77623612',

'L77636482',

'L77637997',

'L77639723',

'L77642517',

'L77644662',

'L77648826',

'L77653747',

'L77660831',

'L77941385',

'L72621646',

'L73895803',

'L74409205',

'L74416920',

'L74440405',

'L74442331',

'L74450229',

'L74474041',

'L74476160',

'L74480649',

'L74490038',

'L74493311',

'L74494306',

'L74494856',

'L74510592',

'L74664087',

'L74667693',

'L74691490',

'L74702164',

'L74707657',

'L74707684',

'L74715981',

'L76376252',

'L76411960',

'L76645931',

'L76769668',

'L77366858',

'L77373349',

'L77418564',

'L77471727',

'L77472852',

'L77494330',

'L77503013',

'L77503441',

'L77504039',

'L77515089',

'L77518684',

'L77524310',

'L77525835',

'L77526628'

);
CREATE TEMP TABLE dependent_candidate AS
SELECT * FROM candidate_dashboard

WHERE OrderID not in (SELECT human_id FROM `pacific-plating-282708.temp.2025-03 new order from cancel change order credit shell` )

AND OrderID in (

  'L74256408',

'L74300166',

'L74340842',

'L74343536',

'L74402254',

'L74405784',

'L74427081',

'L74427712',

'L74430507',

'L74438979',

'L74440536',

'L74442869',

'L74453733',

'L74468069',

'L74493645',

'L74494145',

'L74510143',

'L74512746',

'L74520278',

'L74590996',

'L74623408',

'L74624257',

'L74663899',

'L74692981',

'L74768487',

'L74770301',

'L76362624',

'L76381553',

'L76386664',

'L77178953',

'L77311432',

'L77334959',

'L77401037',

'L77423021',

'L77423955',

'L77424504',

'L77437401',

'L77439533',

'L77441582',

'L77443853',

'L77444482',

'L77444681',

'L77445015',

'L77446119',

'L77447067',

'L77447717',

'L77449244',

'L77450551',

'L77458596',

'L77459765',

'L77460002',

'L77465633',

'L77473102',

'L77473637',

'L77474424',

'L73724413',

'L73732471',

'L73910039',

'L73925659',

'L74093732',

'L75280487',

'L77032552',

'L77051000',

'L77076863',

'L77085743',

'L77102636',

'L77105258',

'L77110037',

'L77127267',

'L77127764',

'L77128891',

'L77133830',

'L77136477',

'L77136812',

'L77137046',

'L77139568',

'L77139576',

'L77141259',

'L77144908',

'L77145970',

'L77146702',

'L77147324',

'L77148332',

'L77148824',

'L77148990',

'L77152178',

'L77152594',

'L77152669',

'L77152993',

'L77153011',

'L77153355',

'L77153913',

'L77154875',

'L77158848',

'L77165282',

'L77169952',

'L77172861',

'L77174075',

'L77175455',

'L77176331',

'L77176635',

'L77177754',

'L77178009',

'L77180520',

'L77184251',

'L77184386',

'L77184418',

'L77185233',

'L77190845',

'L77191202',

'L77193042',

'L77194369',

'L77194390',

'L77194782',

'L77195812',

'L77198016',

'L77198191',

'L77199218',

'L77200407',

'L77202025',

'L77202152',

'L77202486',

'L77205144',

'L77205429',

'L77205458',

'L77206258',

'L77208128',

'L77208229',

'L77208499',

'L77208667',

'L77208930',

'L77209484',

'L77209895',

'L77210360',

'L77210654',

'L77210882',

'L77212092',

'L77212473',

'L77212527',

'L77212621',

'L77212687',

'L77212887',

'L77212950',

'L77212990',

'L77213229',

'L77213320',

'L77213486',

'L77213792',

'L77213979',

'L77214023',

'L77214037',

'L77214096',

'L77215448',

'L77216352',

'L77216452',

'L77216713',

'L77216715',

'L77216817',

'L77216874',

'L77216875',

'L77217390',

'L77217399',

'L77218205',

'L77218478',

'L77218532',

'L77218541',

'L77218650',

'L77218667',

'L77218735',

'L77218739',

'L77218743',

'L77218763',

'L77218782',

'L77219002',

'L77219132',

'L77219393',

'L77219524',

'L77219525',

'L77219549',

'L77221329',

'L77222538',

'L77222736',

'L77222948',

'L77222962',

'L77223019',

'L77223803',

'L77223804',

'L77223815',

'L77223837',

'L77223870',

'L77223950',

'L77224836',

'L77225966',

'L77229000',

'L77229017',

'L77229027',

'L77229058',

'L77229103',

'L77229132',

'L77229194',

'L77229227',

'L77229286',

'L77229404',

'L77229467',

'L77229645',

'L77229658',

'L77229804',

'L77229810',

'L77229857',

'L77229893',

'L77229912',

'L77230017',

'L77230021',

'L77230169',

'L77230307',

'L77230313',

'L77230600',

'L77231225',

'L77231526',

'L77231958',

'L77231979',

'L77232990',

'L77233036',

'L77233038',

'L77233055',

'L77233056',

'L77233628',

'L77233676',

'L77233918',

'L77234002',

'L77234099',

'L77234216',

'L77234406',

'L77234422',

'L77234524',

'L77234638',

'L77237853',

'L77238062',

'L77238093',

'L77238163',

'L77238188',

'L77238201',

'L77238335',

'L77238345',

'L77238723',

'L77238756',

'L77240625',

'L77241105',

'L77241139',

'L77241202',

'L77241264',

'L77241329',

'L77241334',

'L77241451',

'L77242398',

'L77242425',

'L77242573',

'L77247024',

'L77247698',

'L77247799',

'L77247915',

'L77248016',

'L77248048',

'L77248281',

'L77248435',

'L77250792',

'L77252691',

'L77252711',

'L77252799',

'L77252906',

'L77254462',

'L77255650',

'L77255767',

'L77255887',

'L77256507',

'L77256551',

'L77256614',

'L77257562',

'L77257815',

'L77258936',

'L77259209',

'L77259249',

'L77259409',

'L77259786',

'L77261965',

'L77262744',

'L77263284',

'L77264170',

'L77264227',

'L77267136',

'L77270447',

'L77270485',

'L77270767',

'L77271411',

'L77272567',

'L77272745',

'L77274365',

'L77276306',

'L77276539',

'L77277778',

'L77278093',

'L77278567',

'L77278599',

'L77278607',

'L77278707',

'L77279034',

'L77279233',

'L77279381',

'L77279529',

'L77282602',

'L77282652',

'L77282653',

'L77282723',

'L77283276',

'L77283552',

'L77283685',

'L77283726',

'L77283859',

'L77286585',

'L77287430',

'L77287643',

'L77287777',

'L77289513',

'L77289531',

'L77291619',

'L77292060',

'L77292120',

'L77292678',

'L77294026',

'L77294047',

'L77294131',

'L77294278',

'L77294284',

'L77295635',

'L77295814',

'L77297352',

'L77298446',

'L77298483',

'L77298558',

'L77298711',

'L77298726',

'L77299851',

'L77300129',

'L77300246',

'L77300381',

'L77303891',

'L77305416',

'L77306947',

'L77307192',

'L77307279',

'L77307460',

'L77308057',

'L77310266',

'L77317220',

'L77318532',

'L77320690',

'L77320878',

'L77322044',

'L77322547',

'L77322548',

'L77322759',

'L77325006',

'L77326458',

'L77328676',

'L77331652',

'L77336150',

'L77336340',

'L77337851',

'L77339334',

'L77341069',

'L77353141',

'L77356606',

'L77356992',

'L77359366',

'L77362585',

'L77429492',

'L77437282',

'L77449310',

'L77458803',

'L77514480',

'L77759837',

'L77781746',

'L77826089',

'L77851893',

'L78041242',

'L78061821',

'L78179246',

'L78224194',

'L78247030',

'L78260856',

'L78273370',

'L78279786',

'L78291382',

'L78291805',

'L78293097',

'L78293100',

'L78294951',

'L78297629',

'L78300917',

'L78301072',

'L78301686',

'L78303282',

'L78309063',

'L78309132',

'L78309686',

'L78309702',

'L78312550',

'L78315011',

'L78315012',

'L78318145',

'L78318797',

'L78320378',

'L78321434',

'L78321723',

'L78322105',

'L78325383',

'L78326034',

'L78326453',

'L78326614',

'L78330003',

'L78330420',

'L78331218',

'L78339673',

'L78340106',

'L78340870',

'L78340933',

'L78341661',

'L78344609',

'L78346392',

'L78346966',

'L78348506',

'L78349202',

'L78349699',

'L78350109',

'L78350285',

'L78350417',

'L78350884',

'L78351432',

'L78351618',

'L78351643',

'L78353169',

'L78354098',

'L78354185',

'L78354426',

'L78355657',

'L78355891',

'L78356643',

'L78356675',

'L78356865',

'L78357034',

'L78357197',

'L78358079',

'L78358718',

'L78358867',

'L78358998',

'L78359581',

'L78359624',

'L78359956',

'L78360224',

'L78360731',

'L78360868',

'L78360932',

'L78360990',

'L78361269',

'L78362383',

'L78362407',

'L78363028',

'L78363036',

'L78363159',

'L78363160',

'L78363471',

'L78363859',

'L78363868',

'L78364108',

'L78364299',

'L78370853',

'L78371247',

'L78372223',

'L78372345',

'L78372369',

'L78372666',

'L78383218',

'L78383609',

'L78383851',

'L78385010',

'L78385353',

'L78385700',

'L78386370',

'L78386453',

'L78386539',

'L78386789',

'L78386946',

'L78387064',

'L72651220',

'L73707169',

'L73875165',

'L75446127',

'L76853344',

'L76958584',

'L76968514',

'L76981184',

'L76982197',

'L76999192',

'L77008110',

'L77018043',

'L77025337',

'L77027850',

'L77029561',

'L77034676',

'L77041221',

'L77047541',

'L77049836',

'L77050000',

'L77052262',

'L77057239',

'L77058749',

'L77065180',

'L77072924',

'L77075290',

'L77086015',

'L77087901',

'L77091196',

'L77098880',

'L77098905',

'L77099208',

'L77099442',

'L77101678',

'L77101681',

'L77102742',

'L77102941',

'L77104293',

'L77104606',

'L77104860',

'L77104923',

'L77105880',

'L77106462',

'L77109519',

'L77110116',

'L77113511',

'L77113682',

'L77114170',

'L77114223',

'L77116123',

'L77116138',

'L77119137',

'L77123767',

'L77124374',

'L77124810',

'L77125555',

'L77126799',

'L77126827',

'L77127209',

'L77131359',

'L77133595',

'L77133683',

'L77133735',

'L77133938',

'L77134760',

'L77134772',

'L77136278',

'L77136546',

'L77139035',

'L77139142',

'L77139286',

'L77139592',

'L77139701',

'L77139826',

'L77140218',

'L77141264',

'L77141560',

'L77141704',

'L77143283',

'L77143837',

'L77144817',

'L77144930',

'L77144944',

'L77145081',

'L77145151',

'L77145714',

'L77145808',

'L77146200',

'L77146632',

'L77146921',

'L77147303',

'L77147574',

'L77148652',

'L77148814',

'L77148883',

'L77149148',

'L77149437',

'L77150602',

'L77151719',

'L77152724',

'L77152765',

'L77153294',

'L77153492',

'L77153544',

'L77153923',

'L77154066',

'L77155283',

'L77155871',

'L77155917',

'L77155966',

'L77158665',

'L77160267',

'L77161050',

'L77163999',

'L77164149',

'L77165784',

'L77166849',

'L77166852',

'L77167118',

'L77167126',

'L77167321',

'L77169632',

'L77170105',

'L77170646',

'L77173557',

'L77174245',

'L77174372',

'L77174390',

'L77177210',

'L77177659',

'L77180779',

'L77181595',

'L77181820',

'L77184571',

'L77185364',

'L77187279',

'L77187322',

'L77191195',

'L77192334',

'L77192340',

'L77194135',

'L77198106',

'L77199221',

'L77203806',

'L77206850',

'L77208133',

'L77208474',

'L77208583',

'L77210549',

'L77212861',

'L77212948',

'L77213349',

'L77214161',

'L77216121',

'L77218762',

'L77219375',

'L77230429',

'L77231496',

'L77238136',

'L77242437',

'L77264456',

'L77283492',

'L77292752',

'L77372225',

'L77759186',

'L77778887',

'L77784301',

'L77790969',

'L77805438',

'L77829701',

'L77844033',

'L77872531',

'L77882359',

'L77883070',

'L77918154',

'L77967640',

'L77968408',

'L78009531',

'L78030077',

'L78059264',

'L78074791',

'L78079340',

'L78083612',

'L78105836',

'L78113757',

'L78128334',

'L78143043',

'L78144429',

'L78145395',

'L78146194',

'L78150429',

'L78152111',

'L78156452',

'L78162765',

'L78166372',

'L78170300',

'L78173613',

'L78175093',

'L78175110',

'L78176209',

'L78177237',

'L78177542',

'L78178719',

'L78182076',

'L78182316',

'L78188524',

'L78197759',

'L78199631',

'L78202870',

'L78204546',

'L78204965',

'L78207619',

'L78208582',

'L78208941',

'L78209767',

'L78212807',

'L78212815',

'L78213346',

'L78214772',

'L78214921',

'L78215303',

'L78218053',

'L78218545',

'L78223030',

'L78223440',

'L78225177',

'L78226256',

'L78226833',

'L78228195',

'L78229855',

'L78229861',

'L78232518',

'L78232871',

'L78233639',

'L78234280',

'L78234933',

'L78235818',

'L78238065',

'L78239097',

'L78239830',

'L78241186',

'L78243146',

'L78244444',

'L78245263',

'L78245700',

'L78245749',

'L78245940',

'L78245957',

'L78245976',

'L78246313',

'L78246467',

'L78246482',

'L78248070',

'L78248856',

'L78249597',

'L78251120',

'L78251598',

'L78252312',

'L78252538',

'L78253337',

'L78253967',

'L78254073',

'L78254227',

'L78256100',

'L78256227',

'L78256813',

'L78258916',

'L78260960',

'L78262447',

'L78263793',

'L78264325',

'L78266003',

'L78266713',

'L78267314',

'L78268000',

'L78268488',

'L78270453',

'L78270858',

'L78271062',

'L78272592',

'L78273997',

'L78278144',

'L78279054',

'L78279359',

'L78281587',

'L78288298',

'L78296185',

'L73283282',

'L73393947',

'L73478141',

'L73716020',

'L75275234',

'L75295225',

'L76871093',

'L76880153',

'L76908179',

'L76924485',

'L76927769',

'L76934924',

'L76951192',

'L76955786',

'L76956366',

'L76964132',

'L76966521',

'L76972734',

'L76975698',

'L76976785',

'L76979612',

'L76981436',

'L76982233',

'L76985594',

'L76990197',

'L76991110',

'L76991147',

'L76991742',

'L76993600',

'L76999033',

'L77009089',

'L77011883',

'L77012087',

'L77015594',

'L77018315',

'L77018902',

'L77020578',

'L77021447',

'L77021974',

'L77024335',

'L77024424',

'L77026257',

'L77030146',

'L77031276',

'L77031677',

'L77032399',

'L77032984',

'L77034796',

'L77037662',

'L77040819',

'L77041526',

'L77043523',

'L77043595',

'L77043622',

'L77044041',

'L77044056',

'L77044125',

'L77044734',

'L77045381',

'L77047111',

'L77047114',

'L77047273',

'L77049680',

'L77049790',

'L77049818',

'L77050049',

'L77050831',

'L77050883',

'L77050899',

'L77050926',

'L77050960',

'L77051212',

'L77051446',

'L77051959',

'L77052260',

'L77052280',

'L77052394',

'L77052407',

'L77052965',

'L77053027',

'L77053115',

'L77053666',

'L77054770',

'L77056979',

'L77057073',

'L77057588',

'L77058662',

'L77058909',

'L77060005',

'L77060444',

'L77060472',

'L77060565',

'L77060894',

'L77061011',

'L77061290',

'L77061311',

'L77062353',

'L77062518',

'L77064685',

'L77065137',

'L77065258',

'L77065321',

'L77065928',

'L77066711',

'L77068178',

'L77068282',

'L77068546',

'L77068866',

'L77069511',

'L77069539',

'L77069556',

'L77069753',

'L77069894',

'L77069967',

'L77069986',

'L77071515',

'L77071764',

'L77073173',

'L77073180',

'L77073190',

'L77073400',

'L77073735',

'L77073757',

'L77073890',

'L77073891',

'L77073957',

'L77074064',

'L77074157',

'L77074367',

'L77075383',

'L77075392',

'L77075515',

'L77075808',

'L77075812',

'L77075844',

'L77075892',

'L77075915',

'L77076902',

'L77076923',

'L77077122',

'L77077186',

'L77078380',

'L77078886',

'L77079110',

'L77079699',

'L77079924',

'L77080205',

'L77081779',

'L77081898',

'L77084251',

'L77084277',

'L77084319',

'L77084383',

'L77084391',

'L77084472',

'L77084511',

'L77084588',

'L77084826',

'L77085190',

'L77085432',

'L77085737',

'L77085949',

'L77086329',

'L77088227',

'L77088575',

'L77088993',

'L77089422',

'L77090691',

'L77090809',

'L77090903',

'L77094570',

'L77095042',

'L77095728',

'L77096638',

'L77096902',

'L77096954',

'L77097121',

'L77098939',

'L77098978',

'L77099325',

'L77099828',

'L77101593',

'L77101662',

'L77102116',

'L77102145',

'L77102209',

'L77102215',

'L77102260',

'L77102855',

'L77102966',

'L77104080',

'L77104295',

'L77104318',

'L77104542',

'L77104560',

'L77104581',

'L77104861',

'L77105060',

'L77105704',

'L77105940',

'L77106271',

'L77106418',

'L77106445',

'L77108897',

'L77108898',

'L77109068',

'L77109573',

'L77109609',

'L77110383',

'L77110545',

'L77111100',

'L77112055',

'L77112061',

'L77112070',

'L77112196',

'L77112267',

'L77112360',

'L77112384',

'L77112536',

'L77113484',

'L77113615',

'L77115498',

'L77115515',

'L77115601',

'L77116032',

'L77116135',

'L77116171',

'L77116490',

'L77119194',

'L77119575',

'L77119876',

'L77120345',

'L77120376',

'L77123476',

'L77123482',

'L77124094',

'L77124207',

'L77124368',

'L77124371',

'L77124472',

'L77124849',

'L77124968',

'L77125038',

'L77125120',

'L77125177',

'L77125503',

'L77127153',

'L77127193',

'L77128159',

'L77128505',

'L77128508',

'L77129567',

'L77129876',

'L77130936',

'L77131211',

'L77132031',

'L77132546',

'L77132551',

'L77133634',

'L77133677',

'L77134040',

'L77134257',

'L77134528',

'L77134546',

'L77134662',

'L77134833',

'L77134884',

'L77135769',

'L77135850',

'L77135893',

'L77138679',

'L77139139',

'L77139181',

'L77139219',

'L77139600',

'L77139964',

'L77141289',

'L77141482',

'L77142861',

'L77143842',

'L77144051',

'L77145032',

'L77145183',

'L77145465',

'L77146122',

'L77146259',

'L77146588',

'L77147317',

'L77148525',

'L77148744',

'L77149242',

'L77150143',

'L77150188',

'L77150486',

'L77152232',

'L77152333',

'L77152402',

'L77152574',

'L77152860',

'L77152940',

'L77152999',

'L77153578',

'L77154006',

'L77154050',

'L77154076',

'L77154483',

'L77155747',

'L77156954',

'L77159948',

'L77162509',

'L77164926',

'L77165779',

'L77173513',

'L77174546',

'L77175514',

'L77177233',

'L77177378',

'L77177455',

'L77180549',

'L77187302',

'L77187305',

'L77191842',

'L77194941',

'L77198936',

'L77218665',

'L77285695',

'L77299734',

'L77444692',

'L77450942',

'L77540230',

'L77613172',

'L77724951',

'L77783851',

'L77825281',

'L77872529',

'L77897197',

'L77924918',

'L77938003',

'L77938297',

'L77938976',

'L77954482',

'L77960094',

'L77980012',

'L78011058',

'L78014120',

'L78031958',

'L78036423',

'L78037947',

'L78044348',

'L78044366',

'L78047041',

'L78047739',

'L78053360',

'L78064271',

'L78064294',

'L78070303',

'L78075235',

'L78075239',

'L78075655',

'L78080847',

'L78081554',

'L78082791',

'L78087251',

'L78087838',

'L78089392',

'L78089676',

'L78090024',

'L78094440',

'L78096197',

'L78096949',

'L78097049',

'L78098543',

'L78098948',

'L78101965',

'L78102881',

'L78106321',

'L78106387',

'L78106577',

'L78110550',

'L78111187',

'L78113222',

'L78115555',

'L78115574',

'L78117522',

'L78117803',

'L78118596',

'L78119070',

'L78119746',

'L78123326',

'L78123857',

'L78123871',

'L78124192',

'L78124913',

'L78127644',

'L78127913',

'L78128201',

'L78128570',

'L78129431',

'L78129988',

'L78130170',

'L78130579',

'L78131039',

'L78131804',

'L78132174',

'L78132246',

'L78133601',

'L78134500',

'L78135002',

'L78136619',

'L78137568',

'L78139223',

'L78139243',

'L78140409',

'L78142204',

'L78142307',

'L78143568',

'L78144209',

'L78144304',

'L78145137',

'L78145258',

'L78145400',

'L78145592',

'L78145616',

'L78145929',

'L78145958',

'L78146726',

'L78146742',

'L78146849',

'L78146940',

'L78147280',

'L78147282',

'L78147441',

'L78148331',

'L78148554',

'L78148628',

'L78149417',

'L78150144',

'L78151408',

'L78151413',

'L78151484',

'L78151976',

'L78152288',

'L78153180',

'L78153338',

'L78153527',

'L78153550',

'L78154455',

'L78155045',

'L78155062',

'L78155076',

'L78155217',

'L78155472',

'L78155602',

'L78155623',

'L78156128',

'L78156202',

'L78156204',

'L78156228',

'L78156602',

'L78156638',

'L78156646',

'L78158615',

'L78158784',

'L78158989',

'L78159000',

'L78159429',

'L78161724',

'L78161959',

'L78164560',

'L78164569',

'L78165086',

'L78166249',

'L78168224',

'L78168625',

'L78168873',

'L78168906',

'L78174118',

'L78177041',

'L78212480',

'L78226914',

'L78247029',

'L78268488',

'L78278144',

'L78296185',

'L73071799',

'L73355971',

'L74806026',

'L75279916',

'L75305359',

'L76833238',

'L76853781',

'L76875776',

'L76879223',

'L76896738',

'L76899855',

'L76901439',

'L76903624',

'L76905878',

'L76908570',

'L76908628',

'L76914603',

'L76914651',

'L76916142',

'L76918356',

'L76918702',

'L76921585',

'L76921879',

'L76922409',

'L76922537',

'L76927356',

'L76927380',

'L76928560',

'L76928998',

'L76935315',

'L76935442',

'L76937144',

'L76937415',

'L76937768',

'L76942513',

'L76944427',

'L76945187',

'L76947082',

'L76947446',

'L76947897',

'L76948536',

'L76950320',

'L76950827',

'L76950830',

'L76953194',

'L76953487',

'L76953493',

'L76954715',

'L76955677',

'L76956525',

'L76956535',

'L76956598',

'L76957614',

'L76957986',

'L76959124',

'L76960446',

'L76960735',

'L76960740',

'L76961792',

'L76963700',

'L76964737',

'L76965191',

'L76967224',

'L76968060',

'L76972054',

'L76972533',

'L76972900',

'L76973795',

'L76973821',

'L76974075',

'L76975750',

'L76976146',

'L76976188',

'L76976359',

'L76976585',

'L76976947',

'L76977494',

'L76978273',

'L76978955',

'L76979687',

'L76980912',

'L76981271',

'L76981896',

'L76981985',

'L76982236',

'L76982274',

'L76983357',

'L76983497',

'L76983548',

'L76983799',

'L76984489',

'L76984571',

'L76984640',

'L76984725',

'L76984780',

'L76987592',

'L76987707',

'L76987828',

'L76989661',

'L76989851',

'L76989947',

'L76990008',

'L76990012',

'L76990017',

'L76990122',

'L76990190',

'L76990422',

'L76990923',

'L76991049',

'L76991328',

'L76991580',

'L76991662',

'L76993712',

'L76994007',

'L76994108',

'L76994124',

'L76994169',

'L76995425',

'L76995621',

'L76995808',

'L76995954',

'L76999046',

'L76999227',

'L76999453',

'L76999622',

'L77001758',

'L77001818',

'L77003428',

'L77004410',

'L77004774',

'L77007681',

'L77008479',

'L77008485',

'L77008611',

'L77011975',

'L77011997',

'L77012109',

'L77013546',

'L77013547',

'L77015405',

'L77015447',

'L77015667',

'L77015728',

'L77015831',

'L77016048',

'L77016304',

'L77017835',

'L77019250',

'L77019305',

'L77020384',

'L77020486',

'L77024642',

'L77025940',

'L77026068',

'L77026300',

'L77028253',

'L77028304',

'L77029221',

'L77029493',

'L77029602',

'L77029817',

'L77029994',

'L77030004',

'L77031393',

'L77032997',

'L77034554',

'L77035826',

'L77038470',

'L77041432',

'L77044350',

'L77044468',

'L77044858',

'L77045846',

'L77047608',

'L77049326',

'L77049675',

'L77050786',

'L77050888',

'L77050954',

'L77051290',

'L77051496',

'L77051604',

'L77052183',

'L77053131',

'L77054773',

'L77057281',

'L77058217',

'L77058222',

'L77064854',

'L77069704',

'L77070026',

'L77070098',

'L77072351',

'L77073251',

'L77073853',

'L77074203',

'L77074313',

'L77075271',

'L77075390',

'L77075516',

'L77076484',

'L77077191',

'L77079067',

'L77081901',

'L77085989',

'L77090957',

'L77090958',

'L77090959',

'L77091513',

'L77095102',

'L77096688',

'L77098964',

'L77101855',

'L77102723',

'L77109393',

'L77110542',

'L77112048',

'L77123963',

'L77124472',

'L77125245',

'L77131192',

'L77132432',

'L77133258',

'L77143116',

'L77152999',

'L77212814',

'L77218665',

'L77239525',

'L77717918',

'L77746820',

'L77774286',

'L77781001',

'L77870896',

'L77874466',

'L77885525',

'L77894111',

'L77899001',

'L77904993',

'L77907743',

'L77910088',

'L77927162',

'L77927701',

'L77936480',

'L77938737',

'L77938744',

'L77941385',

'L77943340',

'L77953584',

'L77957860',

'L77961066',

'L77961552',

'L77965666',

'L77966217',

'L77972632',

'L77974573',

'L77976341',

'L77981348',

'L77982359',

'L77984003',

'L77995253',

'L77995445',

'L77997752',

'L77999514',

'L77999798',

'L78003884',

'L78003891',

'L78004818',

'L78009280',

'L78010442',

'L78012908',

'L78013239',

'L78020280',

'L78022009',

'L78022678',

'L78024551',

'L78025907',

'L78026797',

'L78029195',

'L78029600',

'L78030479',

'L78032216',

'L78033000',

'L78033013',

'L78035055',

'L78036517',

'L78036690',

'L78038595',

'L78039447',

'L78039450',

'L78039498',

'L78039661',

'L78040169',

'L78040726',

'L78040797',

'L78041527',

'L78041747',

'L78042029',

'L78042519',

'L78045033',

'L78047313',

'L78047744',

'L78049965',

'L78050021',

'L78050654',

'L78055952',

'L78056858',

'L78060552',

'L78061399',

'L78064702',

'L78064872',

'L78069167',

'L78072980',

'L78268488',

'L73008308',

'L73320287',

'L73386683',

'L74253681',

'L74759041',

'L74806763',

'L74807170',

'L75116263',

'L75301675',

'L75310817',

'L75488177',

'L75798611',

'L76075484',

'L76184048',

'L76341785',

'L76346556',

'L76347829',

'L76350218',

'L76350913',

'L76354556',

'L76361766',

'L76386094',

'L76419286',

'L76452783',

'L76481644',

'L76510125',

'L76619737',

'L76761120',

'L76820241',

'L76821556',

'L76822331',

'L76823215',

'L76825137',

'L76831155',

'L76831431',

'L76831519',

'L76832406',

'L76832890',

'L76832978',

'L76833132',

'L76835389',

'L76835833',

'L76838393',

'L76840262',

'L76840588',

'L76840592',

'L76840694',

'L76840899',

'L76840913',

'L76841399',

'L76842805',

'L76851443',

'L76854087',

'L76855925',

'L76855939',

'L76856687',

'L76857011',

'L76857725',

'L76860765',

'L76860926',

'L76861150',

'L76861262',

'L76863180',

'L76863674',

'L76864894',

'L76864979',

'L76865314',

'L76865416',

'L76865431',

'L76865795',

'L76868995',

'L76869402',

'L76869694',

'L76870920',

'L76873139',

'L76874770',

'L76875197',

'L76876968',

'L76878292',

'L76878487',

'L76878517',

'L76878588',

'L76879202',

'L76879403',

'L76879462',

'L76882038',

'L76882398',

'L76886467',

'L76886538',

'L76887055',

'L76892595',

'L76892664',

'L76892688',

'L76893958',

'L76894510',

'L76894750',

'L76896219',

'L76896227',

'L76896265',

'L76896388',

'L76896549',

'L76896763',

'L76897488',

'L76897829',

'L76898317',

'L76898462',

'L76899135',

'L76899936',

'L76900193',

'L76900208',

'L76900658',

'L76900717',

'L76900760',

'L76901075',

'L76901257',

'L76901278',

'L76901388',

'L76901516',

'L76901714',

'L76903277',

'L76903575',

'L76903946',

'L76903991',

'L76904284',

'L76904475',

'L76904747',

'L76908385',

'L76908389',

'L76908440',

'L76908479',

'L76908527',

'L76908528',

'L76908832',

'L76908860',

'L76909032',

'L76909112',

'L76909129',

'L76913172',

'L76913434',

'L76913461',

'L76914551',

'L76915197',

'L76916001',

'L76917070',

'L76917258',

'L76917264',

'L76918389',

'L76919099',

'L76919288',

'L76920392',

'L76920405',

'L76920706',

'L76921595',

'L76921642',

'L76921881',

'L76922126',

'L76922128',

'L76922416',

'L76922735',

'L76922770',

'L76924269',

'L76924367',

'L76925903',

'L76925928',

'L76926085',

'L76927505',

'L76927595',

'L76927660',

'L76927666',

'L76928206',

'L76928548',

'L76928690',

'L76931027',

'L76931086',

'L76931331',

'L76931565',

'L76931567',

'L76933417',

'L76933591',

'L76933986',

'L76934922',

'L76935320',

'L76937140',

'L76937559',

'L76938865',

'L76938921',

'L76938973',

'L76941579',

'L76941603',

'L76941758',

'L76944440',

'L76945426',

'L76947167',

'L76947445',

'L76947613',

'L76947994',

'L76948597',

'L76948872',

'L76948924',

'L76950121',

'L76950600',

'L76951145',

'L76951250',

'L76953044',

'L76953092',

'L76953133',

'L76953613',

'L76954084',

'L76957185',

'L76957195',

'L76957955',

'L76958849',

'L76960908',

'L76961070',

'L76961892',

'L76961957',

'L76964190',

'L76966788',

'L76968096',

'L76968518',

'L76975255',

'L76975701',

'L76976160',

'L76976585',

'L76977008',

'L76978291',

'L76978570',

'L76978649',

'L76979973',

'L76980849',

'L76981066',

'L76983509',

'L76984193',

'L76984519',

'L76990024',

'L76990858',

'L76991639',

'L76992753',

'L76995652',

'L76995744',

'L76995761',

'L76996436',

'L76996553',

'L76998955',

'L76998982',

'L76998989',

'L76999696',

'L77009427',

'L77009535',

'L77009581',

'L77009874',

'L77011775',

'L77016325',

'L77020504',

'L77024834',

'L77026271',

'L77026281',

'L77027930',

'L77029280',

'L77029768',

'L77031620',

'L77031672',

'L77044799',

'L77052908',

'L77054804',

'L77088983',

'L77101739',

'L77124472',

'L77152999',

'L77165469',

'L77218665',

'L77575844',

'L77696290',

'L77701507',

'L77711753',

'L77718082',

'L77725472',

'L77737350',

'L77746741',

'L77756102',

'L77773547',

'L77785225',

'L77802847',

'L77817321',

'L77824932',

'L77827561',

'L77831283',

'L77833588',

'L77834099',

'L77835754',

'L77839336',

'L77839669',

'L77840161',

'L77840713',

'L77840736',

'L77840812',

'L77840927',

'L77842353',

'L77843127',

'L77843732',

'L77846587',

'L77847359',

'L77847958',

'L77850526',

'L77852091',

'L77852102',

'L77854534',

'L77855387',

'L77857920',

'L77857977',

'L77860377',

'L77860449',

'L77861423',

'L77861698',

'L77863932',

'L77864422',

'L77864457',

'L77864710',

'L77866861',

'L77867247',

'L77867482',

'L77870372',

'L77871295',

'L77872900',

'L77873853',

'L77874196',

'L77874322',

'L77875602',

'L77877179',

'L77877302',

'L77877419',

'L77883494',

'L77884075',

'L77887162',

'L77887381',

'L77887502',

'L77888394',

'L77888891',

'L77889847',

'L77890723',

'L77891003',

'L77893442',

'L77894041',

'L77895200',

'L77896199',

'L77896253',

'L77897111',

'L77897833',

'L77902866',

'L77903422',

'L77905712',

'L77906048',

'L77906273',

'L77906827',

'L77907708',

'L77908218',

'L77908524',

'L77908687',

'L77909217',

'L77909654',

'L77910615',

'L77911425',

'L77911474',

'L77914439',

'L77914445',

'L77916147',

'L77916555',

'L77916952',

'L77917368',

'L77917372',

'L77920263',

'L77920459',

'L77921023',

'L77921054',

'L77921130',

'L77921344',

'L77921452',

'L77922344',

'L77923401',

'L77924608',

'L77924701',

'L77925030',

'L77926198',

'L77926693',

'L77927405',

'L77931696',

'L77932345',

'L77932492',

'L77933350',

'L77935918',

'L77936181',

'L77936926',

'L77937385',

'L77937532',

'L77937966',

'L77941385',

'L77941418',

'L77942505',

'L77943378',

'L77944365',

'L77944735',

'L78004754',

'L78009353',

'L78268488',

'L72801367',

'L73083336',

'L73187283',

'L73310847',

'L73316548',

'L74400722',

'L74512589',

'L74715718',

'L74728702',

'L74752170',

'L74752222',

'L74768215',

'L74773684',

'L74782669',

'L74787898',

'L74790263',

'L74795895',

'L74801189',

'L74801780',

'L74803046',

'L74803817',

'L74805683',

'L74805811',

'L74806132',

'L74806201',

'L74807423',

'L74811275',

'L74817822',

'L74818434',

'L74821080',

'L74839523',

'L75097396',

'L75271519',

'L75272400',

'L75276079',

'L75276243',

'L75276675',

'L75279035',

'L75279510',

'L75279598',

'L75283605',

'L75284043',

'L75284704',

'L75286046',

'L75286250',

'L75286308',

'L75286378',

'L75287751',

'L75293189',

'L75293498',

'L75296123',

'L75296921',

'L75297016',

'L75302089',

'L75309355',

'L75310577',

'L75310824',

'L75321458',

'L75321793',

'L75368237',

'L75445274',

'L75445322',

'L75452521',

'L75748532',

'L75774760',

'L76059491',

'L76087617',

'L76147726',

'L76343096',

'L76343105',

'L76344235',

'L76344936',

'L76344939',

'L76346858',

'L76347798',

'L76348086',

'L76348179',

'L76348189',

'L76348439',

'L76349812',

'L76350114',

'L76350232',

'L76350362',

'L76350364',

'L76350396',

'L76350968',

'L76352084',

'L76353048',

'L76353097',

'L76353599',

'L76353752',

'L76354723',

'L76360404',

'L76360474',

'L76361593',

'L76361671',

'L76365506',

'L76366762',

'L76367065',

'L76368069',

'L76368496',

'L76368563',

'L76368595',

'L76408098',

'L76408610',

'L76410216',

'L76451016',

'L76453849',

'L76454412',

'L76455348',

'L76487321',

'L76491024',

'L76492531',

'L76492546',

'L76500889',

'L76504095',

'L76506518',

'L76506739',

'L76511501',

'L76515306',

'L76518043',

'L76522260',

'L76522374',

'L76522777',

'L76522987',

'L76523037',

'L76523222',

'L76524140',

'L76610650',

'L76611250',

'L76614208',

'L76616795',

'L76619905',

'L76621117',

'L76621684',

'L76624539',

'L76632967',

'L76636931',

'L76641557',

'L76645875',

'L76651035',

'L76668766',

'L76703505',

'L76761047',

'L76764726',

'L76767423',

'L76770434',

'L76778609',

'L76782357',

'L76782969',

'L76783293',

'L76789584',

'L76820939',

'L76821376',

'L76821399',

'L76821436',

'L76821454',

'L76821558',

'L76821934',

'L76822043',

'L76822100',

'L76822375',

'L76822584',

'L76822591',

'L76824360',

'L76824483',

'L76824510',

'L76825146',

'L76828259',

'L76828957',

'L76829014',

'L76830447',

'L76831136',

'L76831210',

'L76831347',

'L76832543',

'L76832546',

'L76832958',

'L76833183',

'L76833995',

'L76835383',

'L76835965',

'L76838878',

'L76839307',

'L76840123',

'L76840242',

'L76840254',

'L76842647',

'L76842862',

'L76843014',

'L76851843',

'L76853691',

'L76855606',

'L76855863',

'L76856635',

'L76856689',

'L76857938',

'L76860577',

'L76861027',

'L76861893',

'L76862842',

'L76863041',

'L76863089',

'L76863609',

'L76865220',

'L76865295',

'L76869439',

'L76869481',

'L76869788',

'L76870490',

'L76873431',

'L76873944',

'L76875675',

'L76886236',

'L76892822',

'L76893003',

'L76893056',

'L76893120',

'L76896433',

'L76899791',

'L76901705',

'L76903966',

'L76907134',

'L76907399',

'L76908805',

'L76913163',

'L76918345',

'L76918469',

'L76919219',

'L76937785',

'L76953232',

'L76953600',

'L76965029',

'L76969859',

'L76976585',

'L76979680',

'L76984519',

'L76990104',

'L77051465',

'L77053383',

'L77113160',

'L77124472',

'L77152999',

'L77218665',

'L77286989',

'L77439110',

'L77550642',

'L77565242',

'L77641708',

'L77643764',

'L77646144',

'L77682901',

'L77683214',

'L77690309',

'L77700915',

'L77712843',

'L77715783',

'L77717601',

'L77717738',

'L77723478',

'L77727151',

'L77728409',

'L77740261',

'L77740617',

'L77740789',

'L77745436',

'L77749708',

'L77753083',

'L77754774',

'L77755045',

'L77755341',

'L77755667',

'L77756589',

'L77757129',

'L77757614',

'L77757677',

'L77758084',

'L77759515',

'L77762672',

'L77763132',

'L77770449',

'L77771250',

'L77772470',

'L77773451',

'L77774888',

'L77776843',

'L77781233',

'L77781542',

'L77784032',

'L77784042',

'L77784102',

'L77786554',

'L77787053',

'L77788516',

'L77790544',

'L77791589',

'L77794070',

'L77794212',

'L77795244',

'L77795577',

'L77795968',

'L77800081',

'L77800632',

'L77802260',

'L77802581',

'L77803256',

'L77803379',

'L77804752',

'L77805306',

'L77805537',

'L77806470',

'L77806640',

'L77806715',

'L77807301',

'L77808245',

'L77809334',

'L77809478',

'L77810013',

'L77810163',

'L77810305',

'L77812889',

'L77813555',

'L77813590',

'L77814584',

'L77815392',

'L77816130',

'L77816354',

'L77816362',

'L77816455',

'L77816797',

'L77816806',

'L77816842',

'L77817301',

'L77817670',

'L77817847',

'L77817851',

'L77819045',

'L77819218',

'L77819323',

'L77820280',

'L77820384',

'L77821710',

'L77821730',

'L77821882',

'L77822856',

'L77823853',

'L77824104',

'L77825297',

'L77825574',

'L77825602',

'L77826012',

'L77827268',

'L77827338',

'L77827905',

'L77828341',

'L77828458',

'L77830506',

'L77830707',

'L77830715',

'L77830717',

'L77831596',

'L77831925',

'L77838393',

'L77839739',

'L77937966',

'L77941385',

'L78268488',

'L74724350',

'L74731777',

'L74745898',

'L74775718',

'L74775951',

'L74778236',

'L74779128',

'L74779976',

'L74780559',

'L74787193',

'L74804246',

'L74807445',

'L74811654',

'L74982286',

'L75274650',

'L75277943',

'L75444696',

'L75727817',

'L76362231',

'L76367520',

'L76414786',

'L76416002',

'L76788912',

'L76921885',

'L77152999',

'L77218665',

'L77528562',

'L77675096',

'L77680691',

'L77683666',

'L77689773',

'L77711772',

'L77717662',

'L77718799',

'L77720003',

'L77726984',

'L77727310',

'L77728123',

'L77733145',

'L77737869',

'L77745735',

'L77775300',

'L77941385',

'L77983426',

'L74445963',

'L74623168',

'L74624259',

'L74647111',

'L74660647',

'L74694951',

'L74711757',

'L74714501',

'L74723851',

'L74727213',

'L74729155',

'L74747179',

'L74756133',

'L74768335',

'L74771234',

'L74798520',

'L74803327',

'L75272922',

'L76392443',

'L76415057',

'L76523550',

'L76769749',

'L77152999',

'L77218665',

'L77373010',

'L77436630',

'L77576143',

'L77576168',

'L77594173',

'L77599298',

'L77610313',

'L77617049',

'L77618112',

'L77623612',

'L77636482',

'L77637997',

'L77639723',

'L77642517',

'L77644662',

'L77648826',

'L77653747',

'L77660831',

'L77941385',

'L72621646',

'L73895803',

'L74409205',

'L74416920',

'L74440405',

'L74442331',

'L74450229',

'L74474041',

'L74476160',

'L74480649',

'L74490038',

'L74493311',

'L74494306',

'L74494856',

'L74510592',

'L74664087',

'L74667693',

'L74691490',

'L74702164',

'L74707657',

'L74707684',

'L74715981',

'L76376252',

'L76411960',

'L76645931',

'L76769668',

'L77366858',

'L77373349',

'L77418564',

'L77471727',

'L77472852',

'L77494330',

'L77503013',

'L77503441',

'L77504039',

'L77515089',

'L77518684',

'L77524310',

'L77525835',

'L77526628'

);
SELECT CURRENT_TIMESTAMP() AS checked_at_utc, 'sap_integration_v2.rcl_01_new_paid_by_period' AS dependent, (SELECT COUNT(*) FROM dependent_baseline) AS old_rows,(SELECT COUNT(*) FROM dependent_candidate) AS new_rows,(SELECT COUNT(*) FROM (SELECT TO_JSON_STRING(c) FROM dependent_candidate c EXCEPT DISTINCT SELECT TO_JSON_STRING(b) FROM dependent_baseline b)) AS added_payloads,(SELECT COUNT(*) FROM (SELECT TO_JSON_STRING(b) FROM dependent_baseline b EXCEPT DISTINCT SELECT TO_JSON_STRING(c) FROM dependent_candidate c)) AS removed_payloads;
DROP TABLE dependent_baseline; DROP TABLE dependent_candidate;
CREATE TEMP TABLE dependent_baseline AS
SELECT
  CAST(src.CompanyDB AS STRING) AS CompanyDB, CAST(src.OrderID AS STRING) AS OrderID,
  CAST(src.OrderItem AS STRING) AS OrderItem, CAST(src.InvoiceNo AS STRING) AS InvoiceNo,
  CAST(src.OrderDate AS STRING) AS OrderDate, CAST(src.InsuredID AS STRING) AS InsuredID,
  CAST(src.Title AS STRING) AS Title, CAST(src.FirstName AS STRING) AS FirstName,
  CAST(src.LastName AS STRING) AS LastName, CAST(src.InsurerCode AS STRING) AS InsurerCode,
  CAST(src.InsuranceGroup AS STRING) AS InsuranceGroup,
  CAST(src.InsuranceType AS STRING) AS InsuranceType,
  CAST(src.InsuranceProduct AS STRING) AS InsuranceProduct,
  CAST(src.ProductType AS STRING) AS ProductType, CAST(src.PolicyType AS STRING) AS PolicyType,
  CAST(src.Endorse AS STRING) AS Endorse, CAST(src.PolicyDate AS STRING) AS PolicyDate,
  CAST(src.PolicyNo AS STRING) AS PolicyNo, CAST(src.EndorsementNo AS STRING) AS EndorsementNo,
  CAST(src.ChassisNo AS STRING) AS ChassisNo, CAST(src.LicensePlate AS STRING) AS LicensePlate,
  CAST(src.GrossPremium AS STRING) AS GrossPremium, CAST(src.StampDuty AS STRING) AS StampDuty,
  CAST(src.VAT AS STRING) AS VAT, CAST(src.TotalPremium AS STRING) AS TotalPremium,
  CAST(src.WHT AS STRING) AS WHT, CAST(src.TotalEIR AS STRING) AS TotalEIR,
  CAST(src.TotalSBT AS STRING) AS TotalSBT, CAST(src.ProcessingFee AS STRING) AS ProcessingFee,
  CAST(src.ProcessingFeeVat AS STRING) AS ProcessingFeeVat,
  CAST(src.ShippingFee AS STRING) AS ShippingFee,
  CAST(src.ShippingFeeVat AS STRING) AS ShippingFeeVat,
  CAST(src.TotalAmount AS STRING) AS TotalAmount, CAST(src.Discount AS STRING) AS Discount,
  CAST(src.TransactionStatus AS STRING) AS TransactionStatus,
  CAST(src.SubmissionStatus AS STRING) AS SubmissionStatus,
  CAST(src.ApprovalStatus AS STRING) AS ApprovalStatus,
  CAST(src.PaymentStatus AS STRING) AS PaymentStatus,
  CAST(src.ExpectedReceived AS STRING) AS ExpectedReceived,
  CAST(src.ActualReceived AS STRING) AS ActualReceived,
  CAST(src.InterestThisPeriod AS STRING) AS InterestThisPeriod,
  CAST(src.PrincipleThisPeriod AS STRING) AS PrincipleThisPeriod,
  CAST(src.InterestEIRThisPeriod AS STRING) AS InterestEIRThisPeriod,
  CAST(src.PrincipleEIRThisPeriod AS STRING) AS PrincipleEIRThisPeriod,
  CAST(src.PaymentDate AS STRING) AS PaymentDate, CAST(src.Period AS STRING) AS Period,
  CAST(src.TotalPeriods AS STRING) AS TotalPeriods,
  CAST(src.PendingPayment AS STRING) AS PendingPayment,
  CAST(src.PaymentMethod AS STRING) AS PaymentMethod,
  CAST(src.PaymentChannel AS STRING) AS PaymentChannel,
  CAST(src.ExpectedDate AS STRING) AS ExpectedDate, CAST(src.RefOrder AS STRING) AS RefOrder,
  CAST(src.RefundAmountBeforeFee AS STRING) AS RefundAmountBeforeFee,
  CAST(src.RefundAmountAfterFee AS STRING) AS RefundAmountAfterFee,
  CAST(src.BillingAddress AS STRING) AS BillingAddress,
  CAST(src.BatchRunDate AS STRING) AS BatchRunDate
FROM baseline_dashboard AS src
JOIN `pacific-plating-282708.sap_integration_v3.stg_schedule` AS schedule
  ON schedule.order_item = src.OrderItem
  AND schedule.period = SAFE_CAST(src.Period AS INT64)
WHERE schedule.flow = 'RCL_CMI';
CREATE TEMP TABLE dependent_candidate AS
SELECT
  CAST(src.CompanyDB AS STRING) AS CompanyDB, CAST(src.OrderID AS STRING) AS OrderID,
  CAST(src.OrderItem AS STRING) AS OrderItem, CAST(src.InvoiceNo AS STRING) AS InvoiceNo,
  CAST(src.OrderDate AS STRING) AS OrderDate, CAST(src.InsuredID AS STRING) AS InsuredID,
  CAST(src.Title AS STRING) AS Title, CAST(src.FirstName AS STRING) AS FirstName,
  CAST(src.LastName AS STRING) AS LastName, CAST(src.InsurerCode AS STRING) AS InsurerCode,
  CAST(src.InsuranceGroup AS STRING) AS InsuranceGroup,
  CAST(src.InsuranceType AS STRING) AS InsuranceType,
  CAST(src.InsuranceProduct AS STRING) AS InsuranceProduct,
  CAST(src.ProductType AS STRING) AS ProductType, CAST(src.PolicyType AS STRING) AS PolicyType,
  CAST(src.Endorse AS STRING) AS Endorse, CAST(src.PolicyDate AS STRING) AS PolicyDate,
  CAST(src.PolicyNo AS STRING) AS PolicyNo, CAST(src.EndorsementNo AS STRING) AS EndorsementNo,
  CAST(src.ChassisNo AS STRING) AS ChassisNo, CAST(src.LicensePlate AS STRING) AS LicensePlate,
  CAST(src.GrossPremium AS STRING) AS GrossPremium, CAST(src.StampDuty AS STRING) AS StampDuty,
  CAST(src.VAT AS STRING) AS VAT, CAST(src.TotalPremium AS STRING) AS TotalPremium,
  CAST(src.WHT AS STRING) AS WHT, CAST(src.TotalEIR AS STRING) AS TotalEIR,
  CAST(src.TotalSBT AS STRING) AS TotalSBT, CAST(src.ProcessingFee AS STRING) AS ProcessingFee,
  CAST(src.ProcessingFeeVat AS STRING) AS ProcessingFeeVat,
  CAST(src.ShippingFee AS STRING) AS ShippingFee,
  CAST(src.ShippingFeeVat AS STRING) AS ShippingFeeVat,
  CAST(src.TotalAmount AS STRING) AS TotalAmount, CAST(src.Discount AS STRING) AS Discount,
  CAST(src.TransactionStatus AS STRING) AS TransactionStatus,
  CAST(src.SubmissionStatus AS STRING) AS SubmissionStatus,
  CAST(src.ApprovalStatus AS STRING) AS ApprovalStatus,
  CAST(src.PaymentStatus AS STRING) AS PaymentStatus,
  CAST(src.ExpectedReceived AS STRING) AS ExpectedReceived,
  CAST(src.ActualReceived AS STRING) AS ActualReceived,
  CAST(src.InterestThisPeriod AS STRING) AS InterestThisPeriod,
  CAST(src.PrincipleThisPeriod AS STRING) AS PrincipleThisPeriod,
  CAST(src.InterestEIRThisPeriod AS STRING) AS InterestEIRThisPeriod,
  CAST(src.PrincipleEIRThisPeriod AS STRING) AS PrincipleEIRThisPeriod,
  CAST(src.PaymentDate AS STRING) AS PaymentDate, CAST(src.Period AS STRING) AS Period,
  CAST(src.TotalPeriods AS STRING) AS TotalPeriods,
  CAST(src.PendingPayment AS STRING) AS PendingPayment,
  CAST(src.PaymentMethod AS STRING) AS PaymentMethod,
  CAST(src.PaymentChannel AS STRING) AS PaymentChannel,
  CAST(src.ExpectedDate AS STRING) AS ExpectedDate, CAST(src.RefOrder AS STRING) AS RefOrder,
  CAST(src.RefundAmountBeforeFee AS STRING) AS RefundAmountBeforeFee,
  CAST(src.RefundAmountAfterFee AS STRING) AS RefundAmountAfterFee,
  CAST(src.BillingAddress AS STRING) AS BillingAddress,
  CAST(src.BatchRunDate AS STRING) AS BatchRunDate
FROM candidate_dashboard AS src
JOIN `pacific-plating-282708.sap_integration_v3.stg_schedule` AS schedule
  ON schedule.order_item = src.OrderItem
  AND schedule.period = SAFE_CAST(src.Period AS INT64)
WHERE schedule.flow = 'RCL_CMI';
SELECT CURRENT_TIMESTAMP() AS checked_at_utc, 'sap_integration_v3.vw_v3_rcl_cmi_payload_source' AS dependent, (SELECT COUNT(*) FROM dependent_baseline) AS old_rows,(SELECT COUNT(*) FROM dependent_candidate) AS new_rows,(SELECT COUNT(*) FROM (SELECT TO_JSON_STRING(c) FROM dependent_candidate c EXCEPT DISTINCT SELECT TO_JSON_STRING(b) FROM dependent_baseline b)) AS added_payloads,(SELECT COUNT(*) FROM (SELECT TO_JSON_STRING(b) FROM dependent_baseline b EXCEPT DISTINCT SELECT TO_JSON_STRING(c) FROM dependent_candidate c)) AS removed_payloads;
DROP TABLE dependent_baseline; DROP TABLE dependent_candidate;
CREATE TEMP TABLE dependent_baseline AS
-- Full source-only legacy root-fix proposal for:
--   pacific-plating-282708.sap_view.RCL_Motor_process_1_create
--
-- Root cause:
--   sap_dashboard_carepay_installment correctly emits an RCL compulsory M1 as one
--   Period/TotalPeriods 1/1 row. The legacy wrapper then discards it because its
--   final QUALIFY requires every OrderItem to have more than one row and
--   TotalPeriods > 1. That schedule rule is valid for voluntary V1, but not M1.
--
-- Surgical fix:
--   * Allow compulsory M1 through only as Period/TotalPeriods 1/1.
--   * Keep the original multi-row and TotalPeriods > 1 gate for all voluntary rows.
--   * Require RABBIT_CARE_INSTALLMENT plus at least one SUCCESSFUL
--     RABBIT_LENDING charge before any row can enter this RCL interface.
--   * Admit V1 only as an all-or-nothing complete 1..TotalPeriods spine with
--     non-NULL ExpectedReceived, ActualReceived, and ExpectedDate.
--   * Preserve all existing SAP, change-order, year, insurer, and Test exclusions.
--
-- SELECT only: this file does not replace or deploy the live legacy view.

WITH
  eligible_rcl_items AS (
    SELECT DISTINCT order_items.human_id AS OrderItem
    FROM `pacific-plating-282708.careos.careos_orders` AS orders
    JOIN `pacific-plating-282708.careos.careos_order_items` AS order_items
      ON order_items.order_id = orders.id
    JOIN `pacific-plating-282708.careos.carepay_transactions` AS transactions
      ON CONCAT('transactions/', transactions.id) = orders.payment
     AND transactions.payment_option = 'RABBIT_CARE_INSTALLMENT'
    WHERE EXISTS (
      SELECT 1
      FROM `pacific-plating-282708.careos.carepay_charges` AS charges
      WHERE charges.transaction_id = transactions.id
        AND charges.status = 'SUCCESSFUL'
        AND charges.service_provider = 'RABBIT_LENDING'
    )
  ),

  interface AS (
    SELECT dashboard.*
    FROM baseline_dashboard AS dashboard
    JOIN eligible_rcl_items USING (OrderItem)
  ),

  filtered AS (
    SELECT interface.*
    FROM interface
    WHERE interface.OrderItem NOT IN (
      SELECT U_OrderItem
      FROM evidence_sap
    )
      AND interface.OrderID NOT IN (
        SELECT current_human_id
        FROM `pacific-plating-282708.careos.cancelled_change_orders`
      )
      AND interface.OrderDate NOT LIKE '%2023%'
      AND interface.OrderDate NOT LIKE '%2024%'
      AND interface.InsurerCode NOT IN ('45', '49')
      AND LOWER(TRIM(COALESCE(interface.FirstName, ''))) != 'test'
      AND LOWER(TRIM(COALESCE(interface.LastName, ''))) != 'test'
  ),

  spine_metrics AS (
    SELECT
      OrderItem,
      COUNT(*) AS row_count,
      COUNT(DISTINCT SAFE_CAST(Period AS INT64)) AS distinct_periods,
      MIN(SAFE_CAST(Period AS INT64)) AS min_period,
      MAX(SAFE_CAST(Period AS INT64)) AS max_period,
      COUNT(DISTINCT SAFE_CAST(TotalPeriods AS INT64)) AS total_period_versions,
      MAX(SAFE_CAST(TotalPeriods AS INT64)) AS total_periods,
      COUNTIF(SAFE_CAST(ExpectedReceived AS FLOAT64) IS NULL) AS null_expected_rows,
      COUNTIF(SAFE_CAST(ActualReceived AS FLOAT64) IS NULL) AS null_actual_rows,
      COUNTIF(
        NULLIF(TRIM(COALESCE(ExpectedDate, '')), '') IS NULL
      ) AS blank_expected_date_rows
    FROM filtered
    GROUP BY OrderItem
  )

SELECT
  filtered.*
FROM filtered
JOIN spine_metrics USING (OrderItem)
WHERE
  (
    filtered.InsuranceType = 'MOTOR_TYPE_COMPULSORY'
    AND SAFE_CAST(filtered.Period AS INT64) = 1
    AND SAFE_CAST(filtered.TotalPeriods AS INT64) = 1
    AND SAFE_CAST(filtered.ExpectedReceived AS FLOAT64) IS NOT NULL
    AND SAFE_CAST(filtered.ActualReceived AS FLOAT64) IS NOT NULL
    AND NULLIF(TRIM(COALESCE(filtered.ExpectedDate, '')), '') IS NOT NULL
  )
  OR (
    COALESCE(filtered.InsuranceType, '') != 'MOTOR_TYPE_COMPULSORY'
    AND spine_metrics.row_count > 1
    AND spine_metrics.total_periods > 1
    AND spine_metrics.total_period_versions = 1
    AND spine_metrics.min_period = 1
    AND spine_metrics.max_period = spine_metrics.total_periods
    AND spine_metrics.distinct_periods = spine_metrics.total_periods
    AND spine_metrics.null_expected_rows = 0
    AND spine_metrics.null_actual_rows = 0
    AND spine_metrics.blank_expected_date_rows = 0
  )
ORDER BY
  filtered.OrderItem,
  filtered.Period;
CREATE TEMP TABLE dependent_candidate AS
-- Full source-only legacy root-fix proposal for:
--   pacific-plating-282708.sap_view.RCL_Motor_process_1_create
--
-- Root cause:
--   sap_dashboard_carepay_installment correctly emits an RCL compulsory M1 as one
--   Period/TotalPeriods 1/1 row. The legacy wrapper then discards it because its
--   final QUALIFY requires every OrderItem to have more than one row and
--   TotalPeriods > 1. That schedule rule is valid for voluntary V1, but not M1.
--
-- Surgical fix:
--   * Allow compulsory M1 through only as Period/TotalPeriods 1/1.
--   * Keep the original multi-row and TotalPeriods > 1 gate for all voluntary rows.
--   * Require RABBIT_CARE_INSTALLMENT plus at least one SUCCESSFUL
--     RABBIT_LENDING charge before any row can enter this RCL interface.
--   * Admit V1 only as an all-or-nothing complete 1..TotalPeriods spine with
--     non-NULL ExpectedReceived, ActualReceived, and ExpectedDate.
--   * Preserve all existing SAP, change-order, year, insurer, and Test exclusions.
--
-- SELECT only: this file does not replace or deploy the live legacy view.

WITH
  eligible_rcl_items AS (
    SELECT DISTINCT order_items.human_id AS OrderItem
    FROM `pacific-plating-282708.careos.careos_orders` AS orders
    JOIN `pacific-plating-282708.careos.careos_order_items` AS order_items
      ON order_items.order_id = orders.id
    JOIN `pacific-plating-282708.careos.carepay_transactions` AS transactions
      ON CONCAT('transactions/', transactions.id) = orders.payment
     AND transactions.payment_option = 'RABBIT_CARE_INSTALLMENT'
    WHERE EXISTS (
      SELECT 1
      FROM `pacific-plating-282708.careos.carepay_charges` AS charges
      WHERE charges.transaction_id = transactions.id
        AND charges.status = 'SUCCESSFUL'
        AND charges.service_provider = 'RABBIT_LENDING'
    )
  ),

  interface AS (
    SELECT dashboard.*
    FROM candidate_dashboard AS dashboard
    JOIN eligible_rcl_items USING (OrderItem)
  ),

  filtered AS (
    SELECT interface.*
    FROM interface
    WHERE interface.OrderItem NOT IN (
      SELECT U_OrderItem
      FROM evidence_sap
    )
      AND interface.OrderID NOT IN (
        SELECT current_human_id
        FROM `pacific-plating-282708.careos.cancelled_change_orders`
      )
      AND interface.OrderDate NOT LIKE '%2023%'
      AND interface.OrderDate NOT LIKE '%2024%'
      AND interface.InsurerCode NOT IN ('45', '49')
      AND LOWER(TRIM(COALESCE(interface.FirstName, ''))) != 'test'
      AND LOWER(TRIM(COALESCE(interface.LastName, ''))) != 'test'
  ),

  spine_metrics AS (
    SELECT
      OrderItem,
      COUNT(*) AS row_count,
      COUNT(DISTINCT SAFE_CAST(Period AS INT64)) AS distinct_periods,
      MIN(SAFE_CAST(Period AS INT64)) AS min_period,
      MAX(SAFE_CAST(Period AS INT64)) AS max_period,
      COUNT(DISTINCT SAFE_CAST(TotalPeriods AS INT64)) AS total_period_versions,
      MAX(SAFE_CAST(TotalPeriods AS INT64)) AS total_periods,
      COUNTIF(SAFE_CAST(ExpectedReceived AS FLOAT64) IS NULL) AS null_expected_rows,
      COUNTIF(SAFE_CAST(ActualReceived AS FLOAT64) IS NULL) AS null_actual_rows,
      COUNTIF(
        NULLIF(TRIM(COALESCE(ExpectedDate, '')), '') IS NULL
      ) AS blank_expected_date_rows
    FROM filtered
    GROUP BY OrderItem
  )

SELECT
  filtered.*
FROM filtered
JOIN spine_metrics USING (OrderItem)
WHERE
  (
    filtered.InsuranceType = 'MOTOR_TYPE_COMPULSORY'
    AND SAFE_CAST(filtered.Period AS INT64) = 1
    AND SAFE_CAST(filtered.TotalPeriods AS INT64) = 1
    AND SAFE_CAST(filtered.ExpectedReceived AS FLOAT64) IS NOT NULL
    AND SAFE_CAST(filtered.ActualReceived AS FLOAT64) IS NOT NULL
    AND NULLIF(TRIM(COALESCE(filtered.ExpectedDate, '')), '') IS NOT NULL
  )
  OR (
    COALESCE(filtered.InsuranceType, '') != 'MOTOR_TYPE_COMPULSORY'
    AND spine_metrics.row_count > 1
    AND spine_metrics.total_periods > 1
    AND spine_metrics.total_period_versions = 1
    AND spine_metrics.min_period = 1
    AND spine_metrics.max_period = spine_metrics.total_periods
    AND spine_metrics.distinct_periods = spine_metrics.total_periods
    AND spine_metrics.null_expected_rows = 0
    AND spine_metrics.null_actual_rows = 0
    AND spine_metrics.blank_expected_date_rows = 0
  )
ORDER BY
  filtered.OrderItem,
  filtered.Period;
SELECT CURRENT_TIMESTAMP() AS checked_at_utc, 'sap_view.RCL_Motor_process_1_create' AS dependent, (SELECT COUNT(*) FROM dependent_baseline) AS old_rows,(SELECT COUNT(*) FROM dependent_candidate) AS new_rows,(SELECT COUNT(*) FROM (SELECT TO_JSON_STRING(c) FROM dependent_candidate c EXCEPT DISTINCT SELECT TO_JSON_STRING(b) FROM dependent_baseline b)) AS added_payloads,(SELECT COUNT(*) FROM (SELECT TO_JSON_STRING(b) FROM dependent_baseline b EXCEPT DISTINCT SELECT TO_JSON_STRING(c) FROM dependent_candidate c)) AS removed_payloads;
DROP TABLE dependent_baseline; DROP TABLE dependent_candidate;
CREATE TEMP TABLE ranked_charges AS
SELECT id,transaction_id,installment_number,third_party_id,amount,create_time,update_time,payment_method,
 ROW_NUMBER() OVER(PARTITION BY transaction_id,installment_number ORDER BY create_time,id) AS source_charge_rank,
 COUNT(*) OVER(PARTITION BY transaction_id,installment_number) AS period_charge_count,
 COUNT(*) OVER(PARTITION BY transaction_id,installment_number,create_time) AS timestamp_rows,
 COUNT(*) OVER(PARTITION BY transaction_id,installment_number,third_party_id) AS invoice_rows,
 COUNT(*) OVER(PARTITION BY id) AS charge_id_rows
FROM `pacific-plating-282708.careos.carepay_charges`
WHERE status='SUCCESSFUL' AND service_provider='RABBIT_LENDING';
CREATE TEMP TABLE population_a AS
SELECT c.id,c.transaction_id,c.installment_number,c.third_party_id,c.amount,c.create_time,c.update_time,c.payment_method,
 c.source_charge_rank,c.period_charge_count,c.timestamp_rows,c.invoice_rows,c.charge_id_rows
FROM ranked_charges c WHERE c.period_charge_count>1 AND EXISTS (
 SELECT 1 FROM `pacific-plating-282708.careos.carepay_transactions` t WHERE t.id=c.transaction_id AND t.payment_option='RABBIT_CARE_INSTALLMENT');
CREATE TEMP TABLE sap_receipts AS
SELECT DISTINCT U_OrderItem,SAFE_CAST(U_Period AS INT64) AS period,U_InvoiceNo
FROM evidence_sap WHERE LOWER(TRIM(TransactionStatus)) IN ('paid','cancelled','cancelled (change order / rejected)');
CREATE TEMP TABLE population_links AS
SELECT c.transaction_id,c.installment_number,c.source_charge_rank,
 COUNT(DISTINCT oi.human_id) AS item_count,
 COUNTIF(oi.product='MOTOR' AND COALESCE(oi.motor_item_type,'')!='MOTOR_TYPE_COMPULSORY') AS motor_voluntary_links,
 COUNTIF(oi.motor_item_type='MOTOR_TYPE_COMPULSORY') AS compulsory_links,
 COUNTIF(oi.product!='MOTOR') AS nonmotor_links,
 COUNTIF(s.U_OrderItem IS NOT NULL) AS sap_links,
 COUNTIF(w.OrderItem IS NOT NULL) AS candidate_links,
 COUNTIF(d.OrderItem IS NOT NULL) AS dashboard_links
FROM population_a c
LEFT JOIN `pacific-plating-282708.careos.careos_orders` o ON o.payment=CONCAT('transactions/',c.transaction_id)
LEFT JOIN `pacific-plating-282708.careos.careos_order_items` oi ON oi.order_id=o.id
LEFT JOIN sap_receipts s ON s.U_OrderItem=oi.human_id AND s.period=c.installment_number
 AND s.U_InvoiceNo IN (c.third_party_id,IF(c.installment_number=1,CONCAT('2_',c.third_party_id),c.third_party_id))
LEFT JOIN candidate_wrapper w ON w.OrderItem=oi.human_id AND SAFE_CAST(w.Period AS INT64)=c.installment_number
 AND w.InvoiceNo=IF(c.installment_number=1,CONCAT('2_',c.third_party_id),c.third_party_id)
LEFT JOIN candidate_dashboard d ON d.OrderItem=oi.human_id AND SAFE_CAST(d.Period AS INT64)=c.installment_number
 AND d.InvoiceNo=IF(c.installment_number=1,CONCAT('2_',c.third_party_id),c.third_party_id)
GROUP BY 1,2,3;
CREATE TEMP TABLE population_ledger AS
SELECT c.id AS charge_id,c.transaction_id,c.installment_number AS period,c.source_charge_rank,c.third_party_id,
 ROUND(c.amount/100,2) AS charge_amount_thb,FORMAT_TIMESTAMP('%Y-%m',c.create_time) AS charge_month,
 c.payment_method, l.item_count,l.sap_links,l.candidate_links,l.dashboard_links,
 CONCAT(IF(l.motor_voluntary_links>0,'MOTOR_VOLUNTARY;',''),IF(l.compulsory_links>0,'COMPULSORY;',''),IF(l.nonmotor_links>0,'NONMOTOR;','')) AS products,
 c.source_charge_rank>1 AND l.compulsory_links>0 AS additional_with_compulsory_item,
 DATE(c.update_time)<DATE_TRUNC(DATE_SUB(CURRENT_DATE(),INTERVAL 2 MONTH),MONTH) AS older_than_window,
 CASE
 WHEN NULLIF(TRIM(c.id),'') IS NULL OR c.charge_id_rows>1 THEN 'HOLD_INVALID_OR_DUPLICATE_CHARGE_ID'
 WHEN NULLIF(TRIM(c.third_party_id),'') IS NULL OR UPPER(TRIM(c.third_party_id))='NULL' THEN 'HOLD_MISSING_INVOICE'
 WHEN c.invoice_rows>1 THEN 'HOLD_COLLIDING_INVOICE'
 WHEN l.sap_links>0 THEN 'SAP_IDENTITY_PRESENT'
 WHEN l.candidate_links>0 THEN 'LEGACY_CANDIDATE_PRESENT'
 WHEN c.timestamp_rows>1 THEN 'HOLD_TIED_SOURCE_TIME'
 WHEN l.item_count=0 THEN 'HOLD_NO_ORDER_ITEM'
 WHEN DATE(c.update_time)<DATE_TRUNC(DATE_SUB(CURRENT_DATE(),INTERVAL 2 MONTH),MONTH) THEN 'HOLD_OUTSIDE_RECENCY_WINDOW'
 WHEN l.dashboard_links=0 THEN 'HOLD_OUTSIDE_DASHBOARD_SCOPE'
 ELSE 'HOLD_NOT_ROUTED_BY_LEGACY' END AS disposition
FROM population_a c JOIN population_links l USING(transaction_id,installment_number,source_charge_rank);
SELECT CURRENT_TIMESTAMP() AS checked_at_utc,
 (SELECT COUNT(*) FROM population_a) AS population_rows,
 (SELECT COUNT(*) FROM population_ledger) AS ledger_rows,
 (SELECT COUNT(*) FROM population_ledger WHERE disposition IS NULL) AS unclassified_rows,
 (SELECT COUNT(*) FROM population_ledger WHERE older_than_window) AS historical_rows,
 (SELECT COUNT(*) FROM population_ledger WHERE additional_with_compulsory_item) AS additional_compulsory_linked_rows,
 (SELECT COUNT(*) FROM population_ledger WHERE disposition LIKE 'HOLD_%') AS requires_hold_rows;
SELECT CURRENT_TIMESTAMP() AS checked_at_utc,products,IF(source_charge_rank=1,'first','additional') AS charge_kind,
 IF(period=1,'period_1','period_2_plus') AS period_group,charge_month,payment_method,disposition,
 COUNT(*) AS charge_rows,ROUND(SUM(charge_amount_thb),2) AS charge_amount_thb
FROM population_ledger GROUP BY 2,3,4,5,6,7 ORDER BY 2,3,4,5,6,7;
SELECT CURRENT_TIMESTAMP() AS checked_at_utc,COUNT(*) AS additional_shape_without_raw_rank
FROM added_wrapper_rows w WHERE w.ExpectedReceived=0 AND w.ActualReceived>0 AND NOT EXISTS (
 SELECT 1 FROM ranked_charges c JOIN `pacific-plating-282708.careos.careos_orders` o ON o.payment=CONCAT('transactions/',c.transaction_id)
 JOIN `pacific-plating-282708.careos.careos_order_items` oi ON oi.order_id=o.id
 WHERE oi.human_id=w.OrderItem AND c.installment_number=SAFE_CAST(w.Period AS INT64)
 AND w.InvoiceNo=IF(c.installment_number=1,CONCAT('2_',c.third_party_id),c.third_party_id) AND c.source_charge_rank>1);

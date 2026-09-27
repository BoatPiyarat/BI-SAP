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
      CASE WHEN c.installment_number = 1 AND oi.motor_item_type='MOTOR_TYPE_COMPULSORY'
        THEN CONCAT('2_',c.third_party_id)
        WHEN c.installment_number = 1 THEN CONCAT('2_', COALESCE(c.third_party_id, oi.human_id))
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
      AND (COALESCE(oi.motor_item_type,'') != 'MOTOR_TYPE_COMPULSORY' OR c.source_charge_rank=1)
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
      AND v.period=SAFE_CAST(d.Period AS INT64) AND v.invoice_no IS NOT DISTINCT FROM d.InvoiceNo
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

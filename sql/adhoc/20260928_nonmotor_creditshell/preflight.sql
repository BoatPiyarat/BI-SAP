CREATE TEMP TABLE before_producer AS
-- SOURCE-ONLY LEGACY PROPOSAL — DO NOT DEPLOY
-- Object: pacific-plating-282708.sap_integration_v2.RCL 04_new order credit shell
-- Live definition last modified: 2026-08-23 14:47:19 +00:00
-- Captured live query SHA256: 1266758867acc03c48c11fa2486b680eddf32bda7b4e0dd4fbcd0de66a032dba
-- Scope: latest-snapshot selection, complete-snapshot hold, duplicate-period ExpectedReceived,
-- item-master completeness, and period-grain payment identity.
-- Repository policy forbids DDL in sap_integration_v2.
-- BASELINE CAPTURE 2026-07-24 -- pulled verbatim from live BigQuery view definition
-- Object: sap_integration_v2.`RCL 04_new order credit shell new tunning`
-- Boat: fix the same A2 NULL-safe bug here, leave everything else as-is (not
-- confirmed live/nightly production like the other 4 objects, but fixing anyway).
-- See docs/knowledge/30_SAP_CHANGELOG.md (2026-07-24 entry) for the bug.
--
-- FIX 2026-08-23 (SOURCE ONLY, NOT DEPLOYED): re-pulled live 2026-08-23, confirmed byte-for-byte
-- identical to this file after that point, so drift-free as of this fix. Corrects
-- docs/FINDINGS_RCB_ONETIME_CHANGE_ORDER_MISROUTED_RCL_20260803.md's confirmed root cause: a
-- carried-over FULL_PAYMENT/CREDIT_CARD_INSTALLMENT (ONETIME) order was unconditionally labelled
-- 'RCL-Credit Shell' purely because `is_carried_over_from_old_order` was true, with no check of
-- the order's own payment_option. Live-verified trigger case: L80569331-M1 (created 2026-08-13,
-- payment_option=FULL_PAYMENT), reported by Mo 2026-08-23. Three changes, all additive/minimal:
-- (1) carry `payment_option` through transactions -> new_order_txn -> period_spine ->
--     spine_with_payment (new column, no existing column touched);
-- (2) in `channel_final`, route carried-over FULL_PAYMENT/CREDIT_CARD_INSTALLMENT to
--     'RCB-CreditShell' (matches the label already used by the reviewed V3 canonical router,
--     sql/ddl/050_v3_onetime_payload_source.sql); RABBIT_CARE_INSTALLMENT and unknown/NULL
--     payment_option keep the exact prior 'RCL-Credit Shell' behavior unchanged -- no new "hold"
--     state is introduced because this view has no quarantine mechanism to hold into, and
--     changing unproven cases risked a new failure mode with no live evidence to justify it;
-- (3) in `qualifying_orders`, added `PaymentChannel LIKE '%CreditShell%'` alongside the existing
--     '%Credit Shell%'/'%RCL%' checks -- WITHOUT this, rows newly relabelled 'RCB-CreditShell'
--     (no space, TotalPeriods=1) would fail every existing qualification condition and be
--     silently dropped from this view's entire output. Caught by manually tracing the label
--     through STEP 7 before treating the CASE-block change alone as sufficient.
-- Deliberately NOT changed: the MOTOR_TYPE_COMPULSORY path, any non-carried-over routing, and the
-- unproven RABBIT_CARE_INSTALLMENT/unknown-payment_option carried-over case.
-- No deploy performed. Pending Class-A review before Codex applies via CREATE OR REPLACE VIEW.
--
-- FIX 2026-09-07 (SOURCE ONLY, NOT DEPLOYED):
-- (1) remove item-less Period-1 rows that carried payment data but NULL insurance/policy fields
--     and zero premiums because the legacy LEFT JOIN explicitly allowed Period 1 through;
-- (2) source PaymentDate from the successful charge for the same installment period
--     (`payment_date`, falling back to `update_time`) instead of overwriting every historical
--     period with one current-month/SAP batch date;
-- (3) normalize Health/Travel group, type, and product to the existing SAP labels.
-- (4) use the established `<charge_rank>_<OrderItem>` legacy fallback when a SUCCESSFUL charge
--     has no third_party_id, avoiding blank/reused InvoiceNo values across payment rows.
-- (5) collapse exact full-row join duplicates before ranking repeated-period payments; distinct
--     payment rows for the same period remain and only the later rows receive ExpectedReceived = 0.
-- InvoiceNo, PaymentMethod, and PaymentChannel remain sourced from the successful charge joined
-- on `(transaction_id, installment_number = Period)`. Equal method/channel values remain valid
-- when the raw charges genuinely used the same route.

WITH
------------------------------------------------------------------
-- Base tables — only select needed columns, filter by date early
------------------------------------------------------------------
orders_scoped AS (
  SELECT id, human_id, payment, create_time, lead, data
  FROM `pacific-plating-282708.careos.careos_orders`
  WHERE create_time >= '2025-01-01'   -- <<< CONFIRM: adjust if credit shell cases go further back
),

order_items AS (
  SELECT order_id, human_id, is_cancelled, cancel_time, insurer, product,
         motor_item_type, package, policy_start_date, policy_number,
         net_premium, stamp_duty, vat_amount, gross_premium,
         submission_status, approval_status
  FROM `pacific-plating-282708.careos.careos_order_items`
),

leads AS (SELECT id, type, reference FROM `pacific-plating-282708.careos.careos_leads`),

transactions AS (SELECT id, payment_option FROM `pacific-plating-282708.careos.carepay_transactions`),

transaction_snapshots AS (
  SELECT id, transaction_id, number_of_installment
  FROM `pacific-plating-282708.careos.carepay_transaction_snapshots`
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY transaction_id
    ORDER BY update_time DESC, id DESC
  ) = 1
),

transaction_snapshot_installment_details AS (
  SELECT id, snapshot_id, period, payment_amount, principal,
         principal_balance, interest, add_ons
  FROM `pacific-plating-282708.careos.carepay_transaction_snapshot_installment_details`
),

transaction_snapshot_price_summaries AS (
  SELECT snapshot_id, wht_amount, interest_amount, processing_fee_amount,
         shipment_fee, discount_amount
  FROM `pacific-plating-282708.careos.carepay_transaction_snapshot_price_summaries`
),

charges AS (
  SELECT id, transaction_id, installment_number, third_party_id, status,
         amount, payment_method, service_provider, payment_date, update_time,
         ROW_NUMBER() OVER (
           PARTITION BY transaction_id
           ORDER BY create_time, id
         ) AS charge_rank
  FROM `pacific-plating-282708.careos.carepay_charges`
  WHERE status = 'SUCCESSFUL'
),

refunds AS (SELECT transaction_id, amount FROM `pacific-plating-282708.careos.carepay_refunds`),

follow_ups AS (SELECT transaction_id, installment, due_date FROM `pacific-plating-282708.careos.carepay_follow_ups`),

------------------------------------------------------------------
-- STEP 0: each order's own successful charges + invoice_no
------------------------------------------------------------------
order_charges AS (
  SELECT
    o.id AS order_pk,
    o.human_id AS order_id,
    o.create_time AS order_create_time,
    c.third_party_id AS invoice_no
  FROM orders_scoped o
  JOIN transactions t ON CONCAT('transactions/', t.id) = o.payment
  JOIN charges c ON c.transaction_id = t.id
  WHERE c.third_party_id IS NOT NULL
),

------------------------------------------------------------------
-- Pre-filter: invoice_no shared by >1 order before self-join
------------------------------------------------------------------
shared_invoice_candidates AS (
  SELECT invoice_no
  FROM order_charges
  GROUP BY invoice_no
  HAVING COUNT(DISTINCT order_pk) > 1
),

order_charges_candidates_only AS (
  SELECT oc.*
  FROM order_charges oc
  JOIN shared_invoice_candidates sic ON sic.invoice_no = oc.invoice_no
),

------------------------------------------------------------------
-- STEP 1: Credit Shell link
------------------------------------------------------------------
order_item_counts AS (
  SELECT
    order_id,
    COUNTIF(is_cancelled IS NOT TRUE) AS active_remaining,
    COUNT(*) AS total_items
  FROM order_items
  GROUP BY order_id
),

credit_shell_link AS (
  SELECT DISTINCT
    new_oc.order_id   AS new_order_id,
    new_oc.order_pk   AS new_order_pk,
    old_oc.order_id   AS old_order_id,
    old_oc.order_pk   AS old_order_pk,
    IFNULL(oic.active_remaining, 0) AS old_active_remaining,
    IFNULL(oic.total_items, 0)      AS old_total_items
  FROM order_charges_candidates_only new_oc
  JOIN order_charges_candidates_only old_oc
    ON old_oc.invoice_no = new_oc.invoice_no
   AND old_oc.order_pk != new_oc.order_pk
   AND old_oc.order_create_time < new_oc.order_create_time
  LEFT JOIN order_item_counts oic
    ON oic.order_id = old_oc.order_pk
),

credit_shell_classified AS (
  SELECT *,
    CASE
      WHEN old_active_remaining = 0 THEN 'FULL_REPLACEMENT'
      WHEN old_active_remaining > 0 AND old_active_remaining < old_total_items THEN 'PARTIAL_REPLACEMENT'
      ELSE 'REVIEW_UNKNOWN'
    END AS credit_shell_case_type
  FROM credit_shell_link
),

full_replacement_orders AS (
  SELECT new_order_id, old_order_id, old_order_pk
  FROM credit_shell_classified
  WHERE credit_shell_case_type = 'FULL_REPLACEMENT'
),

------------------------------------------------------------------
-- STEP 2: Period spine
-- CHANGED: carry order_pk through the spine (used later to join
-- order_items directly — replaces the old correlated subquery)
------------------------------------------------------------------
new_order_txn AS (
  SELECT
    o.id            AS order_pk,
    o.human_id      AS OrderID,
    o.data          AS order_data,
    o.lead          AS lead_ref,
    o.create_time   AS OrderDate,
    t.id            AS transaction_id,
    t.payment_option AS payment_option,
    ts.id           AS snapshot_id,
    ts.number_of_installment AS TotalPeriods
  FROM orders_scoped o
  JOIN full_replacement_orders fro ON fro.new_order_id = o.human_id
  LEFT JOIN transactions t ON CONCAT('transactions/', t.id) = o.payment
  -- ROOT FIX 2026-09-01: wait for the latest complete schedule snapshot instead of
  -- emitting a temporary NULL/invalid period shape or fanning out all snapshot versions.
  JOIN transaction_snapshots ts
    ON ts.transaction_id = t.id
   AND ts.number_of_installment >= 1
),

period_spine AS (
  SELECT
    n.order_pk,
    n.OrderID, n.transaction_id, n.payment_option, n.snapshot_id, n.TotalPeriods, n.OrderDate,
    n.order_data, n.lead_ref,
    period_num AS Period
  FROM new_order_txn n,
  UNNEST(GENERATE_ARRAY(1, GREATEST(IFNULL(n.TotalPeriods, 1), 1))) AS period_num
),

------------------------------------------------------------------
-- STEP 3: Attach schedule + payment + follow_up due_date per period
------------------------------------------------------------------
spine_with_payment AS (
  SELECT
    s.order_pk,
    s.OrderID, s.transaction_id, s.payment_option, s.snapshot_id, s.TotalPeriods, s.Period, s.OrderDate,
    s.order_data, s.lead_ref,
    isd.payment_amount, isd.principal, isd.principal_balance, isd.interest, isd.add_ons,
    c.third_party_id  AS charge_invoice_no,
    c.charge_rank     AS charge_rank,
    c.status          AS charge_status,
    c.amount          AS charge_amount,
    c.payment_method  AS charge_payment_method,
    c.service_provider AS charge_service_provider,
    COALESCE(c.payment_date, c.update_time) AS charge_payment_date,
    fu.due_date       AS followup_due_date,
    fro.old_order_id,
    fro.old_order_pk
  FROM period_spine s
  JOIN full_replacement_orders fro ON fro.new_order_id = s.OrderID
  LEFT JOIN transaction_snapshot_installment_details isd
    ON isd.snapshot_id = s.snapshot_id AND isd.period = s.Period
  LEFT JOIN charges c
    ON c.transaction_id = s.transaction_id
   AND c.installment_number = s.Period
  LEFT JOIN follow_ups fu
    ON fu.transaction_id = s.transaction_id
   AND fu.installment = s.Period
),

------------------------------------------------------------------
-- STEP 4: Channel split — semi-join instead of correlated EXISTS
------------------------------------------------------------------
old_order_invoices AS (
  SELECT DISTINCT order_pk, invoice_no
  FROM order_charges_candidates_only
),

channel_resolved AS (
  SELECT
    sp.*,
    (sp.charge_status = 'SUCCESSFUL') AS is_paid,
    (ooi.invoice_no IS NOT NULL) AS is_carried_over_from_old_order
  FROM spine_with_payment sp
  LEFT JOIN old_order_invoices ooi
    ON ooi.order_pk = sp.old_order_pk
   AND ooi.invoice_no = sp.charge_invoice_no
),

channel_final AS (
  SELECT
    *,
    CASE
      WHEN NOT is_paid THEN NULL
      -- FIX 2026-08-23 (docs/FINDINGS_RCB_ONETIME_CHANGE_ORDER_MISROUTED_RCL_20260803.md):
      -- a carried-over ONETIME order (FULL_PAYMENT/CREDIT_CARD_INSTALLMENT) must route to
      -- RCB-CreditShell, not RCL-Credit Shell. Only RABBIT_CARE_INSTALLMENT (and unknown/NULL,
      -- unchanged pending vendor confirmation) keeps the original RCL-Credit Shell behavior.
      WHEN is_carried_over_from_old_order AND payment_option IN ('FULL_PAYMENT','CREDIT_CARD_INSTALLMENT') THEN 'RCB-CreditShell'
      WHEN is_carried_over_from_old_order THEN 'RCL-Credit Shell'
      WHEN charge_payment_method = 'CASH' THEN 'RCL-Transfer-อื่นๆ'
      WHEN charge_payment_method = 'QR_CODE' AND charge_service_provider = 'RABBIT_LENDING' THEN 'RCL-Omise QR Prompt Pay-BAY'
      ELSE charge_service_provider
    END AS PaymentChannel_resolved,
    CASE
      WHEN NOT is_paid THEN NULL
      WHEN is_carried_over_from_old_order AND payment_option IN ('FULL_PAYMENT','CREDIT_CARD_INSTALLMENT') THEN 'RCB-CreditShell'
      WHEN is_carried_over_from_old_order THEN 'RCL-Credit Shell'
      WHEN charge_payment_method = 'CASH' THEN 'TRF Transfer'
      WHEN charge_payment_method = 'QR_CODE' THEN 'OME Omise QR Prompt Pay'
      ELSE charge_payment_method
    END AS PaymentMethod_resolved,
    CASE
      WHEN followup_due_date IS NOT NULL THEN DATE(followup_due_date)
      WHEN DATE_TRUNC(DATE(OrderDate), MONTH) < DATE_TRUNC(CURRENT_DATE(), MONTH) THEN CURRENT_DATE()
      ELSE DATE(OrderDate)
    END AS ExpectedDate_resolved
  FROM channel_resolved
),

------------------------------------------------------------------
-- STEP 5: Join order_items
-- CHANGED (CMI fix):
--   * join order_items on order_pk directly (correlated subquery removed)
--   * MOTOR_TYPE_COMPULSORY attaches ONLY to the Period-1 spine row
--     (first payment settles CMI in full; remaining periods belong
--     to the other insurance types)
--   * CMI rows get Period = 1, TotalPeriods = 1 overrides
--   * CMI amounts still come from order_items.gross_premium
--     (add_ons is only the deduction on the voluntary side, Period 1)
------------------------------------------------------------------
combined AS (
  SELECT
    'RCB' AS CompanyDB,
    cr.OrderID,
    oi.human_id AS OrderItem,
    CASE
      WHEN cr.is_paid THEN COALESCE(
        NULLIF(cr.charge_invoice_no, ''),
        CONCAT(CAST(cr.charge_rank AS STRING), '_', oi.human_id)
      )
    END AS raw_invoice_no,
    cr.OrderDate,
    CASE WHEN JSON_VALUE(cr.order_data, '$.policyHolder.isCompany') = 'true'
         THEN JSON_VALUE(cr.order_data, '$.policyHolder.companyTaxId')
         ELSE JSON_VALUE(cr.order_data, '$.idNumber') END AS InsuredID,
    JSON_VALUE(cr.order_data, '$.policyHolder.title') AS Title,
    COALESCE(JSON_VALUE(cr.order_data, '$.policyHolder.firstName'), JSON_VALUE(cr.order_data, '$.policyHolder.policyAddress.companyName')) AS FirstName,
    JSON_VALUE(cr.order_data, '$.policyHolder.lastName') AS LastName,
    oi.insurer AS InsurerCode,
    oi.product AS InsuranceGroup,
    oi.motor_item_type AS InsuranceType,
    oi.package AS InsuranceProduct,
    l.type AS PolicyType,
    oi.policy_start_date AS PolicyDate,
    oi.policy_number AS PolicyNo,
    JSON_VALUE(cr.order_data, '$.chassisNumber') AS ChassisNo,
    JSON_VALUE(cr.order_data, '$.carLicensePlate') AS LicensePlate,
    oi.net_premium AS GrossPremium,
    oi.stamp_duty AS StampDuty,
    oi.vat_amount AS VAT,
    oi.gross_premium AS TotalPremium_base,
    CASE WHEN oi.motor_item_type = 'MOTOR_TYPE_COMPULSORY' THEN 0
         ELSE ROUND((1/100) * tsps.wht_amount, 2) END AS WHT,
    CASE WHEN oi.motor_item_type = 'MOTOR_TYPE_COMPULSORY' THEN 0
         WHEN tsps.interest_amount IS NULL THEN 0
         ELSE ROUND(ROUND((1/100)*tsps.interest_amount,2) - ((ROUND((1/100)*tsps.interest_amount,2)*3.3)/103.3), 2)
    END AS TotalEIR,
    CASE WHEN oi.motor_item_type = 'MOTOR_TYPE_COMPULSORY' THEN 0
         WHEN tsps.interest_amount IS NULL THEN 0
         ELSE ROUND(((ROUND((1/100)*tsps.interest_amount,2)*3.3)/103.3), 2)
    END AS TotalSBT,
    CASE WHEN oi.motor_item_type = 'MOTOR_TYPE_COMPULSORY' THEN 0
         WHEN tsps.processing_fee_amount IS NULL THEN 0
         ELSE ROUND(ROUND((1/100)*tsps.processing_fee_amount,2) * (100/103.3), 2)
    END AS ProcessingFee,
    CASE WHEN oi.motor_item_type = 'MOTOR_TYPE_COMPULSORY' THEN 0
         WHEN tsps.processing_fee_amount IS NULL THEN 0
         ELSE ROUND(ROUND((1/100)*tsps.processing_fee_amount,2) - (ROUND((1/100)*tsps.processing_fee_amount,2)*(100/103.3)), 2)
    END AS ProcessingFeeVat,
    CASE WHEN oi.motor_item_type = 'MOTOR_TYPE_COMPULSORY' THEN 0
         WHEN tsps.shipment_fee IS NULL THEN 0
         ELSE ROUND(ROUND((1/100)*tsps.shipment_fee,2) * (100/107), 2)
    END AS ShippingFee,
    CASE WHEN oi.motor_item_type = 'MOTOR_TYPE_COMPULSORY' THEN 0
         WHEN tsps.shipment_fee IS NULL THEN 0
         ELSE ROUND(ROUND((1/100)*tsps.shipment_fee,2) - ROUND((1/100)*tsps.shipment_fee,2)*(100/107), 2)
    END AS ShippingFeeVat,
    CASE WHEN oi.motor_item_type = 'MOTOR_TYPE_COMPULSORY' THEN 0
         ELSE ROUND((1/100) * tsps.discount_amount, 2) END AS Discount,
    oi.submission_status AS SubmissionStatus,
    oi.approval_status AS ApprovalStatus,
    cr.is_paid,
    CASE
      WHEN oi.motor_item_type = 'MOTOR_TYPE_COMPULSORY' THEN oi.gross_premium
      ELSE
        CASE WHEN cr.Period = 1
             THEN ROUND(ROUND((1/100)*cr.payment_amount,2) - ROUND((1/100)*cr.add_ons,2), 2)
             ELSE ROUND((1/100)*cr.payment_amount, 2) END
    END AS ExpectedReceived,
    CASE
      WHEN NOT cr.is_paid THEN 0
      WHEN oi.motor_item_type = 'MOTOR_TYPE_COMPULSORY' THEN oi.gross_premium
      WHEN cr.Period = 1 THEN ROUND(ROUND((1/100)*cr.charge_amount,2) - ROUND((1/100)*cr.add_ons,2), 2)
      ELSE ROUND((1/100)*cr.charge_amount, 2)
    END AS ActualReceived,
    CASE WHEN oi.motor_item_type = 'MOTOR_TYPE_COMPULSORY' THEN 0
         WHEN tsps.interest_amount = 0 OR cr.TotalPeriods - 1 = 0 THEN 0
         WHEN cr.Period = 1 THEN 0
         ELSE ROUND((ROUND((1/100)*tsps.interest_amount,2) - ((ROUND((1/100)*tsps.interest_amount,2)*3.3)/103.3)) / (cr.TotalPeriods - 1), 2)
    END AS InterestThisPeriod,
    CASE WHEN oi.motor_item_type = 'MOTOR_TYPE_COMPULSORY' THEN 0
         WHEN (cr.TotalPeriods - 1) = 0 THEN 0
         WHEN cr.Period = 1 THEN ROUND((1/100)*cr.principal, 2)
         ELSE ROUND(ROUND((1/100)*cr.payment_amount,2) - (ROUND((1/100)*tsps.interest_amount,2) - ((ROUND((1/100)*tsps.interest_amount,2)*3.3)/103.3)) / (cr.TotalPeriods-1), 2)
    END AS PrincipleThisPeriod,
    CASE WHEN oi.motor_item_type = 'MOTOR_TYPE_COMPULSORY' THEN 0
         ELSE ROUND((1/100) * cr.interest, 2) END AS InterestEIRThisPeriod,
    CASE WHEN oi.motor_item_type = 'MOTOR_TYPE_COMPULSORY' THEN 0
         ELSE ROUND((1/100) * cr.principal, 2) END AS PrincipleEIRThisPeriod,
    CASE WHEN cr.is_paid THEN cr.charge_payment_date END AS PaymentDate,
    
    -- CMI override: always single-period item settled by the first payment
    CASE WHEN oi.motor_item_type = 'MOTOR_TYPE_COMPULSORY' THEN 1 ELSE cr.Period END AS Period,
    CASE WHEN oi.motor_item_type = 'MOTOR_TYPE_COMPULSORY' THEN 1 ELSE cr.TotalPeriods END AS TotalPeriods,
    CASE WHEN cr.is_paid THEN cr.PaymentMethod_resolved ELSE NULL END AS PaymentMethod,
    CASE WHEN cr.is_paid THEN cr.PaymentChannel_resolved ELSE NULL END AS PaymentChannel,
    cr.ExpectedDate_resolved AS ExpectedDate,
    cr.old_order_id AS RefOrder,
    ROUND(rf.amount * (100/107), 2) AS RefundAmountBeforeFee,
    rf.amount AS RefundAmountAfterFee,
    CASE WHEN JSON_VALUE(cr.order_data, '$.policyHolder.policyAddress.isBillingAddress') = 'true'
      THEN CONCAT(
        COALESCE(JSON_VALUE(cr.order_data, '$.policyHolder.policyAddress.fullName'), JSON_VALUE(cr.order_data, '$.policyHolder.policyAddress.companyName')), ', ',
        JSON_VALUE(cr.order_data, '$.policyHolder.policyAddress.address'), ', ',
        JSON_VALUE(cr.order_data, '$.policyHolder.policyAddress.subDistrict'), ', ',
        JSON_VALUE(cr.order_data, '$.policyHolder.policyAddress.district'), ', ',
        JSON_VALUE(cr.order_data, '$.policyHolder.policyAddress.province'), ', ',
        JSON_VALUE(cr.order_data, '$.policyHolder.policyAddress.postCode'))
      ELSE CONCAT(
        JSON_VALUE(cr.order_data, '$.policyHolder.billingAddress.fullName'), ', ',
        JSON_VALUE(cr.order_data, '$.policyHolder.billingAddress.address'), ', ',
        JSON_VALUE(cr.order_data, '$.policyHolder.billingAddress.subDistrict'), ', ',
        JSON_VALUE(cr.order_data, '$.policyHolder.billingAddress.district'), ', ',
        JSON_VALUE(cr.order_data, '$.policyHolder.billingAddress.province'), ', ',
        JSON_VALUE(cr.order_data, '$.policyHolder.billingAddress.postCode'))
    END AS BillingAddress,
    CURRENT_DATE() AS BatchRunDate
  FROM channel_final cr
  LEFT JOIN leads l ON CONCAT('leads/', l.id) = cr.lead_ref
  JOIN order_items oi
    ON oi.order_id = cr.order_pk
   AND oi.is_cancelled IS NOT TRUE
   -- CMI attaches to the Period-1 row only; other item types keep the full spine
   AND (oi.motor_item_type != 'MOTOR_TYPE_COMPULSORY' OR oi.motor_item_type IS NULL OR cr.Period = 1)  -- A2 fix 2026-07-24
  LEFT JOIN transaction_snapshot_price_summaries tsps ON tsps.snapshot_id = cr.snapshot_id
  LEFT JOIN refunds rf ON rf.transaction_id = cr.transaction_id
),

------------------------------------------------------------------
-- STEP 6: Final shaping to 56-column interface format
------------------------------------------------------------------
final AS (
  SELECT
    CompanyDB, OrderID, OrderItem,
    CASE WHEN is_paid THEN raw_invoice_no ELSE '' END AS InvoiceNo,
    CAST(FORMAT_DATE('%d%m%Y', OrderDate) AS STRING) AS OrderDate,
    CASE WHEN InsuredID = '' OR InsuredID IS NULL THEN '-' ELSE InsuredID END AS InsuredID,
    CASE Title WHEN 'KHUN' THEN 'คุณ' WHEN 'MISS' THEN 'นางสาว'
               WHEN 'MR' THEN 'นาย' WHEN 'MRS' THEN 'นาง' ELSE '' END AS Title,
    FirstName, LastName,
    TRIM(InsurerCode, 'insurer/') AS InsurerCode,
    CASE
      WHEN InsuranceGroup = 'products/car-insurance' THEN 'Motor'
      WHEN InsuranceGroup = 'products/health-insurance' THEN 'Health'
      WHEN InsuranceGroup = 'products/travel-insurance' THEN 'TA'
      ELSE InsuranceGroup
    END AS InsuranceGroup,
    CASE
      WHEN (InsuranceType IS NULL OR TRIM(InsuranceType) = '')
        AND InsuranceGroup = 'products/health-insurance' THEN 'Health'
      WHEN (InsuranceType IS NULL OR TRIM(InsuranceType) = '')
        AND InsuranceGroup = 'products/travel-insurance' THEN 'TA'
      ELSE InsuranceType
    END AS InsuranceType,
    CASE
      WHEN InsuranceGroup = 'products/car-insurance' THEN 'Motor'
      WHEN InsuranceGroup = 'products/health-insurance' THEN 'Health'
      WHEN InsuranceGroup = 'products/travel-insurance' THEN 'TA'
      ELSE InsuranceProduct
    END AS InsuranceProduct,
    'Insurance' AS ProductType,
    CASE WHEN PolicyType = 'LEAD_TYPE_RENEWAL' THEN 'R' ELSE 'N' END AS PolicyType,
    'N' AS Endorse,
    CAST(FORMAT_DATE('%d%m%Y', PolicyDate) AS STRING) AS PolicyDate,
    IFNULL(PolicyNo, '') AS PolicyNo,
    NULL AS EndorsementNo,
    ChassisNo, LicensePlate, GrossPremium, StampDuty, VAT,
    ROUND(TotalPremium_base, 2) AS TotalPremium,
    WHT, TotalEIR, TotalSBT, ProcessingFee, ProcessingFeeVat, ShippingFee, ShippingFeeVat,
    ROUND(TotalPremium_base + WHT + TotalEIR + TotalSBT + ProcessingFee + ProcessingFeeVat + ShippingFee + ShippingFeeVat, 2) AS TotalAmount,
    Discount,
    CASE WHEN is_paid THEN 'paid' ELSE 'pending' END AS TransactionStatus,
    CASE SubmissionStatus
      WHEN 'ITEM_SUBMISSION_STATUS_READY_TO_SUBMIT' THEN 'PENDING'
      WHEN 'ITEM_SUBMISSION_STATUS_PRESUBMITTED' THEN 'PRE-SUBMITTED'
      WHEN 'ITEM_SUBMISSION_STATUS_SUBMITTED' THEN 'SUBMITTED'
      WHEN 'ITEM_SUBMISSION_STATUS_PENDING' THEN 'PENDING'
      ELSE SubmissionStatus END AS SubmissionStatus,
    CASE ApprovalStatus
      WHEN 'ITEM_APPROVAL_STATUS_APPROVED' THEN 'APPROVED'
      WHEN 'ITEM_APPROVAL_STATUS_REJECTED' THEN 'REJECTED'
      WHEN 'ITEM_APPROVAL_STATUS_PENDING' THEN 'PENDING'
      WHEN 'ITEM_APPROVAL_STATUS_POLICY_UPLOADED' THEN 'POLICY UPLOADED'
      ELSE ApprovalStatus END AS ApprovalStatus,
    CASE WHEN is_paid THEN 'fully paid' ELSE 'Not fully paid' END AS PaymentStatus,
    ExpectedReceived, ActualReceived, InterestThisPeriod, PrincipleThisPeriod,
    InterestEIRThisPeriod, PrincipleEIRThisPeriod,
    CASE WHEN PaymentDate IS NULL THEN '' ELSE CAST(FORMAT_DATE('%d%m%Y', DATE(PaymentDate)) AS STRING) END AS PaymentDate,
    Period, TotalPeriods,
    -- CMI: TotalPeriods = 1, Period = 1 → (1-1) = 0 pending automatically
    ROUND(((TotalPremium_base + TotalEIR + TotalSBT + ProcessingFee + ProcessingFeeVat + ShippingFee + ShippingFeeVat - Discount) / TotalPeriods) * (TotalPeriods - Period), 2) AS PendingPayment,
    IFNULL(PaymentMethod, '') AS PaymentMethod,
    IFNULL(PaymentChannel, '') AS PaymentChannel,
    CAST(FORMAT_DATE('%d%m%Y', ExpectedDate) AS STRING) AS ExpectedDate,
    RefOrder,
    IFNULL(CAST(RefundAmountBeforeFee AS STRING), '') AS RefundAmountBeforeFee,
    IFNULL(CAST(RefundAmountAfterFee AS STRING), '') AS RefundAmountAfterFee,
    BillingAddress,
    CAST(FORMAT_DATE('%d%m%Y', BatchRunDate) AS STRING) AS BatchRunDate
  FROM combined
),

------------------------------------------------------------------
-- STEP 7 (CHANGED): order-level qualification
-- If ANY row of the order qualifies (installment / RCL / Credit
-- Shell), pull ALL items of that order — including the CMI row
-- that now has TotalPeriods = 1 and would otherwise fall out
------------------------------------------------------------------
qualifying_orders AS (
  SELECT DISTINCT OrderID
  FROM final
  WHERE (TotalPeriods > 1
     OR PaymentChannel LIKE '%RCL%'
     OR PaymentChannel LIKE '%Credit Shell%'
     -- FIX 2026-08-23: 'RCB-CreditShell' (no space) is a new valid label from the
     -- FULL_PAYMENT/CREDIT_CARD_INSTALLMENT routing fix above and must also qualify its
     -- order, or those rows would be silently dropped from this view's output entirely.
     OR PaymentChannel LIKE '%CreditShell%')
),

qualified AS (
  SELECT DISTINCT f.*
  FROM final f
  JOIN qualifying_orders q ON q.OrderID = f.OrderID
),

-- ROOT FIX 2026-09-01: multiple successful payments for one period remain separate
-- business rows, but the schedule expectation belongs to the first payment row only.
expected_received_ranked AS (
  SELECT
    qualified.*,
    ROW_NUMBER() OVER (
      PARTITION BY qualified.OrderItem, qualified.Period
      ORDER BY
        CASE WHEN LOWER(qualified.TransactionStatus) = 'paid' THEN 0 ELSE 1 END,
        SAFE.PARSE_DATE('%d%m%Y', NULLIF(qualified.PaymentDate, '')) NULLS LAST,
        NULLIF(qualified.InvoiceNo, '') NULLS LAST,
        FARM_FINGERPRINT(TO_JSON_STRING(qualified))
    ) AS duplicate_period_seq
  FROM qualified
),

expected_received_fixed AS (
  SELECT
    * EXCEPT (duplicate_period_seq) REPLACE (
      CASE
        WHEN duplicate_period_seq = 1 THEN ExpectedReceived
        ELSE 0
      END AS ExpectedReceived
    )
  FROM expected_received_ranked
)

SELECT *
FROM expected_received_fixed
ORDER BY OrderItem, Period;

CREATE TEMP TABLE before_rcl_wrapper AS
WITH filtered AS (
  SELECT
    src.*
  FROM
    before_producer AS src
  WHERE
    -- Required to preserve the behavior of the original NOT IN condition.
    -- Upstream currently contains OrderItem NULL rows.
    src.OrderItem IS NOT NULL

    AND NOT EXISTS (
      SELECT
        1
      FROM
        `pacific-plating-282708.sap_integration_v2.SAP_LIVE_FULL` AS sap
      WHERE
        sap.U_OrderItem = src.OrderItem
    )

    AND EXISTS (
      SELECT
        1
      FROM
        `pacific-plating-282708.careos.cancelled_change_orders` AS change_order
      WHERE
        change_order.current_human_id = src.OrderID
    )

    AND (
      src.OrderDate LIKE '%2025%'
      OR src.OrderDate LIKE '%2026%'
    )

    AND src.OrderID NOT IN (
      'L79128866', -- incorrect insurer id
      'L79217528', -- incorrect insurer id
      'L79291428'  -- incorrect insurer id
    )

    -- Malformed rows wait until the upstream transaction data is complete.
    AND src.Period IS NOT NULL
    AND src.TotalPeriods IS NOT NULL
    AND src.Period BETWEEN 1 AND src.TotalPeriods
),

ranked AS (
  SELECT
    filtered.*,

    ROW_NUMBER() OVER (
      PARTITION BY
        filtered.OrderItem,
        filtered.Period
      ORDER BY
        -- A successful payment row is the expected schedule row.
        CASE
          WHEN LOWER(filtered.TransactionStatus) = 'paid' THEN 0
          ELSE 1
        END,

        -- Earlier payment keeps ExpectedReceived.
        SAFE.PARSE_DATE(
          '%d%m%Y',
          NULLIF(filtered.PaymentDate, '')
        ) NULLS LAST,

        NULLIF(filtered.InvoiceNo, '') NULLS LAST,

        -- Stable tie-breaker without removing valid additional payments.
        FARM_FINGERPRINT(TO_JSON_STRING(filtered))
    ) AS duplicate_period_seq
  FROM
    filtered
),

fixed AS (
  SELECT
    * EXCEPT (duplicate_period_seq)

    REPLACE (
      -- Period duplication is allowed, but ExpectedReceived must not repeat.
      CASE
        WHEN duplicate_period_seq = 1
          THEN ExpectedReceived
        ELSE 0
      END AS ExpectedReceived,

      -- Pending transactions have no successful charge information.
      CASE
        WHEN LOWER(TransactionStatus) = 'pending'
          THEN ''
        ELSE IFNULL(PaymentMethod, '')
      END AS PaymentMethod,

      CASE
        WHEN LOWER(TransactionStatus) = 'pending'
          THEN ''
        ELSE IFNULL(PaymentChannel, '')
      END AS PaymentChannel
    )
  FROM
    ranked
)

SELECT DISTINCT
  *
FROM
  fixed
ORDER BY
  OrderItem,
  Period;

CREATE TEMP TABLE before_rcb_wrapper AS
-- Full source-only legacy fix proposal for:
--   pacific-plating-282708.sap_view.RCL_Motor_process_4_creditshell
--
-- Root fixes:
--   1. Split Motor and NonMotor routing after the upstream payload is normalized.
--      Motor keeps its existing channel. Health/TA successful QR payments use
--      RCL-Omise QR Prompt Pay-Health, including later CreditShell installments.
--      The carried-over first installment keeps RCL-Credit Shell because its
--      PaymentMethod is RCL-Credit Shell, not OME Omise QR Prompt Pay.
--   2. A paid PaymentDate earlier than the current month is posted as the first
--      day of the current month. A current-month paid date is preserved.
--   3. Pending InvoiceNo/payment routing remains blank.
--   4. Preserve legitimate repeated-period payment rows and keep ExpectedReceived
--      only on the first row for an OrderItem/Period.
--
-- SELECT only: this file does not replace or deploy the live legacy view.

WITH
  filtered AS (
    SELECT src.*
    FROM before_producer AS src
    WHERE src.OrderItem IS NOT NULL
      AND NOT EXISTS (
        SELECT 1
        FROM `pacific-plating-282708.sap_integration_v2.SAP_LIVE_FULL` AS sap
        WHERE sap.U_OrderItem = src.OrderItem
      )
      AND EXISTS (
        SELECT 1
        FROM `pacific-plating-282708.careos.cancelled_change_orders` AS change_order
        WHERE change_order.current_human_id = src.OrderID
      )
      AND (
        src.OrderDate LIKE '%2025%'
        OR src.OrderDate LIKE '%2026%'
      )
      AND src.OrderID NOT IN (
        'L79128866',
        'L79217528',
        'L79291428'
      )
      AND src.Period IS NOT NULL
      AND src.TotalPeriods IS NOT NULL
      AND src.Period BETWEEN 1 AND src.TotalPeriods
  ),

  ranked AS (
    SELECT
      filtered.*,
      ROW_NUMBER() OVER (
        PARTITION BY filtered.OrderItem, filtered.Period
        ORDER BY
          CASE WHEN LOWER(filtered.TransactionStatus) = 'paid' THEN 0 ELSE 1 END,
          SAFE.PARSE_DATE('%d%m%Y', NULLIF(filtered.PaymentDate, '')) NULLS LAST,
          NULLIF(filtered.InvoiceNo, '') NULLS LAST,
          FARM_FINGERPRINT(TO_JSON_STRING(filtered))
      ) AS duplicate_period_seq
    FROM filtered
  ),

  fixed_common AS (
    SELECT
      * EXCEPT (duplicate_period_seq)
      REPLACE (
        CASE
          WHEN duplicate_period_seq = 1 THEN ExpectedReceived
          ELSE 0
        END AS ExpectedReceived,
        CASE
          WHEN LOWER(TransactionStatus) = 'pending' THEN ''
          ELSE IFNULL(PaymentMethod, '')
        END AS PaymentMethod,
        CASE
          WHEN LOWER(TransactionStatus) = 'pending' THEN ''
          ELSE IFNULL(PaymentChannel, '')
        END AS PaymentChannel
      )
    FROM ranked
  ),

  motor_rows AS (
    SELECT *
    FROM fixed_common
    WHERE InsuranceGroup = 'Motor'
  ),

  nonmotor_rows AS (
    SELECT
      * REPLACE (
        CASE
          WHEN LOWER(TransactionStatus) = 'paid'
            AND PaymentMethod = 'OME Omise QR Prompt Pay'
          THEN 'RCL-Omise QR Prompt Pay-Health'
          ELSE PaymentChannel
        END AS PaymentChannel
      )
    FROM fixed_common
    WHERE InsuranceGroup IN ('Health', 'TA')
  ),

  unclassified_rows AS (
    -- Preserve unknown legacy product labels without guessing a payment route.
    SELECT *
    FROM fixed_common
    WHERE InsuranceGroup IS NULL
       OR InsuranceGroup NOT IN ('Motor', 'Health', 'TA')
  ),

  routed AS (
    SELECT * FROM motor_rows
    UNION ALL
    SELECT * FROM nonmotor_rows
    UNION ALL
    SELECT * FROM unclassified_rows
  ),

  payment_date_fixed AS (
    SELECT
      * REPLACE (
        CASE
          WHEN LOWER(TransactionStatus) = 'pending' THEN ''
          WHEN SAFE.PARSE_DATE('%d%m%Y', NULLIF(PaymentDate, ''))
            < DATE_TRUNC(CURRENT_DATE(), MONTH)
          THEN FORMAT_DATE('%d%m%Y', DATE_TRUNC(CURRENT_DATE(), MONTH))
          ELSE IFNULL(PaymentDate, '')
        END AS PaymentDate
      )
    FROM routed
  )

SELECT DISTINCT *
FROM payment_date_fixed
ORDER BY OrderItem, Period;

CREATE TEMP TABLE after_producer AS
-- SOURCE-ONLY LEGACY PROPOSAL — DO NOT DEPLOY
-- Object: pacific-plating-282708.sap_integration_v2.RCL 04_new order credit shell
-- Live definition last modified: 2026-08-23 14:47:19 +00:00
-- Captured live query SHA256: 1266758867acc03c48c11fa2486b680eddf32bda7b4e0dd4fbcd0de66a032dba
-- Scope: latest-snapshot selection, complete-snapshot hold, duplicate-period ExpectedReceived,
-- item-master completeness, and period-grain payment identity.
-- Repository policy forbids DDL in sap_integration_v2.
-- BASELINE CAPTURE 2026-07-24 -- pulled verbatim from live BigQuery view definition
-- Object: sap_integration_v2.`RCL 04_new order credit shell new tunning`
-- Boat: fix the same A2 NULL-safe bug here, leave everything else as-is (not
-- confirmed live/nightly production like the other 4 objects, but fixing anyway).
-- See docs/knowledge/30_SAP_CHANGELOG.md (2026-07-24 entry) for the bug.
--
-- FIX 2026-08-23 (SOURCE ONLY, NOT DEPLOYED): re-pulled live 2026-08-23, confirmed byte-for-byte
-- identical to this file after that point, so drift-free as of this fix. Corrects
-- docs/FINDINGS_RCB_ONETIME_CHANGE_ORDER_MISROUTED_RCL_20260803.md's confirmed root cause: a
-- carried-over FULL_PAYMENT/CREDIT_CARD_INSTALLMENT (ONETIME) order was unconditionally labelled
-- 'RCL-Credit Shell' purely because `is_carried_over_from_old_order` was true, with no check of
-- the order's own payment_option. Live-verified trigger case: L80569331-M1 (created 2026-08-13,
-- payment_option=FULL_PAYMENT), reported by Mo 2026-08-23. Three changes, all additive/minimal:
-- (1) carry `payment_option` through transactions -> new_order_txn -> period_spine ->
--     spine_with_payment (new column, no existing column touched);
-- (2) in `channel_final`, route carried-over FULL_PAYMENT/CREDIT_CARD_INSTALLMENT to
--     'RCB-CreditShell' (matches the label already used by the reviewed V3 canonical router,
--     sql/ddl/050_v3_onetime_payload_source.sql); RABBIT_CARE_INSTALLMENT and unknown/NULL
--     payment_option keep the exact prior 'RCL-Credit Shell' behavior unchanged -- no new "hold"
--     state is introduced because this view has no quarantine mechanism to hold into, and
--     changing unproven cases risked a new failure mode with no live evidence to justify it;
-- (3) in `qualifying_orders`, added `PaymentChannel LIKE '%CreditShell%'` alongside the existing
--     '%Credit Shell%'/'%RCL%' checks -- WITHOUT this, rows newly relabelled 'RCB-CreditShell'
--     (no space, TotalPeriods=1) would fail every existing qualification condition and be
--     silently dropped from this view's entire output. Caught by manually tracing the label
--     through STEP 7 before treating the CASE-block change alone as sufficient.
-- Deliberately NOT changed: the MOTOR_TYPE_COMPULSORY path, any non-carried-over routing, and the
-- unproven RABBIT_CARE_INSTALLMENT/unknown-payment_option carried-over case.
-- No deploy performed. Pending Class-A review before Codex applies via CREATE OR REPLACE VIEW.
--
-- FIX 2026-09-07 (SOURCE ONLY, NOT DEPLOYED):
-- (1) remove item-less Period-1 rows that carried payment data but NULL insurance/policy fields
--     and zero premiums because the legacy LEFT JOIN explicitly allowed Period 1 through;
-- (2) source PaymentDate from the successful charge for the same installment period
--     (`payment_date`, falling back to `update_time`) instead of overwriting every historical
--     period with one current-month/SAP batch date;
-- (3) normalize Health/Travel group, type, and product to the existing SAP labels.
-- (4) use the established `<charge_rank>_<OrderItem>` legacy fallback when a SUCCESSFUL charge
--     has no third_party_id, avoiding blank/reused InvoiceNo values across payment rows.
-- (5) collapse exact full-row join duplicates before ranking repeated-period payments; distinct
--     payment rows for the same period remain and only the later rows receive ExpectedReceived = 0.
-- InvoiceNo, PaymentMethod, and PaymentChannel remain sourced from the successful charge joined
-- on `(transaction_id, installment_number = Period)`. Equal method/channel values remain valid
-- when the raw charges genuinely used the same route.

WITH
------------------------------------------------------------------
-- Base tables — only select needed columns, filter by date early
------------------------------------------------------------------
orders_scoped AS (
  SELECT id, human_id, payment, create_time, lead, data
  FROM `pacific-plating-282708.careos.careos_orders`
  WHERE create_time >= '2025-01-01'   -- <<< CONFIRM: adjust if credit shell cases go further back
),

order_items AS (
  SELECT order_id, human_id, is_cancelled, cancel_time, insurer, product,
         motor_item_type, package, policy_start_date, policy_number,
         net_premium, stamp_duty, vat_amount, gross_premium,
         submission_status, approval_status
  FROM `pacific-plating-282708.careos.careos_order_items`
),

leads AS (SELECT id, type, reference FROM `pacific-plating-282708.careos.careos_leads`),

transactions AS (SELECT id, payment_option FROM `pacific-plating-282708.careos.carepay_transactions`),

transaction_snapshots AS (
  SELECT id, transaction_id, number_of_installment
  FROM `pacific-plating-282708.careos.carepay_transaction_snapshots`
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY transaction_id
    ORDER BY update_time DESC, id DESC
  ) = 1
),

transaction_snapshot_installment_details AS (
  SELECT id, snapshot_id, period, payment_amount, principal,
         principal_balance, interest, add_ons
  FROM `pacific-plating-282708.careos.carepay_transaction_snapshot_installment_details`
),

transaction_snapshot_price_summaries AS (
  SELECT snapshot_id, wht_amount, interest_amount, processing_fee_amount,
         shipment_fee, discount_amount
  FROM `pacific-plating-282708.careos.carepay_transaction_snapshot_price_summaries`
),

charges AS (
  SELECT id, transaction_id, installment_number, third_party_id, status,
         amount, payment_method, service_provider, payment_date, update_time,
         ROW_NUMBER() OVER (
           PARTITION BY transaction_id
           ORDER BY create_time, id
         ) AS charge_rank
  FROM `pacific-plating-282708.careos.carepay_charges`
  WHERE status = 'SUCCESSFUL'
),

refunds AS (SELECT transaction_id, amount FROM `pacific-plating-282708.careos.carepay_refunds`),

follow_ups AS (SELECT transaction_id, installment, due_date FROM `pacific-plating-282708.careos.carepay_follow_ups`),

------------------------------------------------------------------
-- STEP 0: each order's own successful charges + invoice_no
------------------------------------------------------------------
order_charges AS (
  SELECT
    o.id AS order_pk,
    o.human_id AS order_id,
    o.create_time AS order_create_time,
    c.third_party_id AS invoice_no
  FROM orders_scoped o
  JOIN transactions t ON CONCAT('transactions/', t.id) = o.payment
  JOIN charges c ON c.transaction_id = t.id
  WHERE c.third_party_id IS NOT NULL
),

------------------------------------------------------------------
-- Pre-filter: invoice_no shared by >1 order before self-join
------------------------------------------------------------------
shared_invoice_candidates AS (
  SELECT invoice_no
  FROM order_charges
  GROUP BY invoice_no
  HAVING COUNT(DISTINCT order_pk) > 1
),

order_charges_candidates_only AS (
  SELECT oc.*
  FROM order_charges oc
  JOIN shared_invoice_candidates sic ON sic.invoice_no = oc.invoice_no
),

------------------------------------------------------------------
-- STEP 1: Credit Shell link
------------------------------------------------------------------
order_item_counts AS (
  SELECT
    order_id,
    COUNTIF(is_cancelled IS NOT TRUE) AS active_remaining,
    COUNT(*) AS total_items
  FROM order_items
  GROUP BY order_id
),

credit_shell_link AS (
  SELECT DISTINCT
    new_oc.order_id   AS new_order_id,
    new_oc.order_pk   AS new_order_pk,
    old_oc.order_id   AS old_order_id,
    old_oc.order_pk   AS old_order_pk,
    IFNULL(oic.active_remaining, 0) AS old_active_remaining,
    IFNULL(oic.total_items, 0)      AS old_total_items
  FROM order_charges_candidates_only new_oc
  JOIN order_charges_candidates_only old_oc
    ON old_oc.invoice_no = new_oc.invoice_no
   AND old_oc.order_pk != new_oc.order_pk
   AND old_oc.order_create_time < new_oc.order_create_time
  LEFT JOIN order_item_counts oic
    ON oic.order_id = old_oc.order_pk
),

credit_shell_classified AS (
  SELECT *,
    CASE
      WHEN old_active_remaining = 0 THEN 'FULL_REPLACEMENT'
      WHEN old_active_remaining > 0 AND old_active_remaining < old_total_items THEN 'PARTIAL_REPLACEMENT'
      ELSE 'REVIEW_UNKNOWN'
    END AS credit_shell_case_type
  FROM credit_shell_link
),

full_replacement_orders AS (
  SELECT new_order_id, old_order_id, old_order_pk
  FROM credit_shell_classified
  WHERE credit_shell_case_type = 'FULL_REPLACEMENT'
),

------------------------------------------------------------------
-- STEP 2: Period spine
-- CHANGED: carry order_pk through the spine (used later to join
-- order_items directly — replaces the old correlated subquery)
------------------------------------------------------------------
new_order_txn AS (
  SELECT
    o.id            AS order_pk,
    o.human_id      AS OrderID,
    o.data          AS order_data,
    o.lead          AS lead_ref,
    o.create_time   AS OrderDate,
    t.id            AS transaction_id,
    t.payment_option AS payment_option,
    ts.id           AS snapshot_id,
    ts.number_of_installment AS TotalPeriods
  FROM orders_scoped o
  JOIN full_replacement_orders fro ON fro.new_order_id = o.human_id
  LEFT JOIN transactions t ON CONCAT('transactions/', t.id) = o.payment
  -- ROOT FIX 2026-09-01: wait for the latest complete schedule snapshot instead of
  -- emitting a temporary NULL/invalid period shape or fanning out all snapshot versions.
  JOIN transaction_snapshots ts
    ON ts.transaction_id = t.id
   AND ts.number_of_installment >= 1
),

period_spine AS (
  SELECT
    n.order_pk,
    n.OrderID, n.transaction_id, n.payment_option, n.snapshot_id, n.TotalPeriods, n.OrderDate,
    n.order_data, n.lead_ref,
    period_num AS Period
  FROM new_order_txn n,
  UNNEST(GENERATE_ARRAY(1, GREATEST(IFNULL(n.TotalPeriods, 1), 1))) AS period_num
),

------------------------------------------------------------------
-- STEP 3: Attach schedule + payment + follow_up due_date per period
------------------------------------------------------------------
spine_with_payment AS (
  SELECT
    s.order_pk,
    s.OrderID, s.transaction_id, s.payment_option, s.snapshot_id, s.TotalPeriods, s.Period, s.OrderDate,
    s.order_data, s.lead_ref,
    isd.payment_amount, isd.principal, isd.principal_balance, isd.interest, isd.add_ons,
    c.third_party_id  AS charge_invoice_no,
    c.charge_rank     AS charge_rank,
    c.status          AS charge_status,
    c.amount          AS charge_amount,
    c.payment_method  AS charge_payment_method,
    c.service_provider AS charge_service_provider,
    COALESCE(c.payment_date, c.update_time) AS charge_payment_date,
    fu.due_date       AS followup_due_date,
    fro.old_order_id,
    fro.old_order_pk
  FROM period_spine s
  JOIN full_replacement_orders fro ON fro.new_order_id = s.OrderID
  LEFT JOIN transaction_snapshot_installment_details isd
    ON isd.snapshot_id = s.snapshot_id AND isd.period = s.Period
  LEFT JOIN charges c
    ON c.transaction_id = s.transaction_id
   AND c.installment_number = s.Period
  LEFT JOIN follow_ups fu
    ON fu.transaction_id = s.transaction_id
   AND fu.installment = s.Period
),

------------------------------------------------------------------
-- STEP 4: Channel split — semi-join instead of correlated EXISTS
------------------------------------------------------------------
old_order_invoices AS (
  SELECT DISTINCT order_pk, invoice_no
  FROM order_charges_candidates_only
),

channel_resolved AS (
  SELECT
    sp.*,
    (sp.charge_status = 'SUCCESSFUL') AS is_paid,
    (ooi.invoice_no IS NOT NULL) AS is_carried_over_from_old_order
  FROM spine_with_payment sp
  LEFT JOIN old_order_invoices ooi
    ON ooi.order_pk = sp.old_order_pk
   AND ooi.invoice_no = sp.charge_invoice_no
),

channel_final AS (
  SELECT
    *,
    CASE
      WHEN NOT is_paid THEN NULL
      -- FIX 2026-08-23 (docs/FINDINGS_RCB_ONETIME_CHANGE_ORDER_MISROUTED_RCL_20260803.md):
      -- a carried-over ONETIME order (FULL_PAYMENT/CREDIT_CARD_INSTALLMENT) must route to
      -- RCB-CreditShell, not RCL-Credit Shell. Only RABBIT_CARE_INSTALLMENT (and unknown/NULL,
      -- unchanged pending vendor confirmation) keeps the original RCL-Credit Shell behavior.
      WHEN is_carried_over_from_old_order AND payment_option IN ('FULL_PAYMENT','CREDIT_CARD_INSTALLMENT') THEN 'RCB-CreditShell'
      WHEN is_carried_over_from_old_order THEN 'RCL-Credit Shell'
      WHEN charge_payment_method = 'CASH' THEN 'RCL-Transfer-อื่นๆ'
      WHEN charge_payment_method = 'QR_CODE' AND charge_service_provider = 'RABBIT_LENDING' THEN 'RCL-Omise QR Prompt Pay-BAY'
      ELSE charge_service_provider
    END AS PaymentChannel_resolved,
    CASE
      WHEN NOT is_paid THEN NULL
      WHEN is_carried_over_from_old_order AND payment_option IN ('FULL_PAYMENT','CREDIT_CARD_INSTALLMENT') THEN 'RCB-CreditShell'
      WHEN is_carried_over_from_old_order THEN 'RCL-Credit Shell'
      WHEN charge_payment_method = 'CASH' THEN 'TRF Transfer'
      WHEN charge_payment_method = 'QR_CODE' THEN 'OME Omise QR Prompt Pay'
      ELSE charge_payment_method
    END AS PaymentMethod_resolved,
    CASE
      WHEN followup_due_date IS NOT NULL THEN DATE(followup_due_date)
      WHEN DATE_TRUNC(DATE(OrderDate), MONTH) < DATE_TRUNC(CURRENT_DATE(), MONTH) THEN CURRENT_DATE()
      ELSE DATE(OrderDate)
    END AS ExpectedDate_resolved
  FROM channel_resolved
),

------------------------------------------------------------------
-- STEP 5: Join order_items
-- CHANGED (CMI fix):
--   * join order_items on order_pk directly (correlated subquery removed)
--   * MOTOR_TYPE_COMPULSORY attaches ONLY to the Period-1 spine row
--     (first payment settles CMI in full; remaining periods belong
--     to the other insurance types)
--   * CMI rows get Period = 1, TotalPeriods = 1 overrides
--   * CMI amounts still come from order_items.gross_premium
--     (add_ons is only the deduction on the voluntary side, Period 1)
------------------------------------------------------------------
combined AS (
  SELECT
    'RCB' AS CompanyDB,
    cr.OrderID,
    oi.human_id AS OrderItem,
    CASE
      WHEN cr.is_paid THEN COALESCE(
        NULLIF(cr.charge_invoice_no, ''),
        CONCAT(CAST(cr.charge_rank AS STRING), '_', oi.human_id)
      )
    END AS raw_invoice_no,
    cr.OrderDate,
    CASE WHEN JSON_VALUE(cr.order_data, '$.policyHolder.isCompany') = 'true'
         THEN JSON_VALUE(cr.order_data, '$.policyHolder.companyTaxId')
         ELSE JSON_VALUE(cr.order_data, '$.idNumber') END AS InsuredID,
    JSON_VALUE(cr.order_data, '$.policyHolder.title') AS Title,
    COALESCE(JSON_VALUE(cr.order_data, '$.policyHolder.firstName'), JSON_VALUE(cr.order_data, '$.policyHolder.policyAddress.companyName')) AS FirstName,
    JSON_VALUE(cr.order_data, '$.policyHolder.lastName') AS LastName,
    oi.insurer AS InsurerCode,
    oi.product AS InsuranceGroup,
    oi.motor_item_type AS InsuranceType,
    oi.package AS InsuranceProduct,
    l.type AS PolicyType,
    oi.policy_start_date AS PolicyDate,
    oi.policy_number AS PolicyNo,
    JSON_VALUE(cr.order_data, '$.chassisNumber') AS ChassisNo,
    JSON_VALUE(cr.order_data, '$.carLicensePlate') AS LicensePlate,
    oi.net_premium AS GrossPremium,
    oi.stamp_duty AS StampDuty,
    oi.vat_amount AS VAT,
    oi.gross_premium AS TotalPremium_base,
    CASE WHEN oi.motor_item_type = 'MOTOR_TYPE_COMPULSORY' THEN 0
         ELSE ROUND((1/100) * tsps.wht_amount, 2) END AS WHT,
    CASE WHEN oi.motor_item_type = 'MOTOR_TYPE_COMPULSORY' THEN 0
         WHEN tsps.interest_amount IS NULL THEN 0
         ELSE ROUND(ROUND((1/100)*tsps.interest_amount,2) - ((ROUND((1/100)*tsps.interest_amount,2)*3.3)/103.3), 2)
    END AS TotalEIR,
    CASE WHEN oi.motor_item_type = 'MOTOR_TYPE_COMPULSORY' THEN 0
         WHEN tsps.interest_amount IS NULL THEN 0
         ELSE ROUND(((ROUND((1/100)*tsps.interest_amount,2)*3.3)/103.3), 2)
    END AS TotalSBT,
    CASE WHEN oi.motor_item_type = 'MOTOR_TYPE_COMPULSORY' THEN 0
         WHEN tsps.processing_fee_amount IS NULL THEN 0
         ELSE ROUND(ROUND((1/100)*tsps.processing_fee_amount,2) * (100/103.3), 2)
    END AS ProcessingFee,
    CASE WHEN oi.motor_item_type = 'MOTOR_TYPE_COMPULSORY' THEN 0
         WHEN tsps.processing_fee_amount IS NULL THEN 0
         ELSE ROUND(ROUND((1/100)*tsps.processing_fee_amount,2) - (ROUND((1/100)*tsps.processing_fee_amount,2)*(100/103.3)), 2)
    END AS ProcessingFeeVat,
    CASE WHEN oi.motor_item_type = 'MOTOR_TYPE_COMPULSORY' THEN 0
         WHEN tsps.shipment_fee IS NULL THEN 0
         ELSE ROUND(ROUND((1/100)*tsps.shipment_fee,2) * (100/107), 2)
    END AS ShippingFee,
    CASE WHEN oi.motor_item_type = 'MOTOR_TYPE_COMPULSORY' THEN 0
         WHEN tsps.shipment_fee IS NULL THEN 0
         ELSE ROUND(ROUND((1/100)*tsps.shipment_fee,2) - ROUND((1/100)*tsps.shipment_fee,2)*(100/107), 2)
    END AS ShippingFeeVat,
    CASE WHEN oi.motor_item_type = 'MOTOR_TYPE_COMPULSORY' THEN 0
         ELSE ROUND((1/100) * tsps.discount_amount, 2) END AS Discount,
    oi.submission_status AS SubmissionStatus,
    oi.approval_status AS ApprovalStatus,
    cr.is_paid,
    CASE
      WHEN oi.motor_item_type = 'MOTOR_TYPE_COMPULSORY' THEN oi.gross_premium
      ELSE
        CASE WHEN cr.Period = 1
             THEN ROUND(ROUND((1/100)*cr.payment_amount,2) - ROUND((1/100)*cr.add_ons,2), 2)
             ELSE ROUND((1/100)*cr.payment_amount, 2) END
    END AS ExpectedReceived,
    CASE
      WHEN NOT cr.is_paid THEN 0
      WHEN oi.motor_item_type = 'MOTOR_TYPE_COMPULSORY' THEN oi.gross_premium
      WHEN cr.Period = 1 THEN ROUND(ROUND((1/100)*cr.charge_amount,2) - ROUND((1/100)*cr.add_ons,2), 2)
      ELSE ROUND((1/100)*cr.charge_amount, 2)
    END AS ActualReceived,
    CASE WHEN oi.motor_item_type = 'MOTOR_TYPE_COMPULSORY' THEN 0
         WHEN tsps.interest_amount = 0 OR cr.TotalPeriods - 1 = 0 THEN 0
         WHEN cr.Period = 1 THEN 0
         ELSE ROUND((ROUND((1/100)*tsps.interest_amount,2) - ((ROUND((1/100)*tsps.interest_amount,2)*3.3)/103.3)) / (cr.TotalPeriods - 1), 2)
    END AS InterestThisPeriod,
    CASE WHEN oi.motor_item_type = 'MOTOR_TYPE_COMPULSORY' THEN 0
         WHEN (cr.TotalPeriods - 1) = 0 THEN 0
         WHEN cr.Period = 1 THEN ROUND((1/100)*cr.principal, 2)
         ELSE ROUND(ROUND((1/100)*cr.payment_amount,2) - (ROUND((1/100)*tsps.interest_amount,2) - ((ROUND((1/100)*tsps.interest_amount,2)*3.3)/103.3)) / (cr.TotalPeriods-1), 2)
    END AS PrincipleThisPeriod,
    CASE WHEN oi.motor_item_type = 'MOTOR_TYPE_COMPULSORY' THEN 0
         ELSE ROUND((1/100) * cr.interest, 2) END AS InterestEIRThisPeriod,
    CASE WHEN oi.motor_item_type = 'MOTOR_TYPE_COMPULSORY' THEN 0
         ELSE ROUND((1/100) * cr.principal, 2) END AS PrincipleEIRThisPeriod,
    CASE WHEN cr.is_paid THEN cr.charge_payment_date END AS PaymentDate,
    
    -- CMI override: always single-period item settled by the first payment
    CASE WHEN oi.motor_item_type = 'MOTOR_TYPE_COMPULSORY' THEN 1 ELSE cr.Period END AS Period,
    CASE WHEN oi.motor_item_type = 'MOTOR_TYPE_COMPULSORY' THEN 1 ELSE cr.TotalPeriods END AS TotalPeriods,
    CASE WHEN cr.is_paid THEN cr.PaymentMethod_resolved ELSE NULL END AS PaymentMethod,
    CASE WHEN cr.is_paid THEN cr.PaymentChannel_resolved ELSE NULL END AS PaymentChannel,
    cr.ExpectedDate_resolved AS ExpectedDate,
    cr.old_order_id AS RefOrder,
    ROUND(rf.amount * (100/107), 2) AS RefundAmountBeforeFee,
    rf.amount AS RefundAmountAfterFee,
    CASE WHEN JSON_VALUE(cr.order_data, '$.policyHolder.policyAddress.isBillingAddress') = 'true'
      THEN CONCAT(
        COALESCE(JSON_VALUE(cr.order_data, '$.policyHolder.policyAddress.fullName'), JSON_VALUE(cr.order_data, '$.policyHolder.policyAddress.companyName')), ', ',
        JSON_VALUE(cr.order_data, '$.policyHolder.policyAddress.address'), ', ',
        JSON_VALUE(cr.order_data, '$.policyHolder.policyAddress.subDistrict'), ', ',
        JSON_VALUE(cr.order_data, '$.policyHolder.policyAddress.district'), ', ',
        JSON_VALUE(cr.order_data, '$.policyHolder.policyAddress.province'), ', ',
        JSON_VALUE(cr.order_data, '$.policyHolder.policyAddress.postCode'))
      ELSE CONCAT(
        JSON_VALUE(cr.order_data, '$.policyHolder.billingAddress.fullName'), ', ',
        JSON_VALUE(cr.order_data, '$.policyHolder.billingAddress.address'), ', ',
        JSON_VALUE(cr.order_data, '$.policyHolder.billingAddress.subDistrict'), ', ',
        JSON_VALUE(cr.order_data, '$.policyHolder.billingAddress.district'), ', ',
        JSON_VALUE(cr.order_data, '$.policyHolder.billingAddress.province'), ', ',
        JSON_VALUE(cr.order_data, '$.policyHolder.billingAddress.postCode'))
    END AS BillingAddress,
    CURRENT_DATE() AS BatchRunDate
  FROM channel_final cr
  LEFT JOIN leads l ON CONCAT('leads/', l.id) = cr.lead_ref
  JOIN order_items oi
    ON oi.order_id = cr.order_pk
   AND oi.is_cancelled IS NOT TRUE
   -- CMI attaches to the Period-1 row only; other item types keep the full spine
   AND (oi.motor_item_type != 'MOTOR_TYPE_COMPULSORY' OR oi.motor_item_type IS NULL OR cr.Period = 1)  -- A2 fix 2026-07-24
  LEFT JOIN transaction_snapshot_price_summaries tsps ON tsps.snapshot_id = cr.snapshot_id
  LEFT JOIN refunds rf ON rf.transaction_id = cr.transaction_id
),

------------------------------------------------------------------
-- STEP 6: Final shaping to 56-column interface format
------------------------------------------------------------------
final AS (
  SELECT
    CompanyDB, OrderID, OrderItem,
    CASE WHEN is_paid THEN raw_invoice_no ELSE '' END AS InvoiceNo,
    CAST(FORMAT_DATE('%d%m%Y', OrderDate) AS STRING) AS OrderDate,
    CASE WHEN InsuredID = '' OR InsuredID IS NULL THEN '-' ELSE InsuredID END AS InsuredID,
    CASE Title WHEN 'KHUN' THEN 'คุณ' WHEN 'MISS' THEN 'นางสาว'
               WHEN 'MR' THEN 'นาย' WHEN 'MRS' THEN 'นาง' ELSE '' END AS Title,
    FirstName, LastName,
    CASE WHEN InsuranceGroup IN ('products/health-insurance', 'products/travel-insurance')
      THEN CASE InsurerCode
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
        ELSE InsurerCode
      END
      ELSE TRIM(InsurerCode, 'insurer/') END AS InsurerCode,
    CASE
      WHEN InsuranceGroup = 'products/car-insurance' THEN 'Motor'
      WHEN InsuranceGroup = 'products/health-insurance' THEN 'Health'
      WHEN InsuranceGroup = 'products/travel-insurance' THEN 'TA'
      ELSE InsuranceGroup
    END AS InsuranceGroup,
    CASE
      WHEN (InsuranceType IS NULL OR TRIM(InsuranceType) = '')
        AND InsuranceGroup = 'products/health-insurance' THEN 'Health'
      WHEN (InsuranceType IS NULL OR TRIM(InsuranceType) = '')
        AND InsuranceGroup = 'products/travel-insurance' THEN 'TA'
      ELSE InsuranceType
    END AS InsuranceType,
    CASE
      WHEN InsuranceGroup = 'products/car-insurance' THEN 'Motor'
      WHEN InsuranceGroup = 'products/health-insurance' THEN 'Health'
      WHEN InsuranceGroup = 'products/travel-insurance' THEN 'TA'
      ELSE InsuranceProduct
    END AS InsuranceProduct,
    'Insurance' AS ProductType,
    CASE WHEN PolicyType = 'LEAD_TYPE_RENEWAL' THEN 'R' ELSE 'N' END AS PolicyType,
    'N' AS Endorse,
    CAST(FORMAT_DATE('%d%m%Y', PolicyDate) AS STRING) AS PolicyDate,
    IFNULL(PolicyNo, '') AS PolicyNo,
    NULL AS EndorsementNo,
    ChassisNo, LicensePlate, GrossPremium, StampDuty, VAT,
    ROUND(TotalPremium_base, 2) AS TotalPremium,
    WHT, TotalEIR, TotalSBT, ProcessingFee, ProcessingFeeVat, ShippingFee, ShippingFeeVat,
    ROUND(TotalPremium_base + WHT + TotalEIR + TotalSBT + ProcessingFee + ProcessingFeeVat + ShippingFee + ShippingFeeVat, 2) AS TotalAmount,
    Discount,
    CASE WHEN is_paid THEN 'paid' ELSE 'pending' END AS TransactionStatus,
    CASE SubmissionStatus
      WHEN 'ITEM_SUBMISSION_STATUS_READY_TO_SUBMIT' THEN 'PENDING'
      WHEN 'ITEM_SUBMISSION_STATUS_PRESUBMITTED' THEN 'PRE-SUBMITTED'
      WHEN 'ITEM_SUBMISSION_STATUS_SUBMITTED' THEN 'SUBMITTED'
      WHEN 'ITEM_SUBMISSION_STATUS_PENDING' THEN 'PENDING'
      ELSE SubmissionStatus END AS SubmissionStatus,
    CASE ApprovalStatus
      WHEN 'ITEM_APPROVAL_STATUS_APPROVED' THEN 'APPROVED'
      WHEN 'ITEM_APPROVAL_STATUS_REJECTED' THEN 'REJECTED'
      WHEN 'ITEM_APPROVAL_STATUS_PENDING' THEN 'PENDING'
      WHEN 'ITEM_APPROVAL_STATUS_POLICY_UPLOADED' THEN 'POLICY UPLOADED'
      ELSE ApprovalStatus END AS ApprovalStatus,
    CASE WHEN is_paid THEN 'fully paid' ELSE 'Not fully paid' END AS PaymentStatus,
    ExpectedReceived, ActualReceived, InterestThisPeriod, PrincipleThisPeriod,
    InterestEIRThisPeriod, PrincipleEIRThisPeriod,
    CASE WHEN PaymentDate IS NULL THEN '' ELSE CAST(FORMAT_DATE('%d%m%Y', DATE(PaymentDate)) AS STRING) END AS PaymentDate,
    Period, TotalPeriods,
    -- CMI: TotalPeriods = 1, Period = 1 → (1-1) = 0 pending automatically
    ROUND(((TotalPremium_base + TotalEIR + TotalSBT + ProcessingFee + ProcessingFeeVat + ShippingFee + ShippingFeeVat - Discount) / TotalPeriods) * (TotalPeriods - Period), 2) AS PendingPayment,
    IFNULL(PaymentMethod, '') AS PaymentMethod,
    IFNULL(PaymentChannel, '') AS PaymentChannel,
    CAST(FORMAT_DATE('%d%m%Y', ExpectedDate) AS STRING) AS ExpectedDate,
    RefOrder,
    IFNULL(CAST(RefundAmountBeforeFee AS STRING), '') AS RefundAmountBeforeFee,
    IFNULL(CAST(RefundAmountAfterFee AS STRING), '') AS RefundAmountAfterFee,
    BillingAddress,
    CAST(FORMAT_DATE('%d%m%Y', BatchRunDate) AS STRING) AS BatchRunDate
  FROM combined
),

------------------------------------------------------------------
-- STEP 7 (CHANGED): order-level qualification
-- If ANY row of the order qualifies (installment / RCL / Credit
-- Shell), pull ALL items of that order — including the CMI row
-- that now has TotalPeriods = 1 and would otherwise fall out
------------------------------------------------------------------
qualifying_orders AS (
  SELECT DISTINCT OrderID
  FROM final
  WHERE (TotalPeriods > 1
     OR PaymentChannel LIKE '%RCL%'
     OR PaymentChannel LIKE '%Credit Shell%'
     -- FIX 2026-08-23: 'RCB-CreditShell' (no space) is a new valid label from the
     -- FULL_PAYMENT/CREDIT_CARD_INSTALLMENT routing fix above and must also qualify its
     -- order, or those rows would be silently dropped from this view's output entirely.
     OR PaymentChannel LIKE '%CreditShell%')
),

qualified AS (
  SELECT DISTINCT f.*
  FROM final f
  JOIN qualifying_orders q ON q.OrderID = f.OrderID
),

-- ROOT FIX 2026-09-01: multiple successful payments for one period remain separate
-- business rows, but the schedule expectation belongs to the first payment row only.
expected_received_ranked AS (
  SELECT
    qualified.*,
    ROW_NUMBER() OVER (
      PARTITION BY qualified.OrderItem, qualified.Period
      ORDER BY
        CASE WHEN LOWER(qualified.TransactionStatus) = 'paid' THEN 0 ELSE 1 END,
        SAFE.PARSE_DATE('%d%m%Y', NULLIF(qualified.PaymentDate, '')) NULLS LAST,
        NULLIF(qualified.InvoiceNo, '') NULLS LAST,
        FARM_FINGERPRINT(TO_JSON_STRING(qualified))
    ) AS duplicate_period_seq
  FROM qualified
),

expected_received_fixed AS (
  SELECT
    * EXCEPT (duplicate_period_seq) REPLACE (
      CASE
        WHEN duplicate_period_seq = 1 THEN ExpectedReceived
        ELSE 0
      END AS ExpectedReceived
    )
  FROM expected_received_ranked
)

SELECT * REPLACE (
  CASE WHEN InsuranceGroup IN ('Health', 'TA') AND LOWER(TransactionStatus) = 'pending'
       THEN ExpectedReceived ELSE ActualReceived END AS ActualReceived
)
FROM expected_received_fixed
ORDER BY OrderItem, Period;

CREATE TEMP TABLE after_rcl_wrapper AS
WITH filtered AS (
  SELECT
    src.*
  FROM
    after_producer AS src
  WHERE
    -- Required to preserve the behavior of the original NOT IN condition.
    -- Upstream currently contains OrderItem NULL rows.
    src.OrderItem IS NOT NULL

    AND NOT EXISTS (
      SELECT
        1
      FROM
        `pacific-plating-282708.sap_integration_v2.SAP_LIVE_FULL` AS sap
      WHERE
        sap.U_OrderItem = src.OrderItem
    )

    AND EXISTS (
      SELECT
        1
      FROM
        `pacific-plating-282708.careos.cancelled_change_orders` AS change_order
      WHERE
        change_order.current_human_id = src.OrderID
    )

    AND (
      src.OrderDate LIKE '%2025%'
      OR src.OrderDate LIKE '%2026%'
    )

    AND src.OrderID NOT IN (
      'L79128866', -- incorrect insurer id
      'L79217528', -- incorrect insurer id
      'L79291428'  -- incorrect insurer id
    )

    -- Malformed rows wait until the upstream transaction data is complete.
    AND src.Period IS NOT NULL
    AND src.TotalPeriods IS NOT NULL
    AND src.Period BETWEEN 1 AND src.TotalPeriods
),

ranked AS (
  SELECT
    filtered.*,

    ROW_NUMBER() OVER (
      PARTITION BY
        filtered.OrderItem,
        filtered.Period
      ORDER BY
        -- A successful payment row is the expected schedule row.
        CASE
          WHEN LOWER(filtered.TransactionStatus) = 'paid' THEN 0
          ELSE 1
        END,

        -- Earlier payment keeps ExpectedReceived.
        SAFE.PARSE_DATE(
          '%d%m%Y',
          NULLIF(filtered.PaymentDate, '')
        ) NULLS LAST,

        NULLIF(filtered.InvoiceNo, '') NULLS LAST,

        -- Stable tie-breaker without removing valid additional payments.
        FARM_FINGERPRINT(TO_JSON_STRING(filtered))
    ) AS duplicate_period_seq
  FROM
    filtered
),

fixed AS (
  SELECT
    * EXCEPT (duplicate_period_seq)

    REPLACE (
      -- Period duplication is allowed, but ExpectedReceived must not repeat.
      CASE
        WHEN duplicate_period_seq = 1
          THEN ExpectedReceived
        ELSE 0
      END AS ExpectedReceived,

      -- Pending transactions have no successful charge information.
      CASE
        WHEN LOWER(TransactionStatus) = 'pending'
          THEN ''
        ELSE IFNULL(PaymentMethod, '')
      END AS PaymentMethod,

      CASE
        WHEN LOWER(TransactionStatus) = 'pending'
          THEN ''
        ELSE IFNULL(PaymentChannel, '')
      END AS PaymentChannel
    )
  FROM
    ranked
)

SELECT DISTINCT
  * REPLACE (
  CASE WHEN InsuranceGroup IN ('Health', 'TA') AND LOWER(TransactionStatus) = 'paid'
         AND SAFE.PARSE_DATE('%d%m%Y', NULLIF(PaymentDate, '')) < DATE_TRUNC(CURRENT_DATE('Asia/Bangkok'), MONTH)
       THEN FORMAT_DATE('%d%m%Y', DATE_TRUNC(CURRENT_DATE('Asia/Bangkok'), MONTH))
       ELSE PaymentDate END AS PaymentDate
)
FROM
  fixed
ORDER BY
  OrderItem,
  Period;

CREATE TEMP TABLE after_rcb_wrapper AS
-- Full source-only legacy fix proposal for:
--   pacific-plating-282708.sap_view.RCL_Motor_process_4_creditshell
--
-- Root fixes:
--   1. Split Motor and NonMotor routing after the upstream payload is normalized.
--      Motor keeps its existing channel. Health/TA successful QR payments use
--      RCL-Omise QR Prompt Pay-Health, including later CreditShell installments.
--      The carried-over first installment keeps RCL-Credit Shell because its
--      PaymentMethod is RCL-Credit Shell, not OME Omise QR Prompt Pay.
--   2. A paid PaymentDate earlier than the current month is posted as the first
--      day of the current month. A current-month paid date is preserved.
--   3. Pending InvoiceNo/payment routing remains blank.
--   4. Preserve legitimate repeated-period payment rows and keep ExpectedReceived
--      only on the first row for an OrderItem/Period.
--
-- SELECT only: this file does not replace or deploy the live legacy view.

WITH
  filtered AS (
    SELECT src.*
    FROM after_producer AS src
    WHERE src.OrderItem IS NOT NULL
      AND NOT EXISTS (
        SELECT 1
        FROM `pacific-plating-282708.sap_integration_v2.SAP_LIVE_FULL` AS sap
        WHERE sap.U_OrderItem = src.OrderItem
      )
      AND EXISTS (
        SELECT 1
        FROM `pacific-plating-282708.careos.cancelled_change_orders` AS change_order
        WHERE change_order.current_human_id = src.OrderID
      )
      AND (
        src.OrderDate LIKE '%2025%'
        OR src.OrderDate LIKE '%2026%'
      )
      AND src.OrderID NOT IN (
        'L79128866',
        'L79217528',
        'L79291428'
      )
      AND src.Period IS NOT NULL
      AND src.TotalPeriods IS NOT NULL
      AND src.Period BETWEEN 1 AND src.TotalPeriods
  ),

  ranked AS (
    SELECT
      filtered.*,
      ROW_NUMBER() OVER (
        PARTITION BY filtered.OrderItem, filtered.Period
        ORDER BY
          CASE WHEN LOWER(filtered.TransactionStatus) = 'paid' THEN 0 ELSE 1 END,
          SAFE.PARSE_DATE('%d%m%Y', NULLIF(filtered.PaymentDate, '')) NULLS LAST,
          NULLIF(filtered.InvoiceNo, '') NULLS LAST,
          FARM_FINGERPRINT(TO_JSON_STRING(filtered))
      ) AS duplicate_period_seq
    FROM filtered
  ),

  fixed_common AS (
    SELECT
      * EXCEPT (duplicate_period_seq)
      REPLACE (
        CASE
          WHEN duplicate_period_seq = 1 THEN ExpectedReceived
          ELSE 0
        END AS ExpectedReceived,
        CASE
          WHEN LOWER(TransactionStatus) = 'pending' THEN ''
          ELSE IFNULL(PaymentMethod, '')
        END AS PaymentMethod,
        CASE
          WHEN LOWER(TransactionStatus) = 'pending' THEN ''
          ELSE IFNULL(PaymentChannel, '')
        END AS PaymentChannel
      )
    FROM ranked
  ),

  motor_rows AS (
    SELECT *
    FROM fixed_common
    WHERE InsuranceGroup = 'Motor'
  ),

  nonmotor_rows AS (
    SELECT
      * REPLACE (
        CASE
          WHEN LOWER(TransactionStatus) = 'paid'
            AND PaymentMethod = 'OME Omise QR Prompt Pay'
          THEN 'RCL-Omise QR Prompt Pay-Health'
          ELSE PaymentChannel
        END AS PaymentChannel
      )
    FROM fixed_common
    WHERE InsuranceGroup IN ('Health', 'TA')
  ),

  unclassified_rows AS (
    -- Preserve unknown legacy product labels without guessing a payment route.
    SELECT *
    FROM fixed_common
    WHERE InsuranceGroup IS NULL
       OR InsuranceGroup NOT IN ('Motor', 'Health', 'TA')
  ),

  routed AS (
    SELECT * FROM motor_rows
    UNION ALL
    SELECT * FROM nonmotor_rows
    UNION ALL
    SELECT * FROM unclassified_rows
  ),

  payment_date_fixed AS (
    SELECT
      * REPLACE (
        CASE
          WHEN LOWER(TransactionStatus) = 'pending' THEN ''
          WHEN SAFE.PARSE_DATE('%d%m%Y', NULLIF(PaymentDate, ''))
            < DATE_TRUNC(CURRENT_DATE(), MONTH)
          THEN FORMAT_DATE('%d%m%Y', DATE_TRUNC(CURRENT_DATE(), MONTH))
          ELSE IFNULL(PaymentDate, '')
        END AS PaymentDate
      )
    FROM routed
  )

SELECT DISTINCT * REPLACE (
  CASE WHEN InsuranceGroup IN ('Health', 'TA') AND LOWER(TransactionStatus) = 'paid'
         AND SAFE.PARSE_DATE('%d%m%Y', NULLIF(PaymentDate, '')) < DATE_TRUNC(CURRENT_DATE('Asia/Bangkok'), MONTH)
       THEN FORMAT_DATE('%d%m%Y', DATE_TRUNC(CURRENT_DATE('Asia/Bangkok'), MONTH))
       ELSE PaymentDate END AS PaymentDate
)
FROM payment_date_fixed
ORDER BY OrderItem, Period;

SELECT CURRENT_TIMESTAMP() observed_at,'producer' AS object,
 (SELECT COUNT(*) FROM before_producer) AS before_rows,
 (SELECT COUNT(*) FROM after_producer) AS after_rows,
 (SELECT COUNT(*) FROM after_producer WHERE InsuranceGroup IN ('Health','TA') AND LOWER(TransactionStatus)='pending' AND ActualReceived IS DISTINCT FROM ExpectedReceived) AS pending_amount_failures,
 (SELECT COUNT(*) FROM after_producer WHERE InsuranceGroup IN ('Health','TA') AND NOT STARTS_WITH(IFNULL(InsurerCode,''),'N')) AS insurer_failures,
 (SELECT COUNT(*) FROM after_producer WHERE InsuranceGroup IN ('Health','TA') AND LOWER(TransactionStatus)='paid' AND SAFE.PARSE_DATE('%d%m%Y',PaymentDate)<DATE_TRUNC(CURRENT_DATE('Asia/Bangkok'),MONTH)) AS prior_month_paid,
 (SELECT COUNT(*) FROM (SELECT TO_JSON_STRING(t) AS payload FROM before_producer t WHERE InsuranceGroup='Motor' EXCEPT DISTINCT SELECT TO_JSON_STRING(t) FROM after_producer t WHERE InsuranceGroup='Motor')) AS removed_motor,
 (SELECT COUNT(*) FROM (SELECT TO_JSON_STRING(t) AS payload FROM after_producer t WHERE InsuranceGroup='Motor' EXCEPT DISTINCT SELECT TO_JSON_STRING(t) FROM before_producer t WHERE InsuranceGroup='Motor')) AS added_motor,
 (SELECT COUNT(*) FROM (SELECT TO_JSON_STRING((SELECT AS STRUCT t.* EXCEPT(InsurerCode,ActualReceived,PaymentDate))) AS payload FROM before_producer t EXCEPT DISTINCT SELECT TO_JSON_STRING((SELECT AS STRUCT t.* EXCEPT(InsurerCode,ActualReceived,PaymentDate))) FROM after_producer t)) AS removed_other_fields,
 (SELECT COUNT(*) FROM (SELECT TO_JSON_STRING((SELECT AS STRUCT t.* EXCEPT(InsurerCode,ActualReceived,PaymentDate))) AS payload FROM after_producer t EXCEPT DISTINCT SELECT TO_JSON_STRING((SELECT AS STRUCT t.* EXCEPT(InsurerCode,ActualReceived,PaymentDate))) FROM before_producer t)) AS added_other_fields;

SELECT CURRENT_TIMESTAMP() observed_at,'rcl_wrapper' AS object,
 (SELECT COUNT(*) FROM before_rcl_wrapper) AS before_rows,
 (SELECT COUNT(*) FROM after_rcl_wrapper) AS after_rows,
 (SELECT COUNT(*) FROM after_rcl_wrapper WHERE InsuranceGroup IN ('Health','TA') AND LOWER(TransactionStatus)='pending' AND ActualReceived IS DISTINCT FROM ExpectedReceived) AS pending_amount_failures,
 (SELECT COUNT(*) FROM after_rcl_wrapper WHERE InsuranceGroup IN ('Health','TA') AND NOT STARTS_WITH(IFNULL(InsurerCode,''),'N')) AS insurer_failures,
 (SELECT COUNT(*) FROM after_rcl_wrapper WHERE InsuranceGroup IN ('Health','TA') AND LOWER(TransactionStatus)='paid' AND SAFE.PARSE_DATE('%d%m%Y',PaymentDate)<DATE_TRUNC(CURRENT_DATE('Asia/Bangkok'),MONTH)) AS prior_month_paid,
 (SELECT COUNT(*) FROM (SELECT TO_JSON_STRING(t) AS payload FROM before_rcl_wrapper t WHERE InsuranceGroup='Motor' EXCEPT DISTINCT SELECT TO_JSON_STRING(t) FROM after_rcl_wrapper t WHERE InsuranceGroup='Motor')) AS removed_motor,
 (SELECT COUNT(*) FROM (SELECT TO_JSON_STRING(t) AS payload FROM after_rcl_wrapper t WHERE InsuranceGroup='Motor' EXCEPT DISTINCT SELECT TO_JSON_STRING(t) FROM before_rcl_wrapper t WHERE InsuranceGroup='Motor')) AS added_motor,
 (SELECT COUNT(*) FROM (SELECT TO_JSON_STRING((SELECT AS STRUCT t.* EXCEPT(InsurerCode,ActualReceived,PaymentDate))) AS payload FROM before_rcl_wrapper t EXCEPT DISTINCT SELECT TO_JSON_STRING((SELECT AS STRUCT t.* EXCEPT(InsurerCode,ActualReceived,PaymentDate))) FROM after_rcl_wrapper t)) AS removed_other_fields,
 (SELECT COUNT(*) FROM (SELECT TO_JSON_STRING((SELECT AS STRUCT t.* EXCEPT(InsurerCode,ActualReceived,PaymentDate))) AS payload FROM after_rcl_wrapper t EXCEPT DISTINCT SELECT TO_JSON_STRING((SELECT AS STRUCT t.* EXCEPT(InsurerCode,ActualReceived,PaymentDate))) FROM before_rcl_wrapper t)) AS added_other_fields;

SELECT CURRENT_TIMESTAMP() observed_at,'rcb_wrapper' AS object,
 (SELECT COUNT(*) FROM before_rcb_wrapper) AS before_rows,
 (SELECT COUNT(*) FROM after_rcb_wrapper) AS after_rows,
 (SELECT COUNT(*) FROM after_rcb_wrapper WHERE InsuranceGroup IN ('Health','TA') AND LOWER(TransactionStatus)='pending' AND ActualReceived IS DISTINCT FROM ExpectedReceived) AS pending_amount_failures,
 (SELECT COUNT(*) FROM after_rcb_wrapper WHERE InsuranceGroup IN ('Health','TA') AND NOT STARTS_WITH(IFNULL(InsurerCode,''),'N')) AS insurer_failures,
 (SELECT COUNT(*) FROM after_rcb_wrapper WHERE InsuranceGroup IN ('Health','TA') AND LOWER(TransactionStatus)='paid' AND SAFE.PARSE_DATE('%d%m%Y',PaymentDate)<DATE_TRUNC(CURRENT_DATE('Asia/Bangkok'),MONTH)) AS prior_month_paid,
 (SELECT COUNT(*) FROM (SELECT TO_JSON_STRING(t) AS payload FROM before_rcb_wrapper t WHERE InsuranceGroup='Motor' EXCEPT DISTINCT SELECT TO_JSON_STRING(t) FROM after_rcb_wrapper t WHERE InsuranceGroup='Motor')) AS removed_motor,
 (SELECT COUNT(*) FROM (SELECT TO_JSON_STRING(t) AS payload FROM after_rcb_wrapper t WHERE InsuranceGroup='Motor' EXCEPT DISTINCT SELECT TO_JSON_STRING(t) FROM before_rcb_wrapper t WHERE InsuranceGroup='Motor')) AS added_motor,
 (SELECT COUNT(*) FROM (SELECT TO_JSON_STRING((SELECT AS STRUCT t.* EXCEPT(InsurerCode,ActualReceived,PaymentDate))) AS payload FROM before_rcb_wrapper t EXCEPT DISTINCT SELECT TO_JSON_STRING((SELECT AS STRUCT t.* EXCEPT(InsurerCode,ActualReceived,PaymentDate))) FROM after_rcb_wrapper t)) AS removed_other_fields,
 (SELECT COUNT(*) FROM (SELECT TO_JSON_STRING((SELECT AS STRUCT t.* EXCEPT(InsurerCode,ActualReceived,PaymentDate))) AS payload FROM after_rcb_wrapper t EXCEPT DISTINCT SELECT TO_JSON_STRING((SELECT AS STRUCT t.* EXCEPT(InsurerCode,ActualReceived,PaymentDate))) FROM before_rcb_wrapper t)) AS added_other_fields;

SELECT OrderID,OrderItem,Period,TotalPeriods,InsuranceGroup,InsurerCode,TransactionStatus,ExpectedReceived,ActualReceived,PaymentDate,InvoiceNo,PaymentChannel FROM after_rcl_wrapper WHERE InsuranceGroup IN ('Health','TA') ORDER BY OrderItem,Period;
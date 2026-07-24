-- BASELINE CAPTURE 2026-07-24 -- pulled verbatim from live BigQuery view definition
-- Object: sap_integration_v2.`RCL 04_new order credit shell new tunning`
-- Boat: fix the same A2 NULL-safe bug here, leave everything else as-is (not
-- confirmed live/nightly production like the other 4 objects, but fixing anyway).
-- See docs/knowledge/30_SAP_CHANGELOG.md (2026-07-24 entry) for the bug.

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

transactions AS (SELECT id FROM `pacific-plating-282708.careos.carepay_transactions`),

transaction_snapshots AS (
  SELECT id, transaction_id, number_of_installment
  FROM `pacific-plating-282708.careos.carepay_transaction_snapshots`
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
         amount, payment_method, service_provider, update_time
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
    ts.id           AS snapshot_id,
    ts.number_of_installment AS TotalPeriods
  FROM orders_scoped o
  JOIN full_replacement_orders fro ON fro.new_order_id = o.human_id
  LEFT JOIN transactions t ON CONCAT('transactions/', t.id) = o.payment
  LEFT JOIN transaction_snapshots ts ON ts.transaction_id = t.id
),

period_spine AS (
  SELECT
    n.order_pk,
    n.OrderID, n.transaction_id, n.snapshot_id, n.TotalPeriods, n.OrderDate,
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
    s.OrderID, s.transaction_id, s.snapshot_id, s.TotalPeriods, s.Period, s.OrderDate,
    s.order_data, s.lead_ref,
    isd.payment_amount, isd.principal, isd.principal_balance, isd.interest, isd.add_ons,
    c.third_party_id  AS charge_invoice_no,
    c.status          AS charge_status,
    c.amount          AS charge_amount,
    c.payment_method  AS charge_payment_method,
    c.service_provider AS charge_service_provider,
    c.update_time     AS charge_payment_date,
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
      WHEN is_carried_over_from_old_order THEN 'RCL-Credit Shell'
      WHEN charge_payment_method = 'CASH' THEN 'RCL-Transfer-อื่นๆ'
      WHEN charge_payment_method = 'QR_CODE' AND charge_service_provider = 'RABBIT_LENDING' THEN 'RCL-Omise QR Prompt Pay-BAY'
      ELSE charge_service_provider
    END AS PaymentChannel_resolved,
    CASE
      WHEN NOT is_paid THEN NULL
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
    cr.charge_invoice_no AS raw_invoice_no,
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
    CASE WHEN sap.BatchRunDate is NOT NULL AND PARSE_TIMESTAMP('%d%m%Y', sap.BatchRunDate) >= TIMESTAMP(DATE_TRUNC(CURRENT_DATE(), MONTH)) 
      THEN PARSE_TIMESTAMP('%d%m%Y', sap.BatchRunDate)
      WHEN sap.BatchRunDate is NOT NULL AND PARSE_TIMESTAMP('%d%m%Y', sap.BatchRunDate) < TIMESTAMP(DATE_TRUNC(CURRENT_DATE(), MONTH))
      THEN TIMESTAMP(DATE_TRUNC(CURRENT_DATE(), MONTH))
      WHEN sap.BatchRunDate is NULL AND cr.charge_payment_date < TIMESTAMP(DATE_TRUNC(CURRENT_DATE(), MONTH)) THEN TIMESTAMP(DATE_TRUNC(CURRENT_DATE(), MONTH))
      WHEN sap.BatchRunDate is NULL AND cr.charge_payment_date >= TIMESTAMP(DATE_TRUNC(CURRENT_DATE(), MONTH)) THEN TIMESTAMP(cr.charge_payment_date)
      ELSE cr.charge_payment_date
  END
    AS PaymentDate,
    
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
  LEFT JOIN order_items oi
    ON oi.order_id = cr.order_pk
   AND oi.is_cancelled IS NOT TRUE
   -- CMI attaches to the Period-1 row only; other item types keep the full spine
   AND (oi.motor_item_type != 'MOTOR_TYPE_COMPULSORY' OR cr.Period = 1)
  LEFT JOIN transaction_snapshot_price_summaries tsps ON tsps.snapshot_id = cr.snapshot_id
  LEFT JOIN refunds rf ON rf.transaction_id = cr.transaction_id
  -- defensive: drop item-less spine rows beyond Period 1
  -- (only possible if an order somehow has CMI as its sole active item)
  LEFT JOIN (SELECT U_OrderID, U_OrderItem, U_InvoiceNo, BatchRunDate FROM pacific-plating-282708.sap_integration_v2.SAP_LIVE_FULL WHERE TransactionStatus = 'Cancelled (Change order / Rejected)' ) sap ON U_OrderID = cr.old_order_id
  WHERE oi.human_id IS NOT NULL OR cr.Period = 1
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
    CASE WHEN InsuranceGroup = 'products/car-insurance' THEN 'Motor' ELSE InsuranceGroup END AS InsuranceGroup,
    InsuranceType,
    CASE WHEN InsuranceGroup = 'products/car-insurance' THEN 'Motor' ELSE InsuranceGroup END AS InsuranceProduct,
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
     OR PaymentChannel LIKE '%Credit Shell%')
)

SELECT f.*
FROM final f
JOIN qualifying_orders q ON q.OrderID = f.OrderID
ORDER BY f.OrderItem, f.Period



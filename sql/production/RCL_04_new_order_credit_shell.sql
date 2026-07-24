-- BASELINE CAPTURE 2026-07-24 -- pulled verbatim from live BigQuery view definition
-- Object: sap_integration_v2.`RCL 04_new order credit shell`
-- This is the CURRENT production query, exactly as running tonight's schedule.
-- Do not hand-edit without diffing against a fresh pull first (it may have
-- changed in BigQuery since this capture). See docs/knowledge/30_SAP_CHANGELOG.md
-- (2026-07-24 entry) for what was found wrong with it and why.

WITH RECURSIVE
------------------------------------------------------------------
-- Base tables
------------------------------------------------------------------
orders_scoped AS (
  SELECT id, human_id, payment, create_time, lead, data
  FROM `pacific-plating-282708.careos.careos_orders`
  WHERE create_time >= '2026-01-01'   -- <<< CONFIRM: new-order scope window
),

orders_all AS (
  SELECT id, human_id, payment, create_time
  FROM `pacific-plating-282708.careos.careos_orders`
  WHERE create_time >= '2024-01-01'   -- <<< CONFIRM: how far back chains can go
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

------------------------------------------------------------------
-- FIX: TotalPeriods now derived from installment_details, not the
-- (unreliable) number_of_installment field on the snapshot itself.
-- Snapshot chosen per transaction by: most installment_details rows
-- → highest max period → most recently updated (tie-break only)
------------------------------------------------------------------
transaction_snapshot_stats AS (
  SELECT
    snapshot_id,
    COUNT(*) AS periods_count,
    MAX(period) AS max_period
  FROM `pacific-plating-282708.careos.carepay_transaction_snapshot_installment_details`
  GROUP BY snapshot_id
),

transaction_snapshots AS (
  SELECT id, transaction_id, TotalPeriods
  FROM (
    SELECT
      ts.id,
      ts.transaction_id,
      -- true period count from schedule; fall back to the raw field
      -- only when there is no installment_details at all
      COALESCE(tss.max_period, ts.number_of_installment, 1) AS TotalPeriods,
      ROW_NUMBER() OVER (
        PARTITION BY ts.transaction_id
        ORDER BY
          COALESCE(tss.periods_count, 0) DESC,
          COALESCE(tss.max_period, 0) DESC,
          ts.update_time DESC,
          ts.id DESC
      ) AS rn
    FROM `pacific-plating-282708.careos.carepay_transaction_snapshots` ts
    LEFT JOIN transaction_snapshot_stats tss ON tss.snapshot_id = ts.id
  )
  WHERE rn = 1
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
-- RCL identifier (order-level): careos_charges has NO order_id —
-- link via CONCAT('transactions/', transaction_id) = orders.payment
------------------------------------------------------------------
rcl_orders AS (
  SELECT DISTINCT o.id AS order_pk
  FROM orders_scoped o
  JOIN `pacific-plating-282708.careos.careos_charges` cc
    ON CONCAT('transactions/', cc.transaction_id) = o.payment
  WHERE cc.service_provider = 'RABBIT_LENDING'
    AND cc.status = 'SUCCESSFUL'
),

------------------------------------------------------------------
-- LINK SOURCE 1 (authoritative): cancelled_change_orders
------------------------------------------------------------------
ccs_links AS (
  SELECT DISTINCT
    current_human_id AS new_order_id,
    old_human_id     AS old_order_id,
    1 AS link_priority
  FROM `pacific-plating-282708.careos.cancelled_change_orders`
  WHERE current_human_id IS NOT NULL
    AND old_human_id IS NOT NULL
),

------------------------------------------------------------------
-- LINK SOURCE 2 (supplementary): shared-invoice detection
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

order_item_counts AS (
  SELECT
    order_id,
    COUNTIF(is_cancelled IS NOT TRUE) AS active_remaining,
    COUNT(*) AS total_items
  FROM order_items
  GROUP BY order_id
),

credit_shell_classified AS (
  SELECT DISTINCT
    new_oc.order_id AS new_order_id,
    old_oc.order_id AS old_order_id,
    CASE
      WHEN IFNULL(oic.active_remaining, 0) = 0 THEN 'FULL_REPLACEMENT'
      WHEN IFNULL(oic.active_remaining, 0) > 0
       AND IFNULL(oic.active_remaining, 0) < IFNULL(oic.total_items, 0) THEN 'PARTIAL_REPLACEMENT'
      ELSE 'REVIEW_UNKNOWN'
    END AS credit_shell_case_type
  FROM order_charges_candidates_only new_oc
  JOIN order_charges_candidates_only old_oc
    ON old_oc.invoice_no = new_oc.invoice_no
   AND old_oc.order_pk != new_oc.order_pk
   AND old_oc.order_create_time < new_oc.order_create_time
  LEFT JOIN order_item_counts oic
    ON oic.order_id = old_oc.order_pk
),

invoice_links AS (
  SELECT DISTINCT new_order_id, old_order_id, 2 AS link_priority
  FROM credit_shell_classified
  WHERE credit_shell_case_type IN ('FULL_REPLACEMENT', 'PARTIAL_REPLACEMENT')
),

------------------------------------------------------------------
-- Merge both link sources
------------------------------------------------------------------
all_links AS (
  SELECT new_order_id, old_order_id, MIN(link_priority) AS link_priority
  FROM (
    SELECT * FROM ccs_links
    UNION ALL
    SELECT * FROM invoice_links
  )
  GROUP BY new_order_id, old_order_id
),

------------------------------------------------------------------
-- Walk the cancel/change chain (multiple rounds → A→B→C→...)
------------------------------------------------------------------
ancestors AS (
  SELECT new_order_id, old_order_id AS ancestor_order_id, 1 AS depth
  FROM all_links
  UNION ALL
  SELECT a.new_order_id, l.old_order_id, a.depth + 1
  FROM ancestors a
  JOIN all_links l ON l.new_order_id = a.ancestor_order_id
  WHERE a.depth < 10
),

------------------------------------------------------------------
-- Invoice pool: all successful-charge invoices of all ancestors
------------------------------------------------------------------
new_order_old_invoice_pool AS (
  SELECT DISTINCT
    a.new_order_id,
    c.third_party_id AS invoice_no
  FROM ancestors a
  JOIN orders_all oa ON oa.human_id = a.ancestor_order_id
  JOIN transactions t ON CONCAT('transactions/', t.id) = oa.payment
  JOIN charges c ON c.transaction_id = t.id
  WHERE c.third_party_id IS NOT NULL
),

------------------------------------------------------------------
-- RefOrder: ONE direct predecessor per new order
------------------------------------------------------------------
credit_shell_orders AS (
  SELECT new_order_id, old_order_id
  FROM (
    SELECT
      al.new_order_id,
      al.old_order_id,
      ROW_NUMBER() OVER (
        PARTITION BY al.new_order_id
        ORDER BY al.link_priority, oa.create_time DESC, al.old_order_id
      ) AS rn
    FROM all_links al
    LEFT JOIN orders_all oa ON oa.human_id = al.old_order_id
  )
  WHERE rn = 1
),

------------------------------------------------------------------
-- SAP: latest Cancelled/Change BatchRunDate per old order
------------------------------------------------------------------
sap_cancelled AS (
  SELECT
    U_OrderID,
    MAX(PARSE_TIMESTAMP('%d%m%Y', BatchRunDate)) AS sap_batch_ts
  FROM `pacific-plating-282708.sap_integration_v2.SAP_LIVE_FULL`
  WHERE TransactionStatus = 'Cancelled (Change order / Rejected)'
    AND BatchRunDate IS NOT NULL
  GROUP BY U_OrderID
),

------------------------------------------------------------------
-- Period spine over credit-shell NEW orders
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
    ts.TotalPeriods AS TotalPeriods,
    cso.old_order_id
  FROM orders_scoped o
  JOIN credit_shell_orders cso ON cso.new_order_id = o.human_id
  LEFT JOIN transactions t ON CONCAT('transactions/', t.id) = o.payment
  LEFT JOIN transaction_snapshots ts ON ts.transaction_id = t.id
),

period_spine AS (
  SELECT
    n.order_pk, n.OrderID, n.transaction_id, n.snapshot_id, n.TotalPeriods,
    n.OrderDate, n.order_data, n.lead_ref, n.old_order_id,
    period_num AS Period
  FROM new_order_txn n,
  UNNEST(GENERATE_ARRAY(1, GREATEST(IFNULL(n.TotalPeriods, 1), 1))) AS period_num
),

------------------------------------------------------------------
-- Attach schedule + payment + follow_up + SAP cancel date
------------------------------------------------------------------
spine_with_payment AS (
  SELECT
    s.*,
    isd.payment_amount, isd.principal, isd.principal_balance, isd.interest, isd.add_ons,
    c.third_party_id  AS charge_invoice_no,
    c.status          AS charge_status,
    c.amount          AS charge_amount,
    c.payment_method  AS charge_payment_method,
    c.service_provider AS charge_service_provider,
    c.update_time     AS charge_payment_date,
    fu.due_date       AS followup_due_date,
    sap.sap_batch_ts
  FROM period_spine s
  LEFT JOIN transaction_snapshot_installment_details isd
    ON isd.snapshot_id = s.snapshot_id AND isd.period = s.Period
  LEFT JOIN charges c
    ON c.transaction_id = s.transaction_id
   AND c.installment_number = s.Period
  LEFT JOIN follow_ups fu
    ON fu.transaction_id = s.transaction_id
   AND fu.installment = s.Period
  LEFT JOIN sap_cancelled sap
    ON sap.U_OrderID = s.old_order_id
),

------------------------------------------------------------------
-- Channel + carried-over detection (pooled ancestor invoices)
------------------------------------------------------------------
channel_resolved AS (
  SELECT
    sp.*,
    (sp.charge_status = 'SUCCESSFUL') AS is_paid,
    (pool.invoice_no IS NOT NULL) AS is_carried_over_from_old_order
  FROM spine_with_payment sp
  LEFT JOIN new_order_old_invoice_pool pool
    ON pool.new_order_id = sp.OrderID
   AND pool.invoice_no = sp.charge_invoice_no
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
    END AS ExpectedDate_resolved,
    CASE
      WHEN is_carried_over_from_old_order AND sap_batch_ts IS NOT NULL THEN sap_batch_ts
      ELSE charge_payment_date
    END AS payment_ts_raw
  FROM channel_resolved
),

------------------------------------------------------------------
-- Period-lock clamp
------------------------------------------------------------------
payment_resolved AS (
  SELECT
    *,
    CASE
      WHEN payment_ts_raw IS NULL THEN NULL
      WHEN payment_ts_raw < TIMESTAMP(DATE_TRUNC(CURRENT_DATE(), MONTH))
        THEN TIMESTAMP(DATE_TRUNC(CURRENT_DATE(), MONTH))
      ELSE payment_ts_raw
    END AS PaymentDate_final
  FROM channel_final
),

------------------------------------------------------------------
-- Join order_items (CMI fix retained) + RCL flag
------------------------------------------------------------------
combined AS (
  SELECT
    'RCB' AS CompanyDB,
    cr.OrderID,
    oi.human_id AS OrderItem,
    cr.charge_invoice_no AS raw_invoice_no,
    cr.OrderDate,
    (ro.order_pk IS NOT NULL) AS is_rcl_order,
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
      
      WHEN oi.motor_item_type = 'MOTOR_TYPE_COMPULSORY' THEN oi.gross_premium
      WHEN cr.Period = 1 THEN ROUND(ROUND((1/100)*cr.charge_amount,2) - ROUND((1/100)*cr.add_ons,2), 2)
      ELSE ROUND((1/100)*cr.payment_amount, 2)
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
    cr.PaymentDate_final AS PaymentDate,
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
  FROM payment_resolved cr
  LEFT JOIN leads l ON CONCAT('leads/', l.id) = cr.lead_ref
  LEFT JOIN order_items oi
    ON oi.order_id = cr.order_pk
   AND oi.is_cancelled IS NOT TRUE
   AND (oi.motor_item_type != 'MOTOR_TYPE_COMPULSORY' OR oi.motor_item_type IS NULL OR cr.Period = 1)  -- P0/A2 fix 2026-07-24: NULL motor_item_type failed this join for period != 1, then got dropped by the WHERE below
  LEFT JOIN rcl_orders ro ON ro.order_pk = cr.order_pk
  LEFT JOIN transaction_snapshot_price_summaries tsps ON tsps.snapshot_id = cr.snapshot_id
  LEFT JOIN refunds rf ON rf.transaction_id = cr.transaction_id
  WHERE oi.human_id IS NOT NULL OR cr.Period = 1
),

------------------------------------------------------------------
-- Final shaping to 56-column interface format
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
    ROUND(((TotalPremium_base + TotalEIR + TotalSBT + ProcessingFee + ProcessingFeeVat + ShippingFee + ShippingFeeVat - Discount) / TotalPeriods) * (TotalPeriods - Period), 2) AS PendingPayment,
    IFNULL(PaymentMethod, '') AS PaymentMethod,
    IFNULL(PaymentChannel, '') AS PaymentChannel,
    CAST(FORMAT_DATE('%d%m%Y', ExpectedDate) AS STRING) AS ExpectedDate,
    RefOrder,
    IFNULL(CAST(RefundAmountBeforeFee AS STRING), '') AS RefundAmountBeforeFee,
    IFNULL(CAST(RefundAmountAfterFee AS STRING), '') AS RefundAmountAfterFee,
    BillingAddress,
    CAST(FORMAT_DATE('%d%m%Y', BatchRunDate) AS STRING) AS BatchRunDate,
    is_rcl_order
  FROM combined
),

------------------------------------------------------------------
-- Order-level qualification
------------------------------------------------------------------
qualifying_orders AS (
  SELECT DISTINCT OrderItem
  FROM final
  WHERE TotalPeriods > 1
     OR is_rcl_order
     OR PaymentChannel LIKE '%Credit Shell%'
)

SELECT f.* EXCEPT (is_rcl_order)
FROM final f
JOIN qualifying_orders q ON q.OrderItem = f.OrderItem

ORDER BY f.OrderItem, f.Period

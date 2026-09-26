-- ============================================================
-- SAP INTERFACE v1.1 — all RCB CREDIT_CARD_INSTALLMENT cases
-- Started: 2026-08-30
-- Base: urgent batch derived from sap_dashboard_carepay_fully_paid
--
-- v1.1 scope change:
--   - Removed the manual target_items list.
--   - orders now contains every motor CREDIT_CARD_INSTALLMENT order.
--   - order_items contains every item for those orders, except items already
--     present in SAP_LIVE_FULL.
--
-- There is intentionally no date filter. This is a historical catch-up of all
-- currently eligible, unsent items. Run validation.sql before export.
-- Confirmed RCB credit-card-installment definition (Boat, 2026-08-30):
--   transactions.payment_option = 'CREDIT_CARD_INSTALLMENT'
--   charges.payment_method = 'EDC'
--   charges.service_provider <> 'RABBIT_LENDING'
-- ============================================================
WITH
charges AS (
  SELECT
    *,
    ROW_NUMBER() OVER (
      PARTITION BY transaction_id
      ORDER BY create_time
    ) AS charge_rank
  FROM `pacific-plating-282708.careos.carepay_charges`
  WHERE status = 'SUCCESSFUL'
    --AND payment_method = 'EDC'
    AND service_provider <> 'RABBIT_LENDING'
    AND create_time  >= '2026-01-01'
    AND delete_time IS NULL
),

transaction_snapshot_price_summaries AS (
  SELECT *
  FROM `pacific-plating-282708.careos.carepay_transaction_snapshot_price_summaries`
),

-- Use the latest snapshot per transaction to prevent snapshot fanout.
transaction_snapshots AS (
  SELECT *
  FROM (
    SELECT
      *,
      ROW_NUMBER() OVER (
        PARTITION BY transaction_id
        ORDER BY update_time DESC, id DESC
      ) AS rn
    FROM `pacific-plating-282708.careos.carepay_transaction_snapshots`
    WHERE delete_time IS NULL
  )
  WHERE rn = 1
),

transactions AS (
  SELECT *
  FROM `pacific-plating-282708.careos.carepay_transactions`
  WHERE delete_time IS NULL
),

-- General v1.1 scope: all motor orders paid by credit-card installment.
orders AS (
  SELECT o.*
  FROM `pacific-plating-282708.careos.careos_orders` AS o
  JOIN transactions AS t
    ON o.payment = CONCAT('transactions/', CAST(t.id AS STRING))
  WHERE --t.payment_option = 'CREDIT_CARD_INSTALLMENT' AND
    o.product = 'products/car-insurance'
),

-- All eligible items, retaining the item-level SAP idempotency control.
order_items AS (
  SELECT i.*
  FROM `pacific-plating-282708.careos.careos_order_items` AS i
  JOIN orders AS o
    ON o.id = i.order_id
  WHERE NOT EXISTS (
    SELECT 1
    FROM `pacific-plating-282708.sap_integration_v2.SAP_LIVE_FULL` AS s
    WHERE s.U_OrderItem = i.human_id
  )
),

leads AS (
  SELECT *
  FROM `pacific-plating-282708.careos.careos_leads`
),

change AS (
  SELECT *
  FROM `pacific-plating-282708.careos.cancelled_change_orders`
),

compu_detail AS (
  SELECT
    orders.human_id AS order_id,
    CASE
      WHEN order_items.gross_premium IS NULL THEN 0
      ELSE order_items.gross_premium
    END AS gross_premium
  FROM `pacific-plating-282708.careos.careos_order_items` AS order_items
  LEFT JOIN `pacific-plating-282708.careos.careos_orders` AS orders
    ON order_items.order_id = orders.id
  WHERE order_items.motor_item_type = 'MOTOR_TYPE_COMPULSORY'
    AND orders.product = 'products/car-insurance'
),

onetime_master AS (
  SELECT DISTINCT
    CAST(charges.amount AS FLOAT64) AS charges_amount,
    order_items.motor_item_type,
    charges.service_provider,
    charges.charge_rank,
    orders.create_time AS OrderDate,
    charges.status,
    orders.human_id AS OrderID,
    order_items.human_id AS OrderItem,
    order_items.net_premium AS GrossPremium,
    order_items.stamp_duty AS StampDuty,
    order_items.vat_amount AS VAT,
    order_items.gross_premium AS TotalPremium,
    COALESCE(ROUND(0.01 * transaction_snapshot_price_summaries.wht_amount, 2), 0) AS WHT_master,
    CASE
      WHEN transaction_snapshot_price_summaries.interest_amount IS NULL THEN 0
      ELSE ROUND(
        ROUND(0.01 * transaction_snapshot_price_summaries.interest_amount, 2)
        - (
          ROUND(0.01 * transaction_snapshot_price_summaries.interest_amount, 2)
          * 3.3 / 103.3
        ),
        2
      )
    END AS TotalEIR,
    CASE
      WHEN transaction_snapshot_price_summaries.interest_amount IS NULL THEN 0
      ELSE ROUND(
        ROUND(0.01 * transaction_snapshot_price_summaries.interest_amount, 2)
        * 3.3 / 103.3,
        2
      )
    END AS TotalSBT,
    CASE
      WHEN transaction_snapshot_price_summaries.processing_fee_amount IS NULL THEN 0
      ELSE ROUND(
        ROUND(0.01 * transaction_snapshot_price_summaries.processing_fee_amount, 2)
        * (100 / 107),
        2
      )
    END AS ProcessingFee_master,
    CASE
      WHEN transaction_snapshot_price_summaries.processing_fee_amount IS NULL THEN 0
      ELSE ROUND(
        ROUND(0.01 * transaction_snapshot_price_summaries.processing_fee_amount, 2)
        - ROUND(0.01 * transaction_snapshot_price_summaries.processing_fee_amount, 2)
          * (100 / 107),
        2
      )
    END AS ProcessingFeeVat_master,
    CASE
      WHEN transaction_snapshot_price_summaries.shipment_fee IS NULL THEN 0
      ELSE ROUND(
        ROUND(0.01 * transaction_snapshot_price_summaries.shipment_fee, 2)
        * (100 / 107),
        2
      )
    END AS ShippingFee_master,
    CASE
      WHEN transaction_snapshot_price_summaries.shipment_fee IS NULL THEN 0
      ELSE ROUND(
        ROUND(0.01 * transaction_snapshot_price_summaries.shipment_fee, 2)
        - ROUND(0.01 * transaction_snapshot_price_summaries.shipment_fee, 2)
          * (100 / 107),
        2
      )
    END AS ShippingFeeVat_master,
    COALESCE(ROUND(0.01 * transaction_snapshot_price_summaries.discount_amount, 2), 0) AS Discount_master,
    charges.status AS TransactionStatus,
    order_items.submission_status AS SubmissionStatus,
    order_items.approval_status AS ApprovalStatus,
    transactions.status AS PaymentStatus,
    ROUND(0.01 * charges.amount, 2) AS ActualReceived_master,
    0 AS PrincipleThisPeriod,
    transaction_snapshot_price_summaries.interest_amount AS InterestEIRThisPeriod,
    0 AS PrincipleEIRThisPeriod,
    CASE
      WHEN DATE(COALESCE(charges.payment_date, charges.update_time))
        < DATE_TRUNC(CURRENT_DATE(), MONTH)
        AND CURRENT_DATE() > DATE_ADD(
          LAST_DAY(DATE_SUB(CURRENT_DATE(), INTERVAL 1 MONTH)),
          INTERVAL 3 DAY
        )
      THEN TIMESTAMP(DATE_TRUNC(CURRENT_DATE(), MONTH))
      ELSE COALESCE(charges.payment_date, charges.update_time)
    END AS PaymentDate,
    1 AS Period,
    1 AS TotalPeriods,
    0 AS PendingPayment,
    charges.create_time AS ExpectedDate,
    CASE
      WHEN charges.third_party_id IS NULL AND charges.status = 'SUCCESSFUL'
        THEN CONCAT(charges.charge_rank, '_', order_items.human_id)
      WHEN charges.third_party_id IS NULL AND charges.status <> 'SUCCESSFUL' THEN ''
      ELSE charges.third_party_id
    END AS InvoiceNo,
    order_items.insurer AS InsurerCode,
    order_items.product AS InsuranceGroup,
    order_items.motor_item_type AS InsuranceType,
    leads.type AS PolicyType,
    order_items.policy_start_date AS PolicyDate,
    order_items.policy_number AS PolicyNo,
    JSON_VALUE(orders.data, '$.chassisNumber') AS ChassisNo,
    JSON_VALUE(orders.data, '$.carLicensePlate') AS LicensePlate,
    CASE
      WHEN JSON_VALUE(orders.data, '$.policyHolder.isCompany') = 'true'
        AND JSON_VALUE(orders.data, '$.policyHolder.companyTaxId') IS NULL THEN '-'
      WHEN JSON_VALUE(orders.data, '$.policyHolder.isCompany') = 'true'
        AND JSON_VALUE(orders.data, '$.policyHolder.companyTaxId') IS NOT NULL
        THEN JSON_VALUE(orders.data, '$.policyHolder.companyTaxId')
      WHEN JSON_VALUE(orders.data, '$.idNumber') IS NULL
        OR JSON_VALUE(orders.data, '$.idNumber') IN ('', ' ') THEN '-'
      ELSE JSON_VALUE(orders.data, '$.idNumber')
    END AS InsuredID,
    JSON_VALUE(orders.data, '$.policyHolder.title') AS Title,
    COALESCE(
      JSON_VALUE(orders.data, '$.policyHolder.firstName'),
      JSON_VALUE(orders.data, '$.policyHolder.policyAddress.companyName')
    ) AS FirstName,
    JSON_VALUE(orders.data, '$.policyHolder.lastName') AS LastName,
    JSON_VALUE(orders.data, '$.oicCode') AS oicCode,
    0 AS RefundAmountBeforeFee,
    0 AS RefundAmountAfterFee,
    CASE
      WHEN JSON_VALUE(orders.data, '$.policyHolder.policyAddress.isBillingAddress') = 'true'
      THEN CONCAT(
        COALESCE(
          JSON_VALUE(orders.data, '$.policyHolder.policyAddress.fullName'),
          JSON_VALUE(orders.data, '$.policyHolder.policyAddress.companyName')
        ), ', ',
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
    'RCB' AS CompanyDB,
    ch.old_human_id AS RefOrder,
    ROW_NUMBER() OVER (
      PARTITION BY order_items.human_id
      ORDER BY order_items.create_time, charges.create_time
    ) AS cmi_rank
  FROM orders
  LEFT JOIN leads
    ON CONCAT('leads/', leads.id) = orders.lead
  LEFT JOIN transactions
    ON CONCAT('transactions/', transactions.id) = orders.payment
  LEFT JOIN charges
    ON charges.transaction_id = transactions.id
  LEFT JOIN order_items
    ON order_items.order_id = orders.id
  LEFT JOIN transaction_snapshots
    ON transaction_snapshots.transaction_id = transactions.id
  LEFT JOIN transaction_snapshot_price_summaries
    ON transaction_snapshot_price_summaries.snapshot_id = transaction_snapshots.id
  LEFT JOIN change AS ch
    ON ch.current_human_id = orders.human_id
  WHERE charges.status = 'SUCCESSFUL'
    --AND transactions.payment_option = 'CREDIT_CARD_INSTALLMENT'
    AND orders.product = 'products/car-insurance'
    AND order_items.human_id IS NOT NULL
),

onetime_master_go AS (
  SELECT
    * EXCEPT(charge_rank),
    charge_rank,
    CASE
      WHEN motor_item_type = 'MOTOR_TYPE_COMPULSORY' THEN 0
      ELSE WHT_master
    END AS WHT,
    CASE
      WHEN motor_item_type = 'MOTOR_TYPE_COMPULSORY' THEN 0
      ELSE ProcessingFee_master
    END AS ProcessingFee,
    CASE
      WHEN motor_item_type = 'MOTOR_TYPE_COMPULSORY' THEN 0
      ELSE ProcessingFeeVat_master
    END AS ProcessingFeeVat,
    CASE
      WHEN motor_item_type = 'MOTOR_TYPE_COMPULSORY' THEN 0
      ELSE ShippingFee_master
    END AS ShippingFee,
    CASE
      WHEN motor_item_type = 'MOTOR_TYPE_COMPULSORY' THEN 0
      ELSE ShippingFeeVat_master
    END AS ShippingFeeVat,
    CASE
      WHEN motor_item_type = 'MOTOR_TYPE_COMPULSORY' THEN TotalPremium
      ELSE ROUND(
        TotalPremium + TotalEIR + TotalSBT + ProcessingFee_master
        + ProcessingFeeVat_master + ShippingFee_master + ShippingFeeVat_master,
        2
      )
    END AS TotalAmount,
    CASE
      WHEN motor_item_type = 'MOTOR_TYPE_COMPULSORY' THEN 0
      ELSE Discount_master
    END AS Discount,
    CASE
      WHEN motor_item_type = 'MOTOR_TYPE_COMPULSORY' THEN compu_detail.gross_premium
      WHEN charge_rank = 1 THEN ROUND(
        TotalPremium + TotalEIR + TotalSBT + ProcessingFee_master
        + ProcessingFeeVat_master + ShippingFee_master + ShippingFeeVat_master
        - Discount_master,
        2
      )
      WHEN charge_rank <> 1 THEN 0
    END AS ExpectedReceived,
    CASE
      WHEN motor_item_type = 'MOTOR_TYPE_COMPULSORY' THEN compu_detail.gross_premium
      WHEN motor_item_type <> 'MOTOR_TYPE_COMPULSORY' AND charge_rank <> 1
        THEN COALESCE(ActualReceived_master, ROUND(0.01 * TotalPremium, 2))
      WHEN compu_detail.gross_premium IS NOT NULL
        AND motor_item_type <> 'MOTOR_TYPE_COMPULSORY'
        AND charge_rank = 1
        THEN ROUND(ActualReceived_master - compu_detail.gross_premium, 2)
      ELSE COALESCE(ActualReceived_master, ROUND(0.01 * TotalPremium, 2))
    END AS ActualReceived,
    0 AS InterestThisPeriod
  FROM onetime_master
  LEFT JOIN compu_detail
    ON compu_detail.order_id = onetime_master.OrderID
  WHERE NOT (cmi_rank <> 1 AND motor_item_type = 'MOTOR_TYPE_COMPULSORY')
),

final_export AS (
SELECT DISTINCT
  CompanyDB,
  OrderID,
  OrderItem,
  InvoiceNo,
  CAST(FORMAT_DATE('%d%m%Y', OrderDate) AS STRING) AS OrderDate,
  InsuredID,
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
  'Motor' AS InsuranceGroup,
  InsuranceType,
  CASE
    WHEN oicCode IN ('TYPE_610', 'TYPE_620', 'TYPE_630') THEN 'MotorBike'
    ELSE 'Motor'
  END AS InsuranceProduct,
  'Insurance' AS ProductType,
  CASE
    WHEN PolicyType = 'LEAD_TYPE_RENEWAL' THEN 'R'
    ELSE 'N'
  END AS PolicyType,
  'N' AS Endorse,
  CAST(FORMAT_DATE('%d%m%Y', PolicyDate) AS STRING) AS PolicyDate,
  PolicyNo,
  CAST(NULL AS STRING) AS EndorsementNo,
  ChassisNo,
  LicensePlate,
  FORMAT('%.2f', GrossPremium) AS GrossPremium,
  FORMAT('%.2f', StampDuty) AS StampDuty,
  FORMAT('%.2f', VAT) AS VAT,
  FORMAT('%.2f', TotalPremium) AS TotalPremium,
  FORMAT('%.2f', WHT) AS WHT,
  FORMAT('%.2f', TotalEIR) AS TotalEIR,
  FORMAT('%.2f', TotalSBT) AS TotalSBT,
  FORMAT('%.2f', ProcessingFee) AS ProcessingFee,
  FORMAT('%.2f', ProcessingFeeVat) AS ProcessingFeeVat,
  FORMAT('%.2f', ShippingFee) AS ShippingFee,
  FORMAT('%.2f', ShippingFeeVat) AS ShippingFeeVat,
  FORMAT('%.2f', TotalAmount) AS TotalAmount,
  FORMAT('%.2f', Discount) AS Discount,
  'paid' AS TransactionStatus,
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
  'Fully paid' AS PaymentStatus,
  FORMAT('%.2f', ExpectedReceived) AS ExpectedReceived,
  FORMAT('%.2f', ActualReceived) AS ActualReceived,
  InterestThisPeriod,
  PrincipleThisPeriod,
  InterestEIRThisPeriod,
  PrincipleEIRThisPeriod,
  CAST(FORMAT_DATE('%d%m%Y', PaymentDate) AS STRING) AS PaymentDate,
  Period,
  TotalPeriods,
  PendingPayment,
  'EDC EDC' AS PaymentMethod,
  'RCB-EDC-KBANK' AS PaymentChannel,
  CAST(FORMAT_DATE('%d%m%Y', ExpectedDate) AS STRING) AS ExpectedDate,
  RefOrder,
  RefundAmountBeforeFee,
  RefundAmountAfterFee,
  BillingAddress,
  CAST(FORMAT_DATE('%d%m%Y', BatchRunDate) AS STRING) AS BatchRunDate
FROM onetime_master_go
)

SELECT *
FROM final_export

ORDER BY OrderItem;

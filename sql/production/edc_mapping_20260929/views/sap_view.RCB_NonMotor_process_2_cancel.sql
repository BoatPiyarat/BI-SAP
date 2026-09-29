CREATE OR REPLACE VIEW `pacific-plating-282708.sap_view.RCB_NonMotor_process_2_cancel` AS
-- Full source-only legacy reuse proposal for:
--   pacific-plating-282708.sap_view.RCB_NonMotor_process_2_cancel
--
-- New responsibility (MS-01):
--   RCB Health new-order payloads whose current order is linked to an old order by
--   careos.cancelled_change_orders and whose current OrderItem is not yet in SAP.
--
-- Legacy rules preserved:
--   * RCB_HEALTH field calculations and insurer/payment mappings.
--   * Successful CareOS charges are the payment source.
--   * RABBIT_CARE_INSTALLMENT/RABBIT_LENDING are excluded to prevent RCB/RCL mixing.
--   * A legitimate later charge remains another Period 1 row, but its
--     ExpectedReceived is 0 so expected revenue is not repeated.
--   * SELECT DISTINCT removes only exact final-payload duplicates.
--
-- SELECT only: this file does not replace or deploy the live legacy view.

WITH
  change_orders AS (
    SELECT DISTINCT
      current_human_id,
      old_human_id
    FROM `pacific-plating-282708.careos.cancelled_change_orders`
    WHERE current_human_id IS NOT NULL
      AND old_human_id IS NOT NULL
  ),

  latest_snapshot AS (
    SELECT *
    FROM `pacific-plating-282708.careos.carepay_transaction_snapshots`
    QUALIFY ROW_NUMBER() OVER (
      PARTITION BY transaction_id
      ORDER BY update_time DESC, create_time DESC, id DESC
    ) = 1
  ),

  successful_charges AS (
    SELECT *
    FROM `pacific-plating-282708.careos.carepay_charges`
    WHERE status = 'SUCCESSFUL'
      AND (service_provider IS NULL OR service_provider NOT IN ('ICOLLECTION', 'RABBIT_LENDING'))
    QUALIFY ROW_NUMBER() OVER (
      PARTITION BY id
      ORDER BY update_time DESC, create_time DESC
    ) = 1
  ),

  source_rows AS (
    SELECT
      'RCB' AS CompanyDB,
      orders.human_id AS OrderID,
      order_items.human_id AS OrderItem,
      orders.create_time AS OrderDate,
      CASE
        WHEN JSON_VALUE(orders.data, '$.policyHolder.isCompany') = 'true'
          AND JSON_VALUE(orders.data, '$.policyHolder.companyTaxId') IS NULL THEN '-'
        WHEN JSON_VALUE(orders.data, '$.policyHolder.isCompany') = 'true'
          THEN JSON_VALUE(orders.data, '$.policyHolder.companyTaxId')
        WHEN JSON_VALUE(orders.data, '$.idNumber') IS NULL
          OR TRIM(JSON_VALUE(orders.data, '$.idNumber')) = '' THEN '-'
        ELSE JSON_VALUE(orders.data, '$.idNumber')
      END AS InsuredID,
      JSON_VALUE(orders.data, '$.policyHolder.title') AS source_title,
      COALESCE(
        JSON_VALUE(orders.data, '$.policyHolder.firstName'),
        JSON_VALUE(orders.data, '$.policyHolder.policyAddress.companyName')
      ) AS FirstName,
      JSON_VALUE(orders.data, '$.policyHolder.lastName') AS LastName,
      order_items.insurer AS source_insurer,
      order_items.product AS source_product,
      order_items.motor_item_type AS source_insurance_type,
      leads.type AS source_policy_type,
      order_items.policy_start_date AS PolicyDate,
      order_items.policy_number AS PolicyNo,
      JSON_VALUE(orders.data, '$.chassisNumber') AS ChassisNo,
      JSON_VALUE(orders.data, '$.carLicensePlate') AS LicensePlate,
      COALESCE(order_items.net_premium, 0) AS GrossPremium,
      COALESCE(order_items.stamp_duty, 0) AS StampDuty,
      COALESCE(order_items.vat_amount, 0) AS VAT,
      COALESCE(order_items.gross_premium, 0) AS TotalPremium,
      COALESCE(ROUND(price_summary.wht_amount / 100, 2), 0) AS WHT,
      CASE
        WHEN price_summary.interest_amount IS NULL THEN 0
        ELSE ROUND(
          ROUND(price_summary.interest_amount / 100, 2)
          - (ROUND(price_summary.interest_amount / 100, 2) * 3.3 / 103.3),
          2
        )
      END AS TotalEIR,
      CASE
        WHEN price_summary.interest_amount IS NULL THEN 0
        ELSE ROUND(
          ROUND(price_summary.interest_amount / 100, 2) * 3.3 / 103.3,
          2
        )
      END AS TotalSBT,
      CASE
        WHEN price_summary.processing_fee_amount IS NULL THEN 0
        ELSE ROUND(
          ROUND(price_summary.processing_fee_amount / 100, 2) * 100 / 107,
          2
        )
      END AS ProcessingFee,
      CASE
        WHEN price_summary.processing_fee_amount IS NULL THEN 0
        ELSE ROUND(
          ROUND(price_summary.processing_fee_amount / 100, 2)
          - ROUND(price_summary.processing_fee_amount / 100, 2) * 100 / 107,
          2
        )
      END AS ProcessingFeeVat,
      CASE
        WHEN price_summary.shipment_fee IS NULL THEN 0
        ELSE ROUND(
          ROUND(price_summary.shipment_fee / 100, 2) * 100 / 107,
          2
        )
      END AS ShippingFee,
      CASE
        WHEN price_summary.shipment_fee IS NULL THEN 0
        ELSE ROUND(
          ROUND(price_summary.shipment_fee / 100, 2)
          - ROUND(price_summary.shipment_fee / 100, 2) * 100 / 107,
          2
        )
      END AS ShippingFeeVat,
      COALESCE(ROUND(price_summary.discount_amount / 100, 2), 0) AS Discount,
      COALESCE(SAFE_CAST(price_summary.interest_amount AS INT64), 0)
        AS InterestEIRThisPeriod,
      order_items.submission_status AS source_submission_status,
      order_items.approval_status AS source_approval_status,
      transactions.status AS source_payment_status,
      COALESCE(SAFE_CAST(charges.installment_number AS INT64), 1) AS Period,
      charges.payment_method AS source_payment_method,
      charges.service_provider AS source_payment_channel,
      charges.third_party_id,
      charges.id AS charge_id,
      charges.create_time AS charge_create_time,
      COALESCE(charges.payment_date, charges.update_time, charges.create_time)
        AS source_payment_date,
      ROUND(charges.amount / 100, 2) AS ActualReceived,
      change_orders.old_human_id AS RefOrder,
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
      ROW_NUMBER() OVER (
        PARTITION BY order_items.human_id
        ORDER BY
          COALESCE(charges.payment_date, charges.update_time, charges.create_time),
          charges.create_time,
          charges.id
      ) AS item_charge_rank
    FROM `pacific-plating-282708.careos.careos_orders` AS orders
    JOIN change_orders
      ON change_orders.current_human_id = orders.human_id
    JOIN `pacific-plating-282708.careos.careos_order_items` AS order_items
      ON order_items.order_id = orders.id
    JOIN `pacific-plating-282708.careos.carepay_transactions` AS transactions
      ON CONCAT('transactions/', transactions.id) = orders.payment
    JOIN successful_charges AS charges
      ON charges.transaction_id = transactions.id
    LEFT JOIN `pacific-plating-282708.careos.careos_leads` AS leads
      ON CONCAT('leads/', leads.id) = orders.lead
    LEFT JOIN latest_snapshot AS snapshot
      ON snapshot.transaction_id = transactions.id
    LEFT JOIN `pacific-plating-282708.careos.carepay_transaction_snapshot_price_summaries`
      AS price_summary
      ON price_summary.snapshot_id = snapshot.id
    LEFT JOIN `pacific-plating-282708.sap_integration_v3.stg_sap_state` AS sap
      ON sap.U_OrderItem = order_items.human_id
    WHERE order_items.product = 'products/health-insurance'
      AND order_items.is_cancelled IS NOT TRUE
      AND order_items.cancel_time IS NULL
      AND orders.is_fully_paid IS TRUE
      AND transactions.status = 'SUCCESSFUL'
      AND transactions.payment_option != 'RABBIT_CARE_INSTALLMENT'
      AND (
        snapshot.number_of_installment = 1
        OR transactions.payment_option = 'CREDIT_CARD_INSTALLMENT'
      )
      AND GREATEST(
        DATE(orders.create_time, 'Asia/Bangkok'),
        COALESCE(
          DATE(order_items.policy_start_date, 'Asia/Bangkok'),
          DATE(orders.create_time, 'Asia/Bangkok')
        )
      ) >= DATE '2026-01-01'
      AND sap.U_OrderItem IS NULL
      AND LOWER(TRIM(COALESCE(
        JSON_VALUE(orders.data, '$.policyHolder.firstName'),
        JSON_VALUE(orders.data, '$.policyHolder.policyAddress.companyName'),
        ''
      ))) != 'test'
      AND LOWER(TRIM(COALESCE(
        JSON_VALUE(orders.data, '$.policyHolder.lastName'),
        ''
      ))) != 'test'
  ),

  calculated AS (
    SELECT
      source_rows.*,
      ROUND(
        TotalPremium + TotalEIR + TotalSBT
        + ProcessingFee + ProcessingFeeVat + ShippingFee + ShippingFeeVat,
        2
      ) AS TotalAmount,
      CASE
        WHEN item_charge_rank = 1 THEN ROUND(
          TotalPremium + TotalEIR + TotalSBT
          + ProcessingFee + ProcessingFeeVat + ShippingFee + ShippingFeeVat
          - Discount,
          2
        )
        ELSE 0
      END AS ExpectedReceived,
      CASE
        WHEN DATE(source_payment_date, 'Asia/Bangkok')
          < DATE_TRUNC(CURRENT_DATE('Asia/Bangkok'), MONTH)
        THEN DATE_TRUNC(CURRENT_DATE('Asia/Bangkok'), MONTH)
        ELSE DATE(source_payment_date, 'Asia/Bangkok')
      END AS PaymentDate,
      COALESCE(
        NULLIF(third_party_id, ''),
        CONCAT(
          CASE source_payment_method
            WHEN 'DIRECT_PAYMENT' THEN 'dpm'
            WHEN 'BANK_TRANSFER' THEN 'trf'
            WHEN 'CASH' THEN 'cash'
            WHEN 'EDC' THEN 'edc'
            ELSE LOWER(COALESCE(source_payment_method, 'payment'))
          END,
          '_', CAST(item_charge_rank AS STRING), '_', OrderItem
        )
      ) AS InvoiceNo
    FROM source_rows
  )

SELECT DISTINCT
  CompanyDB,
  OrderID,
  OrderItem,
  InvoiceNo,
  FORMAT_DATE('%d%m%Y', DATE(OrderDate, 'Asia/Bangkok')) AS OrderDate,
  InsuredID,
  CASE source_title
    WHEN 'KHUN' THEN 'คุณ'
    WHEN 'MISS' THEN 'นางสาว'
    WHEN 'MR' THEN 'นาย'
    WHEN 'MRS' THEN 'นาง'
    ELSE ''
  END AS Title,
  FirstName,
  LastName,
  CASE source_insurer
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
    ELSE source_insurer
  END AS InsurerCode,
  'Health' AS InsuranceGroup,
  CASE
    WHEN source_insurance_type IS NULL OR TRIM(source_insurance_type) = '' THEN 'Health'
    ELSE source_insurance_type
  END AS InsuranceType,
  'Health' AS InsuranceProduct,
  'Insurance' AS ProductType,
  CASE WHEN source_policy_type = 'LEAD_TYPE_RENEWAL' THEN 'R' ELSE 'N' END AS PolicyType,
  'N' AS Endorse,
  FORMAT_DATE('%d%m%Y', DATE(PolicyDate, 'Asia/Bangkok')) AS PolicyDate,
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
  CASE source_submission_status
    WHEN 'ITEM_SUBMISSION_STATUS_READY_TO_SUBMIT' THEN 'PENDING'
    WHEN 'ITEM_SUBMISSION_STATUS_PRESUBMITTED' THEN 'PRE-SUBMITTED'
    WHEN 'ITEM_SUBMISSION_STATUS_SUBMITTED' THEN 'SUBMITTED'
    WHEN 'ITEM_SUBMISSION_STATUS_PENDING' THEN 'PENDING'
    ELSE source_submission_status
  END AS SubmissionStatus,
  CASE source_approval_status
    WHEN 'ITEM_APPROVAL_STATUS_APPROVED' THEN 'APPROVED'
    WHEN 'ITEM_APPROVAL_STATUS_REJECTED' THEN 'REJECTED'
    WHEN 'ITEM_APPROVAL_STATUS_PENDING' THEN 'PENDING'
    WHEN 'ITEM_APPROVAL_STATUS_POLICY_UPLOADED' THEN 'POLICY UPLOADED'
    ELSE source_approval_status
  END AS ApprovalStatus,
  CASE source_payment_status
    WHEN 'SUCCESSFUL' THEN 'Fully paid'
    WHEN 'PENDING' THEN 'Not fully paid'
    ELSE source_payment_status
  END AS PaymentStatus,
  FORMAT('%.2f', ExpectedReceived) AS ExpectedReceived,
  FORMAT('%.2f', ActualReceived) AS ActualReceived,
  CAST(0 AS INT64) AS InterestThisPeriod,
  CAST(0 AS INT64) AS PrincipleThisPeriod,
  InterestEIRThisPeriod,
  CAST(0 AS INT64) AS PrincipleEIRThisPeriod,
  FORMAT_DATE('%d%m%Y', PaymentDate) AS PaymentDate,
  Period,
  CAST(1 AS INT64) AS TotalPeriods,
  CAST(0 AS INT64) AS PendingPayment,
  `pacific-plating-282708.sap_integration_v3.fn_rcb_payment_mapping`(source_payment_method, source_payment_channel).sap_payment_method AS PaymentMethod,
  `pacific-plating-282708.sap_integration_v3.fn_rcb_payment_mapping`(source_payment_method, source_payment_channel).sap_payment_channel AS PaymentChannel,
  FORMAT_DATE('%d%m%Y', DATE(charge_create_time, 'Asia/Bangkok')) AS ExpectedDate,
  RefOrder,
  CAST(0 AS INT64) AS RefundAmountBeforeFee,
  CAST(0 AS INT64) AS RefundAmountAfterFee,
  BillingAddress,
  FORMAT_DATE('%d%m%Y', CURRENT_DATE('Asia/Bangkok')) AS BatchRunDate
FROM calculated
ORDER BY OrderID, OrderItem, Period, InvoiceNo
;

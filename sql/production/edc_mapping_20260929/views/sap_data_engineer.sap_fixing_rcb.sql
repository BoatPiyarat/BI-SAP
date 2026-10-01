CREATE OR REPLACE VIEW `pacific-plating-282708.sap_data_engineer.sap_fixing_rcb` AS
WITH
get_charges_ref AS (
  SELECT 
    charges.third_party_id, 
    orders.human_id AS order_id, 
    orders.payment
  FROM `pacific-plating-282708.careos.carepay_charges` charges
  LEFT JOIN `pacific-plating-282708.careos.careos_orders` orders 
    ON orders.payment = CONCAT('transactions/', charges.transaction_id) 
  WHERE 
    (service_provider IS NULL OR service_provider <> 'ICOLLECTION')
    AND status = 'SUCCESSFUL'
    AND third_party_id IS NOT NULL 
    AND orders.human_id IS NOT NULL
),

charges AS (
  SELECT * FROM `pacific-plating-282708.careos.carepay_charges`
),

follow_ups AS ( 
  SELECT * FROM `pacific-plating-282708.careos.carepay_follow_ups`
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
),

charge_one AS (
  SELECT 
    charges.id AS charges_id, 
    charges.transaction_id
  FROM charges 
  RIGHT JOIN (
    SELECT 
      charges.transaction_id AS id, 
      MIN(charges.create_time) AS timee
    FROM orders 
    LEFT JOIN transactions 
      ON CONCAT('transactions/', transactions.id) = orders.payment
    LEFT JOIN charges 
      ON charges.transaction_id = transactions.id 
    WHERE 
      charges.status = 'SUCCESSFUL' 
      AND (charges.service_provider IS NULL OR charges.service_provider <> 'ICOLLECTION')
    GROUP BY charges.transaction_id
  ) AS minn 
  ON minn.id = charges.transaction_id 
  AND charges.create_time = minn.timee
),

check_order_items AS (
  SELECT 
    orders.human_id AS OrderID, 
    COUNT(order_items) AS no_items
  FROM `pacific-plating-282708.careos.careos_order_items` order_items
  LEFT JOIN `pacific-plating-282708.careos.careos_orders` orders
    ON order_items.order_id = orders.id
  WHERE 1 = 1 
  GROUP BY orders.human_id
),

compu_detail AS (
  SELECT 
    orders.human_id AS order_id,
    CASE 
      WHEN order_items.gross_premium IS NULL THEN 0 
      ELSE order_items.gross_premium 
    END AS gross_premium
  FROM `pacific-plating-282708.careos.careos_order_items` order_items
  LEFT JOIN `pacific-plating-282708.careos.careos_orders` orders
    ON order_items.order_id = orders.id
  WHERE order_items.packagetype = 'mandatoryPackages'
),

onetime_master AS (
    SELECT 
        charges.amount AS charges_amount,
        charges.installment_number AS charges_installment_number,
        transaction_snapshot_price_summaries.interest_amount,
        charges.*,
        follow_ups.*,
        order_items.motor_item_type,
        order_items.packagetype,
        charges.service_provider, 
        orders.create_time AS OrderDate,
        charges.status,
        orders.human_id,
        order_items.human_id AS OrderItem,
        order_items.price,
        order_items.net_premium AS GrossPremium,
        order_items.stamp_duty AS StampDuty,
        order_items.vat_amount AS VAT,
        order_items.gross_premium AS TotalPremium,
        ROUND((1 / 100) * transaction_snapshot_price_summaries.wht_amount, 2) AS WHT_master,
        ROUND((1 / 100) * transaction_snapshot_price_summaries.interest_amount, 2) AS TotalEIR_check,
        CASE
            WHEN transaction_snapshot_price_summaries.interest_amount IS NULL THEN 0
            ELSE ROUND(ROUND((1 / 100) * transaction_snapshot_price_summaries.interest_amount, 2) - ((ROUND((1 / 100) * transaction_snapshot_price_summaries.interest_amount, 2) * 3.3) / 103.3), 2)
        END AS TotalEIR,
        CASE
            WHEN transaction_snapshot_price_summaries.interest_amount IS NULL THEN 0
            ELSE ROUND(((ROUND((1 / 100) * transaction_snapshot_price_summaries.interest_amount, 2) * 3.3) / 103.3), 2)
        END AS TotalSBT,
        CASE 
            WHEN transaction_snapshot_price_summaries.processing_fee_amount IS NULL THEN 0
            ELSE ROUND(ROUND((1 / 100) * transaction_snapshot_price_summaries.processing_fee_amount, 2) * (100/107), 2)
        END AS ProcessingFee_master,
        CASE
            WHEN transaction_snapshot_price_summaries.processing_fee_amount IS NULL THEN 0
            ELSE ROUND(ROUND((1 / 100) * transaction_snapshot_price_summaries.processing_fee_amount, 2) - (ROUND((1 / 100) * transaction_snapshot_price_summaries.processing_fee_amount, 2) * (100/107)), 2)
        END AS ProcessingFeeVat_master,
        CASE
            WHEN transaction_snapshot_price_summaries.shipment_fee IS NULL THEN 0
            ELSE ROUND(ROUND((1 / 100) * transaction_snapshot_price_summaries.shipment_fee, 2) * (100/107), 2)
        END AS ShippingFee_master,
        CASE
            WHEN transaction_snapshot_price_summaries.shipment_fee IS NULL THEN 0
            ELSE ROUND(ROUND((1 / 100) * transaction_snapshot_price_summaries.shipment_fee, 2) - ROUND((1 / 100) * transaction_snapshot_price_summaries.shipment_fee, 2) * (100/107), 2)
        END AS ShippingFeeVat_master,
        ROUND((1 / 100) * transaction_snapshot_price_summaries.discount_amount, 2) AS Discount_master,
        charges.status AS TransactionStatus,
        order_items.submission_status AS SubmissionStatus,
        order_items.approval_status AS ApprovalStatus,
        transactions.status AS PaymentStatus,
        ROUND(((1 / 100) * charges.amount), 2) AS ActualReceived_master,
        0 AS PrincipleThisPeriod,
        transaction_snapshot_price_summaries.interest_amount AS InterestEIRThisPeriod,
        0 AS PrincipleEIRThisPeriod,
        COALESCE(charges.payment_date, charges.update_time) AS PaymentDate,
        charges.installment_number AS Period,
        1 AS TotalPeriods,
        0 AS PendingPayment,
        charges.create_time AS ExpectedDate,
        charges.id AS charges_id,
        CASE 
            WHEN charges.third_party_id IS NULL THEN order_items.human_id 
            ELSE charges.third_party_id 
        END AS InvoiceNo,
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
        charges.payment_method AS PaymentMethod,
        charges.service_provider AS PaymentChannel,
        CASE 
            WHEN JSON_VALUE(orders.data, '$.policyHolder.isCompany') = 'true' THEN JSON_VALUE(orders.data, '$.policyHolder.companyTaxId') 
            ELSE JSON_VALUE(orders.data, '$.idNumber') 
        END AS InsuredID,
        JSON_VALUE(orders.data, '$.policyHolder.title') AS Title,
        COALESCE(JSON_VALUE(orders.data, '$.policyHolder.firstName'), JSON_VALUE(orders.data, '$.policyHolder.policyAddress.companyName')) AS FirstName,
        JSON_VALUE(orders.data, '$.policyHolder.lastName') AS LastName,
        0 AS RefundAmountBeforeFee,
        0 AS RefundAmountAfterFee,
        CASE
            WHEN JSON_VALUE(orders.data, '$.policyHolder.policyAddress.isBillingAddress') = 'true' THEN CONCAT(
                COALESCE(JSON_VALUE(orders.data, '$.policyHolder.policyAddress.fullName'), JSON_VALUE(orders.data, '$.policyHolder.policyAddress.companyName')), ' ',
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
        CURRENT_DATE() AS BatchRunDate,
        'RCB' AS CompanyDB,
        leads.reference AS RefOrder
    FROM orders
    LEFT JOIN leads ON CONCAT('leads/', leads.id) = orders.lead
    LEFT JOIN transactions ON CONCAT('transactions/', transactions.id) = orders.payment
    LEFT JOIN follow_ups ON follow_ups.transaction_id = transactions.id
    LEFT JOIN charges ON charges.transaction_id = transactions.id 
    LEFT JOIN order_items ON order_items.order_id = orders.id
    LEFT JOIN transaction_snapshots ON transaction_snapshots.transaction_id = transactions.id
    LEFT JOIN transaction_snapshot_price_summaries ON transaction_snapshot_price_summaries.snapshot_id = transaction_snapshots.id
    WHERE 1 = 1
    AND orders.is_fully_paid IS TRUE
    AND charges.status = 'SUCCESSFUL'
    AND follow_ups.id IS NULL
    AND (charges.service_provider IS NULL OR charges.service_provider <> 'ICOLLECTION')
),

onetime_master_go AS (
    SELECT *, 
        CASE WHEN packagetype = 'mandatoryPackages' THEN 0 ELSE WHT_master END AS WHT,
        CASE WHEN packagetype = 'mandatoryPackages' THEN 0 ELSE ProcessingFee_master END AS ProcessingFee,
        CASE WHEN packagetype = 'mandatoryPackages' THEN 0 ELSE ProcessingFeeVat_master END AS ProcessingFeeVat,
        CASE WHEN packagetype = 'mandatoryPackages' THEN 0 ELSE ShippingFee_master END AS ShippingFee,
        CASE WHEN packagetype = 'mandatoryPackages' THEN 0 ELSE ShippingFeeVat_master END AS ShippingFeeVat,
        CASE 
            WHEN packagetype = 'mandatoryPackages' THEN TotalPremium 
            ELSE ROUND((TotalPremium) + TotalEIR + TotalSBT + ProcessingFee_master + ProcessingFeeVat_master + ShippingFee_master + ShippingFeeVat_master, 2) 
        END AS TotalAmount,
        CASE WHEN packagetype = 'mandatoryPackages' THEN 0 ELSE Discount_master END AS Discount,
        CASE 
            WHEN packagetype = 'mandatoryPackages' THEN TotalPremium 
            ELSE CASE WHEN compu_detail.gross_premium IS NULL THEN ActualReceived_master ELSE ROUND(ActualReceived_master - compu_detail.gross_premium, 2) END 
        END AS ActualReceived,
        0 AS InterestThisPeriod
    FROM onetime_master
    LEFT JOIN compu_detail ON compu_detail.order_id = onetime_master.human_id
    LEFT JOIN check_order_items ON check_order_items.OrderID = onetime_master.human_id 
    WHERE 1 = 1
    AND onetime_master.charges_id IN (SELECT DISTINCT charges_id FROM charge_one)
),

final AS (
  SELECT 
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
    TotalAmount,
    Discount,
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
    ActualReceived,
    InterestThisPeriod,
    PrincipleThisPeriod,
    InterestEIRThisPeriod,
    PrincipleEIRThisPeriod,
    CAST(FORMAT_DATE('%d%m%Y', PaymentDate) AS STRING) AS PaymentDate,
    Period,
    TotalPeriods,
    PendingPayment,
    `pacific-plating-282708.sap_integration_v3.fn_rcb_payment_mapping`(PaymentMethod, PaymentChannel).sap_payment_method AS PaymentMethod,
    `pacific-plating-282708.sap_integration_v3.fn_rcb_payment_mapping`(PaymentMethod, PaymentChannel).sap_payment_channel AS PaymentChannel,
    CAST(FORMAT_DATE('%d%m%Y', ExpectedDate) AS STRING) AS ExpectedDate,
    get_charges_ref.order_id AS RefOrder,
    RefundAmountBeforeFee,
    RefundAmountAfterFee,
    BillingAddress,
    CAST(FORMAT_DATE('%d%m%Y', BatchRunDate) AS STRING) AS BatchRunDate
  FROM onetime_master_go
  LEFT JOIN get_charges_ref 
    ON onetime_master_go.InvoiceNo = get_charges_ref.third_party_id 
    AND get_charges_ref.order_id != onetime_master_go.OrderID
)

SELECT * FROM final
;

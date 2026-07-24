-- BASELINE CAPTURE 2026-07-24 -- pulled verbatim from live BigQuery view definition
-- Object: sap_data_engineer.sap_fix_rcl_2025
-- Boat: fix the same A2 NULL-safe bug here, leave everything else as-is (not
-- confirmed live/nightly production like the other 4 objects, but fixing anyway).
-- See docs/knowledge/30_SAP_CHANGELOG.md (2026-07-24 entry) for the bug.

-- Final error-free SQL for SAP view `sap_fix_rcl_2025`
-- Preserves original columns & names

WITH
-- 1. Map successful third-party charges to orders
get_charges_ref AS (
  SELECT
    c.third_party_id,
    MIN(o.human_id) AS order_id
  FROM `pacific-plating-282708.careos.carepay_charges` AS c
  JOIN `pacific-plating-282708.careos.careos_orders` AS o
    ON o.payment = CONCAT('transactions/', c.transaction_id)
  WHERE
    c.service_provider != 'ICOLLECTION'
    AND c.status = 'SUCCESSFUL'
    AND c.third_party_id IS NOT NULL
    AND o.human_id IS NOT NULL
    AND c.create_time >= '2024-09-01'
  GROUP BY c.third_party_id
),
-- 2. Compulsory add-ons for first installment
takeaway_compulsary AS (
  SELECT
    snapshot_id,
    ROUND(add_ons / 100, 2) AS add_ons
  FROM `pacific-plating-282708.careos.carepay_transaction_snapshot_installment_details`
  WHERE period = 1
    AND add_ons IS NOT NULL
),
-- 3a. RCB voluntary installments
rcb_voluntary_installment_details AS (
  SELECT
    'rcb_voluntary_installment_details' AS CompanyDB,
    o.human_id                     AS OrderID,
    oi.human_id                    AS OrderItem,
    COALESCE(c.third_party_id, oi.human_id) AS InvoiceNo,
    FORMAT_DATE('%d%m%Y', o.create_time)     AS OrderDate,
    JSON_VALUE(o.data,'$.idNumber')           AS InsuredID,
    CASE JSON_VALUE(o.data,'$.policyHolder.title')
      WHEN 'KHUN' THEN 'คุณ'
      WHEN 'MISS' THEN 'นางสาว'
      WHEN 'MR'   THEN 'นาย'
      WHEN 'MRS'  THEN 'นาง'
      ELSE '' END                             AS Title,
    COALESCE(
      JSON_VALUE(o.data,'$.policyHolder.firstName'),
      JSON_VALUE(o.data,'$.policyHolder.policyAddress.companyName')
    )                                        AS FirstName,
    JSON_VALUE(o.data,'$.policyHolder.lastName')   AS LastName,
    oi.insurer                              AS InsurerCode,
    IF(oi.product='products/car-insurance','Motor',oi.product) AS InsuranceGroup,
    oi.motor_item_type                      AS InsuranceType,
    IF(oi.product='products/car-insurance','Motor',oi.product) AS InsuranceProduct,
    'Insurance'                             AS ProductType,
    CASE l.type WHEN 'LEAD_TYPE_RENEWAL' THEN 'R' ELSE 'N' END AS PolicyType,
    'N'                                     AS Endorse,
    FORMAT_DATE('%d%m%Y', oi.policy_start_date)      AS PolicyDate,
    oi.policy_number                       AS PolicyNo,
    ''                                      AS EndorsementNo,
    JSON_VALUE(o.data,'$.chassisNumber')   AS ChassisNo,
    JSON_VALUE(o.data,'$.carLicensePlate') AS LicensePlate,
    oi.net_premium                         AS GrossPremium,
    oi.stamp_duty                          AS StampDuty,
    oi.vat_amount                          AS VAT,
    oi.gross_premium                       AS TotalPremium,
    ROUND(ps.wht_amount/100,2)             AS WHT,
    CASE WHEN ps.interest_amount IS NULL THEN 0
      ELSE ROUND(ROUND(ps.interest_amount/100,2) - ROUND(ps.interest_amount/100,2)*3.3/103.3,2) END AS TotalEIR,
    CASE WHEN ps.interest_amount IS NULL THEN 0
      ELSE ROUND(ROUND(ps.interest_amount/100,2)*3.3/103.3,2) END AS TotalSBT,
    CASE WHEN ps.processing_fee_amount IS NULL THEN 0
      ELSE ROUND(ROUND(ps.processing_fee_amount/100,2)*100/103.3,2) END AS ProcessingFee,
    CASE WHEN ps.processing_fee_amount IS NULL THEN 0
      ELSE ROUND(ROUND(ps.processing_fee_amount/100,2) - ROUND(ps.processing_fee_amount/100,2)*100/103.3,2) END AS ProcessingFeeVat,
    CASE WHEN ps.shipment_fee IS NULL THEN 0
      ELSE ROUND(ROUND(ps.shipment_fee/100,2)*100/107,2) END AS ShippingFee,
    CASE WHEN ps.shipment_fee IS NULL THEN 0
      ELSE ROUND(ROUND(ps.shipment_fee/100,2) - ROUND(ps.shipment_fee/100,2)*100/107,2) END AS ShippingFeeVat,
    CASE WHEN tc.add_ons IS NOT NULL
      THEN ROUND((ps.net_premium_amount/100 - tc.add_ons) + ps.discount_amount/100,2)
      ELSE ROUND(ps.net_premium_amount/100 + ps.discount_amount/100,2)
    END                                     AS TotalAmount,
    ROUND(ps.discount_amount/100,2)         AS Discount,
    f.status                               AS TransactionStatus,
    oi.submission_status                   AS SubmissionStatus,
    oi.approval_status                     AS ApprovalStatus,
    CASE t.status WHEN 'SUCCESSFUL' THEN 'fully paid' WHEN 'PENDING' THEN 'Not fully paid' ELSE t.status END AS PaymentStatus,
    CASE WHEN d.period=1
      THEN ROUND(ROUND(d.payment_amount/100,2)-ROUND(d.add_ons/100,2),2)
      ELSE ROUND(d.payment_amount/100,2) END AS ExpectedReceived,
    CASE WHEN d.period=1
      THEN ROUND(ROUND(d.payment_amount/100,2)-ROUND(d.add_ons/100,2),2)
      ELSE ROUND(d.payment_amount/100,2) END AS ActualReceived,
    CASE WHEN ps.interest_amount=0 OR s.number_of_installment<=1 THEN 0
      WHEN d.period=1 THEN 0
      ELSE ROUND((ROUND(ps.interest_amount/100,2)-ROUND(ps.interest_amount/100,2)*3.3/103.3)/(s.number_of_installment-1),2) END AS InterestThisPeriod,
    CASE WHEN s.number_of_installment<=1 THEN 0
      WHEN d.period=1 THEN ROUND(d.principal/100,2)
      ELSE ROUND(ROUND(d.payment_amount/100,2)-((ROUND(ps.interest_amount/100,2)-ROUND(ps.interest_amount/100,2)*3.3/103.3)/(s.number_of_installment-1)),2) END AS PrincipleThisPeriod,
    ROUND(d.interest/100,2)                AS InterestEIRThisPeriod,
    ROUND(d.principal/100,2)               AS PrincipleEIRThisPeriod,
    FORMAT_DATE('%d%m%Y', c.update_time)   AS PaymentDate,
    d.period                               AS Period,
    s.number_of_installment                AS TotalPeriods,
    ROUND(d.principal_balance/100,2)       AS PendingPayment,
    c.payment_method                       AS PaymentMethod,
    CASE
      WHEN oi.motor_item_type='MOTOR_TYPE_COMPULSORY' THEN 'RCL-CMI-channel'
      WHEN c.payment_method='CASH' THEN 'TRF Transfer'
      WHEN c.payment_method='QR_CODE' THEN 'OME Omise QR Prompt Pay'
      ELSE c.payment_method END              AS PaymentChannel,
    FORMAT_DATE('%d%m%Y', f.due_date)      AS ExpectedDate,
    ''                                      AS RefOrder,
    ROUND(r.amount*100/107,2)             AS RefundAmountBeforeFee,
    r.amount                               AS RefundAmountAfterFee,
    CASE WHEN JSON_VALUE(o.data,'$.policyHolder.policyAddress.isBillingAddress')='true' THEN
      CONCAT(
        COALESCE(JSON_VALUE(o.data,'$.policyHolder.policyAddress.fullName'),JSON_VALUE(o.data,'$.policyHolder.policyAddress.companyName')),
        ', ',JSON_VALUE(o.data,'$.policyHolder.policyAddress.address'),', ',
        JSON_VALUE(o.data,'$.policyHolder.policyAddress.subDistrict'),', ',
        JSON_VALUE(o.data,'$.policyHolder.policyAddress.district'),', ',
        JSON_VALUE(o.data,'$.policyHolder.policyAddress.province'),', ',
        JSON_VALUE(o.data,'$.policyHolder.policyAddress.postCode')
      ) ELSE
      CONCAT(
        JSON_VALUE(o.data,'$.policyHolder.billingAddress.fullName'),', ',
        JSON_VALUE(o.data,'$.policyHolder.billingAddress.address'),', ',
        JSON_VALUE(o.data,'$.policyHolder.billingAddress.subDistrict'),', ',
        JSON_VALUE(o.data,'$.policyHolder.billingAddress.district'),', ',
        JSON_VALUE(o.data,'$.policyHolder.billingAddress.province'),', ',
        JSON_VALUE(o.data,'$.policyHolder.billingAddress.postCode')
      ) END                                 AS BillingAddress,
    FORMAT_DATE('%d%m%Y', CURRENT_DATE()) AS BatchRunDate
  FROM `pacific-plating-282708.careos.careos_orders`                     AS o
  LEFT JOIN `pacific-plating-282708.careos.careos_leads`                 AS l ON CONCAT('leads/',l.id)=o.lead
  LEFT JOIN `pacific-plating-282708.careos.carepay_transactions`         AS t ON CONCAT('transactions/',t.id)=o.payment
  LEFT JOIN `pacific-plating-282708.careos.carepay_transaction_snapshots` AS s ON s.transaction_id=t.id
  LEFT JOIN `pacific-plating-282708.careos.carepay_transaction_snapshot_price_summaries` AS ps ON ps.snapshot_id=s.id
  LEFT JOIN `pacific-plating-282708.careos.carepay_transaction_snapshot_installment_details` AS d ON d.snapshot_id=s.id
  LEFT JOIN `pacific-plating-282708.careos.carepay_charges`            AS c ON c.transaction_id=t.id AND c.installment_number=d.period AND c.status NOT IN('FAILED','PENDING')
  LEFT JOIN `pacific-plating-282708.careos.careos_order_items`          AS oi ON oi.order_id=o.id
  LEFT JOIN `pacific-plating-282708.careos.carepay_refunds`             AS r ON r.transaction_id=t.id
  LEFT JOIN `pacific-plating-282708.careos.carepay_follow_ups`          AS f ON f.transaction_id=t.id AND f.installment=d.period
  LEFT JOIN takeaway_compulsary                                          AS tc ON tc.snapshot_id=s.id
  WHERE d.id IS NOT NULL
    AND (oi.motor_item_type != 'MOTOR_TYPE_COMPULSORY' OR oi.motor_item_type IS NULL)  -- A2 fix 2026-07-24
    AND f.transaction_id IS NULL
    AND o.create_time >= '2025-01-01'
),
-- 3b. RCL voluntary installments (override insured_id)
rcl_voluntary_installment_details AS (
  SELECT
    * EXCEPT(InsuredID),
    CASE WHEN JSON_VALUE(o.data,'$.policyHolder.isCompany')='true'
      THEN JSON_VALUE(o.data,'$.policyHolder.companyTaxId')
      ELSE InsuredID END AS InsuredID
  FROM rcb_voluntary_installment_details AS rcb
  JOIN `pacific-plating-282708.careos.careos_orders` AS o
    ON rcb.OrderID=o.human_id
),
-- 3c. Compulsory installments
compulsary_installment_details AS (
  -- similar to rcb but all fees=0, periods=1, join logic identical
  SELECT *
  FROM rcb_voluntary_installment_details
  WHERE OrderItem LIKE '%-V1' -- placeholder for compulsory logic
),
-- 4. Combine
combine AS (
  -- 4a. RCB voluntary
  SELECT
    CompanyDB, OrderID, OrderItem, InvoiceNo, OrderDate, InsuredID, Title,
    FirstName, LastName, InsurerCode, InsuranceGroup, InsuranceType,
    InsuranceProduct, ProductType, PolicyType, Endorse, PolicyDate,
    PolicyNo, EndorsementNo, ChassisNo, LicensePlate, GrossPremium,
    StampDuty, VAT, TotalPremium, WHT, TotalEIR, TotalSBT,
    ProcessingFee, ProcessingFeeVat, ShippingFee, ShippingFeeVat,
    TotalAmount, Discount, TransactionStatus, SubmissionStatus,
    ApprovalStatus, PaymentStatus, ExpectedReceived, ActualReceived,
    InterestThisPeriod, PrincipleThisPeriod, InterestEIRThisPeriod,
    PrincipleEIRThisPeriod, PaymentDate, Period, TotalPeriods,
    PendingPayment, PaymentMethod, PaymentChannel, ExpectedDate,
    RefOrder, RefundAmountBeforeFee, RefundAmountAfterFee,
    BillingAddress, BatchRunDate
  FROM rcb_voluntary_installment_details
  UNION ALL
  -- 4b. RCL voluntary: match columns exactly, reuse RCB defaults for missing
  SELECT
    CompanyDB, OrderID, OrderItem, InvoiceNo, OrderDate,
    InsuredID, Title, FirstName, LastName, InsurerCode,
    InsuranceGroup, InsuranceType, InsuranceProduct, ProductType,
    PolicyType, Endorse, PolicyDate, PolicyNo, EndorsementNo,
    ChassisNo, LicensePlate, GrossPremium, StampDuty, VAT,
    TotalPremium, WHT, TotalEIR, TotalSBT, ProcessingFee,
    ProcessingFeeVat, ShippingFee, ShippingFeeVat, TotalAmount,
    Discount, TransactionStatus, SubmissionStatus, ApprovalStatus,
    PaymentStatus, ExpectedReceived, ActualReceived,
    InterestThisPeriod, PrincipleThisPeriod, InterestEIRThisPeriod,
    PrincipleEIRThisPeriod, PaymentDate, Period, TotalPeriods,
    PendingPayment, PaymentMethod, PaymentChannel, ExpectedDate,
    RefOrder, RefundAmountBeforeFee, RefundAmountAfterFee,
    BillingAddress, BatchRunDate
  FROM rcl_voluntary_installment_details
  UNION ALL
  -- 4c. Compulsory: same structure, zero fees and single period
  SELECT
    CompanyDB, OrderID, OrderItem, InvoiceNo, OrderDate,
    InsuredID, Title, FirstName, LastName, InsurerCode,
    InsuranceGroup, InsuranceType, InsuranceProduct, ProductType,
    PolicyType, Endorse, PolicyDate, PolicyNo, EndorsementNo,
    ChassisNo, LicensePlate, GrossPremium, StampDuty, VAT,
    TotalPremium, WHT, TotalEIR, TotalSBT, 0         AS ProcessingFee,
    0         AS ProcessingFeeVat, 0       AS ShippingFee,
    0         AS ShippingFeeVat, TotalPremium  AS TotalAmount,
    0         AS Discount, TransactionStatus,
    SubmissionStatus, ApprovalStatus, PaymentStatus,
    ExpectedReceived, ActualReceived, InterestThisPeriod,
    PrincipleThisPeriod, InterestEIRThisPeriod,
    PrincipleEIRThisPeriod, PaymentDate, 1        AS Period,
    1        AS TotalPeriods, 0        AS PendingPayment,
    PaymentMethod, PaymentChannel, ExpectedDate,
    RefOrder, RefundAmountBeforeFee, RefundAmountAfterFee,
    BillingAddress, BatchRunDate
  FROM compulsary_installment_details
),

-- then proceed with rest of script using `combine` as before

-- 5. Attach ref_order & safe-guard
transformation_xxx AS (
  SELECT
    c.* EXCEPT(RefOrder),
    IFNULL(g.order_id,'') AS RefOrder
  FROM combine AS c
  LEFT JOIN get_charges_ref AS g
    ON c.InvoiceNo=g.third_party_id AND g.order_id!=c.OrderID
),
-- 6. First EIR reallocation
arrange AS (
  SELECT OrderItem, ROUND(SUM(InterestEIRThisPeriod),2) AS total_eir_allocated
  FROM transformation_xxx
  GROUP BY OrderItem
),
finish AS (
  SELECT
    t.* EXCEPT(InterestEIRThisPeriod),
    CASE
      WHEN a.total_eir_allocated<>t.TotalEIR AND t.Period<>1 AND t.TotalPeriods>1
      THEN ABS(ROUND(t.InterestEIRThisPeriod - SAFE_DIVIDE(t.TotalSBT,t.TotalPeriods-1),2))
      ELSE t.InterestEIRThisPeriod END AS InterestEIRThisPeriod
  FROM transformation_xxx AS t
  LEFT JOIN arrange AS a ON t.OrderItem=a.OrderItem
),
-- 7. Second EIR reallocation
arrange_again AS (
  SELECT OrderItem, ROUND(SUM(InterestEIRThisPeriod),2) AS total_eir_allocated
  FROM finish GROUP BY OrderItem
),
finish_2 AS (
  SELECT
    f.* EXCEPT(InterestEIRThisPeriod),
    CASE
      WHEN ag.total_eir_allocated<>f.TotalEIR AND f.TotalPeriods>1
      THEN CASE WHEN f.Period=f.TotalPeriods
        THEN ROUND(f.InterestEIRThisPeriod - (ag.total_eir_allocated-f.TotalEIR),2)
        ELSE f.InterestEIRThisPeriod END
      ELSE f.InterestEIRThisPeriod END AS InterestEIRThisPeriod
  FROM finish AS f
  LEFT JOIN arrange_again AS ag ON f.OrderItem=ag.OrderItem
)
SELECT
  CompanyDB,OrderID,OrderItem,InvoiceNo,OrderDate,InsuredID,Title,FirstName,LastName,
  InsurerCode,InsuranceGroup,InsuranceType,InsuranceProduct,ProductType,PolicyType,Endorse,
  PolicyDate,PolicyNo,EndorsementNo,ChassisNo,LicensePlate,GrossPremium,StampDuty,VAT,TotalPremium,
  WHT,TotalEIR,TotalSBT,ProcessingFee,ProcessingFeeVat,ShippingFee,ShippingFeeVat,TotalAmount,
  Discount,TransactionStatus,SubmissionStatus,ApprovalStatus,PaymentStatus,ExpectedReceived,ActualReceived,
  InterestThisPeriod,PrincipleThisPeriod,InterestEIRThisPeriod,PrincipleEIRThisPeriod,PaymentDate,
  Period,TotalPeriods,PendingPayment,PaymentMethod,PaymentChannel,ExpectedDate,RefOrder,
  RefundAmountBeforeFee,RefundAmountAfterFee,BillingAddress,BatchRunDate
FROM finish_2
ORDER BY OrderDate DESC
--LIMIT 10;


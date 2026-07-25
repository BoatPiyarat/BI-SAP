-- 009_fix_rcl_newpayment_date_override.sql
-- Boat, 2026-07-25: "I'm not sure about the current RCL_Motor_process_2_newpayment /
-- RCL_NonMotor_process_2_newpayment logic of payment date, it can be only in current month.
-- If the actual payment date on charge table is older than current month you can override to
-- 1st date of current month, you had the SAP interface rules"
--
-- Matches the real SAP import error log Boat shared (2026-07-16 cancel batch):
-- "PaymentDate:Posting Periods must be Unlocked,PaymentDate:RCL Posting Periods must be Unlocked" -
-- SAP's accounting posting-period lock rejects any transaction dated into an already-closed
-- period, permanently. Our export has been sending the real historical charge date (e.g. April,
-- May, June for periods paid months ago) - once that month's posting period closes on SAP's
-- side, every nightly resend fails the same way forever. Overriding to the 1st of the CURRENT
-- month for any PaymentDate older than the current month keeps every post inside the
-- currently-open period.
--
-- Applied as a thin outer wrapper (* EXCEPT(PaymentDate), <override> AS PaymentDate) around each
-- view's existing, unmodified logic - does not touch anything else about row selection.
-- CSV column headers are derived from query_job.schema at export time (see
-- rcb-motor-order-payment-sap-bucket-1 / rcb-nonmotor-order-payment-sap-bucket-1 main.py), so
-- moving PaymentDate to the end of the column list is safe - column order is not assumed.

CREATE OR REPLACE VIEW `pacific-plating-282708.sap_view.RCL_Motor_process_2_newpayment` AS
WITH base AS (
--new payment BY period
    WITH
        interface AS (
            SELECT
                *
            FROM
                `pacific-plating-282708.sap_integration_v2.RCL 05_paid` paid
            UNION ALL
            SELECT
                *
            FROM
                `pacific-plating-282708.sap_integration_v2.RCL 05_newpayment`
        ),
        cmi AS (
            SELECT
                human_id order_item,
                *
            FROM
                `pacific-plating-282708.careos.careos_order_items`
            WHERE
                DATE (create_time) < DATE (DATE_TRUNC (CURRENT_DATE(), MONTH))
                AND motor_item_type = 'MOTOR_TYPE_COMPULSORY'
        )
    SELECT DISTINCT
        *
    FROM
        interface
    WHERE OrderItem IN (
            SELECT DISTINCT OrderItem
            FROM `pacific-plating-282708.sap_integration_v2.RCL 05_paid by period`)

        AND NOT EXISTS (
            SELECT DISTINCT
                order_item
            FROM
                cmi
            WHERE
                interface.OrderItem = cmi.human_id
        )
        AND OrderID NOT IN (
            SELECT
                current_human_id
            FROM
                `pacific-plating-282708.careos.cancelled_change_orders`
        )
        AND (
            PaymentChannel NOT LIKE '%RCB%'
            OR PaymentChannel IS NULL
        )
        --AND OrderDate LIKE '%092024%'
)
SELECT
  * EXCEPT(PaymentDate),
  CASE
    WHEN PaymentDate IS NULL OR PaymentDate = '' THEN PaymentDate
    WHEN PARSE_DATE('%d%m%Y', PaymentDate) < DATE_TRUNC(CURRENT_DATE(), MONTH)
      THEN FORMAT_DATE('%d%m%Y', DATE_TRUNC(CURRENT_DATE(), MONTH))
    ELSE PaymentDate
  END AS PaymentDate
FROM base
ORDER BY
    OrderID,
    OrderItem,
    Period;

CREATE OR REPLACE VIEW `pacific-plating-282708.sap_view.RCL_NonMotor_process_2_newpayment` AS
WITH base AS (
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
    SPLIT(U_InsurerCode, '-')[OFFSET(1)] AS InsurerCode,
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
    CAST(EndorsementNo AS STRING) EndorsementNo,  -- fix 2026-07-25: was U_EndorsementNo, doesn't exist (query wouldn't even parse before this)
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
    TransactionStatus,
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
    CAST(RefundAmountBeforeFee AS STRING) RefundAmountBeforeFee,
    CAST(RefundAmountAfterFee AS STRING) RefundAmountAfterFee,
    BillingAddress BillingAddress,
    CAST(FORMAT_DATE('%d%m%Y', CURRENT_DATE()) AS STRING)  AS BatchRunDate,
    CONCAT(U_OrderItem,U_Period) keys
  FROM
    `pacific-plating-282708.sap_integration_v2.SAP_LIVE_FULL`
  WHERE U_InsuranceGroup NOT IN ( 'Motor', 'Corporate')
  AND PolicyDate NOT LIKE '%2023%'
  AND PolicyDate NOT LIKE '%2024%'),

  cancelled AS (  SELECT distinct U_OrderItem
  FROM `pacific-plating-282708.sap_integration_v2.SAP_LIVE_FULL`
  WHERE U_OrderID like '%C%'
  OR TransactionStatus in ('Cancelled','Cancelled (Change order / Rejected)')
),

  newpayment AS (
  SELECT
    U_OrderItem order_item,
    MAX(U_Period) installment_number
  FROM
    `pacific-plating-282708.sap_integration_v2.RCL 05-1_paid by period_NonMotor` p INNER JOIN
    `pacific-plating-282708.sap_integration_v2.SAP_LIVE_FULL` s
  ON p.order_item = s.U_OrderItem
  WHERE
  (s.TransactionStatus in ('Paid', 'paid') )
  AND DATE(p.charges_update_time) BETWEEN '2025-11-01' AND '2026-12-31'
  GROUP BY U_OrderItem
  ),

interface AS (
  SELECT
    *, CONCAT(OrderItem,Period) keys,
    SAFE_CAST(Period AS INT64) AS careos_installment
  FROM `pacific-plating-282708.sap_data_engineer.RCL_HEALTH`
),

combine AS (SELECT
  sap.* except(keys)
FROM sap
JOIN newpayment
ON sap.OrderItem = newpayment.order_item
WHERE
  sap.Period <= newpayment.installment_number
AND OrderID NOT LIKE '%_X%'
AND OrderID NOT LIKE 'C#%'
AND PaymentDate IS NOT NULL
AND PaymentDate <> ''

UNION ALL

SELECT
  interface.* except(keys,careos_installment)
FROM interface
JOIN newpayment
  ON interface.OrderItem = newpayment.order_item
WHERE
  interface.careos_installment > newpayment.installment_number
AND OrderID NOT LIKE '%_X%'
AND OrderID NOT LIKE 'C#%'
)

SELECT *
FROM combine
WHERE LOWER(FirstName) <> 'test'
)
SELECT
  * EXCEPT(PaymentDate),
  CASE
    WHEN PaymentDate IS NULL OR PaymentDate = '' THEN PaymentDate
    WHEN PARSE_DATE('%d%m%Y', PaymentDate) < DATE_TRUNC(CURRENT_DATE(), MONTH)
      THEN FORMAT_DATE('%d%m%Y', DATE_TRUNC(CURRENT_DATE(), MONTH))
    ELSE PaymentDate
  END AS PaymentDate
FROM base
ORDER BY OrderItem, Period;

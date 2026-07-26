-- 019_fix_column_reordering_bug.sql
-- URGENT FIX (Boat, 2026-07-26): "this is interface column, I know the root cause. Your backfill
-- file reordering column."
--
-- The real root cause of tonight's "Conversion failed when converting the nvarchar value 'X' to
-- data type int" failures (both my backfill AND, critically, tonight's real automated NonMotor
-- production run - since the Cloud Function reads from the same production view I modified
-- earlier today): `009_fix_rcl_newpayment_date_override.sql` used
-- `SELECT * EXCEPT(PaymentDate), <expr> AS PaymentDate FROM base` to apply the posting-period
-- date override. In BigQuery, `* EXCEPT(col)` followed by re-adding that column as a new
-- expression MOVES that column to the END of the output - it does not preserve its original
-- position. Since SAP's import is column-position-based (not header-name-based), moving
-- PaymentDate out of its real position (between PaymentStatus/ActualReceived-adjacent fields and
-- Period/TotalPeriods) shifted every subsequent column by one, eventually landing a decimal value
-- in an Int-typed destination column (Period or TotalPeriods) - exactly matching the error.
--
-- This means the earlier ExpectedReceived hypothesis (still-unconfirmed, in the superseded
-- 019_remove_expectedreceived_column.sql draft) was very likely a red herring - the real bug was
-- my own column-order corruption, introduced when I deployed 009 tonight. That fix has been live
-- in the actual production views (sap_view.RCL_Motor_process_2_newpayment,
-- sap_view.RCL_NonMotor_process_2_newpayment) since earlier today, so tonight's real automated
-- NonMotor newpayment failure is very likely a direct consequence of this bug, not a pre-existing
-- production issue.
--
-- Fix: use `SELECT * REPLACE(<expr> AS PaymentDate) FROM base` instead - this overwrites
-- PaymentDate's value in place, preserving its original column position exactly. No other change
-- from what 009 intended (still: PaymentDate older than current month -> 1st of current month).
-- ExpectedReceived is left untouched (reverting that speculative removal) until independently
-- confirmed necessary.
--
-- Separate, unrelated issue hit while redeploying: `sap_data_engineer.RCL_HEALTH` now has 56
-- columns but the NonMotor view's `sap` CTE only defined 55 - missing `InsuranceProduct` (real
-- source: SAP_LIVE_FULL's `U_InsuranceProduct`). This must have drifted since this view last
-- deployed successfully earlier today (RCL_HEALTH is an external table, not something this
-- session touches) - added back in the correct position to restore the UNION ALL column-count
-- match between the `sap` and `interface` branches.

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
SELECT * REPLACE(
  CASE
    WHEN PaymentDate IS NULL OR PaymentDate = '' THEN PaymentDate
    WHEN PARSE_DATE('%d%m%Y', PaymentDate) < DATE_TRUNC(CURRENT_DATE(), MONTH)
      THEN FORMAT_DATE('%d%m%Y', DATE_TRUNC(CURRENT_DATE(), MONTH))
    ELSE PaymentDate
  END AS PaymentDate
)
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
    CAST(EndorsementNo AS STRING) EndorsementNo,
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
SELECT * REPLACE(
  CASE
    WHEN PaymentDate IS NULL OR PaymentDate = '' THEN PaymentDate
    WHEN PARSE_DATE('%d%m%Y', PaymentDate) < DATE_TRUNC(CURRENT_DATE(), MONTH)
      THEN FORMAT_DATE('%d%m%Y', DATE_TRUNC(CURRENT_DATE(), MONTH))
    ELSE PaymentDate
  END AS PaymentDate
)
FROM base
ORDER BY OrderItem, Period;

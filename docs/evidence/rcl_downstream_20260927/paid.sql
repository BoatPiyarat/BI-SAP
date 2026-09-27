-- RCL 05_paid -- FIXED & TUNED VERSION

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

    `pacific-plating-282708.sap_integration_v2.SAP_LIVE_FULL`

    WHERE PaymentChannel LIKE '%RCL%'),



  cancelled AS (  SELECT distinct U_OrderItem

  FROM `pacific-plating-282708.sap_integration_v2.SAP_LIVE_FULL`

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



Order by OrderID, Period

-- Full source-only legacy root-fix proposal for:
--   pacific-plating-282708.sap_view.RCB_Motor_process_2_cancel_new
--
-- Root fixes from SAP Upload LogID 22049:
--   1. Emit only one current SAP document per (OrderItem, Period), using the
--      established status/invoice/date/DocEntry precedence.
--   2. Require the complete 1..TotalPeriods spine to exist in SAP already.
--      Do not synthesize missing periods from the CareOS dashboard and attempt
--      to cancel them in the same file. Such items wait for a separate
--      create/pending -> SAP refresh -> cancel sequence.
--   3. Hold the whole item when SAP is Pending but CareOS already has a
--      SUCCESSFUL charge for that period. Paid must reach SAP first.
--   4. Require Period 1 to be Paid and all later predecessor rows to be
--      Paid/Pending, matching the SAP cancel contract.
--   5. Normalize SQL NULL, blank, and literal NULL ProductType to Insurance.
--   6. Hold material TotalEIR-versus-period-interest inconsistencies; do not
--      rewrite historical accounting values. For valid items, canonicalize the
--      harmless <= 0.01 rounding difference to the period-interest sum.
--   7. Preserve SAP InvoiceNo/PaymentDate and Pending amounts verbatim; Pending
--      PaymentMethod and PaymentChannel remain blank.
--   8. Scope by the 2026 CareOS cancellation event, not original OrderDate, and
--      exclude Test items. is_cancelled=true with NULL cancel_time remains held
--      for human investigation.
--
-- SELECT only: this file does not replace or deploy the live legacy view.

WITH
  sap_distinct AS (
    SELECT DISTINCT *
    FROM `pacific-plating-282708.sap_integration_v2.SAP_LIVE_FULL`
  ),

  sap_ranked AS (
    SELECT
      sap_distinct.*,
      ROW_NUMBER() OVER (
        PARTITION BY U_OrderItem, SAFE_CAST(U_Period AS INT64)
        ORDER BY
          CASE
            WHEN TransactionStatus IN ('Cancelled', 'Cancelled (Change order / Rejected)') THEN 0
            WHEN LOWER(TransactionStatus) = 'paid' THEN 1
            WHEN LOWER(TransactionStatus) = 'pending' THEN 2
            ELSE 3
          END,
          CASE
            WHEN NULLIF(TRIM(COALESCE(U_InvoiceNo, '')), '') IS NOT NULL
              AND UPPER(TRIM(U_InvoiceNo)) != 'NULL'
            THEN 0 ELSE 1
          END,
          SAFE.PARSE_DATE('%d%m%Y', NULLIF(BatchRunDate, '')) DESC,
          DocEntry DESC
      ) AS current_doc_rank,
      MAX(
        CASE
          WHEN U_OrderID LIKE 'C#%'
            OR TransactionStatus IN ('Cancelled', 'Cancelled (Change order / Rejected)')
          THEN 1 ELSE 0
        END
      ) OVER (PARTITION BY U_OrderItem) AS is_already_cancelled_flag
    FROM sap_distinct
    WHERE U_OrderItem IS NOT NULL
      AND U_Period IS NOT NULL
  ),

  sap_current AS (
    SELECT * EXCEPT (current_doc_rank)
    FROM sap_ranked
    WHERE current_doc_rank = 1
  ),

  cancelled_items_2026 AS (
    SELECT
      order_item.human_id AS OrderItem,
      orders.human_id AS CareOSOrderID,
      transactions.id AS transaction_id,
      order_item.cancel_time
    FROM `pacific-plating-282708.careos.careos_order_items` AS order_item
    JOIN `pacific-plating-282708.careos.careos_orders` AS orders
      ON orders.id = order_item.order_id
    LEFT JOIN `pacific-plating-282708.careos.carepay_transactions` AS transactions
      ON CONCAT('transactions/', transactions.id) = orders.payment
    WHERE order_item.cancel_time IS NOT NULL
      AND DATE(order_item.cancel_time) >= DATE '2026-01-01'
  ),

  base_eligible_items AS (
    SELECT DISTINCT sap_current.U_OrderItem AS OrderItem
    FROM sap_current
    JOIN cancelled_items_2026
      ON cancelled_items_2026.OrderItem = sap_current.U_OrderItem
    WHERE sap_current.is_already_cancelled_flag = 0
      AND sap_current.U_OrderID NOT LIKE 'C#%'
      AND sap_current.U_OrderID NOT LIKE '%_X%'
      AND NOT EXISTS (
        SELECT 1
        FROM sap_current AS test_row
        WHERE test_row.U_OrderItem = sap_current.U_OrderItem
          AND (
            LOWER(TRIM(COALESCE(test_row.U_FirstName, ''))) = 'test'
            OR LOWER(TRIM(COALESCE(test_row.U_LastName, ''))) = 'test'
          )
      )
  ),

  spine_metrics AS (
    SELECT
      sap_current.U_OrderItem AS OrderItem,
      COUNT(*) AS row_count,
      COUNT(DISTINCT SAFE_CAST(sap_current.U_Period AS INT64)) AS distinct_period_count,
      MIN(SAFE_CAST(sap_current.U_Period AS INT64)) AS min_period,
      MAX(SAFE_CAST(sap_current.U_Period AS INT64)) AS max_period,
      MAX(SAFE_CAST(sap_current.TotalPeriods AS INT64)) AS canonical_total_periods,
      COUNTIF(
        SAFE_CAST(sap_current.U_Period AS INT64) = 1
          AND LOWER(sap_current.TransactionStatus) = 'paid'
      ) AS paid_first_period_rows,
      COUNTIF(
        LOWER(sap_current.TransactionStatus) NOT IN ('paid', 'pending')
      ) AS invalid_predecessor_rows,
      MAX(COALESCE(SAFE_CAST(sap_current.TotalEIR AS FLOAT64), 0)) AS max_total_eir,
      MIN(COALESCE(SAFE_CAST(sap_current.TotalEIR AS FLOAT64), 0)) AS min_total_eir,
      ROUND(SUM(COALESCE(SAFE_CAST(sap_current.U_InterestEIRThisPeriod AS FLOAT64), 0)), 2)
        AS period_interest_eir_sum
    FROM sap_current
    JOIN base_eligible_items
      ON base_eligible_items.OrderItem = sap_current.U_OrderItem
    GROUP BY sap_current.U_OrderItem
  ),

  stale_pending_paid_items AS (
    SELECT DISTINCT sap_current.U_OrderItem AS OrderItem
    FROM sap_current
    JOIN base_eligible_items
      ON base_eligible_items.OrderItem = sap_current.U_OrderItem
    JOIN cancelled_items_2026
      ON cancelled_items_2026.OrderItem = sap_current.U_OrderItem
    JOIN `pacific-plating-282708.careos.carepay_charges` AS charge
      ON charge.transaction_id = cancelled_items_2026.transaction_id
     AND charge.installment_number = SAFE_CAST(sap_current.U_Period AS INT64)
     AND charge.status = 'SUCCESSFUL'
    WHERE LOWER(sap_current.TransactionStatus) = 'pending'
  ),

  ready_items AS (
    SELECT
      spine_metrics.OrderItem,
      spine_metrics.canonical_total_periods,
      spine_metrics.period_interest_eir_sum AS canonical_total_eir
    FROM spine_metrics
    WHERE spine_metrics.canonical_total_periods >= 1
      AND spine_metrics.row_count = spine_metrics.canonical_total_periods
      AND spine_metrics.distinct_period_count = spine_metrics.canonical_total_periods
      AND spine_metrics.min_period = 1
      AND spine_metrics.max_period = spine_metrics.canonical_total_periods
      AND spine_metrics.paid_first_period_rows = 1
      AND spine_metrics.invalid_predecessor_rows = 0
      AND ABS(spine_metrics.max_total_eir - spine_metrics.min_total_eir) <= 0.01
      AND ABS(spine_metrics.max_total_eir - spine_metrics.period_interest_eir_sum) <= 0.01
      AND NOT EXISTS (
        SELECT 1
        FROM stale_pending_paid_items AS stale
        WHERE stale.OrderItem = spine_metrics.OrderItem
      )
  )

SELECT
  sap.CompanyDB,
  sap.U_OrderID AS OrderID,
  sap.U_OrderItem AS OrderItem,
  CASE
    WHEN UPPER(TRIM(COALESCE(sap.U_InvoiceNo, ''))) = 'NULL' THEN ''
    ELSE COALESCE(sap.U_InvoiceNo, '')
  END AS InvoiceNo,
  sap.OrderDate,
  sap.U_InsuredID AS InsuredID,
  sap.U_Title AS Title,
  sap.U_FirstName AS FirstName,
  sap.U_LastName AS LastName,
  COALESCE(SPLIT(sap.U_InsurerCode, '-')[SAFE_OFFSET(1)], sap.U_InsurerCode) AS InsurerCode,
  sap.U_InsuranceGroup AS InsuranceGroup,
  sap.U_InsuranceType AS InsuranceType,
  sap.U_InsuranceProduct AS InsuranceProduct,
  CASE
    WHEN NULLIF(TRIM(COALESCE(sap.U_ProductType, '')), '') IS NULL
      OR UPPER(TRIM(sap.U_ProductType)) = 'NULL'
    THEN 'Insurance'
    ELSE sap.U_ProductType
  END AS ProductType,
  sap.U_PolicyType AS PolicyType,
  'N' AS Endorse,
  sap.PolicyDate,
  sap.U_PolicyNo AS PolicyNo,
  sap.EndorsementNo,
  sap.U_ChassisNo AS ChassisNo,
  sap.U_LicensePlate AS LicensePlate,
  sap.GrossPremium,
  sap.StampDuty,
  sap.VAT,
  sap.TotalPremium,
  sap.WHT,
  ready_items.canonical_total_eir AS TotalEIR,
  sap.TotalSBT,
  sap.U_ProcessingFee AS ProcessingFee,
  sap.U_ProcessingFeeVat AS ProcessingFeeVat,
  sap.U_ShippingFee AS ShippingFee,
  sap.U_ShippingFeeVat AS ShippingFeeVat,
  sap.U_TotalAmount AS TotalAmount,
  sap.U_Discount AS Discount,
  CASE
    WHEN EXISTS (
      SELECT 1
      FROM `pacific-plating-282708.careos.cancelled_change_orders` AS change_order
      WHERE change_order.old_human_id = sap.U_OrderID
    )
    THEN 'Cancelled (Change order / Rejected)'
    ELSE 'Cancelled'
  END AS TransactionStatus,
  sap.U_SubmissionStatus AS SubmissionStatus,
  sap.U_ApprovalStatus AS ApprovalStatus,
  sap.U_PaymentStatus AS PaymentStatus,
  COALESCE(sap.ExpectedReceived, 0) AS ExpectedReceived,
  COALESCE(sap.U_ActualReceived, 0) AS ActualReceived,
  COALESCE(sap.U_InterestThisPeriod, 0) AS InterestThisPeriod,
  COALESCE(sap.U_PrincipleThisPeriod, 0) AS PrincipleThisPeriod,
  COALESCE(sap.U_InterestEIRThisPeriod, 0) AS InterestEIRThisPeriod,
  COALESCE(sap.U_PrincipleEIRThisPeriod, 0) AS PrincipleEIRThisPeriod,
  CASE
    WHEN UPPER(TRIM(COALESCE(sap.PaymentDate, ''))) = 'NULL' THEN ''
    ELSE COALESCE(sap.PaymentDate, '')
  END AS PaymentDate,
  SAFE_CAST(sap.U_Period AS INT64) AS Period,
  ready_items.canonical_total_periods AS TotalPeriods,
  sap.PendingPayment,
  CASE
    WHEN LOWER(sap.TransactionStatus) = 'pending' THEN ''
    WHEN UPPER(TRIM(COALESCE(sap.PaymentMethod, ''))) = 'NULL' THEN ''
    ELSE COALESCE(sap.PaymentMethod, '')
  END AS PaymentMethod,
  CASE
    WHEN LOWER(sap.TransactionStatus) = 'pending' THEN ''
    WHEN UPPER(TRIM(COALESCE(sap.PaymentChannel, ''))) = 'NULL' THEN ''
    WHEN sap.PaymentChannel = 'Credit Shell' THEN 'RCB-Credit Shell'
    ELSE COALESCE(sap.PaymentChannel, '')
  END AS PaymentChannel,
  COALESCE(
    NULLIF(NULLIF(TRIM(sap.ExpectedDate), ''), 'NULL'),
    NULLIF(NULLIF(TRIM(sap.PaymentDate), ''), 'NULL'),
    FORMAT_DATE('%d%m%Y', CURRENT_DATE())
  ) AS ExpectedDate,
  sap.RefOrder,
  sap.RefundAmountBeforeFee,
  sap.RefundAmountAfterFee,
  sap.BillingAddress,
  FORMAT_DATE('%d%m%Y', CURRENT_DATE()) AS BatchRunDate
FROM sap_current AS sap
JOIN ready_items
  ON ready_items.OrderItem = sap.U_OrderItem
WHERE sap.U_OrderID NOT IN ('L80625878', 'L78637687')
ORDER BY OrderItem, Period, InvoiceNo;

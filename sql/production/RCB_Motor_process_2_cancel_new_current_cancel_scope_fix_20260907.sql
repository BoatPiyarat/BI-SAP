-- Full source-only legacy proposal for:
--   pacific-plating-282708.sap_view.RCB_Motor_process_2_cancel_new
--
-- Root fixes:
--   1. Keep SAP_LIVE_FULL as the authoritative source for periods already present in SAP.
--   2. For an SAP-present cancelled item whose SAP period spine is incomplete, supplement only
--      missing periods from the existing complete sap_dashboard_carepay_installment schedule.
--   3. Canonicalize TotalPeriods to the largest observed schedule value per item so historical
--      one-period rows can coexist with a later legitimate installment schedule.
--   4. Preserve legitimate duplicate-period payment rows; remove only exact full-row duplicates.
--   5. Scope every item by its 2026 cancellation event, not the original OrderDate year.
--   6. Exclude Test customer rows from the universal cancel interface.
--
-- SELECT only: this file does not replace or deploy the legacy view.

WITH
  sap_distinct AS (
    SELECT DISTINCT *
    FROM `pacific-plating-282708.sap_integration_v2.SAP_LIVE_FULL`
  ),

  sap_scan AS (
    SELECT
      *,
      ROW_NUMBER() OVER (
        PARTITION BY U_OrderItem, U_Period
        ORDER BY TransactionStatus, U_InvoiceNo, BatchRunDate DESC
      ) AS dup,
      MAX(
        CASE
          WHEN U_OrderID LIKE 'C#%'
            OR TransactionStatus IN ('Cancelled', 'Cancelled (Change order / Rejected)')
          THEN 1
          ELSE 0
        END
      ) OVER (PARTITION BY U_OrderItem) AS is_already_cancelled_flag
    FROM sap_distinct
  ),

  item_cancelled AS (
    SELECT human_id, cancel_time
    FROM `pacific-plating-282708.careos.careos_order_items`
    WHERE (cancel_time IS NOT NULL OR is_cancelled IS TRUE)
      AND DATE(cancel_time) >= '2026-01-01'
  ),

  change_orders AS (
    SELECT current_human_id, old_human_id
    FROM `pacific-plating-282708.careos.cancelled_change_orders`
  ),

  eligible_items AS (
    SELECT DISTINCT sap_scan.U_OrderItem AS OrderItem
    FROM sap_scan
    JOIN item_cancelled
      ON item_cancelled.human_id = sap_scan.U_OrderItem
    WHERE sap_scan.is_already_cancelled_flag = 0
      AND sap_scan.U_OrderID NOT LIKE 'C#%'
      AND sap_scan.U_OrderID NOT LIKE '%_X%'
      AND NOT EXISTS (
        SELECT 1
        FROM sap_scan AS test_row
        WHERE test_row.U_OrderItem = sap_scan.U_OrderItem
          AND LOWER(TRIM(COALESCE(test_row.U_FirstName, ''))) = 'test'
      )
  ),

  sap_periods AS (
    SELECT DISTINCT
      sap_scan.U_OrderItem AS OrderItem,
      sap_scan.U_Period AS Period
    FROM sap_scan
    JOIN eligible_items
      ON eligible_items.OrderItem = sap_scan.U_OrderItem
  ),

  eligible_installment_items AS (
    SELECT sap_scan.U_OrderItem AS OrderItem
    FROM sap_scan
    JOIN eligible_items
      ON eligible_items.OrderItem = sap_scan.U_OrderItem
    GROUP BY sap_scan.U_OrderItem
    -- Fail closed against RCB/RCL mixing: the SAP history itself must prove that this
    -- item was an installment schedule before missing periods may be supplemented.
    HAVING MAX(SAFE_CAST(sap_scan.TotalPeriods AS INT64)) > 1
  ),

  installment_spines AS (
    SELECT
      installment.OrderItem,
      COUNTIF(SAFE_CAST(installment.Period AS INT64) IS NULL) AS invalid_period_rows,
      COUNTIF(SAFE_CAST(installment.TotalPeriods AS INT64) IS NULL) AS invalid_total_period_rows,
      COUNT(DISTINCT SAFE_CAST(installment.TotalPeriods AS INT64)) AS total_period_versions,
      MAX(SAFE_CAST(installment.TotalPeriods AS INT64)) AS total_periods,
      MIN(SAFE_CAST(installment.Period AS INT64)) AS min_period,
      MAX(SAFE_CAST(installment.Period AS INT64)) AS max_period,
      COUNT(DISTINCT SAFE_CAST(installment.Period AS INT64)) AS distinct_period_count
    FROM `pacific-plating-282708.sap_data_engineer.sap_dashboard_carepay_installment` AS installment
    JOIN eligible_installment_items
      USING (OrderItem)
    GROUP BY installment.OrderItem
    HAVING invalid_period_rows = 0
      AND invalid_total_period_rows = 0
      AND total_period_versions = 1
      AND min_period = 1
      AND max_period = total_periods
      AND distinct_period_count = total_periods
  ),

  sap_cancel_rows AS (
    SELECT DISTINCT
      sap_scan.CompanyDB,
      sap_scan.U_OrderID AS OrderID,
      sap_scan.U_OrderItem AS OrderItem,
      CASE WHEN sap_scan.U_InvoiceNo = 'NULL' THEN '' ELSE sap_scan.U_InvoiceNo END AS InvoiceNo,
      sap_scan.OrderDate,
      sap_scan.U_InsuredID AS InsuredID,
      sap_scan.U_Title AS Title,
      sap_scan.U_FirstName AS FirstName,
      sap_scan.U_LastName AS LastName,
      SPLIT(sap_scan.U_InsurerCode, '-')[SAFE_OFFSET(1)] AS InsurerCode,
      sap_scan.U_InsuranceGroup AS InsuranceGroup,
      sap_scan.U_InsuranceType AS InsuranceType,
      sap_scan.U_InsuranceProduct AS InsuranceProduct,
      CASE WHEN sap_scan.U_ProductType = 'NULL' THEN 'Insurance' ELSE sap_scan.U_ProductType END AS ProductType,
      sap_scan.U_PolicyType AS PolicyType,
      'N' AS Endorse,
      sap_scan.PolicyDate,
      sap_scan.U_PolicyNo AS PolicyNo,
      sap_scan.EndorsementNo,
      sap_scan.U_ChassisNo AS ChassisNo,
      sap_scan.U_LicensePlate AS LicensePlate,
      sap_scan.GrossPremium,
      sap_scan.StampDuty,
      sap_scan.VAT,
      sap_scan.TotalPremium,
      sap_scan.WHT,
      sap_scan.TotalEIR,
      sap_scan.TotalSBT,
      sap_scan.U_ProcessingFee AS ProcessingFee,
      sap_scan.U_ProcessingFeeVat AS ProcessingFeeVat,
      sap_scan.U_ShippingFee AS ShippingFee,
      sap_scan.U_ShippingFeeVat AS ShippingFeeVat,
      sap_scan.U_TotalAmount AS TotalAmount,
      sap_scan.U_Discount AS Discount,
      CASE
        WHEN change_orders.old_human_id IS NOT NULL THEN 'Cancelled (Change order / Rejected)'
        ELSE 'Cancelled'
      END AS TransactionStatus,
      sap_scan.U_SubmissionStatus AS SubmissionStatus,
      sap_scan.U_ApprovalStatus AS ApprovalStatus,
      sap_scan.U_PaymentStatus AS PaymentStatus,
      CASE
        WHEN (sap_scan.ExpectedReceived = 0 OR sap_scan.ExpectedReceived IS NULL)
          AND sap_scan.dup = 1
        THEN sap_scan.U_ActualReceived
        WHEN sap_scan.ExpectedReceived > 0 THEN sap_scan.ExpectedReceived
      END AS ExpectedReceived,
      sap_scan.U_ActualReceived AS ActualReceived,
      sap_scan.U_InterestThisPeriod AS InterestThisPeriod,
      sap_scan.U_PrincipleThisPeriod AS PrincipleThisPeriod,
      sap_scan.U_InterestEIRThisPeriod AS InterestEIRThisPeriod,
      sap_scan.U_PrincipleEIRThisPeriod AS PrincipleEIRThisPeriod,
      CASE WHEN sap_scan.PaymentDate = 'NULL' THEN '' ELSE sap_scan.PaymentDate END AS PaymentDate,
      sap_scan.U_Period AS Period,
      sap_scan.TotalPeriods,
      sap_scan.PendingPayment,
      CASE WHEN sap_scan.PaymentMethod = 'NULL' THEN '' ELSE sap_scan.PaymentMethod END AS PaymentMethod,
      CASE
        WHEN sap_scan.PaymentChannel = 'NULL' THEN ''
        WHEN sap_scan.PaymentChannel = 'Credit Shell' THEN 'RCB-Credit Shell'
        ELSE sap_scan.PaymentChannel
      END AS PaymentChannel,
      CASE
        WHEN sap_scan.PaymentDate = 'NULL'
          OR sap_scan.PaymentDate = ''
          OR sap_scan.PaymentChannel = 'NULL'
          OR sap_scan.PaymentMethod = 'NULL'
        THEN CAST(FORMAT_DATE('%d%m%Y', CURRENT_DATE()) AS STRING)
        ELSE sap_scan.ExpectedDate
      END AS ExpectedDate,
      sap_scan.RefOrder,
      sap_scan.RefundAmountBeforeFee,
      sap_scan.RefundAmountAfterFee,
      sap_scan.BillingAddress,
      CAST(FORMAT_DATE('%d%m%Y', CURRENT_DATE()) AS STRING) AS BatchRunDate
    FROM sap_scan
    JOIN item_cancelled
      ON item_cancelled.human_id = sap_scan.U_OrderItem
    LEFT JOIN change_orders
      ON change_orders.old_human_id = sap_scan.U_OrderID
    WHERE sap_scan.is_already_cancelled_flag = 0
      AND sap_scan.U_OrderID NOT LIKE 'C#%'
      AND sap_scan.U_OrderID NOT LIKE '%_X%'
      AND (
        (sap_scan.U_Period = 1 AND sap_scan.dup = 1)
        OR (sap_scan.U_Period = 1 AND sap_scan.ExpectedReceived = 0)
        OR (sap_scan.U_Period > 1 AND sap_scan.dup = 1)
      )
  ),

  missing_installment_rows AS (
    SELECT DISTINCT
      installment.CompanyDB,
      installment.OrderID,
      installment.OrderItem,
      CASE WHEN installment.InvoiceNo = 'NULL' THEN '' ELSE installment.InvoiceNo END AS InvoiceNo,
      installment.OrderDate,
      installment.InsuredID,
      installment.Title,
      installment.FirstName,
      installment.LastName,
      installment.InsurerCode,
      installment.InsuranceGroup,
      installment.InsuranceType,
      installment.InsuranceProduct,
      CASE WHEN installment.ProductType = 'NULL' THEN 'Insurance' ELSE installment.ProductType END AS ProductType,
      installment.PolicyType,
      'N' AS Endorse,
      installment.PolicyDate,
      installment.PolicyNo,
      installment.EndorsementNo,
      installment.ChassisNo,
      installment.LicensePlate,
      installment.GrossPremium,
      installment.StampDuty,
      installment.VAT,
      installment.TotalPremium,
      installment.WHT,
      installment.TotalEIR,
      installment.TotalSBT,
      installment.ProcessingFee,
      installment.ProcessingFeeVat,
      installment.ShippingFee,
      installment.ShippingFeeVat,
      installment.TotalAmount,
      installment.Discount,
      CASE
        WHEN change_orders.old_human_id IS NOT NULL THEN 'Cancelled (Change order / Rejected)'
        ELSE 'Cancelled'
      END AS TransactionStatus,
      installment.SubmissionStatus,
      installment.ApprovalStatus,
      installment.PaymentStatus,
      installment.ExpectedReceived,
      installment.ActualReceived,
      installment.InterestThisPeriod,
      installment.PrincipleThisPeriod,
      installment.InterestEIRThisPeriod,
      installment.PrincipleEIRThisPeriod,
      CASE
        WHEN installment.PaymentDate IS NULL OR installment.PaymentDate = 'NULL' THEN ''
        ELSE installment.PaymentDate
      END AS PaymentDate,
      installment.Period,
      installment.TotalPeriods,
      installment.PendingPayment,
      CASE
        WHEN installment.PaymentMethod IS NULL OR installment.PaymentMethod = 'NULL' THEN ''
        ELSE installment.PaymentMethod
      END AS PaymentMethod,
      CASE
        WHEN installment.PaymentChannel IS NULL OR installment.PaymentChannel = 'NULL' THEN ''
        WHEN installment.PaymentChannel = 'Credit Shell' THEN 'RCB-Credit Shell'
        ELSE installment.PaymentChannel
      END AS PaymentChannel,
      CASE
        WHEN installment.PaymentDate IS NULL
          OR installment.PaymentDate IN ('', 'NULL')
          OR installment.PaymentChannel IS NULL
          OR installment.PaymentChannel = 'NULL'
          OR installment.PaymentMethod IS NULL
          OR installment.PaymentMethod = 'NULL'
        THEN CAST(FORMAT_DATE('%d%m%Y', CURRENT_DATE()) AS STRING)
        ELSE installment.ExpectedDate
      END AS ExpectedDate,
      installment.RefOrder,
      CAST(installment.RefundAmountBeforeFee AS FLOAT64) AS RefundAmountBeforeFee,
      CAST(installment.RefundAmountAfterFee AS FLOAT64) AS RefundAmountAfterFee,
      installment.BillingAddress,
      CAST(FORMAT_DATE('%d%m%Y', CURRENT_DATE()) AS STRING) AS BatchRunDate
    FROM `pacific-plating-282708.sap_data_engineer.sap_dashboard_carepay_installment` AS installment
    JOIN eligible_items
      USING (OrderItem)
    JOIN installment_spines
      USING (OrderItem)
    LEFT JOIN sap_periods
      ON sap_periods.OrderItem = installment.OrderItem
     AND sap_periods.Period = installment.Period
    LEFT JOIN change_orders
      ON change_orders.old_human_id = installment.OrderID
    WHERE sap_periods.OrderItem IS NULL
  ),

  combined AS (
    SELECT * FROM sap_cancel_rows
    UNION ALL
    SELECT * FROM missing_installment_rows
  ),

  canonical_ranked AS (
    SELECT
      *,
      MAX(TotalPeriods) OVER (PARTITION BY OrderItem) AS canonical_total_periods
    FROM combined
  ),

  canonicalized AS (
    SELECT
      * EXCEPT (canonical_total_periods) REPLACE (
        canonical_total_periods AS TotalPeriods
      )
    FROM canonical_ranked
  )

SELECT DISTINCT *
FROM canonicalized
WHERE LOWER(TRIM(COALESCE(FirstName, ''))) != 'test'
ORDER BY OrderItem, Period, InvoiceNo;

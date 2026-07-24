-- BASELINE CAPTURE 2026-07-25 -- pulled verbatim from live BigQuery view definition
-- Object: sap_view.RCB_Motor_process_2_cancel_new
-- Part of the 11 sap_view process views confirmed as real nightly production, that
-- read directly from sap_integration_v2.SAP_LIVE_FULL. Repointing to
-- sap_integration_v3.stg_sap_state (deduped, no duplicate (OrderItem,Period) rows).
-- See docs/knowledge/30_SAP_CHANGELOG.md 2026-07-25 entry.

-- ============================================================
-- 02 RCB Motor process 2 cancel-new — PRODUCTION TUNED VERSION
-- Tuned: 2026-07-07
-- Validated against original: row count match (1202=1202), schema match (identical)
-- Fix applied: deterministic tie-breaker (BatchRunDate DESC) to prevent
--              non-deterministic dup selection when SAP_LIVE_FULL has
--              duplicate snapshot rows with identical TransactionStatus/InvoiceNo
-- ============================================================

WITH
  sap_scan AS (
    SELECT
      *,
      ROW_NUMBER() OVER (
        PARTITION BY U_OrderItem, U_Period
        ORDER BY TransactionStatus, U_InvoiceNo, BatchRunDate DESC
      ) AS dup,
      MAX(CASE WHEN U_OrderID LIKE 'C#%' OR TransactionStatus IN ('Cancelled', 'Cancelled (Change order / Rejected)')
               THEN 1 ELSE 0 END)
        OVER (PARTITION BY U_OrderItem) AS is_already_cancelled_flag
    FROM (
      SELECT DISTINCT * FROM `pacific-plating-282708.sap_integration_v2.SAP_LIVE_FULL`
      -- dedup ที่นี่: ยืนยันแล้วว่า record ซ้ำมี DocEntry เดียวกัน (เอกสารเดียวกันจริง)
      -- ไม่ใช่ document คนละใบที่บังเอิญ field เหมือนกัน — dedup ปลอดภัย
    )
  ),

  item_cancelled AS (
    SELECT human_id, cancel_time
    FROM `pacific-plating-282708.careos.careos_order_items`
    WHERE (cancel_time IS NOT NULL OR is_cancelled IS TRUE)
      AND DATE(cancel_time) >= '2025-01-01'
  ),

  change AS (
    SELECT current_human_id, old_human_id
    FROM `pacific-plating-282708.careos.cancelled_change_orders`
  )

SELECT
  DISTINCT
  sap_scan.CompanyDB,
  sap_scan.U_OrderID AS OrderID,
  sap_scan.U_OrderItem AS OrderItem,
  CASE WHEN sap_scan.U_InvoiceNo = 'NULL' THEN '' ELSE sap_scan.U_InvoiceNo END AS InvoiceNo,
  sap_scan.OrderDate,
  sap_scan.U_InsuredID AS InsuredID,
  sap_scan.U_Title AS Title,
  sap_scan.U_FirstName AS FirstName,
  sap_scan.U_LastName AS LastName,
  SPLIT(sap_scan.U_InsurerCode, '-')[OFFSET(1)] AS InsurerCode,
  sap_scan.U_InsuranceGroup AS InsuranceGroup,
  sap_scan.U_InsuranceType AS InsuranceType,
  sap_scan.U_InsuranceProduct AS InsuranceProduct,
  CASE WHEN sap_scan.U_ProductType = 'NULL' THEN 'Insurance' ELSE sap_scan.U_ProductType END AS ProductType,
  sap_scan.U_PolicyType AS PolicyType,
  'N' AS Endorse,
  sap_scan.PolicyDate,
  sap_scan.U_PolicyNo AS PolicyNo,
  sap_scan.EndorsementNo AS EndorsementNo,
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
  CASE WHEN change.old_human_id IS NOT NULL THEN 'Cancelled (Change order / Rejected)' ELSE 'Cancelled' END AS TransactionStatus,
  sap_scan.U_SubmissionStatus AS SubmissionStatus,
  sap_scan.U_ApprovalStatus AS ApprovalStatus,
  sap_scan.U_PaymentStatus AS PaymentStatus,
  CASE
    WHEN (sap_scan.ExpectedReceived = 0 OR sap_scan.ExpectedReceived IS NULL) AND sap_scan.dup = 1 THEN sap_scan.U_ActualReceived
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
    WHEN sap_scan.PaymentDate = 'NULL' OR sap_scan.PaymentDate = '' OR sap_scan.PaymentChannel = 'NULL' OR sap_scan.PaymentMethod = 'NULL'
      THEN CAST(FORMAT_DATE('%d%m%Y', CURRENT_DATE()) AS STRING)
    ELSE sap_scan.ExpectedDate
  END AS ExpectedDate,
  sap_scan.RefOrder,
  sap_scan.RefundAmountBeforeFee,
  sap_scan.RefundAmountAfterFee,
  sap_scan.BillingAddress,
  CAST(FORMAT_DATE('%d%m%Y', CURRENT_DATE()) AS STRING) AS BatchRunDate

FROM sap_scan
INNER JOIN item_cancelled
  ON item_cancelled.human_id = sap_scan.U_OrderItem
LEFT JOIN change
  ON change.old_human_id = sap_scan.U_OrderID
WHERE
  sap_scan.is_already_cancelled_flag = 0
  AND sap_scan.U_OrderID NOT LIKE 'C#%'
  AND sap_scan.U_OrderID NOT LIKE '%_X%'
  AND sap_scan.OrderDate NOT LIKE '%2023%'
  AND sap_scan.OrderDate NOT LIKE '%2024%'
  --AND sap_scan.OrderDate NOT LIKE '%2025%'
  AND (
    (sap_scan.U_Period = 1 AND sap_scan.dup = 1)
    OR (sap_scan.U_Period = 1 AND sap_scan.ExpectedReceived = 0)
    OR (sap_scan.U_Period > 1 AND sap_scan.dup = 1)
  )

ORDER BY OrderItem, Period

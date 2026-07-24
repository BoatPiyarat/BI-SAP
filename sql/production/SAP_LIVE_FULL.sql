-- BASELINE CAPTURE 2026-07-24 -- pulled verbatim from live BigQuery view definition
-- Object: sap_integration_v2.SAP_LIVE_FULL
-- This is the CURRENT production query, exactly as running tonight's schedule.
-- Do not hand-edit without diffing against a fresh pull first (it may have
-- changed in BigQuery since this capture). See docs/knowledge/30_SAP_CHANGELOG.md
-- (2026-07-24 entry) for what was found wrong with it and why.

-- ============================================================
-- SAP_LIVE_FULL — FIXED VERSION (เพิ่ม DocEntry เข้าทุก branch)
-- แก้ไข: 2026-07-07
-- เหตุผล: DocEntry มีอยู่แล้วในทั้ง 4 ตารางย่อย แต่ query เดิมไม่เคย select มา
--         ทำให้ dedup/tie-break/audit ย้อนกลับไป SAP source ทำไม่ได้
-- ใช้แทน view/query เดิมที่สร้าง SAP_LIVE_FULL ได้เลย (schema เดิมครบ + เพิ่มแค่ DocEntry)
-- ============================================================

SELECT * EXCEPT(_rn)
FROM (
  SELECT
    *,
    ROW_NUMBER() OVER (
      PARTITION BY DocEntry
      ORDER BY BatchRunDate DESC
    ) AS _rn
  FROM (
  SELECT DISTINCT
    DocEntry,                                                            -- ★ เพิ่มใหม่
    U_CompanyCode CompanyDB,
    U_OrderID,
    U_OrderItem,
    U_InvoiceNo,
    SAFE_CAST(FORMAT_DATE('%d%m%Y', U_OrderDate) AS STRING) AS OrderDate,
    U_InsuredID,
    U_Title,
    U_FirstName,
    U_LastName,
    U_InsurerCode,
    U_InsuranceGroup,
    U_InsuranceType,
    U_InsuranceProduct,
    U_ProductType,
    U_PolicyType,
    CAST(U_Endorse AS STRING) U_Endorse,
    SAFE_CAST(FORMAT_DATE('%d%m%Y', U_PolicyDate) AS STRING) AS PolicyDate,
    U_PolicyNo,
    SAFE_CAST(U_EndorsementNo AS STRING) AS EndorsementNo,
    U_ChassisNo,
    U_LicensePlate,
    U_GrossPremiumAmt GrossPremium,
    CAST(U_StampDutyAmt AS FLOAT64) AS StampDuty,
    SAFE_CAST(U_VATAmt AS FLOAT64) AS VAT,
    SAFE_CAST(U_TotalPremiumAmt AS FLOAT64) AS TotalPremium,
    SAFE_CAST(U_WHTAmt AS FLOAT64) AS WHT,
    SAFE_CAST(U_TotalEIRAmt AS FLOAT64) AS TotalEIR,
    SAFE_CAST(U_TotalSBTAmt AS FLOAT64) AS TotalSBT,
    SAFE_CAST(U_ProcessingFee AS FLOAT64) AS U_ProcessingFee,
    SAFE_CAST(U_ProcessingFeeVat AS FLOAT64) AS U_ProcessingFeeVat,
    SAFE_CAST(U_ShippingFee AS FLOAT64) AS U_ShippingFee,
    SAFE_CAST(U_ShippingFeeVat AS FLOAT64) AS U_ShippingFeeVat,
    SAFE_CAST(U_TotalAmount AS FLOAT64) AS U_TotalAmount,
    SAFE_CAST(U_Discount AS FLOAT64) AS U_Discount,
    U_PolicyStatus TransactionStatus,
    U_SubmissionStatus,
    U_ApprovalStatus,
    U_PaymentStatus,
    SAFE_CAST(U_ExpectedReceived AS FLOAT64) AS ExpectedReceived,
    SAFE_CAST(U_ActualReceived AS FLOAT64) AS U_ActualReceived,
    SAFE_CAST(U_InterestThisPeriod AS FLOAT64) AS U_InterestThisPeriod,
    SAFE_CAST(U_PrincipleThisPeriod AS FLOAT64) AS U_PrincipleThisPeriod,
    SAFE_CAST(U_InterestEIRThisPeriod AS FLOAT64) AS U_InterestEIRThisPeriod,
    SAFE_CAST(U_PrincipleEIRThisPeriod AS FLOAT64) AS U_PrincipleEIRThisPeriod,
    CASE WHEN U_PaymentDate = 'NULL' THEN '' ELSE CAST(FORMAT_DATE('%d%m%Y', DATE(U_PaymentDate)) AS STRING) END AS PaymentDate,
    U_Period,
    U_TotalPeriods TotalPeriods,
    U_PendingPayment PendingPayment,
    U_PaymentMethod PaymentMethod,
    U_PaymentChannel PaymentChannel,
    SAFE_CAST(FORMAT_DATE('%d%m%Y', U_ExpectedDate) AS STRING) AS ExpectedDate,
    U_RefOrder RefOrder,
    U_RefundAmt RefundAmountBeforeFee,
    U_RefundAmountAfterFee RefundAmountAfterFee,
    U_BillingAddress BillingAddress,
    SAFE_CAST(FORMAT_DATE('%d%m%Y', U_BatchRunDate) AS STRING) AS BatchRunDate
  FROM `pacific-plating-282708.sap_integration_v2.SAP_LIVE_2024`
  WHERE U_InsuranceGroup <> 'B2B'

  UNION ALL

  SELECT DISTINCT
    DocEntry,                                                            -- ★ เพิ่มใหม่
    U_CompanyCode CompanyDB,
    U_OrderID,
    U_OrderItem,
    U_InvoiceNo,
    SAFE_CAST(FORMAT_DATE('%d%m%Y', U_OrderDate) AS STRING) AS OrderDate,
    U_InsuredID,
    U_Title,
    U_FirstName,
    U_LastName,
    U_InsurerCode,
    U_InsuranceGroup,
    U_InsuranceType,
    U_InsuranceProduct,
    U_ProductType,
    U_PolicyType,
    CAST(U_Endorse AS STRING) U_Endorse,
    SAFE_CAST(FORMAT_DATE('%d%m%Y', U_PolicyDate) AS STRING) AS PolicyDate,
    U_PolicyNo,
    SAFE_CAST(U_EndorsementNo AS STRING) AS EndorsementNo,
    U_ChassisNo,
    U_LicensePlate,
    U_GrossPremiumAmt GrossPremium,
    CAST(U_StampDutyAmt AS FLOAT64) AS StampDuty,
    SAFE_CAST(U_VATAmt AS FLOAT64) AS VAT,
    SAFE_CAST(U_TotalPremiumAmt AS FLOAT64) AS TotalPremium,
    SAFE_CAST(U_WHTAmt AS FLOAT64) AS WHT,
    SAFE_CAST(U_TotalEIRAmt AS FLOAT64) AS TotalEIR,
    SAFE_CAST(U_TotalSBTAmt AS FLOAT64) AS TotalSBT,
    SAFE_CAST(U_ProcessingFee AS FLOAT64) AS U_ProcessingFee,
    SAFE_CAST(U_ProcessingFeeVat AS FLOAT64) AS U_ProcessingFeeVat,
    SAFE_CAST(U_ShippingFee AS FLOAT64) AS U_ShippingFee,
    SAFE_CAST(U_ShippingFeeVat AS FLOAT64) AS U_ShippingFeeVat,
    SAFE_CAST(U_TotalAmount AS FLOAT64) AS U_TotalAmount,
    SAFE_CAST(U_Discount AS FLOAT64) AS U_Discount,
    U_PolicyStatus TransactionStatus,
    U_SubmissionStatus,
    U_ApprovalStatus,
    U_PaymentStatus,
    SAFE_CAST(U_ExpectedReceived AS FLOAT64) AS ExpectedReceived,
    SAFE_CAST(U_ActualReceived AS FLOAT64) AS U_ActualReceived,
    SAFE_CAST(U_InterestThisPeriod AS FLOAT64) AS U_InterestThisPeriod,
    SAFE_CAST(U_PrincipleThisPeriod AS FLOAT64) AS U_PrincipleThisPeriod,
    SAFE_CAST(U_InterestEIRThisPeriod AS FLOAT64) AS U_InterestEIRThisPeriod,
    SAFE_CAST(U_PrincipleEIRThisPeriod AS FLOAT64) AS U_PrincipleEIRThisPeriod,
    CASE WHEN U_PaymentDate = 'NULL' THEN '' ELSE CAST(FORMAT_DATE('%d%m%Y', DATE(U_PaymentDate)) AS STRING) END AS PaymentDate,
    U_Period,
    U_TotalPeriods TotalPeriods,
    U_PendingPayment PendingPayment,
    U_PaymentMethod PaymentMethod,
    U_PaymentChannel PaymentChannel,
    SAFE_CAST(FORMAT_DATE('%d%m%Y', U_ExpectedDate) AS STRING) AS ExpectedDate,
    U_RefOrder RefOrder,
    U_RefundAmt RefundAmountBeforeFee,
    U_RefundAmountAfterFee RefundAmountAfterFee,
    U_BillingAddress BillingAddress,
    SAFE_CAST(FORMAT_DATE('%d%m%Y', U_BatchRunDate) AS STRING) AS BatchRunDate
  FROM `pacific-plating-282708.sap_integration_v2.SAP_LIVE_2025`
  WHERE U_InsuranceGroup <> 'B2B'

  UNION ALL

  SELECT DISTINCT
    DocEntry,                                                            -- ★ เพิ่มใหม่
    U_CompanyCode CompanyDB,
    U_OrderID,
    U_OrderItem,
    U_InvoiceNo,
    SAFE_CAST(FORMAT_DATE('%d%m%Y', U_OrderDate) AS STRING) AS OrderDate,
    U_InsuredID,
    U_Title,
    U_FirstName,
    U_LastName,
    U_InsurerCode,
    U_InsuranceGroup,
    U_InsuranceType,
    U_InsuranceProduct,
    U_ProductType,
    U_PolicyType,
    CAST(U_Endorse AS STRING) U_Endorse,
    SAFE_CAST(FORMAT_DATE('%d%m%Y', U_PolicyDate) AS STRING) AS PolicyDate,
    U_PolicyNo,
    SAFE_CAST(U_EndorsementNo AS STRING) AS EndorsementNo,
    U_ChassisNo,
    U_LicensePlate,
    U_GrossPremiumAmt GrossPremium,
    CAST(U_StampDutyAmt AS FLOAT64) AS StampDuty,
    SAFE_CAST(U_VATAmt AS FLOAT64) AS VAT,
    SAFE_CAST(U_TotalPremiumAmt AS FLOAT64) AS TotalPremium,
    SAFE_CAST(U_WHTAmt AS FLOAT64) AS WHT,
    SAFE_CAST(U_TotalEIRAmt AS FLOAT64) AS TotalEIR,
    SAFE_CAST(U_TotalSBTAmt AS FLOAT64) AS TotalSBT,
    SAFE_CAST(U_ProcessingFee AS FLOAT64) AS U_ProcessingFee,
    SAFE_CAST(U_ProcessingFeeVat AS FLOAT64) AS U_ProcessingFeeVat,
    SAFE_CAST(U_ShippingFee AS FLOAT64) AS U_ShippingFee,
    SAFE_CAST(U_ShippingFeeVat AS FLOAT64) AS U_ShippingFeeVat,
    SAFE_CAST(U_TotalAmount AS FLOAT64) AS U_TotalAmount,
    SAFE_CAST(U_Discount AS FLOAT64) AS U_Discount,
    U_PolicyStatus TransactionStatus,
    U_SubmissionStatus,
    U_ApprovalStatus,
    U_PaymentStatus,
    SAFE_CAST(U_ExpectedReceived AS FLOAT64) AS ExpectedReceived,
    SAFE_CAST(U_ActualReceived AS FLOAT64) AS U_ActualReceived,
    SAFE_CAST(U_InterestThisPeriod AS FLOAT64) AS U_InterestThisPeriod,
    SAFE_CAST(U_PrincipleThisPeriod AS FLOAT64) AS U_PrincipleThisPeriod,
    SAFE_CAST(U_InterestEIRThisPeriod AS FLOAT64) AS U_InterestEIRThisPeriod,
    SAFE_CAST(U_PrincipleEIRThisPeriod AS FLOAT64) AS U_PrincipleEIRThisPeriod,
    CASE WHEN U_PaymentDate = 'NULL' THEN '' ELSE CAST(FORMAT_DATE('%d%m%Y', DATE(U_PaymentDate)) AS STRING) END AS PaymentDate,
    U_Period,
    U_TotalPeriods TotalPeriods,
    U_PendingPayment PendingPayment,
    U_PaymentMethod PaymentMethod,
    U_PaymentChannel PaymentChannel,
    SAFE_CAST(FORMAT_DATE('%d%m%Y', U_ExpectedDate) AS STRING) AS ExpectedDate,
    U_RefOrder RefOrder,
    U_RefundAmt RefundAmountBeforeFee,
    U_RefundAmountAfterFee RefundAmountAfterFee,
    U_BillingAddress BillingAddress,
    SAFE_CAST(FORMAT_DATE('%d%m%Y', U_BatchRunDate) AS STRING) AS BatchRunDate
  FROM `pacific-plating-282708.sap_integration_v2.SAP_LIVE_2026`
  WHERE U_InsuranceGroup <> 'B2B'

  UNION ALL

  SELECT DISTINCT
    DocEntry,                                                            -- ★ เพิ่มใหม่
    U_CompanyCode CompanyDB,
    U_OrderID,
    U_OrderItem,
    U_InvoiceNo,
    SAFE_CAST(FORMAT_DATE('%d%m%Y', U_OrderDate) AS STRING) AS OrderDate,
    U_InsuredID,
    U_Title,
    U_FirstName,
    U_LastName,
    U_InsurerCode,
    U_InsuranceGroup,
    U_InsuranceType,
    U_InsuranceProduct,
    U_ProductType,
    U_PolicyType,
    CAST(U_Endorse AS STRING) U_Endorse,
    SAFE_CAST(FORMAT_DATE('%d%m%Y', U_PolicyDate) AS STRING) AS PolicyDate,
    U_PolicyNo,
    SAFE_CAST(U_EndorsementNo AS STRING) AS EndorsementNo,               -- (ตาราง SAP_LIVE ใช้ SAFE_CAST ตามต้นฉบับเดิม)
    U_ChassisNo,
    U_LicensePlate,
    U_GrossPremiumAmt GrossPremium,
    CAST(U_StampDutyAmt AS FLOAT64) AS StampDuty,
    SAFE_CAST(U_VATAmt AS FLOAT64) AS VAT,
    SAFE_CAST(U_TotalPremiumAmt AS FLOAT64) AS TotalPremium,
    SAFE_CAST(U_WHTAmt AS FLOAT64) AS WHT,
    SAFE_CAST(U_TotalEIRAmt AS FLOAT64) AS TotalEIR,
    SAFE_CAST(U_TotalSBTAmt AS FLOAT64) AS TotalSBT,
    SAFE_CAST(U_ProcessingFee AS FLOAT64) AS U_ProcessingFee,
    SAFE_CAST(U_ProcessingFeeVat AS FLOAT64) AS U_ProcessingFeeVat,
    SAFE_CAST(U_ShippingFee AS FLOAT64) AS U_ShippingFee,
    SAFE_CAST(U_ShippingFeeVat AS FLOAT64) AS U_ShippingFeeVat,
    SAFE_CAST(U_TotalAmount AS FLOAT64) AS U_TotalAmount,
    SAFE_CAST(U_Discount AS FLOAT64) AS U_Discount,
    U_PolicyStatus TransactionStatus,
    U_SubmissionStatus,
    U_ApprovalStatus,
    U_PaymentStatus,
    SAFE_CAST(U_ExpectedReceived AS FLOAT64) AS ExpectedReceived,
    SAFE_CAST(U_ActualReceived AS FLOAT64) AS U_ActualReceived,
    SAFE_CAST(U_InterestThisPeriod AS FLOAT64) AS U_InterestThisPeriod,
    SAFE_CAST(U_PrincipleThisPeriod AS FLOAT64) AS U_PrincipleThisPeriod,
    SAFE_CAST(U_InterestEIRThisPeriod AS FLOAT64) AS U_InterestEIRThisPeriod,
    SAFE_CAST(U_PrincipleEIRThisPeriod AS FLOAT64) AS U_PrincipleEIRThisPeriod,
    CASE WHEN U_PaymentDate = 'NULL' THEN '' ELSE CAST(FORMAT_DATE('%d%m%Y', DATE(U_PaymentDate)) AS STRING) END AS PaymentDate,
    U_Period,
    U_TotalPeriods TotalPeriods,
    U_PendingPayment PendingPayment,
    U_PaymentMethod PaymentMethod,
    U_PaymentChannel PaymentChannel,
    SAFE_CAST(FORMAT_DATE('%d%m%Y', U_ExpectedDate) AS STRING) AS ExpectedDate,
    U_RefOrder RefOrder,
    U_RefundAmt RefundAmountBeforeFee,
    U_RefundAmountAfterFee RefundAmountAfterFee,
    U_BillingAddress BillingAddress,
    SAFE_CAST(FORMAT_DATE('%d%m%Y', U_BatchRunDate) AS STRING) AS BatchRunDate
  FROM `pacific-plating-282708.sap_integration_v2.SAP_LIVE`
  WHERE U_InsuranceGroup <> 'B2B'
  )
)
WHERE _rn = 1;

-- ============================================================
-- หมายเหตุ (อัปเดตหลังปรับปรุงตาม feedback):
-- 1. เปลี่ยนจาก `SELECT DISTINCT *` (outer) เป็น dedup ด้วย DocEntry +
--    ROW_NUMBER()...BatchRunDate DESC แทน — robust กว่าเดิม เพราะไม่ต้องพึ่ง
--    สมมติฐานว่า "ทุกคอลัมน์เหมือนกันเป๊ะ = record เดียวกัน" (เคยพังกรณี
--    ที่ column ใดคอลัมน์หนึ่งต่างกันนิดเดียวแต่จริงๆ คือเอกสารเดียวกัน)
--    ยังคง SELECT DISTINCT ในแต่ละ branch ไว้เหมือนเดิม (จับ Pattern A:
--    duplicate ภายในตารางเดียวกัน ได้ตั้งแต่ต้นทาง ก่อนเข้า UNION ALL)
-- 2. EndorsementNo: standardize เป็น SAFE_CAST(...AS STRING) ทั้ง 4 branch
--    แล้ว (เดิมมีแค่ branch SAP_LIVE ที่ใช้ SAFE_CAST ต่างจาก 3 branch แรก)
-- 3. หลัง deploy แล้ว แนะนำรัน query ตรวจสอบ duplicate ซ้ำ (Pattern A/B ใน
--    SAP_LIVE_FULL_DUPLICATE_FINDING.md) อีกครั้งเพื่อ track ว่าจำนวน duplicate
--    ลดลงหลังแก้ที่ต้นตอ (SAP_LIVE, sap-order-payment-initial-phase) หรือยัง
-- ============================================================

-- Manual cancel of L81095660-V1 (RCB Motor, Credit Shell) so the live V2-recovery rule in
-- sap_view.RCB_Motor_process_3_change (FIX 2026-11-10) can re-send it as L81095660-V2.
-- Decision: Boat 2026-11-25 ("Cancel รายการเก่า เพื่อนำเข้า รายการใหม่ V2"); FINDINGS_L81095660_CHANGE_ORDER_CHAIN_AP_20261125.md
-- Transform = the SELECT of live sap_view.RCB_Motor_process_2_cancel_new (read 2026-11-25), applied to the
-- one stored SAP row; L81095660 is not an old_human_id, so TransactionStatus = 'Cancelled' (precedent C#L81135161).
-- Output types follow sap_integration_v3.sap_column_contract (money = STRING %.2f).
CREATE TABLE `pacific-plating-282708.sap_integration_v3.diag_manual_cancel_l81095660_20261125`
OPTIONS (expiration_timestamp = TIMESTAMP_ADD(CURRENT_TIMESTAMP(), INTERVAL 14 DAY),
         description = 'Immutable snapshot: manual cancel L81095660-V1 (Boat 2026-11-25)') AS
WITH sap AS (
  SELECT * FROM `pacific-plating-282708.sap_integration_v2.SAP_LIVE_FULL`
  WHERE U_OrderItem = 'L81095660-V1' AND U_OrderID = 'L81095660' AND TransactionStatus = 'Paid'
)
SELECT
  sap.CompanyDB,
  sap.U_OrderID AS OrderID,
  sap.U_OrderItem AS OrderItem,
  CASE WHEN UPPER(TRIM(COALESCE(sap.U_InvoiceNo,''))) = 'NULL' THEN '' ELSE COALESCE(sap.U_InvoiceNo,'') END AS InvoiceNo,
  sap.OrderDate,
  sap.U_InsuredID AS InsuredID,
  sap.U_Title AS Title,
  sap.U_FirstName AS FirstName,
  sap.U_LastName AS LastName,
  COALESCE(SPLIT(sap.U_InsurerCode, '-')[SAFE_OFFSET(1)], sap.U_InsurerCode) AS InsurerCode,
  sap.U_InsuranceGroup AS InsuranceGroup,
  sap.U_InsuranceType AS InsuranceType,
  sap.U_InsuranceProduct AS InsuranceProduct,
  CASE WHEN NULLIF(TRIM(COALESCE(sap.U_ProductType,'')),'') IS NULL OR UPPER(TRIM(sap.U_ProductType)) = 'NULL' THEN 'Insurance' ELSE sap.U_ProductType END AS ProductType,
  sap.U_PolicyType AS PolicyType,
  'N' AS Endorse,
  sap.PolicyDate,
  COALESCE(sap.U_PolicyNo,'') AS PolicyNo,
  COALESCE(sap.EndorsementNo,'') AS EndorsementNo,
  COALESCE(sap.U_ChassisNo,'') AS ChassisNo,
  COALESCE(sap.U_LicensePlate,'') AS LicensePlate,
  FORMAT('%.2f', sap.GrossPremium) AS GrossPremium,
  FORMAT('%.2f', sap.StampDuty) AS StampDuty,
  FORMAT('%.2f', sap.VAT) AS VAT,
  FORMAT('%.2f', sap.TotalPremium) AS TotalPremium,
  FORMAT('%.2f', sap.WHT) AS WHT,
  FORMAT('%.2f', COALESCE(sap.U_InterestEIRThisPeriod, 0)) AS TotalEIR,   -- = canonical_total_eir (single period)
  FORMAT('%.2f', sap.TotalSBT) AS TotalSBT,
  FORMAT('%.2f', sap.U_ProcessingFee) AS ProcessingFee,
  FORMAT('%.2f', sap.U_ProcessingFeeVat) AS ProcessingFeeVat,
  FORMAT('%.2f', sap.U_ShippingFee) AS ShippingFee,
  FORMAT('%.2f', sap.U_ShippingFeeVat) AS ShippingFeeVat,
  FORMAT('%.2f', sap.U_TotalAmount) AS TotalAmount,
  FORMAT('%.2f', sap.U_Discount) AS Discount,
  'Cancelled' AS TransactionStatus,
  sap.U_SubmissionStatus AS SubmissionStatus,
  sap.U_ApprovalStatus AS ApprovalStatus,
  sap.U_PaymentStatus AS PaymentStatus,
  FORMAT('%.2f', COALESCE(sap.ExpectedReceived, 0)) AS ExpectedReceived,
  FORMAT('%.2f', COALESCE(sap.U_ActualReceived, 0)) AS ActualReceived,
  CAST(COALESCE(sap.U_InterestThisPeriod, 0) AS INT64) AS InterestThisPeriod,
  CAST(COALESCE(sap.U_PrincipleThisPeriod, 0) AS INT64) AS PrincipleThisPeriod,
  CAST(COALESCE(sap.U_InterestEIRThisPeriod, 0) AS INT64) AS InterestEIRThisPeriod,
  CAST(COALESCE(sap.U_PrincipleEIRThisPeriod, 0) AS INT64) AS PrincipleEIRThisPeriod,
  CASE WHEN UPPER(TRIM(COALESCE(sap.PaymentDate,''))) = 'NULL' THEN '' ELSE COALESCE(sap.PaymentDate,'') END AS PaymentDate,
  SAFE_CAST(sap.U_Period AS INT64) AS Period,
  SAFE_CAST(sap.TotalPeriods AS INT64) AS TotalPeriods,
  CAST(COALESCE(sap.PendingPayment, 0) AS INT64) AS PendingPayment,
  COALESCE(sap.PaymentMethod,'') AS PaymentMethod,
  CASE WHEN sap.PaymentChannel = 'Credit Shell' THEN 'RCB-Credit Shell' ELSE COALESCE(sap.PaymentChannel,'') END AS PaymentChannel,
  COALESCE(NULLIF(NULLIF(TRIM(sap.ExpectedDate),''),'NULL'), NULLIF(NULLIF(TRIM(sap.PaymentDate),''),'NULL')) AS ExpectedDate,
  sap.RefOrder,
  CAST(COALESCE(sap.RefundAmountBeforeFee, 0) AS INT64) AS RefundAmountBeforeFee,
  CAST(COALESCE(sap.RefundAmountAfterFee, 0) AS INT64) AS RefundAmountAfterFee,
  COALESCE(sap.BillingAddress,'') AS BillingAddress,
  FORMAT_DATE('%d%m%Y', CURRENT_DATE('Asia/Bangkok')) AS BatchRunDate
FROM sap;

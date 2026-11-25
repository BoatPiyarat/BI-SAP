-- Urgent refund (FA/Mo Teams 2026-11-23, tab "urgent_refund to cust"), Phase 1 = PAID spine for 7 RCL
-- Credit Shell items that are NOT in SAP at all. Phase 2 (cancel) goes in a later file only after SAP
-- accepts this one (Aware 2026-08-22: never combine Paid and Cancel transitions).
-- Source: live sap_data_engineer.sap_dashboard_carepay_installment (RCL spine logic), with the
-- RCB_Motor_process_4_creditshell transforms (Pending -> blank PaymentMethod/Channel/PaymentDate) and
-- Aware 2026-08-22 Pending rules (blank InvoiceNo stays blank; NULL money -> 0). Positional 56 columns.
CREATE TABLE `pacific-plating-282708.sap_integration_v3.diag_manual_refund_phase1_20261125`
OPTIONS (expiration_timestamp = TIMESTAMP_ADD(CURRENT_TIMESTAMP(), INTERVAL 14 DAY),
         description = 'Immutable snapshot: urgent refund phase 1 (paid spine) 7 RCL credit-shell items, Boat 2026-11-25') AS
WITH src AS (
  SELECT DISTINCT * FROM `pacific-plating-282708.sap_data_engineer.sap_dashboard_carepay_installment`
  WHERE OrderItem IN ('L80731453-V1','L80776827-V1','L80991399-V1','L81017535-V1','L81058304-V1','L81072618-V1','L81131068-V1')
), f AS (SELECT * FROM src)
SELECT
  IFNULL(CompanyDB,'') AS CompanyDB, OrderID, OrderItem,
  CASE WHEN LOWER(TransactionStatus)='pending' THEN IFNULL(InvoiceNo,'') ELSE InvoiceNo END AS InvoiceNo,
  OrderDate, IFNULL(InsuredID,'') AS InsuredID, IFNULL(Title,'') AS Title, IFNULL(FirstName,'') AS FirstName, IFNULL(LastName,'') AS LastName,
  InsurerCode, InsuranceGroup, InsuranceType,
  IF(UPPER(TRIM(IFNULL(InsuranceProduct,'')))='MOTORBIKE','MotorBike','Motor') AS InsuranceProduct,
  IFNULL(ProductType,'Insurance') AS ProductType, PolicyType, IFNULL(Endorse,'N') AS Endorse, PolicyDate,
  IFNULL(PolicyNo,'') AS PolicyNo, IFNULL(EndorsementNo,'') AS EndorsementNo, IFNULL(ChassisNo,'') AS ChassisNo, IFNULL(LicensePlate,'') AS LicensePlate,
  FORMAT('%.2f', CAST(IFNULL(GrossPremium,0) AS FLOAT64)) AS GrossPremium, FORMAT('%.2f', CAST(IFNULL(StampDuty,0) AS FLOAT64)) AS StampDuty, FORMAT('%.2f', CAST(IFNULL(VAT,0) AS FLOAT64)) AS VAT,
  FORMAT('%.2f', CAST(IFNULL(TotalPremium,0) AS FLOAT64)) AS TotalPremium, FORMAT('%.2f', CAST(IFNULL(WHT,0) AS FLOAT64)) AS WHT, FORMAT('%.2f', CAST(IFNULL(TotalEIR,0) AS FLOAT64)) AS TotalEIR,
  FORMAT('%.2f', CAST(IFNULL(TotalSBT,0) AS FLOAT64)) AS TotalSBT, FORMAT('%.2f', CAST(IFNULL(ProcessingFee,0) AS FLOAT64)) AS ProcessingFee, FORMAT('%.2f', CAST(IFNULL(ProcessingFeeVat,0) AS FLOAT64)) AS ProcessingFeeVat,
  FORMAT('%.2f', CAST(IFNULL(ShippingFee,0) AS FLOAT64)) AS ShippingFee, FORMAT('%.2f', CAST(IFNULL(ShippingFeeVat,0) AS FLOAT64)) AS ShippingFeeVat, FORMAT('%.2f', CAST(IFNULL(TotalAmount,0) AS FLOAT64)) AS TotalAmount,
  FORMAT('%.2f', CAST(IFNULL(Discount,0) AS FLOAT64)) AS Discount,
  TransactionStatus, IFNULL(SubmissionStatus,'') AS SubmissionStatus, IFNULL(ApprovalStatus,'') AS ApprovalStatus, IFNULL(PaymentStatus,'') AS PaymentStatus,
  FORMAT('%.2f', CAST(IFNULL(ExpectedReceived,0) AS FLOAT64)) AS ExpectedReceived, FORMAT('%.2f', CAST(IFNULL(ActualReceived,0) AS FLOAT64)) AS ActualReceived,
  FORMAT('%.2f', CAST(IFNULL(InterestThisPeriod,0) AS FLOAT64)) AS InterestThisPeriod, FORMAT('%.2f', CAST(IFNULL(PrincipleThisPeriod,0) AS FLOAT64)) AS PrincipleThisPeriod,
  FORMAT('%.2f', CAST(IFNULL(InterestEIRThisPeriod,0) AS FLOAT64)) AS InterestEIRThisPeriod, FORMAT('%.2f', CAST(IFNULL(PrincipleEIRThisPeriod,0) AS FLOAT64)) AS PrincipleEIRThisPeriod,
  CASE WHEN LOWER(TransactionStatus)='pending' THEN '' ELSE PaymentDate END AS PaymentDate,
  Period, TotalPeriods, FORMAT('%.2f', CAST(IFNULL(PendingPayment,0) AS FLOAT64)) AS PendingPayment,
  CASE WHEN LOWER(TransactionStatus)='pending' THEN '' ELSE PaymentMethod END AS PaymentMethod,
  CASE WHEN LOWER(TransactionStatus)='pending' THEN '' ELSE PaymentChannel END AS PaymentChannel,
  ExpectedDate, IFNULL(RefOrder,'') AS RefOrder,
  FORMAT('%.2f', CAST(IFNULL(RefundAmountBeforeFee,0) AS FLOAT64)) AS RefundAmountBeforeFee, FORMAT('%.2f', CAST(IFNULL(RefundAmountAfterFee,0) AS FLOAT64)) AS RefundAmountAfterFee,
  IFNULL(BillingAddress,'') AS BillingAddress,
  FORMAT_DATE('%d%m%Y', CURRENT_DATE('Asia/Bangkok')) AS BatchRunDate
FROM f

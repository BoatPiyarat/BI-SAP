-- Operator export query for the validated 2026-08-25 V3 NEWPAYMENT run.
-- Run as a BigQuery script. Every ASSERT must pass before the final 56-column result is returned.
-- The canonical immutable file already exists in the restricted archive; prefer copying that exact
-- object rather than reserializing this result when preparing a manual SAP upload.

DECLARE target_run_id STRING DEFAULT 'V3NIGHTLY-2026-08-25T14:32:37-0ce16d45';
DECLARE target_export_run_id STRING DEFAULT 'V3DAILY-20260825-143823-0c1c161f';

ASSERT (SELECT COUNT(*) FROM `pacific-plating-282708.sap_integration_v3.pipeline_run_log`
  WHERE run_id=target_run_id AND step='UNITS_2_5_ARCHIVE' AND status='SUCCESS')=1
  AS 'Target V3 run is not a completed Units 2-5 archive run';
ASSERT (SELECT COUNT(*) FROM `pacific-plating-282708.sap_integration_v3.export_archive`
  WHERE export_run_id=target_export_run_id
    AND delivery_status='ARCHIVED_PENDING_OBJECT_METADATA')=641
  AS 'Target archive ledger is no longer the reviewed 641-identity archive-only artifact';
ASSERT (SELECT COUNT(*) FROM `pacific-plating-282708.sap_integration_v3.v3_unit5_newpayment_delivery_ready`)=4288
  AS 'Mutable delivery-ready table has changed since physical archive validation';
ASSERT (SELECT COUNT(*) FROM (
  SELECT OrderItem,SAFE_CAST(Period AS INT64),COUNT(*) n
  FROM `pacific-plating-282708.sap_integration_v3.v3_unit5_newpayment_delivery_ready`
  GROUP BY 1,2 HAVING n!=1))=0
  AS 'Delivery-ready result contains duplicate item-periods';
ASSERT (SELECT COUNT(*) FROM (
  SELECT OrderItem,COUNT(*) row_n,COUNT(DISTINCT SAFE_CAST(Period AS INT64)) period_n,
    MAX(SAFE_CAST(TotalPeriods AS INT64)) total_n
  FROM `pacific-plating-282708.sap_integration_v3.v3_unit5_newpayment_delivery_ready`
  GROUP BY OrderItem HAVING row_n!=total_n OR period_n!=total_n))=0
  AS 'Delivery-ready result contains incomplete item spines';

SELECT CompanyDB,OrderID,OrderItem,InvoiceNo,OrderDate,InsuredID,Title,FirstName,LastName,
  InsurerCode,InsuranceGroup,InsuranceType,InsuranceProduct,ProductType,PolicyType,Endorse,
  PolicyDate,PolicyNo,EndorsementNo,ChassisNo,LicensePlate,GrossPremium,StampDuty,VAT,
  TotalPremium,WHT,TotalEIR,TotalSBT,ProcessingFee,ProcessingFeeVat,ShippingFee,ShippingFeeVat,
  TotalAmount,Discount,TransactionStatus,SubmissionStatus,ApprovalStatus,PaymentStatus,
  ExpectedReceived,ActualReceived,InterestThisPeriod,PrincipleThisPeriod,InterestEIRThisPeriod,
  PrincipleEIRThisPeriod,PaymentDate,Period,TotalPeriods,PendingPayment,PaymentMethod,
  PaymentChannel,ExpectedDate,RefOrder,RefundAmountBeforeFee,RefundAmountAfterFee,BillingAddress,
  BatchRunDate
FROM `pacific-plating-282708.sap_integration_v3.v3_unit5_newpayment_delivery_ready`
ORDER BY OrderItem,SAFE_CAST(Period AS INT64);

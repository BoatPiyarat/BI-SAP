-- HUMAN FALLBACK / READ ONLY. Exports one exact immutable Scenario 1 month-end snapshot.
-- Replace only the sentinel, then use the mandatory cost-controlled wrapper:
--   scripts/bq_safe_query.sh --project pacific-plating-282708 \
--     -f sql/operator/20260827_monthend_missing_sap_onetime.sql -- \
--     --format=csv --location=asia-southeast1
-- Never use direct `bq query`. A Class-A source PASS does not authorize export or upload.

DECLARE target_snapshot_run_id STRING DEFAULT 'REPLACE_WITH_REVIEWED_SNAPSHOT_RUN_ID';
DECLARE target_snapshot_date DATE;

ASSERT target_snapshot_run_id!='REPLACE_WITH_REVIEWED_SNAPSHOT_RUN_ID'
  AS 'Set target_snapshot_run_id to the exact independently reviewed immutable snapshot';
ASSERT (SELECT COUNT(*)
  FROM `pacific-plating-282708.sap_integration_v3.v3_monthend_onetime_manifest`
  WHERE snapshot_run_id=target_snapshot_run_id AND flow_key='ORDINARY_ONETIME_CREATE'
    AND build_contract='DDL103_MONTHEND_ONETIME_V1')=1
  AS 'Exact Scenario 1 immutable snapshot manifest is missing or ambiguous';
SET target_snapshot_date=(SELECT DATE(completed_at)
  FROM `pacific-plating-282708.sap_integration_v3.v3_monthend_onetime_manifest`
  WHERE snapshot_run_id=target_snapshot_run_id);

-- Partition-bound, fixed copies ensure all later validation and final output see the same rows.
CREATE TEMP TABLE _target_payload AS
SELECT snapshot_run_id,pipeline_run_id,CompanyDB,OrderID,OrderItem,InvoiceNo,OrderDate,InsuredID,
  Title,FirstName,LastName,InsurerCode,InsuranceGroup,InsuranceType,InsuranceProduct,ProductType,
  PolicyType,Endorse,PolicyDate,PolicyNo,EndorsementNo,ChassisNo,LicensePlate,GrossPremium,
  StampDuty,VAT,TotalPremium,WHT,TotalEIR,TotalSBT,ProcessingFee,ProcessingFeeVat,ShippingFee,
  ShippingFeeVat,TotalAmount,Discount,TransactionStatus,SubmissionStatus,ApprovalStatus,
  PaymentStatus,ExpectedReceived,ActualReceived,InterestThisPeriod,PrincipleThisPeriod,
  InterestEIRThisPeriod,PrincipleEIRThisPeriod,PaymentDate,Period,TotalPeriods,PendingPayment,
  PaymentMethod,PaymentChannel,ExpectedDate,RefOrder,RefundAmountBeforeFee,RefundAmountAfterFee,
  BillingAddress,BatchRunDate,payload_hash,built_at
FROM `pacific-plating-282708.sap_integration_v3.v3_monthend_onetime_payload`
WHERE snapshot_run_id=target_snapshot_run_id AND DATE(built_at)=target_snapshot_date;
CREATE TEMP TABLE _target_identity AS
SELECT snapshot_run_id,pipeline_run_id,flow_key,source_flow,order_item,order_id,period,charge_id,
  invoice_no,source_charge_time,source_payment_date_ict,payload_hash,built_at
FROM `pacific-plating-282708.sap_integration_v3.v3_monthend_onetime_identity`
WHERE snapshot_run_id=target_snapshot_run_id AND DATE(built_at)=target_snapshot_date;
CREATE TEMP TABLE _target_hold AS
SELECT snapshot_run_id,pipeline_run_id,flow_key,order_item,order_id,period,charge_id,invoice_no,
  charge_amount,source_charge_time,source_payment_date_ict,hold_code,hold_reason,detected_at
FROM `pacific-plating-282708.sap_integration_v3.v3_monthend_onetime_hold`
WHERE snapshot_run_id=target_snapshot_run_id AND DATE(detected_at)=target_snapshot_date;

ASSERT (SELECT source_event_count=payload_count+hold_count
  FROM `pacific-plating-282708.sap_integration_v3.v3_monthend_onetime_manifest`
  WHERE snapshot_run_id=target_snapshot_run_id) AS 'Snapshot population is not conserved';
ASSERT (SELECT payload_count
  FROM `pacific-plating-282708.sap_integration_v3.v3_monthend_onetime_manifest`
  WHERE snapshot_run_id=target_snapshot_run_id)=(SELECT COUNT(*) FROM _target_payload)
  AS 'Manifest and payload counts differ';
ASSERT (SELECT hold_count
  FROM `pacific-plating-282708.sap_integration_v3.v3_monthend_onetime_manifest`
  WHERE snapshot_run_id=target_snapshot_run_id)=(SELECT COUNT(*) FROM _target_hold)
  AS 'Manifest and durable hold counts differ';
ASSERT (SELECT COUNT(*) FROM _target_identity)=(SELECT COUNT(*) FROM _target_payload)
  AS 'Payload and identity counts differ';
ASSERT (SELECT COUNT(*) FROM (
  SELECT ordinal_position-2 ordinal_position,column_name,data_type
  FROM `pacific-plating-282708.sap_integration_v3.INFORMATION_SCHEMA.COLUMNS`
  WHERE table_name='v3_monthend_onetime_payload' AND ordinal_position BETWEEN 3 AND 58
  EXCEPT DISTINCT SELECT ordinal_position,column_name,data_type
  FROM `pacific-plating-282708.sap_integration_v3.INFORMATION_SCHEMA.COLUMNS`
  WHERE table_name='v3_unit5_newpayment_delivery_ready'))=0
  AND (SELECT COUNT(*) FROM (
  SELECT ordinal_position,column_name,data_type
  FROM `pacific-plating-282708.sap_integration_v3.INFORMATION_SCHEMA.COLUMNS`
  WHERE table_name='v3_unit5_newpayment_delivery_ready'
  EXCEPT DISTINCT SELECT ordinal_position-2,column_name,data_type
  FROM `pacific-plating-282708.sap_integration_v3.INFORMATION_SCHEMA.COLUMNS`
  WHERE table_name='v3_monthend_onetime_payload' AND ordinal_position BETWEEN 3 AND 58))=0
  AS 'Snapshot differs from the canonical 56-column positional contract';
ASSERT (SELECT COUNT(*) FROM (SELECT OrderItem,Period,InvoiceNo,COUNT(*) row_count
  FROM _target_payload GROUP BY 1,2,3 HAVING row_count!=1))=0
  AS 'Snapshot contains a duplicate SAP identity';
ASSERT (SELECT COUNT(*) FROM _target_payload p JOIN _target_identity i
    ON i.snapshot_run_id=p.snapshot_run_id AND i.order_item=p.OrderItem
   AND CAST(i.period AS STRING)=p.Period AND i.invoice_no=p.InvoiceNo
  WHERE i.source_flow!='ONETIME' OR i.flow_key!='ORDINARY_ONETIME_CREATE'
    OR i.payload_hash!=p.payload_hash
    OR p.payload_hash!=TO_HEX(SHA256(TO_JSON_STRING(STRUCT(
      p.CompanyDB,p.OrderID,p.OrderItem,p.InvoiceNo,p.OrderDate,p.InsuredID,p.Title,p.FirstName,
      p.LastName,p.InsurerCode,p.InsuranceGroup,p.InsuranceType,p.InsuranceProduct,p.ProductType,
      p.PolicyType,p.Endorse,p.PolicyDate,p.PolicyNo,p.EndorsementNo,p.ChassisNo,p.LicensePlate,
      p.GrossPremium,p.StampDuty,p.VAT,p.TotalPremium,p.WHT,p.TotalEIR,p.TotalSBT,p.ProcessingFee,
      p.ProcessingFeeVat,p.ShippingFee,p.ShippingFeeVat,p.TotalAmount,p.Discount,
      p.TransactionStatus,p.SubmissionStatus,p.ApprovalStatus,p.PaymentStatus,p.ExpectedReceived,
      p.ActualReceived,p.InterestThisPeriod,p.PrincipleThisPeriod,p.InterestEIRThisPeriod,
      p.PrincipleEIRThisPeriod,p.PaymentDate,p.Period,p.TotalPeriods,p.PendingPayment,
      p.PaymentMethod,p.PaymentChannel,p.ExpectedDate,p.RefOrder,p.RefundAmountBeforeFee,
      p.RefundAmountAfterFee,p.BillingAddress,p.BatchRunDate)))))=0
  AS 'Source flow, declared flow, or immutable payload hash differs';
ASSERT (SELECT COUNT(*) FROM _target_payload
  WHERE TransactionStatus!='Paid' OR Period!='1' OR TotalPeriods!='1'
    OR LENGTH(InvoiceNo)>30 OR LENGTH(PolicyNo)>50
    OR NULLIF(TRIM(InvoiceNo),'') IS NULL OR NULLIF(TRIM(PaymentDate),'') IS NULL
    OR NULLIF(TRIM(PaymentMethod),'') IS NULL OR NULLIF(TRIM(PaymentChannel),'') IS NULL)=0
  AS 'Final output violates the Paid ONETIME contract';
ASSERT (SELECT COUNT(*) FROM (SELECT OrderItem,date_value FROM _target_payload
  UNPIVOT(date_value FOR date_column IN
    (OrderDate,PolicyDate,ExpectedDate,PaymentDate,BatchRunDate))
  WHERE LENGTH(IFNULL(date_value,''))!=8 OR SAFE.PARSE_DATE('%d%m%Y',date_value) IS NULL))=0
  AS 'Final output contains an invalid interface date';
ASSERT (SELECT COUNT(*) FROM _target_payload p JOIN _target_hold h
    ON h.snapshot_run_id=p.snapshot_run_id AND h.order_item=p.OrderItem
   AND CAST(h.period AS STRING)=p.Period AND h.invoice_no IS NOT DISTINCT FROM p.InvoiceNo)=0
  AS 'Immutable payload intersects a durable hold';

SELECT CompanyDB,OrderID,OrderItem,InvoiceNo,OrderDate,InsuredID,Title,FirstName,LastName,
  InsurerCode,InsuranceGroup,InsuranceType,InsuranceProduct,ProductType,PolicyType,Endorse,
  PolicyDate,PolicyNo,EndorsementNo,ChassisNo,LicensePlate,GrossPremium,StampDuty,VAT,TotalPremium,
  WHT,TotalEIR,TotalSBT,ProcessingFee,ProcessingFeeVat,ShippingFee,ShippingFeeVat,TotalAmount,
  Discount,TransactionStatus,SubmissionStatus,ApprovalStatus,PaymentStatus,ExpectedReceived,
  ActualReceived,InterestThisPeriod,PrincipleThisPeriod,InterestEIRThisPeriod,
  PrincipleEIRThisPeriod,PaymentDate,Period,TotalPeriods,PendingPayment,PaymentMethod,
  PaymentChannel,ExpectedDate,RefOrder,RefundAmountBeforeFee,RefundAmountAfterFee,BillingAddress,
  BatchRunDate
FROM _target_payload
ORDER BY OrderItem,SAFE_CAST(Period AS INT64),InvoiceNo;

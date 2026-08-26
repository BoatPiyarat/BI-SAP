-- HUMAN FALLBACK / READ ONLY. Scenario 1 RCB/ONETIME CREATE interface rows.
-- Replace the sentinel with the exact reviewed pipeline run. This query never writes GCS.

DECLARE target_run_id STRING DEFAULT 'REPLACE_WITH_REVIEWED_PIPELINE_RUN_ID';

ASSERT target_run_id!='REPLACE_WITH_REVIEWED_PIPELINE_RUN_ID'
  AS 'Set target_run_id to the exact reviewed pipeline run';
ASSERT (SELECT COUNT(*) FROM `pacific-plating-282708.sap_integration_v3.pipeline_run_log`
  WHERE run_id=target_run_id AND step='UNIT1_COMPLETE' AND status='SUCCESS')=1
  AS 'Scenario 1 manual export requires one successful Unit 1 completion';
ASSERT (SELECT COUNT(*) FROM `pacific-plating-282708.sap_integration_v3.v3_unit5_payload_identity`
  WHERE pipeline_run_id=target_run_id AND file_role='CREATE_ONETIME')=
  (SELECT COUNT(*) FROM `pacific-plating-282708.sap_integration_v3.v3_onetime_create_ready`)
  AS 'Scenario 1 ready/identity cardinality differs for target run';
ASSERT (SELECT COUNT(*) FROM (SELECT OrderItem,Period,InvoiceNo,COUNT(*) n
  FROM `pacific-plating-282708.sap_integration_v3.v3_onetime_create_ready`
  GROUP BY 1,2,3 HAVING n!=1))=0 AS 'Ready canonical paid identity is duplicated';
ASSERT (SELECT COUNT(*) FROM (SELECT order_item,period,invoice_no,COUNT(*) n
  FROM `pacific-plating-282708.sap_integration_v3.v3_unit5_payload_identity`
  WHERE pipeline_run_id=target_run_id AND file_role='CREATE_ONETIME'
  GROUP BY 1,2,3 HAVING n!=1))=0 AS 'Target-run payload identity is duplicated';
ASSERT (SELECT COUNT(*) FROM `pacific-plating-282708.sap_integration_v3.v3_onetime_create_ready` p
  WHERE NOT EXISTS (SELECT 1
    FROM `pacific-plating-282708.sap_integration_v3.v3_unit5_payload_identity` i
    WHERE i.pipeline_run_id=target_run_id AND i.file_role='CREATE_ONETIME'
      AND i.order_item=p.OrderItem AND CAST(i.period AS STRING)=p.Period
      AND i.invoice_no=p.InvoiceNo))=0 AS 'Ready row is not bound to target run';
ASSERT (SELECT COUNT(*) FROM `pacific-plating-282708.sap_integration_v3.v3_unit5_payload_identity` i
  WHERE i.pipeline_run_id=target_run_id AND i.file_role='CREATE_ONETIME'
    AND NOT EXISTS (SELECT 1
      FROM `pacific-plating-282708.sap_integration_v3.v3_onetime_create_ready` p
      WHERE p.OrderItem=i.order_item AND p.Period=CAST(i.period AS STRING)
        AND p.InvoiceNo=i.invoice_no))=0 AS 'Target-run identity lacks ready row';
ASSERT (SELECT COUNT(*)
  FROM `pacific-plating-282708.sap_integration_v3.v3_onetime_create_ready` p
  JOIN `pacific-plating-282708.sap_integration_v3.v3_unit5_payload_identity` i
    ON i.pipeline_run_id=target_run_id AND i.file_role='CREATE_ONETIME'
   AND i.order_item=p.OrderItem AND CAST(i.period AS STRING)=p.Period AND i.invoice_no=p.InvoiceNo)=
  (SELECT COUNT(*) FROM `pacific-plating-282708.sap_integration_v3.v3_onetime_create_ready`)
  AS 'Target-run identity join is not bijective';
ASSERT (SELECT COUNT(*)
  FROM `pacific-plating-282708.sap_integration_v3.v3_onetime_create_ready` p
  JOIN `pacific-plating-282708.sap_integration_v3.v3_unit5_payload_identity` i
    ON i.pipeline_run_id=target_run_id AND i.file_role='CREATE_ONETIME'
   AND i.order_item=p.OrderItem AND CAST(i.period AS STRING)=p.Period AND i.invoice_no=p.InvoiceNo
  WHERE i.payload_hash!=TO_HEX(SHA256(TO_JSON_STRING(p))))=0
  AS 'Scenario 1 ready row differs from reviewed payload identity hash';
ASSERT (SELECT COUNT(*)
  FROM `pacific-plating-282708.sap_integration_v3.v3_unit5_payload_identity` i
  JOIN `pacific-plating-282708.sap_integration_v3.v3_onetime_create_hold` h
    ON h.pipeline_run_id=i.pipeline_run_id AND h.order_item=i.order_item AND h.period=i.period
   AND h.invoice_no IS NOT DISTINCT FROM i.invoice_no AND h.charge_id=i.charge_id
  WHERE i.pipeline_run_id=target_run_id AND i.file_role='CREATE_ONETIME')=0
  AS 'Target-run released identity intersects a durable hold';

SELECT p.CompanyDB,p.OrderID,p.OrderItem,p.InvoiceNo,p.OrderDate,p.InsuredID,p.Title,p.FirstName,
  p.LastName,p.InsurerCode,p.InsuranceGroup,p.InsuranceType,p.InsuranceProduct,p.ProductType,
  p.PolicyType,p.Endorse,p.PolicyDate,p.PolicyNo,p.EndorsementNo,p.ChassisNo,p.LicensePlate,
  p.GrossPremium,p.StampDuty,p.VAT,p.TotalPremium,p.WHT,p.TotalEIR,p.TotalSBT,p.ProcessingFee,
  p.ProcessingFeeVat,p.ShippingFee,p.ShippingFeeVat,p.TotalAmount,p.Discount,p.TransactionStatus,
  p.SubmissionStatus,p.ApprovalStatus,p.PaymentStatus,p.ExpectedReceived,p.ActualReceived,
  p.InterestThisPeriod,p.PrincipleThisPeriod,p.InterestEIRThisPeriod,p.PrincipleEIRThisPeriod,
  p.PaymentDate,p.Period,p.TotalPeriods,p.PendingPayment,p.PaymentMethod,p.PaymentChannel,
  p.ExpectedDate,p.RefOrder,p.RefundAmountBeforeFee,p.RefundAmountAfterFee,p.BillingAddress,
  p.BatchRunDate
FROM `pacific-plating-282708.sap_integration_v3.v3_onetime_create_ready` p
JOIN `pacific-plating-282708.sap_integration_v3.v3_unit5_payload_identity` i
  ON i.pipeline_run_id=target_run_id AND i.file_role='CREATE_ONETIME'
 AND i.order_item=p.OrderItem AND CAST(i.period AS STRING)=p.Period AND i.invoice_no=p.InvoiceNo
ORDER BY p.OrderItem,SAFE_CAST(p.Period AS INT64),p.InvoiceNo;

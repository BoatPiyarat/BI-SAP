-- Class A / one-time production write authorized by Boat on 2026-08-17.
-- Export only the immutable PASS snapshot. Refuse overwrite and any manifest drift.
DECLARE v_request_id STRING DEFAULT 'MO-RCL-20260817-PROD-02';
DECLARE v_candidate_sha256 STRING DEFAULT
  '8ae11f137495acea6a744b6d1a54f0ee087ea21a6c3f1acbdf8cda04ef182515';
DECLARE v_schema_sha256 STRING DEFAULT
  'c4659cb3e47f12588cef912fa661346477966197e5e05cdf8f5f8d05c981a265';
DECLARE v_file_name STRING DEFAULT 'INSURANCE_RCB_06_MO_RCL_RECOVERY_20260817.csv';
DECLARE v_export_uri STRING DEFAULT
  'gs://interface-file/RCB_MOTOR/INSURANCE_RCB_06_MO_RCL_RECOVERY_20260817_*.csv';

ASSERT (SELECT COUNT(*)
  FROM `pacific-plating-282708.sap_integration_v3.mo_rcl_prod02_gate_manifest`
  WHERE request_id=v_request_id AND gate_status='PASS' AND declared_flow='RCL'
    AND operation='NEWPAYMENT' AND delivery_folder='RCB_MOTOR' AND file_name=v_file_name
    AND CONCAT('gs://interface-file/',delivery_folder,'/',
      REGEXP_REPLACE(file_name,r'[.]csv$','_*.csv'))=v_export_uri
    AND row_count=6093 AND item_count=939 AND paid_count=944 AND pending_count=5149
    AND hold_item_count=1173 AND candidate_sha256=v_candidate_sha256
    AND schema_sha256=v_schema_sha256)=1
  AS 'exact immutable PROD-02 PASS manifest is missing or changed';

CREATE SNAPSHOT TABLE `pacific-plating-282708.sap_integration_v3.mo_rcl_prod02_export_snapshot`
CLONE `pacific-plating-282708.sap_integration_v3.mo_rcl_prod02_ready`;

ASSERT (SELECT COUNT(*)
  FROM `pacific-plating-282708.sap_integration_v3.mo_rcl_prod02_export_snapshot`)=6093
  AS 'ready row count changed after gate';
ASSERT (SELECT COUNT(DISTINCT OrderItem)
  FROM `pacific-plating-282708.sap_integration_v3.mo_rcl_prod02_export_snapshot`)=939
  AS 'ready item count changed after gate';
ASSERT (SELECT TO_HEX(SHA256(STRING_AGG(TO_JSON_STRING(r),'\n'
    ORDER BY OrderItem,SAFE_CAST(Period AS INT64))))
  FROM `pacific-plating-282708.sap_integration_v3.mo_rcl_prod02_export_snapshot` r)=v_candidate_sha256
  AS 'ready payload hash changed after gate';
ASSERT (SELECT TO_HEX(SHA256(STRING_AGG(CONCAT(column_name,'|',data_type,'|',ordinal_position),'\n'
    ORDER BY ordinal_position)))
  FROM `pacific-plating-282708.sap_integration_v3.INFORMATION_SCHEMA.COLUMNS`
  WHERE table_name='mo_rcl_prod02_export_snapshot')=v_schema_sha256
  AS 'export snapshot schema hash changed after gate';
ASSERT (SELECT COUNT(*) FROM (
  SELECT OrderItem,COUNT(*) row_n,COUNT(DISTINCT SAFE_CAST(Period AS INT64)) period_n,
    MIN(SAFE_CAST(Period AS INT64)) first_period,MAX(SAFE_CAST(Period AS INT64)) last_period,
    COUNT(DISTINCT SAFE_CAST(TotalPeriods AS INT64)) total_versions,
    MAX(SAFE_CAST(TotalPeriods AS INT64)) total_n
  FROM `pacific-plating-282708.sap_integration_v3.mo_rcl_prod02_export_snapshot`
  GROUP BY OrderItem
  HAVING row_n!=total_n OR period_n!=total_n OR first_period!=1 OR last_period!=total_n
    OR total_versions!=1))=0 AS 'complete RCL spine regressed after gate';
ASSERT (SELECT COUNT(*)
  FROM `pacific-plating-282708.sap_integration_v3.mo_rcl_prod02_export_snapshot`
  WHERE TransactionStatus NOT IN ('Paid','Pending')
    OR (TransactionStatus='Pending' AND PaymentDate!='')
    OR (TransactionStatus='Paid' AND (InvoiceNo='' OR PaymentDate='')))=0
  AS 'Paid/Pending contract regressed after gate';
ASSERT (SELECT COUNT(*)
  FROM `pacific-plating-282708.sap_integration_v3.mo_rcl_prod02_export_snapshot` r
  WHERE REGEXP_CONTAINS(TO_JSON_STRING(r),r':null|:"NULL"'))=0
  AS 'export snapshot contains SQL NULL or literal NULL';

EXPORT DATA OPTIONS(
  uri='gs://interface-file/RCB_MOTOR/INSURANCE_RCB_06_MO_RCL_RECOVERY_20260817_*.csv',
  format='CSV',overwrite=false,header=true
) AS
SELECT CompanyDB,OrderID,OrderItem,InvoiceNo,OrderDate,InsuredID,Title,FirstName,LastName,
  InsurerCode,InsuranceGroup,InsuranceType,InsuranceProduct,ProductType,PolicyType,Endorse,
  PolicyDate,PolicyNo,EndorsementNo,ChassisNo,LicensePlate,GrossPremium,StampDuty,VAT,
  TotalPremium,WHT,TotalEIR,TotalSBT,ProcessingFee,ProcessingFeeVat,ShippingFee,ShippingFeeVat,
  TotalAmount,Discount,TransactionStatus,SubmissionStatus,ApprovalStatus,PaymentStatus,
  ExpectedReceived,ActualReceived,InterestThisPeriod,PrincipleThisPeriod,InterestEIRThisPeriod,
  PrincipleEIRThisPeriod,PaymentDate,Period,TotalPeriods,PendingPayment,PaymentMethod,
  PaymentChannel,ExpectedDate,RefOrder,RefundAmountBeforeFee,RefundAmountAfterFee,BillingAddress,
  BatchRunDate
FROM `pacific-plating-282708.sap_integration_v3.mo_rcl_prod02_export_snapshot`
ORDER BY OrderItem,SAFE_CAST(Period AS INT64);

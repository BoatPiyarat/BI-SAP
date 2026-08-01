-- Source only / Class A. CALL writes one July-only CSV to the restricted archive prefix only.
-- Exact bytes must pass UAT2, then be copied to production by the reviewed operator runbook.
CREATE OR REPLACE PROCEDURE `pacific-plating-282708.sap_integration_v3.sp_export_july_payment_to_archive`()
BEGIN
  DECLARE v_export_run_id STRING DEFAULT CONCAT('V3JULY-', FORMAT_TIMESTAMP('%Y%m%d-%H%M%S',CURRENT_TIMESTAMP()), '-', SUBSTR(GENERATE_UUID(),1,8));
  DECLARE v_file_name STRING;
  DECLARE v_archive_uri STRING;
  DECLARE export_rows INT64;

  CALL `pacific-plating-282708.sap_integration_v3.sp_build_july_export_shadow`();
  SET export_rows=(SELECT COUNT(*) FROM `pacific-plating-282708.sap_integration_v3.july_export_ready`);
  ASSERT export_rows>0 AS 'No unexported July payment rows; no file written';
  ASSERT (SELECT COUNT(*) FROM `pacific-plating-282708.sap_integration_v3.INFORMATION_SCHEMA.COLUMNS`
    WHERE table_name='july_export_ready')=56 AS 'Position contract failure: expected exactly 56 columns';

  SET v_file_name=CONCAT('INSURANCE_RCB_01_V3_JULY_PAYMENT_20260731_',v_export_run_id);
  SET v_archive_uri=CONCAT('gs://rcb-bronze-zone/sap-interface-archive/2026/07/31/',
    v_export_run_id,'/',v_file_name,'_*.csv');

  INSERT INTO `pacific-plating-282708.sap_integration_v3.export_archive`
    (export_run_id,order_item,period,charge_id,raw_payment_date,file_name,gcs_uri,archive_uri,delivery_folder,
     contract_version,payload_hash,payload_json,run_type,delivery_status,exported_at)
  SELECT v_export_run_id,e.order_item,e.period,e.charge_id,DATE(pe.charge_time),v_file_name,NULL,v_archive_uri,
    'RCB_MOTOR','SAP_INSURANCE_56_V1',TO_HEX(SHA256(TO_JSON_STRING(r))),TO_JSON_STRING(r),
    'MANUAL_JULY_CLOSE','PREPARED_ARCHIVE',CURRENT_TIMESTAMP()
  FROM `pacific-plating-282708.sap_integration_v3.expected_state` e
  JOIN `pacific-plating-282708.sap_integration_v3.stg_payment_events` pe USING(charge_id)
  JOIN `pacific-plating-282708.sap_integration_v3.july_export_ready` r
    ON r.OrderItem=e.order_item AND SAFE_CAST(r.Period AS INT64)=e.period
  WHERE DATE(pe.charge_time)>=DATE '2026-07-01' AND DATE(pe.charge_time)<DATE '2026-08-01';

  ASSERT (SELECT COUNT(*) FROM `pacific-plating-282708.sap_integration_v3.export_archive`
    WHERE export_run_id=v_export_run_id AND raw_payment_date>=DATE '2026-08-01')=0
    AS 'August raw PaymentDate in prepared archive; export aborted';

  EXECUTE IMMEDIATE FORMAT("""
    EXPORT DATA OPTIONS(uri='%s',format='CSV',overwrite=false,header=true)
    AS SELECT CompanyDB,OrderID,OrderItem,InvoiceNo,OrderDate,InsuredID,Title,FirstName,LastName,
      InsurerCode,InsuranceGroup,InsuranceType,InsuranceProduct,ProductType,PolicyType,Endorse,
      PolicyDate,PolicyNo,EndorsementNo,ChassisNo,LicensePlate,GrossPremium,StampDuty,VAT,
      TotalPremium,WHT,TotalEIR,TotalSBT,ProcessingFee,ProcessingFeeVat,ShippingFee,ShippingFeeVat,
      TotalAmount,Discount,TransactionStatus,SubmissionStatus,ApprovalStatus,PaymentStatus,
      ExpectedReceived,ActualReceived,InterestThisPeriod,PrincipleThisPeriod,InterestEIRThisPeriod,
      PrincipleEIRThisPeriod,PaymentDate,Period,TotalPeriods,PendingPayment,PaymentMethod,
      PaymentChannel,ExpectedDate,RefOrder,RefundAmountBeforeFee,RefundAmountAfterFee,BillingAddress,
      BatchRunDate
    FROM `pacific-plating-282708.sap_integration_v3.july_export_ready`
  """,v_archive_uri);

  UPDATE `pacific-plating-282708.sap_integration_v3.export_archive`
  SET delivery_status='ARCHIVED_PENDING_UAT2',exported_at=CURRENT_TIMESTAMP()
  WHERE export_run_id=v_export_run_id;
END;

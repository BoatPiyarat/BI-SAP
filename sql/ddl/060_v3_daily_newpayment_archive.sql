-- Class A / archive write when called. Generic daily NEWPAYMENT successor to July-only 049.
-- This procedure writes the restricted archive prefix only. Production delivery is a separate
-- exact-generation copy gate; never reserialize or write interface-file from this procedure.

CREATE OR REPLACE PROCEDURE `pacific-plating-282708.sap_integration_v3.sp_export_v3_daily_newpayment_archive`(
  p_pipeline_run_id STRING
)
BEGIN
  DECLARE v_period_start DATE;
  DECLARE v_period_end DATE;
  DECLARE v_export_run_id STRING DEFAULT CONCAT('V3DAILY-',
    FORMAT_TIMESTAMP('%Y%m%d-%H%M%S',CURRENT_TIMESTAMP()),'-',SUBSTR(GENERATE_UUID(),1,8));
  DECLARE v_file_name STRING;
  DECLARE v_archive_uri STRING;
  DECLARE v_rows INT64;

  ASSERT NULLIF(TRIM(p_pipeline_run_id),'') IS NOT NULL
    AS 'Daily NEWPAYMENT archive requires pipeline_run_id';
  ASSERT (SELECT COUNT(*) FROM `pacific-plating-282708.sap_integration_v3.sap_period_state`
    WHERE status='OPEN')=1 AS 'Daily archive requires exactly one OPEN period';
  SET (v_period_start,v_period_end)=(SELECT AS STRUCT period_start,period_end
    FROM `pacific-plating-282708.sap_integration_v3.sap_period_state` WHERE status='OPEN');
  SET v_rows=(SELECT COUNT(*)
    FROM `pacific-plating-282708.sap_integration_v3.v3_unit5_newpayment_delivery_ready`);

  ASSERT v_rows>0 AS 'No delivery-ready NEWPAYMENT rows; no archive object written';
  ASSERT (SELECT COUNT(*) FROM `pacific-plating-282708.sap_integration_v3.INFORMATION_SCHEMA.COLUMNS`
    WHERE table_name='v3_unit5_newpayment_delivery_ready')=56
    AS 'Daily NEWPAYMENT archive requires exactly 56 columns';
  ASSERT (SELECT COUNT(*)
    FROM `pacific-plating-282708.sap_integration_v3.v3_unit5_payload_identity` i
    JOIN `pacific-plating-282708.sap_integration_v3.v3_unit5_newpayment_delivery_ready` p
      ON p.OrderItem=i.order_item AND SAFE_CAST(p.Period AS INT64)=i.period
     AND p.InvoiceNo=i.invoice_no
    WHERE i.pipeline_run_id=p_pipeline_run_id AND i.file_role='NEWPAYMENT')=v_rows
    AS 'Delivery-ready rows do not conserve against this run identity';
  ASSERT (SELECT COUNT(*)
    FROM `pacific-plating-282708.sap_integration_v3.v3_unit5_newpayment_delivery_ready`
    WHERE SAFE.PARSE_DATE('%d%m%Y',PaymentDate) IS NULL
       OR SAFE.PARSE_DATE('%d%m%Y',BatchRunDate) IS NULL
       OR SAFE.PARSE_DATE('%d%m%Y',PaymentDate)<v_period_start
       OR SAFE.PARSE_DATE('%d%m%Y',PaymentDate)>=v_period_end
       OR SAFE.PARSE_DATE('%d%m%Y',BatchRunDate)<v_period_start
       OR SAFE.PARSE_DATE('%d%m%Y',BatchRunDate)>=v_period_end)=0
    AS 'Daily archive contains PaymentDate/BatchRunDate outside the OPEN period';
  ASSERT (SELECT COUNT(*)
    FROM `pacific-plating-282708.sap_integration_v3.v3_unit5_payload_identity` i
    JOIN `pacific-plating-282708.sap_integration_v3.export_archive` a
      ON a.order_item=i.order_item AND a.period=i.period AND a.charge_id=i.charge_id
    WHERE i.pipeline_run_id=p_pipeline_run_id AND i.file_role='NEWPAYMENT'
      AND a.delivery_status IN ('PREPARED_ARCHIVE','ARCHIVED_PENDING_OBJECT_METADATA',
        'ARCHIVED_PENDING_DELIVERY','DELIVERED','PICKED_UP','ACKNOWLEDGED'))=0
    AS 'A current-run identity already has an active archive/delivery record; refusing replay';

  -- BU belongs only in the GCS folder (RCB_MOTOR/). SAP's basename contract always starts
  -- INSURANCE_RCB_; prefixing RCB_MOTOR_ changes the interface filename contract.
  SET v_file_name=CONCAT('INSURANCE_RCB_06_V3_DAILY_NEWPAYMENT_',
    FORMAT_DATE('%Y%m%d',CURRENT_DATE('Asia/Bangkok')),'_',v_export_run_id);
  SET v_archive_uri=CONCAT('gs://rcb-bronze-zone/sap-interface-archive/',
    FORMAT_DATE('%Y/%m/%d',CURRENT_DATE('Asia/Bangkok')),'/',v_export_run_id,'/',
    v_file_name,'_*.csv');

  INSERT INTO `pacific-plating-282708.sap_integration_v3.export_archive`
    (export_run_id,order_item,period,charge_id,raw_payment_date,file_name,gcs_uri,archive_uri,
     delivery_folder,contract_version,payload_hash,payload_json,run_type,delivery_status,exported_at)
  SELECT v_export_run_id,i.order_item,i.period,i.charge_id,DATE(e.charge_time),v_file_name,NULL,
    v_archive_uri,'RCB_MOTOR','SAP_INSURANCE_56_V1',i.payload_hash,TO_JSON_STRING(p),
    'DAILY_NEWPAYMENT','PREPARED_ARCHIVE',CURRENT_TIMESTAMP()
  FROM `pacific-plating-282708.sap_integration_v3.v3_unit5_payload_identity` i
  JOIN `pacific-plating-282708.sap_integration_v3.v3_unit5_newpayment_delivery_ready` p
    ON p.OrderItem=i.order_item AND SAFE_CAST(p.Period AS INT64)=i.period
   AND p.InvoiceNo=i.invoice_no
  JOIN `pacific-plating-282708.sap_integration_v3.v3_unit2_event_shadow` e
    ON e.pipeline_run_id=i.pipeline_run_id AND e.order_item=i.order_item
   AND e.period=i.period AND e.charge_id=i.charge_id
  WHERE i.pipeline_run_id=p_pipeline_run_id AND i.file_role='NEWPAYMENT';

  ASSERT (SELECT COUNT(*) FROM `pacific-plating-282708.sap_integration_v3.export_archive`
    WHERE export_run_id=v_export_run_id)=v_rows AS 'Archive ledger row conservation failed';

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
    FROM `pacific-plating-282708.sap_integration_v3.v3_unit5_newpayment_delivery_ready`
  """,v_archive_uri);

  UPDATE `pacific-plating-282708.sap_integration_v3.export_archive`
  SET delivery_status='ARCHIVED_PENDING_OBJECT_METADATA',exported_at=CURRENT_TIMESTAMP()
  WHERE export_run_id=v_export_run_id;
END;

-- Class A / archive write when called. Safe replacement for the legacy manual export entry point.
-- Scope is explicit and limited to the currently proven RCB_MOTOR NEWPAYMENT contract.
-- This procedure never writes the production interface prefix; exact-generation delivery remains
-- a separate reviewed and approved operation.

CREATE TABLE IF NOT EXISTS
  `pacific-plating-282708.sap_integration_v3.manual_export_request` (
    export_run_id STRING NOT NULL,
    pipeline_run_id STRING NOT NULL,
    business_unit STRING NOT NULL,
    file_role STRING NOT NULL,
    requested_order_items ARRAY<STRING>,
    requested_order_ids ARRAY<STRING>,
    requested_by STRING NOT NULL,
    selected_payload_rows INT64 NOT NULL,
    selected_identity_rows INT64 NOT NULL,
    archive_uri STRING NOT NULL,
    request_status STRING NOT NULL,
    requested_at TIMESTAMP NOT NULL,
    completed_at TIMESTAMP
  )
PARTITION BY DATE(requested_at)
CLUSTER BY export_run_id, pipeline_run_id, request_status;

CREATE OR REPLACE PROCEDURE `pacific-plating-282708.sap_integration_v3.sp_manual_export`(
  p_pipeline_run_id STRING,
  p_business_unit STRING,
  p_file_role STRING,
  p_order_items ARRAY<STRING>,
  p_order_ids ARRAY<STRING>,
  p_requested_by STRING
)
BEGIN
  DECLARE v_period_start DATE;
  DECLARE v_period_end DATE;
  DECLARE v_export_run_id STRING DEFAULT CONCAT('V3MANUAL-',
    FORMAT_TIMESTAMP('%Y%m%d-%H%M%S',CURRENT_TIMESTAMP()),'-',SUBSTR(GENERATE_UUID(),1,8));
  DECLARE v_file_name STRING;
  DECLARE v_archive_uri STRING;
  DECLARE v_identity_rows INT64;

  ASSERT NULLIF(TRIM(p_pipeline_run_id),'') IS NOT NULL
    AS 'Manual export requires pipeline_run_id';
  ASSERT UPPER(TRIM(IFNULL(p_business_unit,'')))='RCB_MOTOR'
    AS 'Manual export currently supports only RCB_MOTOR';
  ASSERT UPPER(TRIM(IFNULL(p_file_role,'')))='NEWPAYMENT'
    AS 'Manual export currently supports only NEWPAYMENT';
  ASSERT NULLIF(TRIM(p_requested_by),'') IS NOT NULL
    AS 'Manual export requires requested_by audit identity';
  ASSERT ARRAY_LENGTH(IFNULL(p_order_items,ARRAY<STRING>[]))>0
      OR ARRAY_LENGTH(IFNULL(p_order_ids,ARRAY<STRING>[]))>0
    AS 'Manual export requires at least one OrderItem or OrderID';
  ASSERT (SELECT COUNT(*) FROM `pacific-plating-282708.sap_integration_v3.sap_period_state`
    WHERE status='OPEN')=1 AS 'Manual export requires exactly one OPEN period';
  SET (v_period_start,v_period_end)=(SELECT AS STRUCT period_start,period_end
    FROM `pacific-plating-282708.sap_integration_v3.sap_period_state` WHERE status='OPEN');

  CREATE TEMP TABLE _selected_payload AS
  SELECT p.*
  FROM `pacific-plating-282708.sap_integration_v3.v3_unit5_newpayment_delivery_ready` p
  WHERE p.OrderItem IN UNNEST(IFNULL(p_order_items,ARRAY<STRING>[]))
     OR p.OrderID IN UNNEST(IFNULL(p_order_ids,ARRAY<STRING>[]));

  ASSERT (SELECT COUNT(*) FROM _selected_payload)>0
    AS 'Manual export scope matched no delivery-ready rows';
  ASSERT (SELECT COUNT(*) FROM `pacific-plating-282708.sap_integration_v3.INFORMATION_SCHEMA.COLUMNS`
    WHERE table_name='v3_unit5_newpayment_delivery_ready')=56
    AS 'Manual NEWPAYMENT archive requires exactly 56 columns';
  ASSERT (SELECT COUNT(*) FROM (
    SELECT OrderItem,COUNT(DISTINCT SAFE_CAST(Period AS INT64)) period_n,
      MIN(SAFE_CAST(Period AS INT64)) first_period,MAX(SAFE_CAST(Period AS INT64)) last_period,
      COUNT(DISTINCT SAFE_CAST(TotalPeriods AS INT64)) total_value_n,
      MAX(SAFE_CAST(TotalPeriods AS INT64)) total_n
    FROM _selected_payload GROUP BY OrderItem
    HAVING total_value_n!=1 OR first_period!=1 OR last_period!=total_n OR period_n!=total_n))=0
    AS 'Manual export scope contains an incomplete item period spine';
  ASSERT (SELECT COUNT(*) FROM _selected_payload
    WHERE LENGTH(PolicyNo)>50
       OR (TransactionStatus='Paid' AND NULLIF(TRIM(InvoiceNo),'') IS NULL)
       OR (NULLIF(PaymentDate,'') IS NOT NULL
         AND (LENGTH(PaymentDate)!=8 OR SAFE.PARSE_DATE('%d%m%Y',PaymentDate) IS NULL))
       OR SAFE.PARSE_DATE('%d%m%Y',BatchRunDate) IS NULL
       OR SAFE.PARSE_DATE('%d%m%Y',BatchRunDate)<v_period_start
       OR SAFE.PARSE_DATE('%d%m%Y',BatchRunDate)>=v_period_end)=0
    AS 'Manual export scope violates PolicyNo, InvoiceNo, or date contract';

  CREATE TEMP TABLE _selected_identity AS
  SELECT i.*
  FROM `pacific-plating-282708.sap_integration_v3.v3_unit5_payload_identity` i
  WHERE i.pipeline_run_id=p_pipeline_run_id AND i.file_role='NEWPAYMENT'
    AND EXISTS (SELECT 1 FROM _selected_payload p WHERE p.OrderItem=i.order_item)
    AND NOT EXISTS (SELECT 1
      FROM `pacific-plating-282708.sap_integration_v3.v3_unit5_balance_hold` h
      WHERE h.pipeline_run_id=p_pipeline_run_id AND h.order_item=i.order_item);

  SET v_identity_rows=(SELECT COUNT(*) FROM _selected_identity);
  ASSERT v_identity_rows>0 AS 'Manual export scope has no current-run NEWPAYMENT identities';
  ASSERT (SELECT COUNT(*) FROM _selected_identity i
    JOIN _selected_payload p ON p.OrderItem=i.order_item
      AND SAFE_CAST(p.Period AS INT64)=i.period AND p.InvoiceNo=i.invoice_no)=v_identity_rows
    AS 'Manual export identities do not conserve against the selected payload';
  ASSERT (SELECT COUNT(*) FROM _selected_identity i
    JOIN _selected_payload p ON p.OrderItem=i.order_item
      AND SAFE_CAST(p.Period AS INT64)=i.period AND p.InvoiceNo=i.invoice_no
    WHERE SAFE.PARSE_DATE('%d%m%Y',p.PaymentDate)<v_period_start
       OR SAFE.PARSE_DATE('%d%m%Y',p.PaymentDate)>=v_period_end)=0
    AS 'Manual export target payment event lies outside the OPEN period';
  ASSERT (SELECT COUNT(*) FROM _selected_identity i
    JOIN `pacific-plating-282708.sap_integration_v3.export_archive` a
      ON a.order_item=i.order_item AND a.period=i.period AND a.charge_id=i.charge_id
    WHERE a.delivery_status IN ('PREPARED_ARCHIVE','ARCHIVED_PENDING_OBJECT_METADATA',
      'ARCHIVED_PENDING_DELIVERY','DELIVERED','PICKED_UP','ACKNOWLEDGED'))=0
    AS 'A selected identity already has an active archive/delivery record; refusing replay';

  SET v_file_name=CONCAT('INSURANCE_RCB_06_V3_MANUAL_NEWPAYMENT_',
    FORMAT_DATE('%Y%m%d',CURRENT_DATE('Asia/Bangkok')),'_',v_export_run_id);
  SET v_archive_uri=CONCAT('gs://rcb-bronze-zone/sap-interface-archive/manual/',
    FORMAT_DATE('%Y/%m/%d',CURRENT_DATE('Asia/Bangkok')),'/',v_export_run_id,'/',
    v_file_name,'_*.csv');

  INSERT INTO `pacific-plating-282708.sap_integration_v3.manual_export_request`
    (export_run_id,pipeline_run_id,business_unit,file_role,requested_order_items,
     requested_order_ids,requested_by,selected_payload_rows,selected_identity_rows,archive_uri,
     request_status,requested_at)
  VALUES (v_export_run_id,p_pipeline_run_id,'RCB_MOTOR','NEWPAYMENT',
    IFNULL(p_order_items,ARRAY<STRING>[]),IFNULL(p_order_ids,ARRAY<STRING>[]),TRIM(p_requested_by),
    (SELECT COUNT(*) FROM _selected_payload),v_identity_rows,v_archive_uri,'PREPARING',
    CURRENT_TIMESTAMP());

  INSERT INTO `pacific-plating-282708.sap_integration_v3.export_archive`
    (export_run_id,order_item,period,charge_id,raw_payment_date,file_name,gcs_uri,archive_uri,
     delivery_folder,contract_version,payload_hash,payload_json,run_type,delivery_status,exported_at)
  SELECT v_export_run_id,i.order_item,i.period,i.charge_id,DATE(e.charge_time),v_file_name,NULL,
    v_archive_uri,'RCB_MOTOR','SAP_INSURANCE_56_V1',i.payload_hash,TO_JSON_STRING(p),
    'MANUAL','PREPARED_ARCHIVE',CURRENT_TIMESTAMP()
  FROM _selected_identity i
  JOIN _selected_payload p ON p.OrderItem=i.order_item
    AND SAFE_CAST(p.Period AS INT64)=i.period AND p.InvoiceNo=i.invoice_no
  JOIN `pacific-plating-282708.sap_integration_v3.v3_unit2_event_shadow` e
    ON e.pipeline_run_id=i.pipeline_run_id AND e.order_item=i.order_item
   AND e.period=i.period AND e.charge_id=i.charge_id;

  ASSERT (SELECT COUNT(*) FROM `pacific-plating-282708.sap_integration_v3.export_archive`
    WHERE export_run_id=v_export_run_id)=v_identity_rows
    AS 'Manual event-grain archive ledger conservation failed';

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
    FROM _selected_payload
  """,v_archive_uri);

  UPDATE `pacific-plating-282708.sap_integration_v3.export_archive`
  SET delivery_status='ARCHIVED_PENDING_OBJECT_METADATA',exported_at=CURRENT_TIMESTAMP()
  WHERE export_run_id=v_export_run_id;

  UPDATE `pacific-plating-282708.sap_integration_v3.manual_export_request`
  SET request_status='ARCHIVED_PENDING_OBJECT_METADATA',completed_at=CURRENT_TIMESTAMP()
  WHERE export_run_id=v_export_run_id;
END;

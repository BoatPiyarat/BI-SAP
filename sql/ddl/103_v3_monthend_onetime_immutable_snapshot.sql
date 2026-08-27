-- SOURCE ONLY / Class A. Scenario 1 current-month ONETIME/CREATE immutable fallback snapshot.
-- Creates V3-owned tables and a procedure only; it does not CALL, export, write GCS, touch SAP,
-- activate a Workflow, or mutate Cloud Scheduler.

CREATE TABLE IF NOT EXISTS
  `pacific-plating-282708.sap_integration_v3.v3_monthend_onetime_payload`
PARTITION BY DATE(built_at)
CLUSTER BY snapshot_run_id,OrderItem AS
SELECT CAST(NULL AS STRING) snapshot_run_id,CAST(NULL AS STRING) pipeline_run_id,
  p.CompanyDB,p.OrderID,p.OrderItem,p.InvoiceNo,p.OrderDate,p.InsuredID,p.Title,p.FirstName,
  p.LastName,p.InsurerCode,p.InsuranceGroup,p.InsuranceType,p.InsuranceProduct,p.ProductType,
  p.PolicyType,p.Endorse,p.PolicyDate,p.PolicyNo,p.EndorsementNo,p.ChassisNo,p.LicensePlate,
  p.GrossPremium,p.StampDuty,p.VAT,p.TotalPremium,p.WHT,p.TotalEIR,p.TotalSBT,p.ProcessingFee,
  p.ProcessingFeeVat,p.ShippingFee,p.ShippingFeeVat,p.TotalAmount,p.Discount,p.TransactionStatus,
  p.SubmissionStatus,p.ApprovalStatus,p.PaymentStatus,p.ExpectedReceived,p.ActualReceived,
  p.InterestThisPeriod,p.PrincipleThisPeriod,p.InterestEIRThisPeriod,p.PrincipleEIRThisPeriod,
  p.PaymentDate,p.Period,p.TotalPeriods,p.PendingPayment,p.PaymentMethod,p.PaymentChannel,
  p.ExpectedDate,p.RefOrder,p.RefundAmountBeforeFee,p.RefundAmountAfterFee,p.BillingAddress,
  p.BatchRunDate,CAST(NULL AS STRING) payload_hash,CAST(NULL AS TIMESTAMP) built_at
FROM `pacific-plating-282708.sap_integration_v3.v3_onetime_create_ready` p WHERE FALSE;

CREATE TABLE IF NOT EXISTS
  `pacific-plating-282708.sap_integration_v3.v3_monthend_onetime_identity` (
  snapshot_run_id STRING NOT NULL,pipeline_run_id STRING NOT NULL,flow_key STRING NOT NULL,
  source_flow STRING NOT NULL,order_item STRING NOT NULL,order_id STRING,period INT64 NOT NULL,
  charge_id STRING NOT NULL,invoice_no STRING NOT NULL,source_charge_time TIMESTAMP NOT NULL,
  source_payment_date_ict DATE NOT NULL,payload_hash STRING NOT NULL,built_at TIMESTAMP NOT NULL)
PARTITION BY DATE(built_at) CLUSTER BY snapshot_run_id,order_item;

CREATE TABLE IF NOT EXISTS
  `pacific-plating-282708.sap_integration_v3.v3_monthend_onetime_hold` (
  snapshot_run_id STRING NOT NULL,pipeline_run_id STRING NOT NULL,flow_key STRING NOT NULL,
  order_item STRING,order_id STRING,period INT64,charge_id STRING NOT NULL,invoice_no STRING,
  charge_amount INT64,source_charge_time TIMESTAMP,source_payment_date_ict DATE,
  hold_code STRING NOT NULL,hold_reason STRING NOT NULL,detected_at TIMESTAMP NOT NULL)
PARTITION BY DATE(detected_at) CLUSTER BY snapshot_run_id,hold_code,order_item;

CREATE TABLE IF NOT EXISTS
  `pacific-plating-282708.sap_integration_v3.v3_monthend_onetime_manifest` (
  snapshot_run_id STRING NOT NULL,pipeline_run_id STRING NOT NULL,flow_key STRING NOT NULL,
  month_start DATE NOT NULL,month_end_exclusive DATE NOT NULL,batch_run_date DATE NOT NULL,
  source_event_count INT64 NOT NULL,payload_count INT64 NOT NULL,hold_count INT64 NOT NULL,
  build_job_id STRING NOT NULL,build_contract STRING NOT NULL,completed_at TIMESTAMP NOT NULL)
CLUSTER BY snapshot_run_id,pipeline_run_id;

CREATE OR REPLACE PROCEDURE
  `pacific-plating-282708.sap_integration_v3.sp_build_v3_monthend_onetime_snapshot`(
  p_snapshot_run_id STRING,p_pipeline_run_id STRING,p_month_start DATE,
  p_month_end_exclusive DATE,p_batch_run_date DATE)
BEGIN
  DECLARE v_flow_key STRING DEFAULT 'ORDINARY_ONETIME_CREATE';
  DECLARE v_period_start DATE;
  DECLARE v_period_end DATE;
  DECLARE v_built_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP();

  ASSERT NULLIF(TRIM(p_snapshot_run_id),'') IS NOT NULL
    AND NULLIF(TRIM(p_pipeline_run_id),'') IS NOT NULL AS 'Run IDs are required';
  ASSERT REGEXP_CONTAINS(p_snapshot_run_id,r'^V3-MONTHEND-ONETIME-[A-Za-z0-9._:-]+$')
    AS 'snapshot_run_id must use the V3-MONTHEND-ONETIME prefix';
  ASSERT p_month_start=DATE_TRUNC(p_month_start,MONTH)
    AND p_month_end_exclusive=DATE_ADD(p_month_start,INTERVAL 1 MONTH)
    AND p_batch_run_date=DATE_SUB(p_month_end_exclusive,INTERVAL 1 DAY)
    AS 'Snapshot requires exactly one month and its final day as BatchRunDate';
  ASSERT (SELECT COUNT(*) FROM `pacific-plating-282708.sap_integration_v3.sap_period_state`
    WHERE status='OPEN')=1 AS 'Exactly one OPEN SAP period is required';
  SET (v_period_start,v_period_end)=(SELECT AS STRUCT period_start,period_end
    FROM `pacific-plating-282708.sap_integration_v3.sap_period_state` WHERE status='OPEN');
  ASSERT p_month_start=v_period_start AND p_month_end_exclusive=v_period_end
    AS 'Fallback is restricted to the exact current OPEN SAP month';
  ASSERT (SELECT COUNT(*)
    FROM `pacific-plating-282708.sap_integration_v3.v3_onetime_create_build_manifest`
    WHERE pipeline_run_id=p_pipeline_run_id AND build_contract='DDL085_MANIFEST_V2')=1
    AS 'Exactly one completed DDL 085 Scenario 1 build is required';
  ASSERT (SELECT ready_count
    FROM `pacific-plating-282708.sap_integration_v3.v3_onetime_create_build_manifest`
    WHERE pipeline_run_id=p_pipeline_run_id AND build_contract='DDL085_MANIFEST_V2')=
    (SELECT COUNT(*)
    FROM `pacific-plating-282708.sap_integration_v3.v3_onetime_create_identity`
    WHERE pipeline_run_id=p_pipeline_run_id)
    AS 'Current DDL 085 identity snapshot is not bound to the requested pipeline run';
  ASSERT (SELECT ready_count
    FROM `pacific-plating-282708.sap_integration_v3.v3_onetime_create_build_manifest`
    WHERE pipeline_run_id=p_pipeline_run_id AND build_contract='DDL085_MANIFEST_V2')=
    (SELECT COUNT(*)
    FROM `pacific-plating-282708.sap_integration_v3.v3_onetime_create_ready`)
    AS 'Current DDL 085 payload is not bound to the requested pipeline run';
  ASSERT (SELECT held_count
    FROM `pacific-plating-282708.sap_integration_v3.v3_onetime_create_build_manifest`
    WHERE pipeline_run_id=p_pipeline_run_id AND build_contract='DDL085_MANIFEST_V2')=
    (SELECT COUNT(*)
    FROM `pacific-plating-282708.sap_integration_v3.v3_onetime_create_hold`
    WHERE pipeline_run_id=p_pipeline_run_id)
    AS 'DDL 085 durable holds differ from the requested build manifest';
  ASSERT (SELECT COUNT(*) FROM `pacific-plating-282708.sap_integration_v3.v3_unit2_summary`
    WHERE pipeline_run_id=p_pipeline_run_id AND population_grain='PAYMENT_EVENT')>0
    AS 'Durable Unit 2 payment-event evidence is required';
  ASSERT (SELECT COUNT(*)
    FROM `pacific-plating-282708.sap_integration_v3.v3_monthend_onetime_manifest`
    WHERE snapshot_run_id=p_snapshot_run_id OR pipeline_run_id=p_pipeline_run_id)=0
    AS 'Snapshot or pipeline run is already claimed';
  ASSERT (SELECT COUNT(*) FROM `pacific-plating-282708.sap_integration_v3.INFORMATION_SCHEMA.COLUMNS`
    WHERE table_name='v3_monthend_onetime_payload')=60
    AS 'Payload table must contain 2 run columns, 56 interface columns, hash, and time';
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
    AS 'Snapshot names, types, or positions differ from the canonical 56-column contract';

  BEGIN TRANSACTION;
  CREATE TEMP TABLE _events AS
  SELECT e.pipeline_run_id,e.order_item,e.order_id,e.period,e.charge_id,e.invoice_no,
    e.charge_amount,e.charge_time,e.flow,e.outcome,e.outcome_reason,
    DATE(e.charge_time,'Asia/Bangkok') source_payment_date_ict
  FROM `pacific-plating-282708.sap_integration_v3.v3_unit2_event_shadow` e
  WHERE e.pipeline_run_id=p_pipeline_run_id AND e.flow='ONETIME'
    AND DATE(e.charge_time,'Asia/Bangkok')>=p_month_start
    AND DATE(e.charge_time,'Asia/Bangkok')<p_month_end_exclusive;
  ASSERT (SELECT COUNT(*) FROM (SELECT order_item,period,charge_id,COUNT(*) n
    FROM _events GROUP BY 1,2,3 HAVING n!=1))=0
    AS 'Month event shadow contains duplicate canonical identities';

  CREATE TEMP TABLE _latest_archive AS
  SELECT order_item,period,charge_id,delivery_status,sap_result_status,acknowledged_at FROM (
    SELECT order_item,period,charge_id,delivery_status,sap_result_status,acknowledged_at,
      ROW_NUMBER() OVER(PARTITION BY order_item,period,charge_id
        ORDER BY exported_at DESC,export_run_id DESC) row_number
    FROM `pacific-plating-282708.sap_integration_v3.export_archive`)
  WHERE row_number=1;
  CREATE TEMP TABLE _ddl085_hold AS
  SELECT pipeline_run_id,order_item,period,charge_id,
    STRING_AGG(DISTINCT hold_code,',' ORDER BY hold_code) hold_codes,
    STRING_AGG(DISTINCT hold_reason,' | ' ORDER BY hold_reason) hold_reasons
  FROM `pacific-plating-282708.sap_integration_v3.v3_onetime_create_hold`
  WHERE pipeline_run_id=p_pipeline_run_id GROUP BY 1,2,3,4;

  CREATE TEMP TABLE _ready_match AS
  SELECT e.pipeline_run_id,e.order_item,e.order_id,e.period,e.charge_id,e.invoice_no,
    e.charge_amount,e.charge_time,e.source_payment_date_ict,
    a.delivery_status,a.sap_result_status,a.acknowledged_at,
    (SELECT COUNT(*) FROM `pacific-plating-282708.sap_integration_v3.sap_mirror_doc` m
      WHERE m.U_OrderItem=e.order_item) sap_rows,
    p.CompanyDB,p.OrderID source_order_id,p.OrderDate,p.InsuredID,p.Title,p.FirstName,p.LastName,p.InsurerCode,
    p.InsuranceGroup,p.InsuranceType,p.InsuranceProduct,p.ProductType,p.PolicyType,p.Endorse,
    p.PolicyDate,p.PolicyNo,p.EndorsementNo,p.ChassisNo,p.LicensePlate,p.GrossPremium,p.StampDuty,
    p.VAT,p.TotalPremium,p.WHT,p.TotalEIR,p.TotalSBT,p.ProcessingFee,p.ProcessingFeeVat,
    p.ShippingFee,p.ShippingFeeVat,p.TotalAmount,p.Discount,p.TransactionStatus,p.SubmissionStatus,
    p.ApprovalStatus,p.PaymentStatus,p.ExpectedReceived,p.ActualReceived,p.InterestThisPeriod,
    p.PrincipleThisPeriod,p.InterestEIRThisPeriod,p.PrincipleEIRThisPeriod,p.PendingPayment,
    p.PaymentMethod,p.PaymentChannel,p.ExpectedDate,p.RefOrder,p.RefundAmountBeforeFee,
    p.RefundAmountAfterFee,p.BillingAddress
  FROM _events e
  JOIN `pacific-plating-282708.sap_integration_v3.v3_onetime_create_identity` i
    ON i.pipeline_run_id=e.pipeline_run_id AND i.order_item=e.order_item AND i.period=e.period
   AND i.charge_id=e.charge_id AND i.invoice_no=e.invoice_no
  JOIN `pacific-plating-282708.sap_integration_v3.v3_onetime_create_ready` p
    ON p.OrderItem=i.order_item AND SAFE_CAST(p.Period AS INT64)=i.period
   AND p.InvoiceNo=i.invoice_no AND p.OrderID=e.order_id
   AND TO_HEX(SHA256(TO_JSON_STRING(p)))=i.payload_hash
  LEFT JOIN _latest_archive a USING(order_item,period,charge_id)
  WHERE e.outcome='READY_CREATE_OR_PAYMENT';
  ASSERT (SELECT COUNT(*) FROM (SELECT order_item,period,charge_id,COUNT(*) n
    FROM _ready_match GROUP BY 1,2,3 HAVING n!=1))=0
    AS 'DDL 085 ready rows do not bind bijectively to month events';

  CREATE TEMP TABLE _candidate AS
  SELECT p_snapshot_run_id snapshot_run_id,p_pipeline_run_id pipeline_run_id,
    r.CompanyDB,CAST(r.source_order_id AS STRING) OrderID,CAST(r.order_item AS STRING) OrderItem,
    CAST(r.invoice_no AS STRING) InvoiceNo,r.OrderDate,r.InsuredID,r.Title,r.FirstName,r.LastName,
    r.InsurerCode,r.InsuranceGroup,r.InsuranceType,r.InsuranceProduct,r.ProductType,r.PolicyType,
    r.Endorse,r.PolicyDate,r.PolicyNo,r.EndorsementNo,r.ChassisNo,r.LicensePlate,r.GrossPremium,
    r.StampDuty,r.VAT,r.TotalPremium,r.WHT,r.TotalEIR,r.TotalSBT,r.ProcessingFee,
    r.ProcessingFeeVat,r.ShippingFee,r.ShippingFeeVat,r.TotalAmount,r.Discount,r.TransactionStatus,
    r.SubmissionStatus,r.ApprovalStatus,r.PaymentStatus,r.ExpectedReceived,r.ActualReceived,
    r.InterestThisPeriod,r.PrincipleThisPeriod,r.InterestEIRThisPeriod,r.PrincipleEIRThisPeriod,
    FORMAT_DATE('%d%m%Y',r.source_payment_date_ict) PaymentDate,'1' Period,'1' TotalPeriods,
    r.PendingPayment,r.PaymentMethod,r.PaymentChannel,r.ExpectedDate,r.RefOrder,
    r.RefundAmountBeforeFee,r.RefundAmountAfterFee,r.BillingAddress,
    FORMAT_DATE('%d%m%Y',p_batch_run_date) BatchRunDate
  FROM _ready_match r
  WHERE r.delivery_status IS NULL AND r.sap_result_status IS NULL AND r.acknowledged_at IS NULL
    AND r.sap_rows=0 AND NOT EXISTS (SELECT 1
      FROM `pacific-plating-282708.careos.cancelled_change_orders` c
      WHERE c.current_human_id=r.order_id);

  CREATE TEMP TABLE _validated AS
  SELECT c.*,CASE
    WHEN TransactionStatus!='Paid' OR Period!='1' OR TotalPeriods!='1'
      THEN 'HOLD_STATUS_OR_PERIOD_INVALID'
    WHEN LENGTH(InvoiceNo)>30 OR LENGTH(PolicyNo)>50 THEN 'HOLD_LENGTH_LIMIT_INVALID'
    WHEN NULLIF(TRIM(CompanyDB),'') IS NULL OR NULLIF(TRIM(OrderID),'') IS NULL
      OR NULLIF(TRIM(OrderItem),'') IS NULL OR NULLIF(TRIM(InvoiceNo),'') IS NULL
      OR NULLIF(TRIM(InsuredID),'') IS NULL OR NULLIF(TRIM(FirstName),'') IS NULL
      OR NULLIF(TRIM(InsurerCode),'') IS NULL OR NULLIF(TRIM(InsuranceGroup),'') IS NULL
      OR NULLIF(TRIM(InsuranceProduct),'') IS NULL OR NULLIF(TRIM(ProductType),'') IS NULL
      OR NULLIF(TRIM(PolicyType),'') IS NULL OR NULLIF(TRIM(PolicyNo),'') IS NULL
      OR NULLIF(TRIM(PaymentMethod),'') IS NULL OR NULLIF(TRIM(PaymentChannel),'') IS NULL
      OR NULLIF(TRIM(BillingAddress),'') IS NULL OR REGEXP_CONTAINS(TO_JSON_STRING(c),r':null|:"NULL"')
      THEN 'HOLD_REQUIRED_VALUE_INVALID'
    WHEN (SELECT COUNT(*) FROM UNNEST([OrderDate,PolicyDate,ExpectedDate,PaymentDate,BatchRunDate]) d
      WHERE LENGTH(IFNULL(d,''))!=8 OR SAFE.PARSE_DATE('%d%m%Y',d) IS NULL)>0
      THEN 'HOLD_DATE_CONTRACT_INVALID'
    WHEN NOT REGEXP_CONTAINS(ARRAY_TO_STRING([GrossPremium,StampDuty,VAT,TotalPremium,WHT,
      TotalEIR,TotalSBT,ProcessingFee,ProcessingFeeVat,ShippingFee,ShippingFeeVat,TotalAmount,
      Discount,ExpectedReceived,ActualReceived,InterestThisPeriod,PrincipleThisPeriod,
      InterestEIRThisPeriod,PrincipleEIRThisPeriod,PendingPayment,RefundAmountBeforeFee,
      RefundAmountAfterFee],'|'),r'^(-?[0-9]+\.[0-9]{2}\|){21}-?[0-9]+\.[0-9]{2}$')
      THEN 'HOLD_NUMERIC_CONTRACT_INVALID'
    WHEN SAFE.PARSE_DATE('%d%m%Y',PaymentDate)<p_month_start
      OR SAFE.PARSE_DATE('%d%m%Y',PaymentDate)>=p_month_end_exclusive
      THEN 'HOLD_PAYMENT_DATE_OUTSIDE_ICT_MONTH'
    ELSE 'READY' END validation_code
  FROM _candidate c;

  CREATE TEMP TABLE _ready AS
  SELECT snapshot_run_id,pipeline_run_id,CompanyDB,OrderID,OrderItem,InvoiceNo,OrderDate,InsuredID,
    Title,FirstName,LastName,InsurerCode,InsuranceGroup,InsuranceType,InsuranceProduct,ProductType,
    PolicyType,Endorse,PolicyDate,PolicyNo,EndorsementNo,ChassisNo,LicensePlate,GrossPremium,
    StampDuty,VAT,TotalPremium,WHT,TotalEIR,TotalSBT,ProcessingFee,ProcessingFeeVat,ShippingFee,
    ShippingFeeVat,TotalAmount,Discount,TransactionStatus,SubmissionStatus,ApprovalStatus,
    PaymentStatus,ExpectedReceived,ActualReceived,InterestThisPeriod,PrincipleThisPeriod,
    InterestEIRThisPeriod,PrincipleEIRThisPeriod,PaymentDate,Period,TotalPeriods,PendingPayment,
    PaymentMethod,PaymentChannel,ExpectedDate,RefOrder,RefundAmountBeforeFee,RefundAmountAfterFee,
    BillingAddress,BatchRunDate,
    TO_HEX(SHA256(TO_JSON_STRING(STRUCT(CompanyDB,OrderID,OrderItem,InvoiceNo,OrderDate,InsuredID,
      Title,FirstName,LastName,InsurerCode,InsuranceGroup,InsuranceType,InsuranceProduct,ProductType,
      PolicyType,Endorse,PolicyDate,PolicyNo,EndorsementNo,ChassisNo,LicensePlate,GrossPremium,
      StampDuty,VAT,TotalPremium,WHT,TotalEIR,TotalSBT,ProcessingFee,ProcessingFeeVat,ShippingFee,
      ShippingFeeVat,TotalAmount,Discount,TransactionStatus,SubmissionStatus,ApprovalStatus,
      PaymentStatus,ExpectedReceived,ActualReceived,InterestThisPeriod,PrincipleThisPeriod,
      InterestEIRThisPeriod,PrincipleEIRThisPeriod,PaymentDate,Period,TotalPeriods,PendingPayment,
      PaymentMethod,PaymentChannel,ExpectedDate,RefOrder,RefundAmountBeforeFee,RefundAmountAfterFee,
      BillingAddress,BatchRunDate)))) payload_hash,v_built_at built_at
  FROM _validated WHERE validation_code='READY';

  CREATE TEMP TABLE _ready_identity AS
  SELECT p_snapshot_run_id snapshot_run_id,p_pipeline_run_id pipeline_run_id,v_flow_key flow_key,
    'ONETIME' source_flow,e.order_item,e.order_id,e.period,e.charge_id,e.invoice_no,
    e.charge_time source_charge_time,e.source_payment_date_ict,r.payload_hash,r.built_at
  FROM _events e JOIN _ready r ON r.OrderItem=e.order_item
    AND SAFE_CAST(r.Period AS INT64)=e.period AND r.InvoiceNo=e.invoice_no
  WHERE e.outcome='READY_CREATE_OR_PAYMENT';
  CREATE TEMP TABLE _validation_hold AS
  SELECT OrderItem order_item,SAFE_CAST(Period AS INT64) period,InvoiceNo invoice_no,validation_code
  FROM _validated WHERE validation_code!='READY';
  ASSERT (SELECT COUNT(*) FROM (
    SELECT order_item,period,invoice_no,COUNT(*) row_count
    FROM _validation_hold GROUP BY 1,2,3 HAVING row_count!=1))=0
    AS 'Validation holds must be unique by order item, period, and invoice number';

  CREATE TEMP TABLE _hold AS
  SELECT p_snapshot_run_id snapshot_run_id,p_pipeline_run_id pipeline_run_id,v_flow_key flow_key,
    e.order_item,e.order_id,e.period,e.charge_id,e.invoice_no,e.charge_amount,
    e.charge_time source_charge_time,e.source_payment_date_ict,
    CASE
      WHEN vh.validation_code IS NOT NULL THEN vh.validation_code
      WHEN rm.charge_id IS NOT NULL AND rm.sap_result_status='ACKNOWLEDGED'
        AND rm.acknowledged_at IS NOT NULL THEN 'NOT_EXPORT_TERMINAL_ACKNOWLEDGED'
      WHEN rm.charge_id IS NOT NULL AND rm.sap_result_status IN ('REJECTED','PARTIAL_REJECT')
        THEN CONCAT('NOT_EXPORT_SAP_',rm.sap_result_status)
      WHEN rm.charge_id IS NOT NULL AND rm.delivery_status IN ('DELIVERED','PICKED_UP')
        THEN 'NOT_EXPORT_PENDING_TERMINAL_ACK'
      WHEN rm.charge_id IS NOT NULL THEN 'NOT_EXPORT_ARCHIVE_IN_FLIGHT'
      WHEN e.outcome='READY_CREATE_OR_PAYMENT' AND (SELECT COUNT(*)
        FROM `pacific-plating-282708.sap_integration_v3.sap_mirror_doc` m
        WHERE m.U_OrderItem=e.order_item)>0 THEN 'NOT_EXPORT_ALREADY_IN_SAP'
      WHEN dh.hold_codes IS NOT NULL THEN CONCAT('DDL085_',dh.hold_codes)
      WHEN e.outcome!='READY_CREATE_OR_PAYMENT' THEN CONCAT('UNIT2_',e.outcome)
      ELSE 'HOLD_UNCLASSIFIED_PIPELINE_GAP' END hold_code,
    CASE
      WHEN vh.validation_code IS NOT NULL THEN CONCAT('Final payload validation: ',vh.validation_code)
      WHEN rm.charge_id IS NOT NULL THEN CONCAT('Latest archive lifecycle: delivery=',
        IFNULL(rm.delivery_status,'NULL'),', result=',IFNULL(rm.sap_result_status,'NULL'))
      WHEN e.outcome='READY_CREATE_OR_PAYMENT' AND (SELECT COUNT(*)
        FROM `pacific-plating-282708.sap_integration_v3.sap_mirror_doc` m
        WHERE m.U_OrderItem=e.order_item)>0 THEN 'SAP mirror already contains this order item'
      WHEN dh.hold_reasons IS NOT NULL THEN dh.hold_reasons
      WHEN e.outcome!='READY_CREATE_OR_PAYMENT' THEN e.outcome_reason
      ELSE 'Ready event has neither a validated DDL 085 payload nor a durable DDL 085 hold' END
      hold_reason,v_built_at detected_at
  FROM _events e
  LEFT JOIN _ready_identity ri USING(order_item,period,charge_id)
  LEFT JOIN _latest_archive rm USING(order_item,period,charge_id)
  LEFT JOIN _ddl085_hold dh USING(pipeline_run_id,order_item,period,charge_id)
  LEFT JOIN _validation_hold vh USING(order_item,period,invoice_no)
  WHERE ri.charge_id IS NULL;

  ASSERT (SELECT COUNT(*) FROM _events)=(SELECT COUNT(*) FROM _ready)+(SELECT COUNT(*) FROM _hold)
    AS 'Every event must end in the immutable payload or durable hold';
  ASSERT (SELECT COUNT(*) FROM _ready_identity)=(SELECT COUNT(*) FROM _ready)
    AS 'Payload and identity counts differ';
  ASSERT (SELECT COUNT(*) FROM (SELECT OrderItem,Period,InvoiceNo,COUNT(*) n
    FROM _ready GROUP BY 1,2,3 HAVING n!=1))=0 AS 'Duplicate SAP identity';
  ASSERT (SELECT COUNT(*) FROM _ready WHERE TransactionStatus!='Paid' OR Period!='1'
    OR TotalPeriods!='1' OR LENGTH(InvoiceNo)>30 OR LENGTH(PolicyNo)>50)=0
    AS 'Final output violates status, period, or length contract';
  ASSERT (SELECT COUNT(*) FROM _ready_identity
    WHERE source_flow!='ONETIME' OR flow_key!=v_flow_key)=0 AS 'Flow consistency failed';
  ASSERT (SELECT COUNT(*) FROM _ready_identity ri JOIN _hold h
    USING(snapshot_run_id,pipeline_run_id,order_item,period,charge_id))=0
    AS 'Released and held identities intersect';

  INSERT INTO `pacific-plating-282708.sap_integration_v3.v3_monthend_onetime_payload`
  SELECT snapshot_run_id,pipeline_run_id,CompanyDB,OrderID,OrderItem,InvoiceNo,OrderDate,InsuredID,
    Title,FirstName,LastName,InsurerCode,InsuranceGroup,InsuranceType,InsuranceProduct,ProductType,
    PolicyType,Endorse,PolicyDate,PolicyNo,EndorsementNo,ChassisNo,LicensePlate,GrossPremium,
    StampDuty,VAT,TotalPremium,WHT,TotalEIR,TotalSBT,ProcessingFee,ProcessingFeeVat,ShippingFee,
    ShippingFeeVat,TotalAmount,Discount,TransactionStatus,SubmissionStatus,ApprovalStatus,
    PaymentStatus,ExpectedReceived,ActualReceived,InterestThisPeriod,PrincipleThisPeriod,
    InterestEIRThisPeriod,PrincipleEIRThisPeriod,PaymentDate,Period,TotalPeriods,PendingPayment,
    PaymentMethod,PaymentChannel,ExpectedDate,RefOrder,RefundAmountBeforeFee,RefundAmountAfterFee,
    BillingAddress,BatchRunDate,payload_hash,built_at FROM _ready;
  ASSERT @@row_count=(SELECT COUNT(*) FROM _ready) AS 'Payload insert failed';
  INSERT INTO `pacific-plating-282708.sap_integration_v3.v3_monthend_onetime_identity`
  SELECT snapshot_run_id,pipeline_run_id,flow_key,source_flow,order_item,order_id,period,charge_id,
    invoice_no,source_charge_time,source_payment_date_ict,payload_hash,built_at FROM _ready_identity;
  ASSERT @@row_count=(SELECT COUNT(*) FROM _ready_identity) AS 'Identity insert failed';
  INSERT INTO `pacific-plating-282708.sap_integration_v3.v3_monthend_onetime_hold`
  SELECT snapshot_run_id,pipeline_run_id,flow_key,order_item,order_id,period,charge_id,invoice_no,
    charge_amount,source_charge_time,source_payment_date_ict,hold_code,hold_reason,detected_at
  FROM _hold;
  ASSERT @@row_count=(SELECT COUNT(*) FROM _hold) AS 'Hold insert failed';
  INSERT INTO `pacific-plating-282708.sap_integration_v3.v3_monthend_onetime_manifest`
  SELECT p_snapshot_run_id,p_pipeline_run_id,v_flow_key,p_month_start,p_month_end_exclusive,
    p_batch_run_date,(SELECT COUNT(*) FROM _events),(SELECT COUNT(*) FROM _ready),
    (SELECT COUNT(*) FROM _hold),@@current_job_id,'DDL103_MONTHEND_ONETIME_V1',v_built_at;
  ASSERT @@row_count=1 AS 'Manifest insert failed';
  COMMIT TRANSACTION;
END;

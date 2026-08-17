-- SOURCE ONLY / Class A. Builds the immutable Mo PROD-02 RCL NEWPAYMENT snapshot.
-- It does not write GCS. Every failing OrderItem is quarantined in full.

CREATE TABLE IF NOT EXISTS `pacific-plating-282708.sap_integration_v3.mo_rcl_prod02_interface_hold` (
  request_id STRING NOT NULL,
  order_item STRING NOT NULL,
  rule_code STRING NOT NULL,
  detail STRING NOT NULL,
  detected_at TIMESTAMP NOT NULL
)
CLUSTER BY request_id,rule_code,order_item;

CREATE TABLE IF NOT EXISTS `pacific-plating-282708.sap_integration_v3.mo_rcl_prod02_ready` (
  CompanyDB STRING, OrderID STRING, OrderItem STRING, InvoiceNo STRING, OrderDate STRING,
  InsuredID STRING, Title STRING, FirstName STRING, LastName STRING, InsurerCode STRING,
  InsuranceGroup STRING, InsuranceType STRING, InsuranceProduct STRING, ProductType STRING,
  PolicyType STRING, Endorse STRING, PolicyDate STRING, PolicyNo STRING, EndorsementNo STRING,
  ChassisNo STRING, LicensePlate STRING, GrossPremium STRING, StampDuty STRING, VAT STRING,
  TotalPremium STRING, WHT STRING, TotalEIR STRING, TotalSBT STRING, ProcessingFee STRING,
  ProcessingFeeVat STRING, ShippingFee STRING, ShippingFeeVat STRING, TotalAmount STRING,
  Discount STRING, TransactionStatus STRING, SubmissionStatus STRING, ApprovalStatus STRING,
  PaymentStatus STRING, ExpectedReceived STRING, ActualReceived STRING,
  InterestThisPeriod STRING, PrincipleThisPeriod STRING, InterestEIRThisPeriod STRING,
  PrincipleEIRThisPeriod STRING, PaymentDate STRING, Period STRING, TotalPeriods STRING,
  PendingPayment STRING, PaymentMethod STRING, PaymentChannel STRING, ExpectedDate STRING,
  RefOrder STRING, RefundAmountBeforeFee STRING, RefundAmountAfterFee STRING,
  BillingAddress STRING, BatchRunDate STRING
);

CREATE OR REPLACE PROCEDURE `pacific-plating-282708.sap_integration_v3.sp_build_mo_rcl_prod02_interface`(
  p_request_id STRING
)
BEGIN
  DECLARE v_request_id STRING DEFAULT TRIM(p_request_id);
  DECLARE v_batch_date DATE DEFAULT CURRENT_DATE('Asia/Bangkok');

  ASSERT v_request_id='MO-RCL-20260817-PROD-02'
    AS 'This immutable builder is scoped only to MO-RCL-20260817-PROD-02';
  ASSERT (SELECT COUNT(*) FROM `pacific-plating-282708.sap_integration_v3.mo_rcl_recovery_request`
    WHERE request_id=v_request_id AND request_status='CLASSIFIED'
      AND source_request_id='MO-RCL-20260817-PROD-01' AND expected_pair_count=2295)=1
    AS 'PROD-02 must be the classified exact Mo request bound to PROD-01';
  ASSERT (SELECT COUNT(*) FROM `pacific-plating-282708.sap_integration_v3.mo_rcl_prod02_ready`)=0
    AS 'PROD-02 ready snapshot is immutable and already exists';
  ASSERT (SELECT COUNT(*) FROM `pacific-plating-282708.sap_integration_v3.mo_rcl_prod02_interface_hold`
    WHERE request_id=v_request_id)=0 AS 'PROD-02 interface holds already exist';

  CREATE TEMP TABLE _mapped_items AS
  SELECT DISTINCT order_item
  FROM `pacific-plating-282708.sap_integration_v3.mo_rcl_recovery_mapping`
  WHERE request_id=v_request_id;

  CREATE TEMP TABLE _events AS
  SELECT * EXCEPT(rn) FROM (
    SELECT e.order_item,e.period,e.charge_id,e.third_party_id,DATE(e.charge_time) payment_date,
      ROW_NUMBER() OVER(PARTITION BY e.order_item,e.period ORDER BY e.charge_time,e.charge_id) rn,
      COUNT(*) OVER(PARTITION BY e.order_item,e.period) event_count
    FROM (
      SELECT charge_id,order_item,period,third_party_id,charge_time
      FROM `pacific-plating-282708.sap_integration_v3.stg_payment_events`
      WHERE DATE(charge_time) BETWEEN DATE '2026-08-01' AND DATE '2026-08-15'
      UNION ALL
      SELECT charge_id,order_item,period,third_party_id,charge_time
      FROM `pacific-plating-282708.sap_integration_v3.mo_rcl_recovery_event_snapshot`
      WHERE source_request_id='MO-RCL-20260817-PROD-01'
    ) e
    JOIN `pacific-plating-282708.careos.carepay_charges` c
      ON c.id=e.charge_id AND c.status='SUCCESSFUL'
    WHERE EXISTS (SELECT 1 FROM _mapped_items m WHERE m.order_item=e.order_item)
  ) WHERE rn=1;

  CREATE TEMP TABLE _source_ranked AS
  SELECT * EXCEPT(rn),source_count FROM (
    SELECT
      CAST(CompanyDB AS STRING) CompanyDB,CAST(OrderID AS STRING) OrderID,
      CAST(OrderItem AS STRING) OrderItem,CAST(InvoiceNo AS STRING) InvoiceNo,
      CAST(OrderDate AS STRING) OrderDate,CAST(InsuredID AS STRING) InsuredID,
      CAST(Title AS STRING) Title,CAST(FirstName AS STRING) FirstName,CAST(LastName AS STRING) LastName,
      CAST(InsurerCode AS STRING) InsurerCode,CAST(InsuranceGroup AS STRING) InsuranceGroup,
      CAST(InsuranceType AS STRING) InsuranceType,CAST(InsuranceProduct AS STRING) InsuranceProduct,
      CAST(ProductType AS STRING) ProductType,CAST(PolicyType AS STRING) PolicyType,
      CAST(Endorse AS STRING) Endorse,CAST(PolicyDate AS STRING) PolicyDate,
      CAST(PolicyNo AS STRING) PolicyNo,CAST(EndorsementNo AS STRING) EndorsementNo,
      CAST(ChassisNo AS STRING) ChassisNo,CAST(LicensePlate AS STRING) LicensePlate,
      SAFE_CAST(GrossPremium AS FLOAT64) GrossPremium,SAFE_CAST(StampDuty AS FLOAT64) StampDuty,
      SAFE_CAST(VAT AS FLOAT64) VAT,SAFE_CAST(TotalPremium AS FLOAT64) TotalPremium,
      SAFE_CAST(WHT AS FLOAT64) WHT,SAFE_CAST(TotalEIR AS FLOAT64) TotalEIR,
      SAFE_CAST(TotalSBT AS FLOAT64) TotalSBT,SAFE_CAST(ProcessingFee AS FLOAT64) ProcessingFee,
      SAFE_CAST(ProcessingFeeVat AS FLOAT64) ProcessingFeeVat,
      SAFE_CAST(ShippingFee AS FLOAT64) ShippingFee,SAFE_CAST(ShippingFeeVat AS FLOAT64) ShippingFeeVat,
      SAFE_CAST(TotalAmount AS FLOAT64) TotalAmount,SAFE_CAST(Discount AS FLOAT64) Discount,
      CAST(SubmissionStatus AS STRING) SubmissionStatus,CAST(ApprovalStatus AS STRING) ApprovalStatus,
      CAST(PaymentStatus AS STRING) PaymentStatus,SAFE_CAST(ExpectedReceived AS FLOAT64) ExpectedReceived,
      SAFE_CAST(ActualReceived AS FLOAT64) ActualReceived,
      SAFE_CAST(InterestThisPeriod AS FLOAT64) InterestThisPeriod,
      SAFE_CAST(PrincipleThisPeriod AS FLOAT64) PrincipleThisPeriod,
      SAFE_CAST(InterestEIRThisPeriod AS FLOAT64) InterestEIRThisPeriod,
      SAFE_CAST(PrincipleEIRThisPeriod AS FLOAT64) PrincipleEIRThisPeriod,
      SAFE_CAST(Period AS INT64) Period,SAFE_CAST(TotalPeriods AS INT64) TotalPeriods,
      SAFE_CAST(PendingPayment AS FLOAT64) PendingPayment,
      CAST(PaymentMethod AS STRING) PaymentMethod,CAST(PaymentChannel AS STRING) PaymentChannel,
      CAST(ExpectedDate AS STRING) ExpectedDate,CAST(RefOrder AS STRING) RefOrder,
      SAFE_CAST(RefundAmountBeforeFee AS FLOAT64) RefundAmountBeforeFee,
      SAFE_CAST(RefundAmountAfterFee AS FLOAT64) RefundAmountAfterFee,
      CAST(BillingAddress AS STRING) BillingAddress,
      COUNT(*) OVER(PARTITION BY OrderItem,SAFE_CAST(Period AS INT64)) source_count,
      ROW_NUMBER() OVER(PARTITION BY OrderItem,SAFE_CAST(Period AS INT64)
        ORDER BY FARM_FINGERPRINT(TO_JSON_STRING(s))) rn
    FROM `pacific-plating-282708.sap_data_engineer.sap_dashboard_carepay_installment` s
    WHERE EXISTS (SELECT 1 FROM _mapped_items m WHERE m.order_item=CAST(s.OrderItem AS STRING))
  ) WHERE rn=1;

  CREATE TEMP TABLE _candidate AS
  SELECT
    s.CompanyDB,s.OrderID,s.OrderItem,
    CASE WHEN e.charge_id IS NULL THEN ''
      WHEN NULLIF(TRIM(sap.U_InvoiceNo),'') IS NOT NULL THEN sap.U_InvoiceNo
      ELSE `pacific-plating-282708.sap_integration_v3.fn_invoice_no`(e.third_party_id) END InvoiceNo,
    s.OrderDate,COALESCE(NULLIF(TRIM(s.InsuredID),''),'-') InsuredID,s.Title,s.FirstName,s.LastName,
    s.InsurerCode,s.InsuranceGroup,s.InsuranceType,s.InsuranceProduct,s.ProductType,s.PolicyType,
    s.Endorse,s.PolicyDate,s.PolicyNo,s.EndorsementNo,s.ChassisNo,s.LicensePlate,
    FORMAT('%.2f',s.GrossPremium) GrossPremium,FORMAT('%.2f',s.StampDuty) StampDuty,
    FORMAT('%.2f',s.VAT) VAT,FORMAT('%.2f',s.TotalPremium) TotalPremium,
    FORMAT('%.2f',s.WHT) WHT,FORMAT('%.2f',s.TotalEIR) TotalEIR,
    FORMAT('%.2f',s.TotalSBT) TotalSBT,FORMAT('%.2f',s.ProcessingFee) ProcessingFee,
    FORMAT('%.2f',s.ProcessingFeeVat) ProcessingFeeVat,FORMAT('%.2f',s.ShippingFee) ShippingFee,
    FORMAT('%.2f',s.ShippingFeeVat) ShippingFeeVat,FORMAT('%.2f',s.TotalAmount) TotalAmount,
    FORMAT('%.2f',s.Discount) Discount,IF(e.charge_id IS NULL,'Pending','Paid') TransactionStatus,
    s.SubmissionStatus,s.ApprovalStatus,s.PaymentStatus,
    FORMAT('%.2f',s.ExpectedReceived) ExpectedReceived,FORMAT('%.2f',s.ActualReceived) ActualReceived,
    FORMAT('%.2f',s.InterestThisPeriod) InterestThisPeriod,
    FORMAT('%.2f',s.PrincipleThisPeriod) PrincipleThisPeriod,
    FORMAT('%.2f',s.InterestEIRThisPeriod) InterestEIRThisPeriod,
    FORMAT('%.2f',s.PrincipleEIRThisPeriod) PrincipleEIRThisPeriod,
    IF(e.charge_id IS NULL,'',FORMAT_DATE('%d%m%Y',e.payment_date)) PaymentDate,
    CAST(sc.period AS STRING) Period,CAST(sc.total_periods AS STRING) TotalPeriods,
    FORMAT('%.2f',s.PendingPayment) PendingPayment,s.PaymentMethod,s.PaymentChannel,s.ExpectedDate,
    s.RefOrder,FORMAT('%.2f',s.RefundAmountBeforeFee) RefundAmountBeforeFee,
    FORMAT('%.2f',s.RefundAmountAfterFee) RefundAmountAfterFee,s.BillingAddress,
    FORMAT_DATE('%d%m%Y',v_batch_date) BatchRunDate,
    sc.flow,sc.payment_option,s.source_count,IFNULL(e.event_count,0) event_count,
    x.rule_code exclusion_rule,v.check_name validation_rule
  FROM `pacific-plating-282708.sap_integration_v3.stg_schedule` sc
  JOIN _mapped_items m ON m.order_item=sc.order_item
  LEFT JOIN _source_ranked s ON s.OrderItem=sc.order_item AND s.Period=sc.period
  LEFT JOIN _events e ON e.order_item=sc.order_item AND e.period=sc.period
  LEFT JOIN `pacific-plating-282708.sap_integration_v3.stg_sap_state` sap
    ON sap.U_OrderItem=sc.order_item AND sap.U_Period=sc.period
  LEFT JOIN `pacific-plating-282708.sap_integration_v3.sap_excluded_records` x
    ON x.order_item=sc.order_item
  LEFT JOIN `pacific-plating-282708.sap_integration_v3.sap_validation_error` v
    ON v.order_item=sc.order_item;

  CREATE TEMP TABLE _item_rule AS
  SELECT OrderItem,rule_code,detail FROM (
    SELECT OrderItem,'SOURCE_KEY_DUPLICATE' rule_code,'legacy source has duplicate (OrderItem,Period)' detail
    FROM _candidate GROUP BY OrderItem HAVING MAX(source_count)>1
    UNION ALL
    SELECT OrderItem,'SOURCE_PERIOD_MISSING','legacy source lacks a required schedule period'
    FROM _candidate GROUP BY OrderItem HAVING COUNTIF(CompanyDB IS NULL)>0
    UNION ALL
    SELECT OrderItem,'FLOW_NOT_EXACT_RCL','schedule, channel, or method does not prove one RCL flow'
    FROM _candidate GROUP BY OrderItem HAVING COUNTIF(flow!='RCL' OR flow IS NULL
      OR PaymentChannel IS NULL OR NOT STARTS_WITH(UPPER(TRIM(PaymentChannel)),'RCL')
      OR REGEXP_CONTAINS(UPPER(CONCAT(IFNULL(PaymentMethod,''),'|',IFNULL(PaymentChannel,''))),r'(^|[^A-Z])RCB([^A-Z]|$)'))>0
    UNION ALL
    SELECT OrderItem,'PERIOD_SPINE_INVALID','periods must be exactly one physical row for each integer 1..N'
    FROM _candidate GROUP BY OrderItem HAVING COUNT(DISTINCT TotalPeriods)!=1
      OR MIN(SAFE_CAST(Period AS INT64))!=1 OR MAX(SAFE_CAST(Period AS INT64))!=MAX(SAFE_CAST(TotalPeriods AS INT64))
      OR COUNT(*)!=MAX(SAFE_CAST(TotalPeriods AS INT64))
      OR COUNT(DISTINCT SAFE_CAST(Period AS INT64))!=MAX(SAFE_CAST(TotalPeriods AS INT64))
    UNION ALL
    SELECT OrderItem,'SUCCESSFUL_CHARGE_AMBIGUOUS','period has more than one qualified successful charge'
    FROM _candidate GROUP BY OrderItem HAVING MAX(event_count)>1
    UNION ALL
    SELECT OrderItem,'UPSTREAM_EXCLUSION_OR_VALIDATION','item has a current exclusion or validation error'
    FROM _candidate GROUP BY OrderItem HAVING COUNTIF(exclusion_rule IS NOT NULL OR validation_rule IS NOT NULL)>0
    UNION ALL
    SELECT OrderItem,'POLICYNO_TOO_LONG','PolicyNo exceeds 50 characters'
    FROM _candidate GROUP BY OrderItem HAVING COUNTIF(LENGTH(PolicyNo)>50)>0
    UNION ALL
    SELECT OrderItem,'DATE_FORMAT_INVALID','interface date is not valid DDMMYYYY'
    FROM _candidate GROUP BY OrderItem HAVING COUNTIF(
      LENGTH(IFNULL(OrderDate,''))!=8 OR SAFE.PARSE_DATE('%d%m%Y',OrderDate) IS NULL
      OR LENGTH(IFNULL(PolicyDate,''))!=8 OR SAFE.PARSE_DATE('%d%m%Y',PolicyDate) IS NULL
      OR LENGTH(IFNULL(ExpectedDate,''))!=8 OR SAFE.PARSE_DATE('%d%m%Y',ExpectedDate) IS NULL
      OR LENGTH(BatchRunDate)!=8 OR SAFE.PARSE_DATE('%d%m%Y',BatchRunDate) IS NULL
      OR (PaymentDate!='' AND (LENGTH(PaymentDate)!=8 OR SAFE.PARSE_DATE('%d%m%Y',PaymentDate) IS NULL)))>0
    UNION ALL
    SELECT OrderItem,'REQUIRED_VALUE_NULL_OR_LITERAL_NULL','required interface value is SQL/literal NULL or blank'
    FROM _candidate GROUP BY OrderItem HAVING COUNTIF(
      REGEXP_CONTAINS(TO_JSON_STRING((SELECT AS STRUCT c.* EXCEPT(flow,payment_option,source_count,event_count,exclusion_rule,validation_rule))),r':null|:"NULL"')
      OR NULLIF(TRIM(CompanyDB),'') IS NULL OR NULLIF(TRIM(OrderID),'') IS NULL
      OR NULLIF(TRIM(OrderItem),'') IS NULL OR NULLIF(TRIM(InsurerCode),'') IS NULL
      OR NULLIF(TRIM(PaymentMethod),'') IS NULL OR NULLIF(TRIM(PaymentChannel),'') IS NULL
      OR (TransactionStatus='Paid' AND (NULLIF(TRIM(InvoiceNo),'') IS NULL OR PaymentDate='')))>0
    UNION ALL
    SELECT OrderItem,'NUMERIC_CONTRACT_INVALID','numeric field is missing, non-finite, or not at scale 2'
    FROM _candidate GROUP BY OrderItem HAVING COUNTIF(NOT REGEXP_CONTAINS(CONCAT_WS('|',
      GrossPremium,StampDuty,VAT,TotalPremium,WHT,TotalEIR,TotalSBT,ProcessingFee,ProcessingFeeVat,
      ShippingFee,ShippingFeeVat,TotalAmount,Discount,ExpectedReceived,ActualReceived,
      InterestThisPeriod,PrincipleThisPeriod,InterestEIRThisPeriod,PrincipleEIRThisPeriod,
      PendingPayment,RefundAmountBeforeFee,RefundAmountAfterFee),r'^(-?[0-9]+\.[0-9]{2}\|){20}-?[0-9]+\.[0-9]{2}$'))>0
  );

  ASSERT (SELECT COUNT(*) FROM _candidate WHERE TransactionStatus NOT IN ('Paid','Pending'))=0
    AS 'status output is not exact Paid/Pending';

  BEGIN TRANSACTION;
    INSERT INTO `pacific-plating-282708.sap_integration_v3.mo_rcl_prod02_interface_hold`
      (request_id,order_item,rule_code,detail,detected_at)
    SELECT v_request_id,OrderItem,rule_code,detail,CURRENT_TIMESTAMP() FROM _item_rule;

    INSERT INTO `pacific-plating-282708.sap_integration_v3.mo_rcl_prod02_ready`
    SELECT CompanyDB,OrderID,OrderItem,InvoiceNo,OrderDate,InsuredID,Title,FirstName,LastName,
      InsurerCode,InsuranceGroup,InsuranceType,InsuranceProduct,ProductType,PolicyType,Endorse,
      PolicyDate,PolicyNo,EndorsementNo,ChassisNo,LicensePlate,GrossPremium,StampDuty,VAT,
      TotalPremium,WHT,TotalEIR,TotalSBT,ProcessingFee,ProcessingFeeVat,ShippingFee,ShippingFeeVat,
      TotalAmount,Discount,TransactionStatus,SubmissionStatus,ApprovalStatus,PaymentStatus,
      ExpectedReceived,ActualReceived,InterestThisPeriod,PrincipleThisPeriod,InterestEIRThisPeriod,
      PrincipleEIRThisPeriod,PaymentDate,Period,TotalPeriods,PendingPayment,PaymentMethod,
      PaymentChannel,ExpectedDate,RefOrder,RefundAmountBeforeFee,RefundAmountAfterFee,
      BillingAddress,BatchRunDate
    FROM _candidate c
    WHERE NOT EXISTS (SELECT 1 FROM _item_rule r WHERE r.OrderItem=c.OrderItem);

    ASSERT (SELECT COUNT(*) FROM (
      SELECT OrderItem,COUNT(*) n,MAX(SAFE_CAST(TotalPeriods AS INT64)) total_n
      FROM `pacific-plating-282708.sap_integration_v3.mo_rcl_prod02_ready`
      GROUP BY OrderItem HAVING n!=total_n))=0 AS 'ready item lost a full period spine';
    ASSERT (SELECT COUNT(*) FROM _mapped_items)=
      (SELECT COUNT(DISTINCT OrderItem) FROM `pacific-plating-282708.sap_integration_v3.mo_rcl_prod02_ready`)+
      (SELECT COUNT(DISTINCT order_item) FROM `pacific-plating-282708.sap_integration_v3.mo_rcl_prod02_interface_hold`
        WHERE request_id=v_request_id) AS 'mapped item conservation failed';
  COMMIT TRANSACTION;

  ASSERT (SELECT COUNT(*) FROM `pacific-plating-282708.sap_integration_v3.INFORMATION_SCHEMA.COLUMNS`
    WHERE table_name='mo_rcl_prod02_ready')=56 AS 'ready snapshot must have exactly 56 columns';
END;

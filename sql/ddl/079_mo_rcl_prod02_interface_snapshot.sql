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

CREATE TABLE IF NOT EXISTS `pacific-plating-282708.sap_integration_v3.mo_rcl_prod02_gate_manifest` (
  request_id STRING NOT NULL, source_request_id STRING NOT NULL, declared_flow STRING NOT NULL,
  operation STRING NOT NULL, delivery_folder STRING NOT NULL, file_name STRING NOT NULL,
  row_count INT64 NOT NULL, item_count INT64 NOT NULL, paid_count INT64 NOT NULL,
  pending_count INT64 NOT NULL, hold_item_count INT64 NOT NULL, candidate_sha256 STRING NOT NULL,
  schema_sha256 STRING NOT NULL, source_view_checked_at TIMESTAMP NOT NULL,
  built_at TIMESTAMP NOT NULL, gate_status STRING NOT NULL
)
CLUSTER BY request_id,gate_status;

CREATE OR REPLACE PROCEDURE `pacific-plating-282708.sap_integration_v3.sp_build_mo_rcl_prod02_interface`(
  p_request_id STRING
)
BEGIN
  DECLARE v_request_id STRING DEFAULT TRIM(p_request_id);
  DECLARE v_batch_date DATE DEFAULT CURRENT_DATE('Asia/Bangkok');
  DECLARE v_period_start DATE;
  DECLARE v_period_end DATE;

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
  ASSERT (SELECT COUNT(*) FROM `pacific-plating-282708.sap_integration_v3.sap_period_state`
    WHERE status='OPEN')=1 AS 'exactly one SAP period must be OPEN';
  SET (v_period_start,v_period_end)=(SELECT AS STRUCT period_start,period_end
    FROM `pacific-plating-282708.sap_integration_v3.sap_period_state` WHERE status='OPEN');
  ASSERT v_batch_date>=v_period_start AND v_batch_date<v_period_end
    AS 'build date is outside the approved OPEN SAP period';

  CREATE TEMP TABLE _mapped_items AS
  SELECT DISTINCT order_item
  FROM `pacific-plating-282708.sap_integration_v3.mo_rcl_recovery_mapping`
  WHERE request_id=v_request_id;

  CREATE TEMP TABLE _scoped_charge_id AS
  SELECT DISTINCT charge_id FROM (
    SELECT charge_id,order_item FROM `pacific-plating-282708.sap_integration_v3.stg_payment_events`
    WHERE DATE(charge_time) BETWEEN DATE '2000-01-01' AND DATE '2026-08-15'
    UNION ALL
    SELECT charge_id,order_item
    FROM `pacific-plating-282708.sap_integration_v3.mo_rcl_recovery_event_snapshot`
    WHERE source_request_id='MO-RCL-20260817-PROD-01'
  ) e WHERE EXISTS (SELECT 1 FROM _mapped_items m WHERE m.order_item=e.order_item);

  CREATE TEMP TABLE _event_union AS
  SELECT e.charge_id,e.order_item,e.period,e.third_party_id,e.charge_time,e.amount,e.payment_option,
    c.payment_method payment_method_source,c.service_provider payment_channel_source
  FROM `pacific-plating-282708.sap_integration_v3.stg_payment_events` e
  LEFT JOIN `pacific-plating-282708.careos.carepay_charges` c ON c.id=e.charge_id
  WHERE DATE(charge_time) BETWEEN DATE '2000-01-01' AND DATE '2026-08-15'
    AND EXISTS (SELECT 1 FROM _scoped_charge_id s WHERE s.charge_id=e.charge_id)
  UNION ALL
  SELECT charge_id,order_item,period,third_party_id,charge_time,amount,payment_option,
    payment_method_source,payment_channel_source
  FROM `pacific-plating-282708.sap_integration_v3.mo_rcl_recovery_event_snapshot` e
  WHERE source_request_id='MO-RCL-20260817-PROD-01'
    AND EXISTS (SELECT 1 FROM _scoped_charge_id s
      WHERE s.charge_id=e.charge_id);

  CREATE TEMP TABLE _event_charge AS
  SELECT charge_id,ARRAY_AGG(STRUCT(order_item,period,third_party_id,charge_time,amount,payment_option,
      payment_method_source,payment_channel_source) ORDER BY charge_time LIMIT 1)[OFFSET(0)] event,
    COUNT(DISTINCT TO_JSON_STRING(STRUCT(order_item,period,third_party_id,charge_time,amount,
      payment_option,payment_method_source,payment_channel_source))) charge_versions
  FROM _event_union GROUP BY charge_id;

  CREATE TEMP TABLE _charge_conflict_item AS
  SELECT DISTINCT u.order_item
  FROM _event_union u JOIN _event_charge c USING(charge_id)
  WHERE c.charge_versions>1
    AND EXISTS (SELECT 1 FROM _mapped_items m WHERE m.order_item=u.order_item);

  CREATE TEMP TABLE _events AS
  SELECT * EXCEPT(rn) FROM (
    SELECT e.event.order_item,e.event.period,e.charge_id,e.event.third_party_id,
      DATE(e.event.charge_time) payment_date,e.event.amount,e.event.payment_option,
      e.event.payment_method_source,e.event.payment_channel_source,e.charge_versions,
      ROW_NUMBER() OVER(PARTITION BY e.event.order_item,e.event.period
        ORDER BY e.event.charge_time,e.charge_id) rn,
      COUNT(*) OVER(PARTITION BY e.event.order_item,e.event.period) event_count
    FROM _event_charge e
    JOIN `pacific-plating-282708.careos.carepay_charges` c
      ON c.id=e.charge_id AND c.status='SUCCESSFUL'
  ) WHERE rn=1;

  CREATE TEMP TABLE _item_payment_mapping AS
  SELECT order_item,
    ARRAY_AGG(STRUCT(sap_payment_method,sap_payment_channel) ORDER BY payment_date DESC LIMIT 1)[OFFSET(0)] mapped,
    COUNTIF(mapping_count!=1) invalid_mapping_events,
    COUNT(DISTINCT CONCAT(sap_payment_method,'|',sap_payment_channel)) mapping_versions
  FROM (
    SELECT e.* EXCEPT(event_count),pm.sap_payment_method,pm.sap_payment_channel,
      COUNT(pm.mapping_id) OVER(PARTITION BY e.charge_id) mapping_count
    FROM _events e
    LEFT JOIN `pacific-plating-282708.sap_integration_v3.payment_mapping_registry` pm
      ON pm.flow='RCL' AND pm.approval_state='APPROVED' AND pm.product_scope='MOTOR'
      AND pm.is_credit_shell=FALSE AND pm.payment_source_type=IFNULL(e.payment_option,'')
      AND pm.payment_method_source=IFNULL(e.payment_method_source,'')
      AND pm.payment_channel_source=IFNULL(e.payment_channel_source,'')
      AND e.payment_date>=pm.effective_start
      AND e.payment_date<IFNULL(pm.effective_end,DATE '9999-12-31')
  ) GROUP BY order_item;

  CREATE TEMP TABLE _source_ranked AS
  SELECT * EXCEPT(rn) FROM (
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

  CREATE TEMP TABLE _target_transaction AS
  SELECT DISTINCT transaction_id
  FROM `pacific-plating-282708.sap_integration_v3.stg_schedule` s
  WHERE EXISTS (SELECT 1 FROM _mapped_items m WHERE m.order_item=s.order_item);

  CREATE TEMP TABLE _financial AS
  SELECT * EXCEPT(financial_rn) FROM (SELECT s.transaction_id,
    ROUND(IFNULL(ps.processing_fee_amount,0)/100*100/103.3,2) canonical_processing_fee,
    ROUND(IFNULL(ps.processing_fee_amount,0)/100-
      ROUND(IFNULL(ps.processing_fee_amount,0)/100*100/103.3,2),2) canonical_processing_fee_vat,
    ROUND(IFNULL(ps.interest_amount,0)/100-
      ROUND(IFNULL(ps.interest_amount,0)/100*3.3/103.3,2),2) canonical_total_eir,
    ROUND(IFNULL(ps.interest_amount,0)/100*3.3/103.3,2) canonical_total_sbt,
    ROUND(IFNULL(ps.shipment_fee,0)/100*100/107,2) canonical_shipping_fee,
    ROUND(IFNULL(ps.shipment_fee,0)/100-
      ROUND(IFNULL(ps.shipment_fee,0)/100*100/107,2),2) canonical_shipping_fee_vat,
    ROUND(IFNULL(ps.discount_amount,0)/100,2) canonical_discount,
    COUNT(ps.snapshot_id) OVER(PARTITION BY s.transaction_id) canonical_financial_source_count,
    ROW_NUMBER() OVER(PARTITION BY s.transaction_id ORDER BY ps.snapshot_id) financial_rn
  FROM (SELECT * EXCEPT(rn) FROM (
    SELECT *,ROW_NUMBER() OVER(PARTITION BY transaction_id ORDER BY update_time DESC,id DESC) rn
    FROM `pacific-plating-282708.careos.carepay_transaction_snapshots` ts
    WHERE EXISTS (SELECT 1 FROM _target_transaction t WHERE t.transaction_id=ts.transaction_id)
    ) WHERE rn=1) s
  LEFT JOIN `pacific-plating-282708.careos.carepay_transaction_snapshot_price_summaries` ps
    ON ps.snapshot_id=s.id) WHERE financial_rn=1;

  CREATE TEMP TABLE _candidate AS
  SELECT
    s.CompanyDB,s.OrderID,sc.order_item OrderItem,
    CASE WHEN NULLIF(TRIM(sap.U_InvoiceNo),'') IS NOT NULL THEN sap.U_InvoiceNo
      WHEN e.charge_id IS NULL THEN ''
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
    FORMAT('%.2f',s.Discount) Discount,
    IF(sap.TransactionStatus IN ('Paid','paid') OR e.charge_id IS NOT NULL,'Paid','Pending') TransactionStatus,
    s.SubmissionStatus,s.ApprovalStatus,s.PaymentStatus,
    FORMAT('%.2f',s.ExpectedReceived) ExpectedReceived,FORMAT('%.2f',s.ActualReceived) ActualReceived,
    FORMAT('%.2f',s.InterestThisPeriod) InterestThisPeriod,
    FORMAT('%.2f',s.PrincipleThisPeriod) PrincipleThisPeriod,
    FORMAT('%.2f',s.InterestEIRThisPeriod) InterestEIRThisPeriod,
    FORMAT('%.2f',s.PrincipleEIRThisPeriod) PrincipleEIRThisPeriod,
    CASE WHEN sap.TransactionStatus IN ('Paid','paid') THEN CAST(sap.PaymentDate AS STRING)
      WHEN e.charge_id IS NOT NULL THEN FORMAT_DATE('%d%m%Y',e.payment_date) ELSE '' END PaymentDate,
    CAST(sc.period AS STRING) Period,CAST(sc.total_periods AS STRING) TotalPeriods,
    FORMAT('%.2f',s.PendingPayment) PendingPayment,mp.mapped.sap_payment_method PaymentMethod,
    mp.mapped.sap_payment_channel PaymentChannel,s.ExpectedDate,
    s.RefOrder,FORMAT('%.2f',s.RefundAmountBeforeFee) RefundAmountBeforeFee,
    FORMAT('%.2f',s.RefundAmountAfterFee) RefundAmountAfterFee,s.BillingAddress,
    FORMAT_DATE('%d%m%Y',v_batch_date) BatchRunDate,
    sc.flow,sc.payment_option,s.source_count,IFNULL(e.event_count,0) event_count,
    IFNULL(e.charge_versions,1) charge_versions,mp.invalid_mapping_events,mp.mapping_versions,
    x.rule_code exclusion_rule,v.check_name validation_rule,sap.TransactionStatus sap_status,
    oi.net_premium canonical_gross_premium,oi.stamp_duty canonical_stamp_duty,
    oi.vat_amount canonical_vat,oi.gross_premium canonical_total_premium,
    f.canonical_processing_fee,f.canonical_processing_fee_vat,f.canonical_total_eir,
    f.canonical_total_sbt,f.canonical_shipping_fee,f.canonical_shipping_fee_vat,f.canonical_discount,
    f.canonical_financial_source_count
  FROM `pacific-plating-282708.sap_integration_v3.stg_schedule` sc
  JOIN _mapped_items m ON m.order_item=sc.order_item
  LEFT JOIN _source_ranked s ON s.OrderItem=sc.order_item AND s.Period=sc.period
  LEFT JOIN _events e ON e.order_item=sc.order_item AND e.period=sc.period
  LEFT JOIN _item_payment_mapping mp ON mp.order_item=sc.order_item
  LEFT JOIN _financial f ON f.transaction_id=sc.transaction_id
  LEFT JOIN `pacific-plating-282708.careos.careos_order_items` oi ON oi.human_id=sc.order_item
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
    FROM _candidate GROUP BY OrderItem HAVING MAX(event_count)>1 OR MAX(charge_versions)>1
    UNION ALL
    SELECT order_item,'EVENT_CHARGE_VERSION_CONFLICT','item is implicated by conflicting versions of one charge'
    FROM _charge_conflict_item
    UNION ALL
    SELECT OrderItem,'UPSTREAM_EXCLUSION_OR_VALIDATION','item has a current exclusion or validation error'
    FROM _candidate GROUP BY OrderItem HAVING COUNTIF(exclusion_rule IS NOT NULL OR validation_rule IS NOT NULL)>0
    UNION ALL
    SELECT OrderItem,'POLICYNO_TOO_LONG','PolicyNo exceeds 50 characters'
    FROM _candidate GROUP BY OrderItem HAVING COUNTIF(LENGTH(PolicyNo)>50)>0
    UNION ALL
    SELECT OrderItem,'SAP_TERMINAL_STATUS_CONFLICT','Cancelled or other terminal SAP state cannot enter Paid/Pending NEWPAYMENT'
    FROM _candidate GROUP BY OrderItem HAVING COUNTIF(sap_status NOT IN ('Paid','paid','Pending','pending')
      AND sap_status IS NOT NULL)>0
    UNION ALL
    SELECT OrderItem,'SAP_IDENTIFIER_LENGTH_INVALID','InvoiceNo or OrderItem exceeds SAP 30-character limit'
    FROM _candidate GROUP BY OrderItem HAVING COUNTIF(LENGTH(OrderItem)>30 OR LENGTH(InvoiceNo)>30)>0
    UNION ALL
    SELECT OrderItem,'COMPANY_DATABASE_INVALID','CompanyDB must be exactly RCB'
    FROM _candidate GROUP BY OrderItem HAVING COUNTIF(CompanyDB!='RCB' OR CompanyDB IS NULL)>0
    UNION ALL
    SELECT OrderItem,'INSURER_MASTER_UNAPPROVED','InsurerCode is absent from the SAP-received insurer master'
    FROM _candidate c GROUP BY OrderItem HAVING COUNTIF(NOT EXISTS (
      SELECT 1 FROM `pacific-plating-282708.sap_integration_v3.sap_insurer_master` im
      WHERE im.insurer_code=c.InsurerCode))>0
    UNION ALL
    SELECT OrderItem,'PAYMENT_MAPPING_UNAPPROVED','event-date canonical RCL payment mapping is missing or ambiguous'
    FROM _candidate GROUP BY OrderItem HAVING IFNULL(MAX(invalid_mapping_events),1)>0
      OR IFNULL(MAX(mapping_versions),0)!=1
    UNION ALL
    SELECT OrderItem,'DATE_FORMAT_INVALID','interface date is not valid DDMMYYYY'
    FROM _candidate c GROUP BY OrderItem HAVING COUNTIF(
      LENGTH(IFNULL(OrderDate,''))!=8 OR SAFE.PARSE_DATE('%d%m%Y',OrderDate) IS NULL
      OR LENGTH(IFNULL(PolicyDate,''))!=8 OR SAFE.PARSE_DATE('%d%m%Y',PolicyDate) IS NULL
      OR LENGTH(IFNULL(ExpectedDate,''))!=8 OR SAFE.PARSE_DATE('%d%m%Y',ExpectedDate) IS NULL
      OR LENGTH(BatchRunDate)!=8 OR SAFE.PARSE_DATE('%d%m%Y',BatchRunDate) IS NULL
      OR (PaymentDate!='' AND (LENGTH(PaymentDate)!=8 OR SAFE.PARSE_DATE('%d%m%Y',PaymentDate) IS NULL)))>0
    UNION ALL
    SELECT OrderItem,'OPEN_PERIOD_INVALID','BatchRunDate or newly recovered payment lies outside OPEN SAP period'
    FROM _candidate GROUP BY OrderItem HAVING COUNTIF(
      SAFE.PARSE_DATE('%d%m%Y',BatchRunDate)<v_period_start
      OR SAFE.PARSE_DATE('%d%m%Y',BatchRunDate)>=v_period_end
      OR (sap_status IS NULL AND PaymentDate!=''
        AND (SAFE.PARSE_DATE('%d%m%Y',PaymentDate)<v_period_start
          OR SAFE.PARSE_DATE('%d%m%Y',PaymentDate)>=v_period_end)))>0
    UNION ALL
    SELECT OrderItem,'REQUIRED_VALUE_NULL_OR_LITERAL_NULL','required interface value is SQL/literal NULL or blank'
    FROM _candidate c GROUP BY OrderItem HAVING COUNTIF(
      REGEXP_CONTAINS(TO_JSON_STRING((SELECT AS STRUCT c.* EXCEPT(flow,payment_option,source_count,event_count,
        charge_versions,invalid_mapping_events,mapping_versions,exclusion_rule,validation_rule,sap_status,
        canonical_gross_premium,canonical_stamp_duty,canonical_vat,canonical_total_premium,
        canonical_processing_fee,canonical_processing_fee_vat,canonical_total_eir,canonical_total_sbt,
        canonical_shipping_fee,canonical_shipping_fee_vat,canonical_discount,
        canonical_financial_source_count))),r':null|:"NULL"')
      OR NULLIF(TRIM(CompanyDB),'') IS NULL OR NULLIF(TRIM(OrderID),'') IS NULL
      OR NULLIF(TRIM(OrderItem),'') IS NULL OR NULLIF(TRIM(InsurerCode),'') IS NULL
      OR NULLIF(TRIM(OrderDate),'') IS NULL OR NULLIF(TRIM(InsuredID),'') IS NULL
      OR NULLIF(TRIM(FirstName),'') IS NULL OR NULLIF(TRIM(InsuranceGroup),'') IS NULL
      OR NULLIF(TRIM(InsuranceProduct),'') IS NULL OR NULLIF(TRIM(ProductType),'') IS NULL
      OR NULLIF(TRIM(PolicyType),'') IS NULL OR NULLIF(TRIM(PolicyDate),'') IS NULL
      OR NULLIF(TRIM(PolicyNo),'') IS NULL OR NULLIF(TRIM(ExpectedDate),'') IS NULL
      OR NULLIF(TRIM(BillingAddress),'') IS NULL
      OR NULLIF(TRIM(PaymentMethod),'') IS NULL OR NULLIF(TRIM(PaymentChannel),'') IS NULL
      OR (TransactionStatus='Paid' AND (NULLIF(TRIM(InvoiceNo),'') IS NULL OR PaymentDate=''))
      OR (TransactionStatus='Pending' AND PaymentDate!=''))>0
    UNION ALL
    SELECT OrderItem,'NUMERIC_CONTRACT_INVALID','numeric field is missing, non-finite, or not at scale 2'
    FROM _candidate GROUP BY OrderItem HAVING COUNTIF(NOT REGEXP_CONTAINS(ARRAY_TO_STRING([
      GrossPremium,StampDuty,VAT,TotalPremium,WHT,TotalEIR,TotalSBT,ProcessingFee,ProcessingFeeVat,
      ShippingFee,ShippingFeeVat,TotalAmount,Discount,ExpectedReceived,ActualReceived,
      InterestThisPeriod,PrincipleThisPeriod,InterestEIRThisPeriod,PrincipleEIRThisPeriod,
      PendingPayment,RefundAmountBeforeFee,RefundAmountAfterFee],'|'),
      r'^(-?[0-9]+\.[0-9]{2}\|){21}-?[0-9]+\.[0-9]{2}$'))>0
    UNION ALL
    SELECT OrderItem,'CANONICAL_FINANCIAL_MISMATCH','premium fields do not reconcile to canonical CareOS order-item values'
    FROM _candidate GROUP BY OrderItem HAVING COUNTIF(
      canonical_gross_premium IS NULL OR canonical_stamp_duty IS NULL OR canonical_vat IS NULL
      OR canonical_total_premium IS NULL
      OR canonical_processing_fee IS NULL OR canonical_processing_fee_vat IS NULL
      OR canonical_total_eir IS NULL OR canonical_total_sbt IS NULL
      OR canonical_shipping_fee IS NULL OR canonical_shipping_fee_vat IS NULL
      OR canonical_discount IS NULL
      OR ABS(SAFE_CAST(GrossPremium AS NUMERIC)-SAFE_CAST(canonical_gross_premium AS NUMERIC))>0.005
      OR ABS(SAFE_CAST(StampDuty AS NUMERIC)-SAFE_CAST(canonical_stamp_duty AS NUMERIC))>0.005
      OR ABS(SAFE_CAST(VAT AS NUMERIC)-SAFE_CAST(canonical_vat AS NUMERIC))>0.005
      OR ABS(SAFE_CAST(TotalPremium AS NUMERIC)-SAFE_CAST(canonical_total_premium AS NUMERIC))>0.005
      OR ABS(SAFE_CAST(ProcessingFee AS NUMERIC)-canonical_processing_fee)>0.005
      OR ABS(SAFE_CAST(ProcessingFeeVat AS NUMERIC)-canonical_processing_fee_vat)>0.005
      OR ABS(SAFE_CAST(TotalEIR AS NUMERIC)-canonical_total_eir)>0.005
      OR ABS(SAFE_CAST(TotalSBT AS NUMERIC)-canonical_total_sbt)>0.005
      OR ABS(SAFE_CAST(ShippingFee AS NUMERIC)-canonical_shipping_fee)>0.005
      OR ABS(SAFE_CAST(ShippingFeeVat AS NUMERIC)-canonical_shipping_fee_vat)>0.005
      OR ABS(SAFE_CAST(Discount AS NUMERIC)-canonical_discount)>0.005)>0
    UNION ALL
    SELECT OrderItem,'CANONICAL_FINANCIAL_SOURCE_MISSING_OR_AMBIGUOUS',
      'latest transaction snapshot must have exactly one price summary'
    FROM _candidate GROUP BY OrderItem HAVING IFNULL(MAX(canonical_financial_source_count),0)!=1
  );

  ASSERT (SELECT COUNT(*) FROM _candidate WHERE TransactionStatus NOT IN ('Paid','Pending'))=0
    AS 'status output is not exact Paid/Pending';

  ASSERT TO_JSON_STRING((SELECT ARRAY_AGG(STRUCT(column_name,data_type,ordinal_position) ORDER BY ordinal_position)
    FROM `pacific-plating-282708.sap_integration_v3.INFORMATION_SCHEMA.COLUMNS`
    WHERE table_name='mo_rcl_prod02_ready')) = TO_JSON_STRING([
      STRUCT('CompanyDB','STRING',1),STRUCT('OrderID','STRING',2),STRUCT('OrderItem','STRING',3),
      STRUCT('InvoiceNo','STRING',4),STRUCT('OrderDate','STRING',5),STRUCT('InsuredID','STRING',6),
      STRUCT('Title','STRING',7),STRUCT('FirstName','STRING',8),STRUCT('LastName','STRING',9),
      STRUCT('InsurerCode','STRING',10),STRUCT('InsuranceGroup','STRING',11),STRUCT('InsuranceType','STRING',12),
      STRUCT('InsuranceProduct','STRING',13),STRUCT('ProductType','STRING',14),STRUCT('PolicyType','STRING',15),
      STRUCT('Endorse','STRING',16),STRUCT('PolicyDate','STRING',17),STRUCT('PolicyNo','STRING',18),
      STRUCT('EndorsementNo','STRING',19),STRUCT('ChassisNo','STRING',20),STRUCT('LicensePlate','STRING',21),
      STRUCT('GrossPremium','STRING',22),STRUCT('StampDuty','STRING',23),STRUCT('VAT','STRING',24),
      STRUCT('TotalPremium','STRING',25),STRUCT('WHT','STRING',26),STRUCT('TotalEIR','STRING',27),
      STRUCT('TotalSBT','STRING',28),STRUCT('ProcessingFee','STRING',29),STRUCT('ProcessingFeeVat','STRING',30),
      STRUCT('ShippingFee','STRING',31),STRUCT('ShippingFeeVat','STRING',32),STRUCT('TotalAmount','STRING',33),
      STRUCT('Discount','STRING',34),STRUCT('TransactionStatus','STRING',35),STRUCT('SubmissionStatus','STRING',36),
      STRUCT('ApprovalStatus','STRING',37),STRUCT('PaymentStatus','STRING',38),STRUCT('ExpectedReceived','STRING',39),
      STRUCT('ActualReceived','STRING',40),STRUCT('InterestThisPeriod','STRING',41),STRUCT('PrincipleThisPeriod','STRING',42),
      STRUCT('InterestEIRThisPeriod','STRING',43),STRUCT('PrincipleEIRThisPeriod','STRING',44),STRUCT('PaymentDate','STRING',45),
      STRUCT('Period','STRING',46),STRUCT('TotalPeriods','STRING',47),STRUCT('PendingPayment','STRING',48),
      STRUCT('PaymentMethod','STRING',49),STRUCT('PaymentChannel','STRING',50),STRUCT('ExpectedDate','STRING',51),
      STRUCT('RefOrder','STRING',52),STRUCT('RefundAmountBeforeFee','STRING',53),STRUCT('RefundAmountAfterFee','STRING',54),
      STRUCT('BillingAddress','STRING',55),STRUCT('BatchRunDate','STRING',56)])
    AS 'exact 56-column name/type/ordinal contract mismatch';

  BEGIN TRANSACTION;
    UPDATE `pacific-plating-282708.sap_integration_v3.mo_rcl_recovery_lock`
    SET claim_epoch=claim_epoch+1,claimed_at=CURRENT_TIMESTAMP() WHERE lock_name='MO_RCL_RECOVERY';
    ASSERT @@row_count=1 AS 'recovery lock is missing or duplicated';
    ASSERT (SELECT COUNT(*) FROM `pacific-plating-282708.sap_integration_v3.mo_rcl_prod02_ready`)=0
      AS 'PROD-02 ready snapshot exists after claim';
    ASSERT (SELECT COUNT(*) FROM `pacific-plating-282708.sap_integration_v3.mo_rcl_prod02_interface_hold`
      WHERE request_id=v_request_id)=0 AS 'PROD-02 interface holds exist after claim';
    ASSERT (SELECT COUNT(*) FROM `pacific-plating-282708.sap_integration_v3.mo_rcl_prod02_gate_manifest`
      WHERE request_id=v_request_id)=0 AS 'PROD-02 manifest exists after claim';
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

    ASSERT (SELECT COUNT(*) FROM _event_charge ec WHERE
      (ec.charge_versions=1 AND NOT (
        EXISTS (SELECT 1 FROM `pacific-plating-282708.sap_integration_v3.mo_rcl_prod02_ready` r
          WHERE r.OrderItem=ec.event.order_item AND SAFE_CAST(r.Period AS INT64)=ec.event.period
            AND r.TransactionStatus='Paid')
        OR EXISTS (SELECT 1
          FROM `pacific-plating-282708.sap_integration_v3.mo_rcl_prod02_interface_hold` h
          WHERE h.request_id=v_request_id AND h.order_item=ec.event.order_item)))
      OR (ec.charge_versions>1 AND EXISTS (
        SELECT 1 FROM _event_union u JOIN _mapped_items m ON m.order_item=u.order_item
        WHERE u.charge_id=ec.charge_id AND NOT EXISTS (
          SELECT 1 FROM `pacific-plating-282708.sap_integration_v3.mo_rcl_prod02_interface_hold` h
          WHERE h.request_id=v_request_id AND h.order_item=u.order_item
            AND h.rule_code='EVENT_CHARGE_VERSION_CONFLICT'))))=0
      AS 'every distinct successful charge must map to Paid or all implicated mapped items held';

    INSERT INTO `pacific-plating-282708.sap_integration_v3.mo_rcl_prod02_gate_manifest`
    SELECT v_request_id,'MO-RCL-20260817-PROD-01','RCL','NEWPAYMENT','RCB_MOTOR',
      'INSURANCE_RCB_06_MO_RCL_RECOVERY_20260817.csv',COUNT(*),COUNT(DISTINCT OrderItem),
      COUNTIF(TransactionStatus='Paid'),COUNTIF(TransactionStatus='Pending'),
      (SELECT COUNT(DISTINCT order_item)
        FROM `pacific-plating-282708.sap_integration_v3.mo_rcl_prod02_interface_hold`
        WHERE request_id=v_request_id),
      COALESCE(TO_HEX(SHA256(STRING_AGG(TO_JSON_STRING(r),'\n'
        ORDER BY OrderItem,SAFE_CAST(Period AS INT64)))),'EMPTY'),
      (SELECT TO_HEX(SHA256(STRING_AGG(CONCAT(column_name,'|',data_type,'|',ordinal_position),'\n'
        ORDER BY ordinal_position)))
       FROM `pacific-plating-282708.sap_integration_v3.INFORMATION_SCHEMA.COLUMNS`
       WHERE table_name='mo_rcl_prod02_ready'),CURRENT_TIMESTAMP(),CURRENT_TIMESTAMP(),
      IF(COUNT(*)>0,'PASS','BLOCK_NO_READY_ROWS')
    FROM `pacific-plating-282708.sap_integration_v3.mo_rcl_prod02_ready` r;
  COMMIT TRANSACTION;
END;

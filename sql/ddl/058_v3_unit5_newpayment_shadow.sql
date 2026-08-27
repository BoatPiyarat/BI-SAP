-- SOURCE ONLY / Class A. Builds a 56-column NEWPAYMENT shadow; no GCS or SAP mutation.
-- CREATE is deliberately excluded while its 159 Paid source gaps remain unresolved.

CREATE TABLE IF NOT EXISTS `pacific-plating-282708.sap_integration_v3.v3_unit5_payload_identity` (
  pipeline_run_id STRING NOT NULL,
  file_role STRING NOT NULL,
  order_item STRING NOT NULL,
  period INT64 NOT NULL,
  charge_id STRING NOT NULL,
  invoice_no STRING NOT NULL,
  payload_hash STRING NOT NULL,
  built_at TIMESTAMP NOT NULL
)
PARTITION BY DATE(built_at)
CLUSTER BY pipeline_run_id,file_role,order_item;

CREATE TABLE IF NOT EXISTS `pacific-plating-282708.sap_integration_v3.v3_unit5_newpayment_ready` (
  CompanyDB STRING,OrderID STRING,OrderItem STRING,InvoiceNo STRING,OrderDate STRING,
  InsuredID STRING,Title STRING,FirstName STRING,LastName STRING,InsurerCode STRING,
  InsuranceGroup STRING,InsuranceType STRING,InsuranceProduct STRING,ProductType STRING,
  PolicyType STRING,Endorse STRING,PolicyDate STRING,PolicyNo STRING,EndorsementNo STRING,
  ChassisNo STRING,LicensePlate STRING,GrossPremium STRING,StampDuty STRING,VAT STRING,
  TotalPremium STRING,WHT STRING,TotalEIR STRING,TotalSBT STRING,ProcessingFee STRING,
  ProcessingFeeVat STRING,ShippingFee STRING,ShippingFeeVat STRING,TotalAmount STRING,
  Discount STRING,TransactionStatus STRING,SubmissionStatus STRING,ApprovalStatus STRING,
  PaymentStatus STRING,ExpectedReceived STRING,ActualReceived STRING,InterestThisPeriod STRING,
  PrincipleThisPeriod STRING,InterestEIRThisPeriod STRING,PrincipleEIRThisPeriod STRING,
  PaymentDate STRING,Period STRING,TotalPeriods STRING,PendingPayment STRING,PaymentMethod STRING,
  PaymentChannel STRING,ExpectedDate STRING,RefOrder STRING,RefundAmountBeforeFee STRING,
  RefundAmountAfterFee STRING,BillingAddress STRING,BatchRunDate STRING
);

CREATE TABLE IF NOT EXISTS
  `pacific-plating-282708.sap_integration_v3.v3_unit5_newpayment_delivery_ready` (
  CompanyDB STRING,OrderID STRING,OrderItem STRING,InvoiceNo STRING,OrderDate STRING,
  InsuredID STRING,Title STRING,FirstName STRING,LastName STRING,InsurerCode STRING,
  InsuranceGroup STRING,InsuranceType STRING,InsuranceProduct STRING,ProductType STRING,
  PolicyType STRING,Endorse STRING,PolicyDate STRING,PolicyNo STRING,EndorsementNo STRING,
  ChassisNo STRING,LicensePlate STRING,GrossPremium STRING,StampDuty STRING,VAT STRING,
  TotalPremium STRING,WHT STRING,TotalEIR STRING,TotalSBT STRING,ProcessingFee STRING,
  ProcessingFeeVat STRING,ShippingFee STRING,ShippingFeeVat STRING,TotalAmount STRING,
  Discount STRING,TransactionStatus STRING,SubmissionStatus STRING,ApprovalStatus STRING,
  PaymentStatus STRING,ExpectedReceived STRING,ActualReceived STRING,InterestThisPeriod STRING,
  PrincipleThisPeriod STRING,InterestEIRThisPeriod STRING,PrincipleEIRThisPeriod STRING,
  PaymentDate STRING,Period STRING,TotalPeriods STRING,PendingPayment STRING,PaymentMethod STRING,
  PaymentChannel STRING,ExpectedDate STRING,RefOrder STRING,RefundAmountBeforeFee STRING,
  RefundAmountAfterFee STRING,BillingAddress STRING,BatchRunDate STRING
);

CREATE TABLE IF NOT EXISTS
  `pacific-plating-282708.sap_integration_v3.v3_unit5_newpayment_snapshot_manifest` (
    pipeline_run_id STRING NOT NULL,row_count INT64 NOT NULL,payload_set_hash STRING NOT NULL,
    completed_at TIMESTAMP NOT NULL
  )
PARTITION BY DATE(completed_at) CLUSTER BY pipeline_run_id;

CREATE TABLE IF NOT EXISTS
  `pacific-plating-282708.sap_integration_v3.v3_unit5_newpayment_run_state` (
    pipeline_run_id STRING NOT NULL,state STRING NOT NULL,producer_row_count INT64 NOT NULL,
    producer_set_hash STRING NOT NULL,updated_at TIMESTAMP NOT NULL
  )
PARTITION BY DATE(updated_at) CLUSTER BY pipeline_run_id,state;

CREATE TABLE IF NOT EXISTS
  `pacific-plating-282708.sap_integration_v3.v3_unit5_candidate_required_hold` (
    pipeline_run_id STRING NOT NULL,order_item STRING NOT NULL,
    hold_code STRING NOT NULL,hold_reason STRING NOT NULL,
    invalid_fields ARRAY<STRING> NOT NULL,invalid_period_count INT64 NOT NULL,
    detected_at TIMESTAMP NOT NULL
  )
PARTITION BY DATE(detected_at) CLUSTER BY pipeline_run_id,hold_code,order_item;

CREATE OR REPLACE PROCEDURE `pacific-plating-282708.sap_integration_v3.sp_build_v3_newpayment_shadow`(
  p_pipeline_run_id STRING
)
BEGIN
  DECLARE v_period_start DATE;
  DECLARE v_period_end DATE;
  DECLARE v_batch_date DATE;

  ASSERT NULLIF(TRIM(p_pipeline_run_id),'') IS NOT NULL
    AS 'NEWPAYMENT shadow requires pipeline_run_id';
  ASSERT (SELECT COUNT(*) FROM `pacific-plating-282708.sap_integration_v3.v3_automation_gate_result`
    WHERE pipeline_run_id=p_pipeline_run_id AND blocker_count!=0)=0
    AS 'NEWPAYMENT shadow requires zero automation blockers';
  ASSERT (SELECT COUNT(*) FROM `pacific-plating-282708.sap_integration_v3.sap_period_state`
    WHERE status='OPEN')=1 AS 'NEWPAYMENT shadow requires exactly one OPEN period';
  SET (v_period_start,v_period_end)=(SELECT AS STRUCT period_start,period_end
    FROM `pacific-plating-282708.sap_integration_v3.sap_period_state` WHERE status='OPEN');
  SET v_batch_date=LEAST(CURRENT_DATE('Asia/Bangkok'),DATE_SUB(v_period_end,INTERVAL 1 DAY));

  -- PHASE 2 (docs/FINDINGS_EMPTY_INSTALLMENT_DETAILS_20260825.md): record this run's
  -- HOLD_EMPTY_INSTALLMENT_DETAILS order_items (from 082_v3_rcl_empty_installment_detail_hold.sql)
  -- before _target excludes them, so the gap is visible and queryable rather than silently
  -- disappearing at the _resolved join below.
  CREATE TEMP TABLE _installment_detail_hold AS
  SELECT p_pipeline_run_id,order_item,order_id,transaction_id,snapshot_id,
    declared_total_periods,number_of_installment,detail_row_count,rule_code,detected_at
  FROM `pacific-plating-282708.sap_integration_v3.vw_v3_rcl_empty_installment_detail_hold`;
  ASSERT (SELECT COUNT(*) FROM _installment_detail_hold)=(SELECT COUNT(*) FROM (
    SELECT order_item,order_id,transaction_id,snapshot_id,rule_code
    FROM _installment_detail_hold GROUP BY 1,2,3,4,5))
    AS 'Unit 5 installment-detail hold source contains duplicate identities';

  CREATE TEMP TABLE _target AS
  SELECT e.*
  FROM `pacific-plating-282708.sap_integration_v3.v3_unit2_event_shadow` e
  WHERE e.pipeline_run_id=p_pipeline_run_id AND e.outcome='READY_CREATE_OR_PAYMENT'
    AND EXISTS (SELECT 1 FROM `pacific-plating-282708.sap_integration_v3.sap_mirror_doc` m
      WHERE m.U_OrderItem=e.order_item)
    AND NOT EXISTS (SELECT 1
      FROM `pacific-plating-282708.sap_integration_v3.v3_unit3_mapping_hold` h
      WHERE h.pipeline_run_id=e.pipeline_run_id AND h.order_item=e.order_item
        AND h.period=e.period AND h.charge_id=e.charge_id)
    AND NOT EXISTS (SELECT 1
      FROM _installment_detail_hold d WHERE d.order_item=e.order_item);

  CREATE TEMP TABLE _source AS
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
    CAST(TransactionStatus AS STRING) TransactionStatus,CAST(SubmissionStatus AS STRING) SubmissionStatus,
    CAST(ApprovalStatus AS STRING) ApprovalStatus,CAST(PaymentStatus AS STRING) PaymentStatus,
    SAFE_CAST(ExpectedReceived AS FLOAT64) ExpectedReceived,
    SAFE_CAST(ActualReceived AS FLOAT64) ActualReceived,
    SAFE_CAST(InterestThisPeriod AS FLOAT64) InterestThisPeriod,
    SAFE_CAST(PrincipleThisPeriod AS FLOAT64) PrincipleThisPeriod,
    SAFE_CAST(InterestEIRThisPeriod AS FLOAT64) InterestEIRThisPeriod,
    SAFE_CAST(PrincipleEIRThisPeriod AS FLOAT64) PrincipleEIRThisPeriod,
    CAST(PaymentDate AS STRING) PaymentDate,SAFE_CAST(Period AS INT64) Period,
    SAFE_CAST(TotalPeriods AS INT64) TotalPeriods,CAST(PendingPayment AS STRING) PendingPayment,
    CAST(PaymentMethod AS STRING) PaymentMethod,CAST(PaymentChannel AS STRING) PaymentChannel,
    CAST(ExpectedDate AS STRING) ExpectedDate,CAST(RefOrder AS STRING) RefOrder,
    SAFE_CAST(RefundAmountBeforeFee AS FLOAT64) RefundAmountBeforeFee,
    SAFE_CAST(RefundAmountAfterFee AS FLOAT64) RefundAmountAfterFee,
    CAST(BillingAddress AS STRING) BillingAddress,CAST(BatchRunDate AS STRING) BatchRunDate
  FROM `pacific-plating-282708.sap_integration_v3.vw_onetime_payload_source`
  WHERE EXISTS (SELECT 1 FROM _target t WHERE t.order_item=OrderItem AND t.flow='ONETIME')
  UNION ALL
  SELECT CAST(CompanyDB AS STRING),CAST(OrderID AS STRING),CAST(OrderItem AS STRING),
    CAST(InvoiceNo AS STRING),CAST(OrderDate AS STRING),CAST(InsuredID AS STRING),CAST(Title AS STRING),
    CAST(FirstName AS STRING),CAST(LastName AS STRING),CAST(InsurerCode AS STRING),
    CAST(InsuranceGroup AS STRING),CAST(InsuranceType AS STRING),CAST(InsuranceProduct AS STRING),
    CAST(ProductType AS STRING),CAST(PolicyType AS STRING),CAST(Endorse AS STRING),
    CAST(PolicyDate AS STRING),CAST(PolicyNo AS STRING),CAST(EndorsementNo AS STRING),
    CAST(ChassisNo AS STRING),CAST(LicensePlate AS STRING),SAFE_CAST(GrossPremium AS FLOAT64),
    SAFE_CAST(StampDuty AS FLOAT64),SAFE_CAST(VAT AS FLOAT64),SAFE_CAST(TotalPremium AS FLOAT64),
    SAFE_CAST(WHT AS FLOAT64),SAFE_CAST(TotalEIR AS FLOAT64),SAFE_CAST(TotalSBT AS FLOAT64),
    SAFE_CAST(ProcessingFee AS FLOAT64),SAFE_CAST(ProcessingFeeVat AS FLOAT64),
    SAFE_CAST(ShippingFee AS FLOAT64),SAFE_CAST(ShippingFeeVat AS FLOAT64),
    SAFE_CAST(TotalAmount AS FLOAT64),SAFE_CAST(Discount AS FLOAT64),CAST(TransactionStatus AS STRING),
    CAST(SubmissionStatus AS STRING),CAST(ApprovalStatus AS STRING),CAST(PaymentStatus AS STRING),
    SAFE_CAST(ExpectedReceived AS FLOAT64),SAFE_CAST(ActualReceived AS FLOAT64),
    SAFE_CAST(InterestThisPeriod AS FLOAT64),SAFE_CAST(PrincipleThisPeriod AS FLOAT64),
    SAFE_CAST(InterestEIRThisPeriod AS FLOAT64),SAFE_CAST(PrincipleEIRThisPeriod AS FLOAT64),
    CAST(PaymentDate AS STRING),SAFE_CAST(Period AS INT64),SAFE_CAST(TotalPeriods AS INT64),
    CAST(PendingPayment AS STRING),CAST(PaymentMethod AS STRING),CAST(PaymentChannel AS STRING),
    CAST(ExpectedDate AS STRING),CAST(RefOrder AS STRING),SAFE_CAST(RefundAmountBeforeFee AS FLOAT64),
    SAFE_CAST(RefundAmountAfterFee AS FLOAT64),CAST(BillingAddress AS STRING),CAST(BatchRunDate AS STRING)
  FROM `pacific-plating-282708.sap_data_engineer.sap_dashboard_carepay_installment`
  WHERE EXISTS (SELECT 1 FROM _target t WHERE t.order_item=OrderItem AND t.flow!='ONETIME');

  CREATE TEMP TABLE _context AS
  WITH category AS (
    SELECT human_id,COUNT(DISTINCT product_category) category_count,
      ANY_VALUE(product_category HAVING MIN product_category) category_value
    FROM `pacific-plating-282708.analytics_reports.non_motor_report_order_for_accounting`
    GROUP BY human_id)
  SELECT t.*,DATE(p.charge_time) raw_payment_date,p.payment_option,
    c.payment_method payment_method_source,c.service_provider payment_channel_source,
    IF(oi.product='products/car-insurance','MOTOR','NONMOTOR') product_scope,
    IF(oi.product='products/car-insurance',oi.product,
      IF(category_count=1,category_value,'__AMBIGUOUS_OR_MISSING__')) insurance_group_source,
    co.current_human_id IS NOT NULL is_credit_shell,
    IF(t.flow='ONETIME','RCB','RCL') business_unit
  FROM _target t
  JOIN `pacific-plating-282708.sap_integration_v3.stg_payment_events` p USING(charge_id)
  JOIN `pacific-plating-282708.careos.carepay_charges` c ON c.id=t.charge_id
  JOIN `pacific-plating-282708.careos.careos_order_items` oi ON oi.human_id=t.order_item
  LEFT JOIN category n ON n.human_id=t.order_id
  LEFT JOIN (SELECT DISTINCT current_human_id
    FROM `pacific-plating-282708.careos.cancelled_change_orders`) co ON co.current_human_id=t.order_id;

  ASSERT (SELECT COUNT(*) FROM _context WHERE raw_payment_date>=v_period_end)=0
    AS 'Future payment date lies outside OPEN period';

  CREATE TEMP TABLE _resolved AS
  SELECT c.*,s.* EXCEPT(OrderItem,OrderID,Period,InvoiceNo),
    pm.sap_payment_method,pm.sap_payment_channel,
    IF(c.product_scope='NONMOTOR',ig.sap_insurance_group,s.InsuranceGroup) resolved_insurance_group
  FROM _context c
  JOIN _source s ON s.OrderItem=c.order_item AND s.Period=c.period
    AND NULLIF(TRIM(s.InvoiceNo),'')=c.invoice_no
  JOIN `pacific-plating-282708.sap_integration_v3.payment_mapping_registry` pm
    ON pm.approval_state='APPROVED' AND pm.flow=c.flow AND pm.product_scope=c.product_scope
   AND pm.is_credit_shell=c.is_credit_shell AND pm.payment_source_type=IFNULL(c.payment_option,'')
   AND pm.payment_method_source=IFNULL(c.payment_method_source,'')
   AND pm.payment_channel_source=IFNULL(c.payment_channel_source,'')
   AND c.raw_payment_date>=pm.effective_start
   AND c.raw_payment_date<IFNULL(pm.effective_end,DATE '9999-12-31')
  LEFT JOIN `pacific-plating-282708.sap_integration_v3.insurance_group_registry` ig
    ON ig.approval_state='APPROVED' AND ig.source_insurance_group=c.insurance_group_source
   AND ig.product_scope='NONMOTOR' AND ig.business_unit=c.business_unit
   AND c.raw_payment_date>=ig.effective_start
   AND c.raw_payment_date<IFNULL(ig.effective_end,DATE '9999-12-31');

  ASSERT (SELECT COUNT(*) FROM _resolved)=(SELECT COUNT(*) FROM _target)
    AS 'NEWPAYMENT target must resolve exactly once through source and registries';
  ASSERT (SELECT COUNT(*) FROM (
    SELECT order_item,period,charge_id,COUNT(*) n FROM _resolved GROUP BY 1,2,3 HAVING n!=1))=0
    AS 'NEWPAYMENT target has missing or ambiguous source/mapping resolution';
  ASSERT (SELECT COUNT(*) FROM _resolved
    WHERE product_scope='NONMOTOR' AND NULLIF(TRIM(resolved_insurance_group),'') IS NULL)=0
    AS 'Released NonMotor row lacks its approved InsuranceGroup value';
  ASSERT (SELECT COUNT(*) FROM _resolved
    WHERE flow='ONETIME' AND REGEXP_CONTAINS(
      UPPER(CONCAT(IFNULL(sap_payment_method,''),'|',IFNULL(sap_payment_channel,''))),
      r'(^|\|)RCL'))=0
    AS 'ONETIME row resolved to an RCL payment mapping';

  CREATE TEMP TABLE _candidate_target AS SELECT
    CAST(CompanyDB AS STRING) CompanyDB,CAST(order_id AS STRING) OrderID,
    CAST(order_item AS STRING) OrderItem,CAST(invoice_no AS STRING) InvoiceNo,
    CAST(OrderDate AS STRING) OrderDate,COALESCE(NULLIF(TRIM(InsuredID),''),'-') InsuredID,
    CAST(Title AS STRING) Title,CAST(FirstName AS STRING) FirstName,CAST(LastName AS STRING) LastName,
    CAST(InsurerCode AS STRING) InsurerCode,CAST(resolved_insurance_group AS STRING) InsuranceGroup,
    CAST(InsuranceType AS STRING) InsuranceType,CAST(InsuranceProduct AS STRING) InsuranceProduct,
    CAST(ProductType AS STRING) ProductType,CAST(PolicyType AS STRING) PolicyType,
    CAST(Endorse AS STRING) Endorse,CAST(PolicyDate AS STRING) PolicyDate,CAST(PolicyNo AS STRING) PolicyNo,
    IFNULL(CAST(EndorsementNo AS STRING),'') EndorsementNo,CAST(ChassisNo AS STRING) ChassisNo,
    CAST(LicensePlate AS STRING) LicensePlate,FORMAT('%.2f',GrossPremium) GrossPremium,
    FORMAT('%.2f',StampDuty) StampDuty,FORMAT('%.2f',VAT) VAT,
    FORMAT('%.2f',TotalPremium) TotalPremium,FORMAT('%.2f',WHT) WHT,
    FORMAT('%.2f',TotalEIR) TotalEIR,FORMAT('%.2f',TotalSBT) TotalSBT,
    FORMAT('%.2f',ProcessingFee) ProcessingFee,FORMAT('%.2f',ProcessingFeeVat) ProcessingFeeVat,
    FORMAT('%.2f',ShippingFee) ShippingFee,FORMAT('%.2f',ShippingFeeVat) ShippingFeeVat,
    FORMAT('%.2f',TotalAmount) TotalAmount,FORMAT('%.2f',Discount) Discount,
    'Paid' TransactionStatus,CAST(SubmissionStatus AS STRING) SubmissionStatus,
    CAST(ApprovalStatus AS STRING) ApprovalStatus,CAST(PaymentStatus AS STRING) PaymentStatus,
    FORMAT('%.2f',ExpectedReceived) ExpectedReceived,FORMAT('%.2f',ActualReceived) ActualReceived,
    FORMAT('%.2f',InterestThisPeriod) InterestThisPeriod,
    FORMAT('%.2f',PrincipleThisPeriod) PrincipleThisPeriod,
    FORMAT('%.2f',InterestEIRThisPeriod) InterestEIRThisPeriod,
    FORMAT('%.2f',PrincipleEIRThisPeriod) PrincipleEIRThisPeriod,
    FORMAT_DATE('%d%m%Y',CASE
      WHEN raw_payment_date>=DATE '2026-07-01' AND raw_payment_date<DATE '2026-08-01'
        THEN DATE '2026-07-31'
      ELSE raw_payment_date END) PaymentDate,
    CAST(period AS STRING) Period,CAST(TotalPeriods AS STRING) TotalPeriods,
    CAST(PendingPayment AS STRING) PendingPayment,CAST(sap_payment_method AS STRING) PaymentMethod,
    CAST(sap_payment_channel AS STRING) PaymentChannel,CAST(ExpectedDate AS STRING) ExpectedDate,
    IFNULL(CAST(RefOrder AS STRING),'') RefOrder,
    FORMAT('%.2f',RefundAmountBeforeFee) RefundAmountBeforeFee,
    FORMAT('%.2f',RefundAmountAfterFee) RefundAmountAfterFee,CAST(BillingAddress AS STRING) BillingAddress,
    FORMAT_DATE('%d%m%Y',v_batch_date) BatchRunDate
  FROM _resolved;

  -- SAP validates RCL sequence at the complete order-item spine, not at payment-event grain.
  -- Preserve every non-target period from the proven source contract and replace only the exact
  -- target period/invoice row with the newly resolved Paid event. One event is not one file row.
  CREATE TEMP TABLE _candidate AS
  SELECT CompanyDB,OrderID,OrderItem,InvoiceNo,OrderDate,InsuredID,Title,FirstName,LastName,
    InsurerCode,InsuranceGroup,InsuranceType,InsuranceProduct,ProductType,PolicyType,Endorse,
    PolicyDate,PolicyNo,EndorsementNo,ChassisNo,LicensePlate,GrossPremium,StampDuty,VAT,
    TotalPremium,WHT,TotalEIR,TotalSBT,ProcessingFee,ProcessingFeeVat,ShippingFee,ShippingFeeVat,
    TotalAmount,Discount,TransactionStatus,SubmissionStatus,ApprovalStatus,PaymentStatus,
    ExpectedReceived,ActualReceived,InterestThisPeriod,PrincipleThisPeriod,
    InterestEIRThisPeriod,PrincipleEIRThisPeriod,PaymentDate,Period,TotalPeriods,PendingPayment,
    PaymentMethod,PaymentChannel,ExpectedDate,RefOrder,RefundAmountBeforeFee,
    RefundAmountAfterFee,BillingAddress,BatchRunDate
  FROM _candidate_target
  UNION ALL
  SELECT CAST(s.CompanyDB AS STRING),CAST(s.OrderID AS STRING),CAST(s.OrderItem AS STRING),
    CAST(IFNULL(s.InvoiceNo,'') AS STRING),CAST(s.OrderDate AS STRING),
    COALESCE(NULLIF(TRIM(s.InsuredID),''),'-'),CAST(s.Title AS STRING),CAST(s.FirstName AS STRING),
    CAST(s.LastName AS STRING),CAST(s.InsurerCode AS STRING),CAST(s.InsuranceGroup AS STRING),
    CAST(s.InsuranceType AS STRING),CAST(s.InsuranceProduct AS STRING),CAST(s.ProductType AS STRING),
    CAST(s.PolicyType AS STRING),CAST(s.Endorse AS STRING),CAST(s.PolicyDate AS STRING),
    CAST(s.PolicyNo AS STRING),IFNULL(CAST(s.EndorsementNo AS STRING),''),CAST(s.ChassisNo AS STRING),
    CAST(s.LicensePlate AS STRING),FORMAT('%.2f',s.GrossPremium),FORMAT('%.2f',s.StampDuty),
    FORMAT('%.2f',s.VAT),FORMAT('%.2f',s.TotalPremium),FORMAT('%.2f',s.WHT),
    FORMAT('%.2f',s.TotalEIR),FORMAT('%.2f',s.TotalSBT),FORMAT('%.2f',s.ProcessingFee),
    FORMAT('%.2f',s.ProcessingFeeVat),FORMAT('%.2f',s.ShippingFee),
    FORMAT('%.2f',s.ShippingFeeVat),FORMAT('%.2f',s.TotalAmount),FORMAT('%.2f',s.Discount),
    CAST(CASE s.TransactionStatus
      WHEN 'paid' THEN 'Paid'
      WHEN 'pending' THEN 'Pending'
      ELSE s.TransactionStatus
    END AS STRING),CAST(s.SubmissionStatus AS STRING),
    CAST(s.ApprovalStatus AS STRING),CAST(s.PaymentStatus AS STRING),
    FORMAT('%.2f',s.ExpectedReceived),FORMAT('%.2f',s.ActualReceived),
    FORMAT('%.2f',s.InterestThisPeriod),FORMAT('%.2f',s.PrincipleThisPeriod),
    FORMAT('%.2f',s.InterestEIRThisPeriod),FORMAT('%.2f',s.PrincipleEIRThisPeriod),
    CAST(IFNULL(s.PaymentDate,'') AS STRING),CAST(s.Period AS STRING),CAST(s.TotalPeriods AS STRING),
    CAST(s.PendingPayment AS STRING),CAST(IFNULL(s.PaymentMethod,'') AS STRING),
    CAST(IFNULL(s.PaymentChannel,'') AS STRING),CAST(s.ExpectedDate AS STRING),
    IFNULL(CAST(s.RefOrder AS STRING),''),FORMAT('%.2f',s.RefundAmountBeforeFee),
    FORMAT('%.2f',s.RefundAmountAfterFee),CAST(s.BillingAddress AS STRING),
    FORMAT_DATE('%d%m%Y',v_batch_date)
  FROM _source s
  WHERE EXISTS (SELECT 1 FROM _target t WHERE t.order_item=s.OrderItem)
    AND NOT EXISTS (SELECT 1 FROM _candidate_target t
      WHERE t.OrderItem=s.OrderItem AND SAFE_CAST(t.Period AS INT64)=s.Period);

  ASSERT (SELECT COUNT(*) FROM _candidate WHERE NULLIF(TRIM(OrderItem),'') IS NULL)=0
    AS 'Candidate with missing OrderItem cannot be quarantined durably';

  CREATE TEMP TABLE _spine_invalid_item AS
  SELECT OrderItem FROM (
    SELECT OrderItem,COUNT(DISTINCT SAFE_CAST(Period AS INT64)) period_n,
      MIN(SAFE_CAST(Period AS INT64)) first_period,MAX(SAFE_CAST(Period AS INT64)) last_period,
      COUNT(DISTINCT SAFE_CAST(TotalPeriods AS INT64)) total_value_n,
      MAX(SAFE_CAST(TotalPeriods AS INT64)) total_n
    FROM _candidate GROUP BY OrderItem)
  WHERE total_value_n!=1 OR first_period!=1 OR last_period!=total_n OR period_n!=total_n;

  -- Every item-level pre-export failure becomes a PII-safe issue. One issue quarantines the
  -- complete OrderItem spine while unrelated clean items continue.
  CREATE TEMP TABLE _candidate_validation_issue AS
  SELECT c.OrderItem order_item,SAFE_CAST(c.Period AS INT64) period,
    'SPINE_INCOMPLETE' rule_code,CAST(NULL AS STRING) field_name
  FROM _candidate c JOIN _spine_invalid_item b USING(OrderItem)
  UNION ALL
  SELECT OrderItem,SAFE_CAST(Period AS INT64),'STATUS_INVALID','TransactionStatus'
  FROM _candidate
  WHERE TransactionStatus NOT IN ('Paid','Pending') OR TransactionStatus IS NULL
  UNION ALL
  SELECT OrderItem,SAFE_CAST(Period AS INT64),'DUPLICATE_PERIOD_INVOICE_IDENTITY',
    CAST(NULL AS STRING)
  FROM (
    SELECT OrderItem,Period,IFNULL(InvoiceNo,'') invoice_no,COUNT(*) row_count
    FROM _candidate GROUP BY 1,2,3 HAVING row_count!=1)
  UNION ALL
  SELECT OrderItem,SAFE_CAST(Period AS INT64),'POLICYNO_TOO_LONG','PolicyNo'
  FROM _candidate WHERE LENGTH(PolicyNo)>50
  UNION ALL
  SELECT c.OrderItem,SAFE_CAST(c.Period AS INT64),'PAID_REQUIRED_FIELD_BLANK',f.field_name
  FROM _candidate c
  CROSS JOIN UNNEST([
    STRUCT('InvoiceNo' AS field_name,c.InvoiceNo AS field_value),
    STRUCT('PaymentDate' AS field_name,c.PaymentDate AS field_value),
    STRUCT('PaymentMethod' AS field_name,c.PaymentMethod AS field_value),
    STRUCT('PaymentChannel' AS field_name,c.PaymentChannel AS field_value)
  ]) f
  WHERE c.TransactionStatus='Paid' AND NULLIF(TRIM(f.field_value),'') IS NULL
  UNION ALL
  SELECT c.OrderItem,SAFE_CAST(c.Period AS INT64),'REQUIRED_VALUE_NULL_OR_LITERAL_NULL',field_name
  FROM _candidate c,
  UNNEST(REGEXP_EXTRACT_ALL(TO_JSON_STRING(c),r'"([^"]+)":(?:null|"NULL")')) field_name
  UNION ALL
  SELECT OrderItem,SAFE_CAST(Period AS INT64),'DATE_FORMAT_INVALID',date_column
  FROM _candidate
  UNPIVOT(date_value FOR date_column IN (OrderDate,PolicyDate,ExpectedDate,BatchRunDate))
  WHERE LENGTH(IFNULL(date_value,''))!=8 OR SAFE.PARSE_DATE('%d%m%Y',date_value) IS NULL
  UNION ALL
  SELECT OrderItem,SAFE_CAST(Period AS INT64),'PAYMENT_DATE_FORMAT_INVALID','PaymentDate'
  FROM _candidate
  WHERE NULLIF(PaymentDate,'') IS NOT NULL
    AND (LENGTH(PaymentDate)!=8 OR SAFE.PARSE_DATE('%d%m%Y',PaymentDate) IS NULL);

  CREATE TEMP TABLE _candidate_invalid_field AS
  SELECT order_item,ARRAY_AGG(DISTINCT field_name ORDER BY field_name) invalid_fields
  FROM _candidate_validation_issue
  WHERE field_name IS NOT NULL
  GROUP BY order_item;

  CREATE TEMP TABLE _candidate_required_hold AS
  SELECT p_pipeline_run_id pipeline_run_id,i.order_item,
    'HOLD_SPINE_PREEXPORT_VALIDATION' hold_code,
    STRING_AGG(DISTINCT i.rule_code,'|' ORDER BY i.rule_code) hold_reason,
    IFNULL(ANY_VALUE(f.invalid_fields),ARRAY<STRING>[]) invalid_fields,
    COUNT(DISTINCT i.period) invalid_period_count,
    CURRENT_TIMESTAMP() detected_at
  FROM _candidate_validation_issue i
  LEFT JOIN _candidate_invalid_field f USING(order_item)
  GROUP BY i.order_item;
  ASSERT (SELECT COUNT(*) FROM _candidate_required_hold WHERE order_item IS NULL)=0
    AS 'Validation hold cannot preserve a NULL OrderItem identity';

  CREATE TEMP TABLE _candidate_release AS
  SELECT c.CompanyDB,c.OrderID,c.OrderItem,c.InvoiceNo,c.OrderDate,c.InsuredID,c.Title,c.FirstName,
    c.LastName,c.InsurerCode,c.InsuranceGroup,c.InsuranceType,c.InsuranceProduct,c.ProductType,
    c.PolicyType,c.Endorse,c.PolicyDate,c.PolicyNo,c.EndorsementNo,c.ChassisNo,c.LicensePlate,
    c.GrossPremium,c.StampDuty,c.VAT,c.TotalPremium,c.WHT,c.TotalEIR,c.TotalSBT,c.ProcessingFee,
    c.ProcessingFeeVat,c.ShippingFee,c.ShippingFeeVat,c.TotalAmount,c.Discount,
    c.TransactionStatus,c.SubmissionStatus,c.ApprovalStatus,c.PaymentStatus,c.ExpectedReceived,
    c.ActualReceived,c.InterestThisPeriod,c.PrincipleThisPeriod,c.InterestEIRThisPeriod,
    c.PrincipleEIRThisPeriod,c.PaymentDate,c.Period,c.TotalPeriods,c.PendingPayment,c.PaymentMethod,
    c.PaymentChannel,c.ExpectedDate,c.RefOrder,c.RefundAmountBeforeFee,c.RefundAmountAfterFee,
    c.BillingAddress,c.BatchRunDate
  FROM _candidate c
  WHERE NOT EXISTS (SELECT 1 FROM _candidate_required_hold h WHERE h.order_item=c.OrderItem);
  ASSERT (SELECT COUNT(*) FROM _candidate_validation_issue i
    WHERE EXISTS (SELECT 1 FROM _candidate_release r WHERE r.OrderItem=i.order_item))=0
    AS 'Released NEWPAYMENT item still has a validation issue';
  ASSERT (SELECT COUNT(*) FROM _candidate_release c
    WHERE REGEXP_CONTAINS(TO_JSON_STRING(c),r':null|:"NULL"'))=0
    AS 'Released NEWPAYMENT candidate must not contain SQL NULL or literal NULL';
  ASSERT (SELECT COUNT(DISTINCT OrderItem) FROM _candidate)=
    (SELECT COUNT(DISTINCT OrderItem) FROM _candidate_release)
      +(SELECT COUNT(*) FROM _candidate_required_hold)
    AS 'Released plus validation-held NEWPAYMENT items do not conserve';

  CREATE TABLE IF NOT EXISTS `pacific-plating-282708.sap_integration_v3.v3_unit5_newpayment_ready` AS
  SELECT CompanyDB,OrderID,OrderItem,InvoiceNo,OrderDate,InsuredID,Title,FirstName,LastName,
    InsurerCode,InsuranceGroup,InsuranceType,InsuranceProduct,ProductType,PolicyType,Endorse,
    PolicyDate,PolicyNo,EndorsementNo,ChassisNo,LicensePlate,GrossPremium,StampDuty,VAT,
    TotalPremium,WHT,TotalEIR,TotalSBT,ProcessingFee,ProcessingFeeVat,ShippingFee,ShippingFeeVat,
    TotalAmount,Discount,TransactionStatus,SubmissionStatus,ApprovalStatus,PaymentStatus,
    ExpectedReceived,ActualReceived,InterestThisPeriod,PrincipleThisPeriod,
    InterestEIRThisPeriod,PrincipleEIRThisPeriod,PaymentDate,Period,TotalPeriods,PendingPayment,
    PaymentMethod,PaymentChannel,ExpectedDate,RefOrder,RefundAmountBeforeFee,
    RefundAmountAfterFee,BillingAddress,BatchRunDate
  FROM _candidate WHERE FALSE;
  ASSERT (SELECT COUNT(*) FROM `pacific-plating-282708.sap_integration_v3.INFORMATION_SCHEMA.COLUMNS`
    WHERE table_name='v3_unit5_newpayment_ready')=56 AS 'NEWPAYMENT payload must have exactly 56 columns';
  ASSERT (SELECT COUNT(*) FROM (
    SELECT ordinal_position,column_name,data_type
    FROM `pacific-plating-282708.sap_integration_v3.INFORMATION_SCHEMA.COLUMNS`
    WHERE table_name='v3_unit5_newpayment_ready'
    EXCEPT DISTINCT
    SELECT ordinal_position,column_name,data_type
    FROM `pacific-plating-282708.sap_integration_v3.INFORMATION_SCHEMA.COLUMNS`
    WHERE table_name='v3_unit5_newpayment_delivery_ready'))=0
    AND (SELECT COUNT(*) FROM (
    SELECT ordinal_position,column_name,data_type
    FROM `pacific-plating-282708.sap_integration_v3.INFORMATION_SCHEMA.COLUMNS`
    WHERE table_name='v3_unit5_newpayment_delivery_ready'
    EXCEPT DISTINCT
    SELECT ordinal_position,column_name,data_type
    FROM `pacific-plating-282708.sap_integration_v3.INFORMATION_SCHEMA.COLUMNS`
    WHERE table_name='v3_unit5_newpayment_ready'))=0
    AS 'NEWPAYMENT names/types/ordinals differ from reviewed 56-column contract';

  BEGIN TRANSACTION;
  MERGE `pacific-plating-282708.sap_integration_v3.v3_unit5_newpayment_run_state` t
  USING (SELECT p_pipeline_run_id pipeline_run_id,'BUILDING' state,COUNT(*) producer_row_count,
    TO_HEX(SHA256(COALESCE(STRING_AGG(TO_HEX(SHA256(TO_JSON_STRING(c))),''
      ORDER BY c.OrderItem,SAFE_CAST(c.Period AS INT64),c.InvoiceNo,TO_JSON_STRING(c)),
      '<EMPTY>'))) producer_set_hash,CURRENT_TIMESTAMP() updated_at FROM _candidate_release c) s
  ON t.pipeline_run_id=s.pipeline_run_id
  WHEN NOT MATCHED THEN INSERT ROW;
  ASSERT @@row_count=1 AS 'Unit 5 producer run already claimed; refusing rewrite or concurrent build';
  DELETE FROM `pacific-plating-282708.sap_integration_v3.v3_unit5_candidate_required_hold`
  WHERE pipeline_run_id=p_pipeline_run_id;
  INSERT INTO `pacific-plating-282708.sap_integration_v3.v3_unit5_candidate_required_hold`
    (pipeline_run_id,order_item,hold_code,hold_reason,invalid_fields,invalid_period_count,detected_at)
  SELECT pipeline_run_id,order_item,hold_code,hold_reason,invalid_fields,invalid_period_count,
    detected_at
  FROM _candidate_required_hold;
  ASSERT @@row_count=(SELECT COUNT(*) FROM _candidate_required_hold)
    AS 'Unit 5 required-value hold publication failed';
  DELETE FROM `pacific-plating-282708.sap_integration_v3.v3_unit5_installment_detail_hold`
  WHERE pipeline_run_id=p_pipeline_run_id;
  INSERT INTO `pacific-plating-282708.sap_integration_v3.v3_unit5_installment_detail_hold`
    (pipeline_run_id,order_item,order_id,transaction_id,snapshot_id,declared_total_periods,
      number_of_installment,detail_row_count,rule_code,detected_at)
  SELECT pipeline_run_id,order_item,order_id,transaction_id,snapshot_id,declared_total_periods,
    number_of_installment,detail_row_count,rule_code,detected_at
  FROM _installment_detail_hold;
  ASSERT @@row_count=(SELECT COUNT(*) FROM _installment_detail_hold)
    AS 'Unit 5 installment-detail hold publication failed';
  DELETE FROM `pacific-plating-282708.sap_integration_v3.v3_unit5_newpayment_ready` WHERE TRUE;
  INSERT INTO `pacific-plating-282708.sap_integration_v3.v3_unit5_newpayment_ready`
    (CompanyDB,OrderID,OrderItem,InvoiceNo,OrderDate,InsuredID,Title,FirstName,LastName,InsurerCode,
      InsuranceGroup,InsuranceType,InsuranceProduct,ProductType,PolicyType,Endorse,PolicyDate,
      PolicyNo,EndorsementNo,ChassisNo,LicensePlate,GrossPremium,StampDuty,VAT,TotalPremium,WHT,
      TotalEIR,TotalSBT,ProcessingFee,ProcessingFeeVat,ShippingFee,ShippingFeeVat,TotalAmount,
      Discount,TransactionStatus,SubmissionStatus,ApprovalStatus,PaymentStatus,ExpectedReceived,
      ActualReceived,InterestThisPeriod,PrincipleThisPeriod,InterestEIRThisPeriod,
      PrincipleEIRThisPeriod,PaymentDate,Period,TotalPeriods,PendingPayment,PaymentMethod,
      PaymentChannel,ExpectedDate,RefOrder,RefundAmountBeforeFee,RefundAmountAfterFee,
      BillingAddress,BatchRunDate)
  SELECT CompanyDB,OrderID,OrderItem,InvoiceNo,OrderDate,InsuredID,Title,FirstName,LastName,
    InsurerCode,InsuranceGroup,InsuranceType,InsuranceProduct,ProductType,PolicyType,Endorse,
    PolicyDate,PolicyNo,EndorsementNo,ChassisNo,LicensePlate,GrossPremium,StampDuty,VAT,
    TotalPremium,WHT,TotalEIR,TotalSBT,ProcessingFee,ProcessingFeeVat,ShippingFee,ShippingFeeVat,
    TotalAmount,Discount,TransactionStatus,SubmissionStatus,ApprovalStatus,PaymentStatus,
    ExpectedReceived,ActualReceived,InterestThisPeriod,PrincipleThisPeriod,
    InterestEIRThisPeriod,PrincipleEIRThisPeriod,PaymentDate,Period,TotalPeriods,PendingPayment,
    PaymentMethod,PaymentChannel,ExpectedDate,RefOrder,RefundAmountBeforeFee,
    RefundAmountAfterFee,BillingAddress,BatchRunDate
  FROM _candidate_release;
  ASSERT @@row_count=(SELECT COUNT(*) FROM _candidate_release)
    AS 'Unit 5 candidate publication row conservation failed';
  DELETE FROM `pacific-plating-282708.sap_integration_v3.v3_unit5_payload_identity`
  WHERE pipeline_run_id=p_pipeline_run_id AND file_role='NEWPAYMENT';
  INSERT INTO `pacific-plating-282708.sap_integration_v3.v3_unit5_payload_identity`
  SELECT p_pipeline_run_id,'NEWPAYMENT',r.order_item,r.period,r.charge_id,r.invoice_no,
    TO_HEX(SHA256(TO_JSON_STRING(c))),CURRENT_TIMESTAMP()
  FROM _resolved r JOIN _candidate_target c
    ON c.OrderItem=r.order_item AND SAFE_CAST(c.Period AS INT64)=r.period AND c.InvoiceNo=r.invoice_no
  WHERE EXISTS (SELECT 1 FROM _candidate_release q WHERE q.OrderItem=c.OrderItem);
  ASSERT @@row_count=(SELECT COUNT(*) FROM _resolved r
    WHERE EXISTS (SELECT 1 FROM _candidate_release q WHERE q.OrderItem=r.order_item))
    AS 'Unit 5 target identity row conservation failed';

  COMMIT TRANSACTION;
END;

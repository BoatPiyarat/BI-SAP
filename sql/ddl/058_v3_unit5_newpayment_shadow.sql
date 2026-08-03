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

  CREATE TEMP TABLE _target AS
  SELECT e.*
  FROM `pacific-plating-282708.sap_integration_v3.v3_unit2_event_shadow` e
  WHERE e.pipeline_run_id=p_pipeline_run_id AND e.outcome='READY_CREATE_OR_PAYMENT'
    AND EXISTS (SELECT 1 FROM `pacific-plating-282708.sap_integration_v3.sap_mirror_doc` m
      WHERE m.U_OrderItem=e.order_item)
    AND NOT EXISTS (SELECT 1
      FROM `pacific-plating-282708.sap_integration_v3.v3_unit3_mapping_hold` h
      WHERE h.pipeline_run_id=e.pipeline_run_id AND h.order_item=e.order_item
        AND h.period=e.period AND h.charge_id=e.charge_id);

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

  CREATE TEMP TABLE _candidate_target AS SELECT
    CAST(CompanyDB AS STRING) CompanyDB,CAST(order_id AS STRING) OrderID,
    CAST(order_item AS STRING) OrderItem,CAST(invoice_no AS STRING) InvoiceNo,
    CAST(OrderDate AS STRING) OrderDate,COALESCE(NULLIF(TRIM(InsuredID),''),'-') InsuredID,
    CAST(Title AS STRING) Title,CAST(FirstName AS STRING) FirstName,CAST(LastName AS STRING) LastName,
    CAST(InsurerCode AS STRING) InsurerCode,CAST(resolved_insurance_group AS STRING) InsuranceGroup,
    CAST(InsuranceType AS STRING) InsuranceType,CAST(InsuranceProduct AS STRING) InsuranceProduct,
    CAST(ProductType AS STRING) ProductType,CAST(PolicyType AS STRING) PolicyType,
    CAST(Endorse AS STRING) Endorse,CAST(PolicyDate AS STRING) PolicyDate,CAST(PolicyNo AS STRING) PolicyNo,
    CAST(EndorsementNo AS STRING) EndorsementNo,CAST(ChassisNo AS STRING) ChassisNo,
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
    CAST(RefOrder AS STRING) RefOrder,FORMAT('%.2f',RefundAmountBeforeFee) RefundAmountBeforeFee,
    FORMAT('%.2f',RefundAmountAfterFee) RefundAmountAfterFee,CAST(BillingAddress AS STRING) BillingAddress,
    FORMAT_DATE('%d%m%Y',v_batch_date) BatchRunDate
  FROM _resolved;

  -- SAP validates RCL sequence at the complete order-item spine, not at payment-event grain.
  -- Preserve every non-target period from the proven source contract and replace only the exact
  -- target period/invoice row with the newly resolved Paid event. One event is not one file row.
  CREATE TEMP TABLE _candidate AS
  SELECT * FROM _candidate_target
  UNION ALL
  SELECT CAST(s.CompanyDB AS STRING),CAST(s.OrderID AS STRING),CAST(s.OrderItem AS STRING),
    CAST(IFNULL(s.InvoiceNo,'') AS STRING),CAST(s.OrderDate AS STRING),
    COALESCE(NULLIF(TRIM(s.InsuredID),''),'-'),CAST(s.Title AS STRING),CAST(s.FirstName AS STRING),
    CAST(s.LastName AS STRING),CAST(s.InsurerCode AS STRING),CAST(s.InsuranceGroup AS STRING),
    CAST(s.InsuranceType AS STRING),CAST(s.InsuranceProduct AS STRING),CAST(s.ProductType AS STRING),
    CAST(s.PolicyType AS STRING),CAST(s.Endorse AS STRING),CAST(s.PolicyDate AS STRING),
    CAST(s.PolicyNo AS STRING),CAST(s.EndorsementNo AS STRING),CAST(s.ChassisNo AS STRING),
    CAST(s.LicensePlate AS STRING),FORMAT('%.2f',s.GrossPremium),FORMAT('%.2f',s.StampDuty),
    FORMAT('%.2f',s.VAT),FORMAT('%.2f',s.TotalPremium),FORMAT('%.2f',s.WHT),
    FORMAT('%.2f',s.TotalEIR),FORMAT('%.2f',s.TotalSBT),FORMAT('%.2f',s.ProcessingFee),
    FORMAT('%.2f',s.ProcessingFeeVat),FORMAT('%.2f',s.ShippingFee),
    FORMAT('%.2f',s.ShippingFeeVat),FORMAT('%.2f',s.TotalAmount),FORMAT('%.2f',s.Discount),
    CAST(s.TransactionStatus AS STRING),CAST(s.SubmissionStatus AS STRING),
    CAST(s.ApprovalStatus AS STRING),CAST(s.PaymentStatus AS STRING),
    FORMAT('%.2f',s.ExpectedReceived),FORMAT('%.2f',s.ActualReceived),
    FORMAT('%.2f',s.InterestThisPeriod),FORMAT('%.2f',s.PrincipleThisPeriod),
    FORMAT('%.2f',s.InterestEIRThisPeriod),FORMAT('%.2f',s.PrincipleEIRThisPeriod),
    CAST(IFNULL(s.PaymentDate,'') AS STRING),CAST(s.Period AS STRING),CAST(s.TotalPeriods AS STRING),
    CAST(s.PendingPayment AS STRING),CAST(IFNULL(s.PaymentMethod,'') AS STRING),
    CAST(IFNULL(s.PaymentChannel,'') AS STRING),CAST(s.ExpectedDate AS STRING),
    CAST(s.RefOrder AS STRING),FORMAT('%.2f',s.RefundAmountBeforeFee),
    FORMAT('%.2f',s.RefundAmountAfterFee),CAST(s.BillingAddress AS STRING),
    FORMAT_DATE('%d%m%Y',v_batch_date)
  FROM _source s
  WHERE EXISTS (SELECT 1 FROM _target t WHERE t.order_item=s.OrderItem)
    AND NOT EXISTS (SELECT 1 FROM _candidate_target t
      WHERE t.OrderItem=s.OrderItem AND SAFE_CAST(t.Period AS INT64)=s.Period);

  ASSERT (SELECT COUNT(*) FROM (
    SELECT OrderItem,COUNT(DISTINCT SAFE_CAST(Period AS INT64)) period_n,
      MAX(SAFE_CAST(TotalPeriods AS INT64)) total_n
    FROM _candidate GROUP BY OrderItem HAVING period_n!=total_n))=0
    AS 'NEWPAYMENT full period spine is incomplete';
  ASSERT (SELECT COUNT(*) FROM (
    SELECT OrderItem,Period,IFNULL(InvoiceNo,''),COUNT(*) n FROM _candidate
    GROUP BY 1,2,3 HAVING n!=1))=0 AS 'NEWPAYMENT full period spine has duplicate identities';

  ASSERT (SELECT COUNT(*) FROM _candidate WHERE LENGTH(PolicyNo)>50)=0
    AS 'POLICYNO_TOO_LONG in NEWPAYMENT candidate';
  ASSERT (SELECT COUNT(*) FROM _candidate WHERE TransactionStatus='Paid'
    AND (NULLIF(TRIM(InvoiceNo),'') IS NULL
    OR NULLIF(TRIM(PaymentDate),'') IS NULL OR NULLIF(TRIM(PaymentMethod),'') IS NULL
    OR NULLIF(TRIM(PaymentChannel),'') IS NULL))=0 AS 'Paid completeness failed';
  ASSERT (SELECT COUNT(*) FROM (
    SELECT OrderItem,date_value FROM _candidate
    UNPIVOT(date_value FOR date_column IN (OrderDate,PolicyDate,ExpectedDate,BatchRunDate))
    WHERE LENGTH(IFNULL(date_value,''))!=8
       OR SAFE.PARSE_DATE('%d%m%Y',date_value) IS NULL))=0 AS 'DATE_FORMAT_INVALID';
  ASSERT (SELECT COUNT(*) FROM _candidate WHERE NULLIF(PaymentDate,'') IS NOT NULL
    AND (LENGTH(PaymentDate)!=8 OR SAFE.PARSE_DATE('%d%m%Y',PaymentDate) IS NULL))=0
    AS 'PAYMENT_DATE_FORMAT_INVALID';

  CREATE OR REPLACE TABLE `pacific-plating-282708.sap_integration_v3.v3_unit5_newpayment_ready` AS
  SELECT * FROM _candidate;
  ASSERT (SELECT COUNT(*) FROM `pacific-plating-282708.sap_integration_v3.INFORMATION_SCHEMA.COLUMNS`
    WHERE table_name='v3_unit5_newpayment_ready')=56 AS 'NEWPAYMENT payload must have exactly 56 columns';

  DELETE FROM `pacific-plating-282708.sap_integration_v3.v3_unit5_payload_identity`
  WHERE pipeline_run_id=p_pipeline_run_id AND file_role='NEWPAYMENT';
  INSERT INTO `pacific-plating-282708.sap_integration_v3.v3_unit5_payload_identity`
  SELECT p_pipeline_run_id,'NEWPAYMENT',r.order_item,r.period,r.charge_id,r.invoice_no,
    TO_HEX(SHA256(TO_JSON_STRING(c))),CURRENT_TIMESTAMP()
  FROM _resolved r JOIN _candidate_target c
    ON c.OrderItem=r.order_item AND SAFE_CAST(c.Period AS INT64)=r.period AND c.InvoiceNo=r.invoice_no;
END;

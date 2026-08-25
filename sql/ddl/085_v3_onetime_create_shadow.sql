-- SOURCE ONLY / Class A. Scenario 1: ordinary RCB/ONETIME CREATE preparation.
-- Builds a 56-column shadow and durable holds. No GCS write or scheduler activation.

CREATE TABLE IF NOT EXISTS `pacific-plating-282708.sap_integration_v3.v3_onetime_create_hold` (
  pipeline_run_id STRING NOT NULL, order_item STRING, order_id STRING, period INT64,
  charge_id STRING, invoice_no STRING, hold_code STRING NOT NULL,
  hold_reason STRING NOT NULL, detected_at TIMESTAMP NOT NULL
)
PARTITION BY DATE(detected_at)
CLUSTER BY pipeline_run_id,hold_code,order_item;

CREATE OR REPLACE PROCEDURE
  `pacific-plating-282708.sap_integration_v3.sp_build_v3_onetime_create_shadow`(
    p_pipeline_run_id STRING)
BEGIN
  DECLARE v_period_id STRING;
  DECLARE v_period_state_version INT64;
  DECLARE v_period_start DATE;
  DECLARE v_period_end DATE;
  DECLARE v_batch_date DATE;

  ASSERT NULLIF(TRIM(p_pipeline_run_id),'') IS NOT NULL
    AS 'ONETIME CREATE requires pipeline_run_id';
  ASSERT (SELECT COUNT(*) FROM `pacific-plating-282708.sap_integration_v3.pipeline_run_log`
    WHERE run_id=p_pipeline_run_id AND step='UNIT1_COMPLETE' AND status='SUCCESS')=1
    AS 'ONETIME CREATE requires exactly one successful Unit 1 row';
  ASSERT (SELECT COUNT(*) FROM `pacific-plating-282708.sap_integration_v3.v3_unit3_run_summary`
    WHERE pipeline_run_id=p_pipeline_run_id)=1 AS 'ONETIME CREATE requires Unit 3 evaluation';
  ASSERT (SELECT COUNT(*) FROM `pacific-plating-282708.sap_integration_v3.sap_period_state`
    WHERE status='OPEN')=1 AS 'ONETIME CREATE requires exactly one OPEN period';
  SET (v_period_id,v_period_state_version,v_period_start,v_period_end)=(SELECT AS STRUCT
      period_id,state_version,period_start,period_end
    FROM `pacific-plating-282708.sap_integration_v3.sap_period_state` WHERE status='OPEN');
  SET v_batch_date=LEAST(CURRENT_DATE('Asia/Bangkok'),DATE_SUB(v_period_end,INTERVAL 1 DAY));

  CREATE TEMP TABLE _event_raw AS
  SELECT e.pipeline_run_id,e.order_item,e.order_id,e.period,e.charge_id,e.invoice_no
  FROM `pacific-plating-282708.sap_integration_v3.v3_unit2_event_shadow` e
  WHERE e.pipeline_run_id=p_pipeline_run_id AND e.outcome='READY_CREATE_OR_PAYMENT'
    AND e.flow='ONETIME'
    AND NOT EXISTS (SELECT 1 FROM `pacific-plating-282708.sap_integration_v3.sap_mirror_doc` m
      WHERE m.U_OrderItem=e.order_item)
    AND NOT EXISTS (SELECT 1
      FROM `pacific-plating-282708.sap_integration_v3.v3_unit3_mapping_hold` h
      WHERE h.pipeline_run_id=e.pipeline_run_id AND h.order_item=e.order_item
        AND h.period=e.period AND h.charge_id=e.charge_id);

  CREATE TEMP TABLE _event AS
  SELECT pipeline_run_id,order_item,period,charge_id,ANY_VALUE(order_id) order_id,
    ANY_VALUE(invoice_no) invoice_no,COUNT(*) event_rows,
    COUNT(DISTINCT IFNULL(order_id,'<NULL>')) order_id_values,
    COUNT(DISTINCT IFNULL(invoice_no,'<NULL>')) invoice_values
  FROM _event_raw GROUP BY pipeline_run_id,order_item,period,charge_id;

  CREATE TEMP TABLE _identity AS
  SELECT e.*,COUNT(c.id) raw_rows,ANY_VALUE(c.third_party_id) raw_third_party_id,
    COUNT(s.charge_id) staged_rows,ANY_VALUE(s.third_party_id) staged_third_party_id
  FROM _event e
  LEFT JOIN `pacific-plating-282708.careos.carepay_charges` c ON c.id=e.charge_id
  LEFT JOIN `pacific-plating-282708.sap_integration_v3.stg_payment_events` s
    ON s.charge_id=e.charge_id
  GROUP BY e.pipeline_run_id,e.order_item,e.order_id,e.period,e.charge_id,e.invoice_no,
    e.event_rows,e.order_id_values,e.invoice_values;

  CREATE TEMP TABLE _shape AS
  SELECT i.*,COUNT(o.OrderItem) source_rows,COUNTIF(o.InvoiceNo=i.invoice_no) exact_rows,
    COUNTIF(o.InvoiceNo=i.invoice_no AND SAFE_CAST(o.Period AS INT64)=1
      AND SAFE_CAST(o.TotalPeriods AS INT64)=1) one_period_rows
  FROM _identity i
  LEFT JOIN `pacific-plating-282708.sap_integration_v3.vw_onetime_payload_source` o
    ON o.OrderItem=i.order_item AND SAFE_CAST(o.Period AS INT64)=i.period
  GROUP BY i.pipeline_run_id,i.order_item,i.order_id,i.period,i.charge_id,i.invoice_no,
    i.event_rows,i.order_id_values,i.invoice_values,i.raw_rows,i.raw_third_party_id,
    i.staged_rows,i.staged_third_party_id;

  CREATE TEMP TABLE _classified AS
  SELECT s.*,co.current_human_id IS NOT NULL is_credit_shell,CASE
    WHEN event_rows!=1 OR order_id_values!=1 OR invoice_values!=1
      THEN 'HOLD_DUPLICATE_OR_CONFLICTING_EVENT'
    WHEN raw_rows!=1 THEN IF(raw_rows=0,'HOLD_MISSING_RAW_CHARGE','HOLD_DUPLICATE_RAW_CHARGE')
    WHEN staged_rows!=1 THEN IF(staged_rows=0,'HOLD_MISSING_STAGED_EVENT','HOLD_DUPLICATE_STAGED_EVENT')
    WHEN NULLIF(TRIM(order_item),'') IS NULL THEN 'HOLD_BLANK_ORDER_ITEM'
    WHEN period!=1 THEN 'HOLD_ONETIME_PERIOD_NOT_ONE'
    WHEN raw_third_party_id IS NULL THEN 'HOLD_NULL_RAW_ID_FALLBACK_CONFLICT'
    WHEN NULLIF(TRIM(raw_third_party_id),'') IS NULL THEN 'HOLD_BLANK_RAW_IDENTITY'
    WHEN NOT (staged_third_party_id IS NOT DISTINCT FROM raw_third_party_id)
      THEN 'HOLD_STAGE_IDENTITY_DRIFT'
    WHEN NOT (invoice_no IS NOT DISTINCT FROM staged_third_party_id)
      THEN 'HOLD_EVENT_IDENTITY_DRIFT'
    WHEN exact_rows=0 THEN 'HOLD_MISSING_EXACT_SOURCE_VARIANT'
    WHEN exact_rows!=1 THEN 'HOLD_AMBIGUOUS_EXACT_SOURCE_VARIANT'
    WHEN one_period_rows!=1 THEN 'HOLD_ONETIME_SOURCE_NOT_ONE_PERIOD'
    WHEN co.current_human_id IS NOT NULL THEN 'HOLD_WRONG_SCENARIO_CREDITSHELL'
    ELSE 'READY' END readiness_code
  FROM _shape s LEFT JOIN (SELECT DISTINCT current_human_id
    FROM `pacific-plating-282708.careos.cancelled_change_orders`) co
    ON co.current_human_id=s.order_id;

  ASSERT (SELECT COALESCE(SUM(event_rows),0) FROM _classified)=(SELECT COUNT(*) FROM _event_raw)
    AS 'ONETIME CREATE event conservation failed';

  CREATE TEMP TABLE _resolution_shape AS
  WITH category AS (
    SELECT human_id,COUNT(DISTINCT product_category) category_count,
      ANY_VALUE(product_category HAVING MIN product_category) category_value
    FROM `pacific-plating-282708.analytics_reports.non_motor_report_order_for_accounting`
    GROUP BY human_id), base AS (
    SELECT t.*,DATE(p.charge_time) raw_payment_date,
      (SELECT COUNT(*) FROM `pacific-plating-282708.careos.careos_order_items` oi
        WHERE oi.human_id=t.order_item) item_rows,
      (SELECT ANY_VALUE(oi.product) FROM `pacific-plating-282708.careos.careos_order_items` oi
        WHERE oi.human_id=t.order_item) item_product,
      n.category_count,n.category_value,p.payment_option,c.payment_method,c.service_provider
    FROM _classified t
    LEFT JOIN `pacific-plating-282708.sap_integration_v3.stg_payment_events` p USING(charge_id)
    LEFT JOIN `pacific-plating-282708.careos.carepay_charges` c ON c.id=t.charge_id
    LEFT JOIN category n ON n.human_id=t.order_id
    WHERE t.readiness_code='READY')
  SELECT b.*,
    IF(item_product='products/car-insurance','MOTOR','NONMOTOR') product_scope,
    (SELECT COUNT(*) FROM `pacific-plating-282708.sap_integration_v3.payment_mapping_registry` pm
      WHERE pm.approval_state='APPROVED' AND pm.flow='ONETIME'
        AND pm.product_scope=IF(b.item_product='products/car-insurance','MOTOR','NONMOTOR')
        AND pm.is_credit_shell=FALSE AND pm.payment_source_type=IFNULL(b.payment_option,'')
        AND pm.payment_method_source=IFNULL(b.payment_method,'')
        AND pm.payment_channel_source=IFNULL(b.service_provider,'')
        AND b.raw_payment_date>=pm.effective_start
        AND b.raw_payment_date<IFNULL(pm.effective_end,DATE '9999-12-31')) payment_mapping_rows,
    (SELECT COUNT(*) FROM `pacific-plating-282708.sap_integration_v3.insurance_group_registry` ig
      WHERE ig.approval_state='APPROVED' AND ig.source_insurance_group=
        IF(b.category_count=1,b.category_value,'__AMBIGUOUS_OR_MISSING__')
        AND ig.product_scope='NONMOTOR' AND ig.business_unit='RCB'
        AND b.raw_payment_date>=ig.effective_start
        AND b.raw_payment_date<IFNULL(ig.effective_end,DATE '9999-12-31')) insurance_mapping_rows
  FROM base b;

  CREATE TEMP TABLE _final_classified AS
  SELECT c.*,c.readiness_code final_readiness_code FROM _classified c WHERE readiness_code!='READY'
  UNION ALL
  SELECT r.* EXCEPT(item_rows,item_product,category_count,category_value,payment_option,payment_method,
      service_provider,raw_payment_date,product_scope,payment_mapping_rows,insurance_mapping_rows),
    CASE WHEN item_rows!=1 THEN IF(item_rows=0,'HOLD_MISSING_ORDER_ITEM','HOLD_DUPLICATE_ORDER_ITEM')
      WHEN raw_payment_date IS NULL THEN 'HOLD_MISSING_PAYMENT_DATE'
      WHEN raw_payment_date>=v_period_end THEN 'HOLD_FUTURE_PAYMENT_DATE'
      WHEN payment_mapping_rows!=1 THEN 'HOLD_PAYMENT_MAPPING'
      WHEN product_scope='NONMOTOR' AND insurance_mapping_rows!=1 THEN 'HOLD_INSURANCE_GROUP_MAPPING'
      ELSE 'READY' END final_readiness_code
  FROM _resolution_shape r;

  DELETE FROM `pacific-plating-282708.sap_integration_v3.v3_onetime_create_hold`
  WHERE pipeline_run_id=p_pipeline_run_id;
  INSERT INTO `pacific-plating-282708.sap_integration_v3.v3_onetime_create_hold`
  SELECT pipeline_run_id,order_item,order_id,period,charge_id,invoice_no,final_readiness_code,
    CONCAT('Scenario 1 held by ',final_readiness_code),CURRENT_TIMESTAMP()
  FROM _final_classified WHERE final_readiness_code!='READY';
  ASSERT (SELECT COUNT(*) FROM _final_classified)=
    (SELECT COUNTIF(final_readiness_code='READY') FROM _final_classified)+
    (SELECT COUNT(*) FROM `pacific-plating-282708.sap_integration_v3.v3_onetime_create_hold`
      WHERE pipeline_run_id=p_pipeline_run_id) AS 'ONETIME CREATE final ready/hold conservation failed';

  CREATE TEMP TABLE _target AS SELECT * EXCEPT(readiness_code,final_readiness_code)
    FROM _final_classified WHERE final_readiness_code='READY';
  CREATE TEMP TABLE _resolved AS
  WITH category AS (
    SELECT human_id,COUNT(DISTINCT product_category) category_count,
      ANY_VALUE(product_category HAVING MIN product_category) category_value
    FROM `pacific-plating-282708.analytics_reports.non_motor_report_order_for_accounting`
    GROUP BY human_id)
  SELECT t.pipeline_run_id,t.order_item,t.order_id,t.period,t.charge_id,t.invoice_no,
    DATE(p.charge_time) raw_payment_date,
    IF(oi.product='products/car-insurance','MOTOR','NONMOTOR') product_scope,
    o.* EXCEPT(OrderItem,OrderID,Period,InvoiceNo),pm.sap_payment_method,pm.sap_payment_channel,
    IF(oi.product!='products/car-insurance',ig.sap_insurance_group,o.InsuranceGroup)
      resolved_insurance_group
  FROM _target t
  JOIN `pacific-plating-282708.sap_integration_v3.stg_payment_events` p USING(charge_id)
  JOIN `pacific-plating-282708.careos.carepay_charges` c ON c.id=t.charge_id
  JOIN `pacific-plating-282708.careos.careos_order_items` oi ON oi.human_id=t.order_item
  LEFT JOIN category n ON n.human_id=t.order_id
  JOIN `pacific-plating-282708.sap_integration_v3.vw_onetime_payload_source` o
    ON o.OrderItem=t.order_item AND SAFE_CAST(o.Period AS INT64)=t.period AND o.InvoiceNo=t.invoice_no
  JOIN `pacific-plating-282708.sap_integration_v3.payment_mapping_registry` pm
    ON pm.approval_state='APPROVED' AND pm.flow='ONETIME'
   AND pm.product_scope=IF(oi.product='products/car-insurance','MOTOR','NONMOTOR')
   AND pm.is_credit_shell=FALSE AND pm.payment_source_type=IFNULL(p.payment_option,'')
   AND pm.payment_method_source=IFNULL(c.payment_method,'')
   AND pm.payment_channel_source=IFNULL(c.service_provider,'')
   AND DATE(p.charge_time)>=pm.effective_start
   AND DATE(p.charge_time)<IFNULL(pm.effective_end,DATE '9999-12-31')
  LEFT JOIN `pacific-plating-282708.sap_integration_v3.insurance_group_registry` ig
    ON ig.approval_state='APPROVED'
   AND ig.source_insurance_group=IF(n.category_count=1,n.category_value,'__AMBIGUOUS_OR_MISSING__')
   AND ig.product_scope='NONMOTOR' AND ig.business_unit='RCB'
   AND DATE(p.charge_time)>=ig.effective_start
   AND DATE(p.charge_time)<IFNULL(ig.effective_end,DATE '9999-12-31');

  ASSERT (SELECT COUNT(*) FROM _resolved)=(SELECT COUNT(*) FROM _target)
    AS 'ONETIME CREATE target must resolve exactly once';
  ASSERT (SELECT COUNT(*) FROM (SELECT order_item,period,charge_id,COUNT(*) n
    FROM _resolved GROUP BY 1,2,3 HAVING n!=1))=0
    AS 'ONETIME CREATE resolved identity is duplicated';
  ASSERT (SELECT COUNT(*) FROM _resolved
    WHERE product_scope='NONMOTOR' AND NULLIF(TRIM(resolved_insurance_group),'') IS NULL)=0
    AS 'ONETIME CREATE NonMotor InsuranceGroup unresolved';
  ASSERT (SELECT COUNT(*) FROM _resolved WHERE REGEXP_CONTAINS(
    UPPER(CONCAT(IFNULL(sap_payment_method,''),'|',IFNULL(sap_payment_channel,''))),r'(^|\|)RCL'))=0
    AS 'ONETIME CREATE resolved to RCL mapping';

  CREATE OR REPLACE TABLE `pacific-plating-282708.sap_integration_v3.v3_onetime_create_ready` AS
  SELECT CAST(CompanyDB AS STRING) CompanyDB,CAST(order_id AS STRING) OrderID,
    CAST(order_item AS STRING) OrderItem,CAST(invoice_no AS STRING) InvoiceNo,
    CAST(OrderDate AS STRING) OrderDate,COALESCE(NULLIF(TRIM(CAST(InsuredID AS STRING)),''),'-') InsuredID,
    CAST(Title AS STRING) Title,CAST(FirstName AS STRING) FirstName,CAST(LastName AS STRING) LastName,
    CAST(InsurerCode AS STRING) InsurerCode,CAST(resolved_insurance_group AS STRING) InsuranceGroup,
    CAST(InsuranceType AS STRING) InsuranceType,CAST(InsuranceProduct AS STRING) InsuranceProduct,
    CAST(ProductType AS STRING) ProductType,CAST(PolicyType AS STRING) PolicyType,
    CAST(Endorse AS STRING) Endorse,CAST(PolicyDate AS STRING) PolicyDate,CAST(PolicyNo AS STRING) PolicyNo,
    CAST(EndorsementNo AS STRING) EndorsementNo,CAST(ChassisNo AS STRING) ChassisNo,
    CAST(LicensePlate AS STRING) LicensePlate,FORMAT('%.2f',SAFE_CAST(GrossPremium AS FLOAT64)) GrossPremium,
    FORMAT('%.2f',SAFE_CAST(StampDuty AS FLOAT64)) StampDuty,FORMAT('%.2f',SAFE_CAST(VAT AS FLOAT64)) VAT,
    FORMAT('%.2f',SAFE_CAST(TotalPremium AS FLOAT64)) TotalPremium,
    FORMAT('%.2f',SAFE_CAST(WHT AS FLOAT64)) WHT,FORMAT('%.2f',SAFE_CAST(TotalEIR AS FLOAT64)) TotalEIR,
    FORMAT('%.2f',SAFE_CAST(TotalSBT AS FLOAT64)) TotalSBT,
    FORMAT('%.2f',SAFE_CAST(ProcessingFee AS FLOAT64)) ProcessingFee,
    FORMAT('%.2f',SAFE_CAST(ProcessingFeeVat AS FLOAT64)) ProcessingFeeVat,
    FORMAT('%.2f',SAFE_CAST(ShippingFee AS FLOAT64)) ShippingFee,
    FORMAT('%.2f',SAFE_CAST(ShippingFeeVat AS FLOAT64)) ShippingFeeVat,
    FORMAT('%.2f',SAFE_CAST(TotalAmount AS FLOAT64)) TotalAmount,
    FORMAT('%.2f',SAFE_CAST(Discount AS FLOAT64)) Discount,'Paid' TransactionStatus,
    CAST(SubmissionStatus AS STRING) SubmissionStatus,CAST(ApprovalStatus AS STRING) ApprovalStatus,
    CAST(PaymentStatus AS STRING) PaymentStatus,
    FORMAT('%.2f',SAFE_CAST(ExpectedReceived AS FLOAT64)) ExpectedReceived,
    FORMAT('%.2f',SAFE_CAST(ActualReceived AS FLOAT64)) ActualReceived,
    FORMAT('%.2f',SAFE_CAST(InterestThisPeriod AS FLOAT64)) InterestThisPeriod,
    FORMAT('%.2f',SAFE_CAST(PrincipleThisPeriod AS FLOAT64)) PrincipleThisPeriod,
    FORMAT('%.2f',SAFE_CAST(InterestEIRThisPeriod AS FLOAT64)) InterestEIRThisPeriod,
    FORMAT('%.2f',SAFE_CAST(PrincipleEIRThisPeriod AS FLOAT64)) PrincipleEIRThisPeriod,
    FORMAT_DATE('%d%m%Y',CASE
      WHEN raw_payment_date>=DATE '2026-07-01' AND raw_payment_date<DATE '2026-08-01'
        THEN DATE '2026-07-31'
      WHEN raw_payment_date<v_period_start THEN v_period_start ELSE raw_payment_date END) PaymentDate,
    '1' Period,'1' TotalPeriods,CAST(PendingPayment AS STRING) PendingPayment,
    CAST(sap_payment_method AS STRING) PaymentMethod,CAST(sap_payment_channel AS STRING) PaymentChannel,
    CAST(ExpectedDate AS STRING) ExpectedDate,CAST(RefOrder AS STRING) RefOrder,
    FORMAT('%.2f',SAFE_CAST(RefundAmountBeforeFee AS FLOAT64)) RefundAmountBeforeFee,
    FORMAT('%.2f',SAFE_CAST(RefundAmountAfterFee AS FLOAT64)) RefundAmountAfterFee,
    CAST(BillingAddress AS STRING) BillingAddress,FORMAT_DATE('%d%m%Y',v_batch_date) BatchRunDate
  FROM _resolved;

  ASSERT (SELECT COUNT(*) FROM `pacific-plating-282708.sap_integration_v3.INFORMATION_SCHEMA.COLUMNS`
    WHERE table_name='v3_onetime_create_ready')=56 AS 'ONETIME CREATE must have 56 columns';
  ASSERT (SELECT COUNT(*) FROM (
    SELECT ordinal_position,column_name,data_type
    FROM `pacific-plating-282708.sap_integration_v3.INFORMATION_SCHEMA.COLUMNS`
    WHERE table_name='v3_onetime_create_ready'
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
    WHERE table_name='v3_onetime_create_ready'))=0
    AS 'ONETIME CREATE names/types/ordinals differ from reviewed 56-column contract';
  CREATE TEMP TABLE _payload_validation AS
  SELECT r.pipeline_run_id,r.order_item,r.order_id,r.period,r.charge_id,r.invoice_no,CASE
    WHEN (SELECT COUNT(*) FROM `pacific-plating-282708.sap_integration_v3.v3_onetime_create_ready` q
      WHERE q.OrderItem=p.OrderItem AND q.Period=p.Period AND q.InvoiceNo=p.InvoiceNo)!=1
      THEN 'HOLD_DUPLICATE_PAYLOAD_GRAIN'
    WHEN p.Period!='1' OR p.TotalPeriods!='1' OR p.TransactionStatus!='Paid'
      THEN 'HOLD_STATUS_OR_PERIOD_INVALID'
    WHEN LENGTH(p.InvoiceNo)>30 OR LENGTH(p.PolicyNo)>50 THEN 'HOLD_LENGTH_LIMIT_INVALID'
    WHEN LENGTH(IFNULL(p.OrderDate,''))!=8 OR SAFE.PARSE_DATE('%d%m%Y',p.OrderDate) IS NULL
      OR LENGTH(IFNULL(p.PolicyDate,''))!=8 OR SAFE.PARSE_DATE('%d%m%Y',p.PolicyDate) IS NULL
      OR LENGTH(IFNULL(p.ExpectedDate,''))!=8 OR SAFE.PARSE_DATE('%d%m%Y',p.ExpectedDate) IS NULL
      OR LENGTH(IFNULL(p.PaymentDate,''))!=8 OR SAFE.PARSE_DATE('%d%m%Y',p.PaymentDate) IS NULL
      OR LENGTH(IFNULL(p.BatchRunDate,''))!=8 OR SAFE.PARSE_DATE('%d%m%Y',p.BatchRunDate) IS NULL
      THEN 'HOLD_DATE_CONTRACT_INVALID'
    WHEN REGEXP_CONTAINS(TO_JSON_STRING(p),r':null|:"NULL"')
      OR NULLIF(TRIM(p.CompanyDB),'') IS NULL OR NULLIF(TRIM(p.OrderID),'') IS NULL
      OR NULLIF(TRIM(p.OrderItem),'') IS NULL OR NULLIF(TRIM(p.InvoiceNo),'') IS NULL
      OR NULLIF(TRIM(p.OrderDate),'') IS NULL OR NULLIF(TRIM(p.InsuredID),'') IS NULL
      OR NULLIF(TRIM(p.FirstName),'') IS NULL OR NULLIF(TRIM(p.InsurerCode),'') IS NULL
      OR NULLIF(TRIM(p.InsuranceGroup),'') IS NULL OR NULLIF(TRIM(p.InsuranceProduct),'') IS NULL
      OR NULLIF(TRIM(p.ProductType),'') IS NULL OR NULLIF(TRIM(p.PolicyType),'') IS NULL
      OR NULLIF(TRIM(p.PolicyDate),'') IS NULL OR NULLIF(TRIM(p.PolicyNo),'') IS NULL
      OR NULLIF(TRIM(p.ExpectedDate),'') IS NULL OR NULLIF(TRIM(p.BillingAddress),'') IS NULL
      OR NULLIF(TRIM(p.PaymentDate),'') IS NULL OR NULLIF(TRIM(p.PaymentMethod),'') IS NULL
      OR NULLIF(TRIM(p.PaymentChannel),'') IS NULL THEN 'HOLD_REQUIRED_VALUE_INVALID'
    WHEN NOT REGEXP_CONTAINS(ARRAY_TO_STRING([p.GrossPremium,p.StampDuty,p.VAT,p.TotalPremium,p.WHT,
      p.TotalEIR,p.TotalSBT,p.ProcessingFee,p.ProcessingFeeVat,p.ShippingFee,p.ShippingFeeVat,p.TotalAmount,
      p.Discount,p.ExpectedReceived,p.ActualReceived,p.InterestThisPeriod,p.PrincipleThisPeriod,
      p.InterestEIRThisPeriod,p.PrincipleEIRThisPeriod,p.PendingPayment,p.RefundAmountBeforeFee,
      p.RefundAmountAfterFee],'|'),r'^(-?[0-9]+\.[0-9]{2}\|){21}-?[0-9]+\.[0-9]{2}$')
      THEN 'HOLD_NUMERIC_CONTRACT_INVALID'
    WHEN TO_JSON_STRING([p.GrossPremium,p.StampDuty,p.VAT,p.TotalPremium,p.WHT,p.TotalEIR,
      p.TotalSBT,p.ProcessingFee,p.ProcessingFeeVat,p.ShippingFee,p.ShippingFeeVat,p.TotalAmount,
      p.Discount,p.ExpectedReceived,p.ActualReceived,p.InterestThisPeriod,p.PrincipleThisPeriod,
      p.InterestEIRThisPeriod,p.PrincipleEIRThisPeriod,p.PendingPayment,p.RefundAmountBeforeFee,
      p.RefundAmountAfterFee]) IS DISTINCT FROM TO_JSON_STRING([
      FORMAT('%.2f',SAFE_CAST(r.GrossPremium AS FLOAT64)),FORMAT('%.2f',SAFE_CAST(r.StampDuty AS FLOAT64)),
      FORMAT('%.2f',SAFE_CAST(r.VAT AS FLOAT64)),FORMAT('%.2f',SAFE_CAST(r.TotalPremium AS FLOAT64)),
      FORMAT('%.2f',SAFE_CAST(r.WHT AS FLOAT64)),FORMAT('%.2f',SAFE_CAST(r.TotalEIR AS FLOAT64)),
      FORMAT('%.2f',SAFE_CAST(r.TotalSBT AS FLOAT64)),FORMAT('%.2f',SAFE_CAST(r.ProcessingFee AS FLOAT64)),
      FORMAT('%.2f',SAFE_CAST(r.ProcessingFeeVat AS FLOAT64)),FORMAT('%.2f',SAFE_CAST(r.ShippingFee AS FLOAT64)),
      FORMAT('%.2f',SAFE_CAST(r.ShippingFeeVat AS FLOAT64)),FORMAT('%.2f',SAFE_CAST(r.TotalAmount AS FLOAT64)),
      FORMAT('%.2f',SAFE_CAST(r.Discount AS FLOAT64)),FORMAT('%.2f',SAFE_CAST(r.ExpectedReceived AS FLOAT64)),
      FORMAT('%.2f',SAFE_CAST(r.ActualReceived AS FLOAT64)),FORMAT('%.2f',SAFE_CAST(r.InterestThisPeriod AS FLOAT64)),
      FORMAT('%.2f',SAFE_CAST(r.PrincipleThisPeriod AS FLOAT64)),FORMAT('%.2f',SAFE_CAST(r.InterestEIRThisPeriod AS FLOAT64)),
      FORMAT('%.2f',SAFE_CAST(r.PrincipleEIRThisPeriod AS FLOAT64)),FORMAT('%.2f',SAFE_CAST(r.PendingPayment AS FLOAT64)),
      FORMAT('%.2f',SAFE_CAST(r.RefundAmountBeforeFee AS FLOAT64)),FORMAT('%.2f',SAFE_CAST(r.RefundAmountAfterFee AS FLOAT64))]))
      THEN 'HOLD_CANONICAL_NUMERIC_MISMATCH'
    ELSE 'READY' END validation_code
  FROM (SELECT x.*,ROW_NUMBER() OVER (
      PARTITION BY order_item,period,invoice_no ORDER BY charge_id) identity_row FROM _resolved x) r
  JOIN (SELECT x.*,ROW_NUMBER() OVER (
      PARTITION BY OrderItem,Period,InvoiceNo ORDER BY TO_JSON_STRING(x)) identity_row
    FROM `pacific-plating-282708.sap_integration_v3.v3_onetime_create_ready` x) p
    ON p.OrderItem=r.order_item AND p.Period=CAST(r.period AS STRING)
      AND p.InvoiceNo=r.invoice_no AND p.identity_row=r.identity_row;

  INSERT INTO `pacific-plating-282708.sap_integration_v3.v3_onetime_create_hold`
  SELECT pipeline_run_id,order_item,order_id,period,charge_id,invoice_no,validation_code,
    CONCAT('Scenario 1 held by ',validation_code),CURRENT_TIMESTAMP()
  FROM _payload_validation WHERE validation_code!='READY';
  DELETE FROM `pacific-plating-282708.sap_integration_v3.v3_onetime_create_ready` p
  WHERE EXISTS (SELECT 1 FROM _payload_validation v WHERE v.validation_code!='READY'
    AND v.order_item=p.OrderItem AND v.invoice_no=p.InvoiceNo);
  ASSERT (SELECT COUNT(*) FROM _target)=
    (SELECT COUNT(*) FROM `pacific-plating-282708.sap_integration_v3.v3_onetime_create_ready`)+
    (SELECT COUNTIF(validation_code!='READY') FROM _payload_validation)
    AS 'ONETIME CREATE target must end as payload or durable validation hold';
  ASSERT (SELECT COUNT(*) FROM `pacific-plating-282708.sap_integration_v3.v3_onetime_create_ready`
    WHERE Period!='1' OR TotalPeriods!='1' OR TransactionStatus!='Paid')=0
    AS 'ONETIME CREATE released rows must be Paid period 1/1';
  ASSERT (SELECT COUNT(*) FROM `pacific-plating-282708.sap_integration_v3.v3_onetime_create_ready`
    WHERE LENGTH(InvoiceNo)>30 OR LENGTH(PolicyNo)>50)=0 AS 'ONETIME CREATE length limit failed';
  ASSERT (SELECT COUNT(*) FROM (SELECT OrderItem,Period,InvoiceNo,COUNT(*) n
    FROM `pacific-plating-282708.sap_integration_v3.v3_onetime_create_ready`
    GROUP BY 1,2,3 HAVING n!=1))=0 AS 'ONETIME CREATE duplicate paid identity';
  ASSERT (SELECT COUNT(*) FROM (SELECT OrderItem,date_value
    FROM `pacific-plating-282708.sap_integration_v3.v3_onetime_create_ready`
    UNPIVOT(date_value FOR date_column IN (OrderDate,PolicyDate,ExpectedDate,PaymentDate,BatchRunDate))
    WHERE LENGTH(IFNULL(date_value,''))!=8 OR SAFE.PARSE_DATE('%d%m%Y',date_value) IS NULL))=0
    AS 'ONETIME CREATE date contract failed';

  DELETE FROM `pacific-plating-282708.sap_integration_v3.v3_unit5_payload_identity`
  WHERE pipeline_run_id=p_pipeline_run_id AND file_role='CREATE_ONETIME';
  INSERT INTO `pacific-plating-282708.sap_integration_v3.v3_unit5_payload_identity`
  SELECT p_pipeline_run_id,'CREATE_ONETIME',r.order_item,r.period,r.charge_id,r.invoice_no,
    TO_HEX(SHA256(TO_JSON_STRING(p))),CURRENT_TIMESTAMP()
  FROM _resolved r JOIN `pacific-plating-282708.sap_integration_v3.v3_onetime_create_ready` p
    ON p.OrderItem=r.order_item AND p.Period=CAST(r.period AS STRING) AND p.InvoiceNo=r.invoice_no;
  ASSERT (SELECT COUNT(*) FROM `pacific-plating-282708.sap_integration_v3.v3_unit5_payload_identity`
    WHERE pipeline_run_id=p_pipeline_run_id AND file_role='CREATE_ONETIME')=
    (SELECT COUNT(*) FROM `pacific-plating-282708.sap_integration_v3.v3_onetime_create_ready`)
    AS 'ONETIME CREATE identity conservation failed';

  CREATE OR REPLACE TABLE `pacific-plating-282708.sap_integration_v3.v3_onetime_create_identity` AS
  SELECT p_pipeline_run_id pipeline_run_id,r.order_item,r.period,r.charge_id,r.invoice_no,
    r.raw_payment_date source_payment_date,SAFE.PARSE_DATE('%d%m%Y',p.PaymentDate) effective_payment_date,
    SAFE.PARSE_DATE('%d%m%Y',p.PaymentDate)!=r.raw_payment_date payment_date_clamped,
    v_period_id period_id,v_period_state_version period_state_version,
    v_period_start period_start,v_period_end period_end,
    r.sap_payment_method,r.sap_payment_channel,r.resolved_insurance_group,
    TO_HEX(SHA256(TO_JSON_STRING(p))) payload_hash,CURRENT_TIMESTAMP() built_at
  FROM _resolved r JOIN `pacific-plating-282708.sap_integration_v3.v3_onetime_create_ready` p
    ON p.OrderItem=r.order_item AND p.InvoiceNo=r.invoice_no;
END;

-- SOURCE ONLY / Class A. Scenario 3: ordinary RCL later-period NEWPAYMENT split.
-- Run-bound target hashes and immutable spine snapshots prevent mutable Unit 5 table drift.
-- No archive, GCS, SAP, or scheduler mutation.

CREATE TABLE IF NOT EXISTS `pacific-plating-282708.sap_integration_v3.v3_rcl_later_newpayment_ready` AS
SELECT * FROM `pacific-plating-282708.sap_integration_v3.v3_unit5_newpayment_ready` WHERE FALSE;

CREATE TABLE IF NOT EXISTS `pacific-plating-282708.sap_integration_v3.v3_rcl_later_newpayment_hold` (
  pipeline_run_id STRING NOT NULL,order_item STRING,order_id STRING,period INT64,
  charge_id STRING,invoice_no STRING,hold_code STRING NOT NULL,hold_reason STRING NOT NULL,
  detected_at TIMESTAMP NOT NULL)
PARTITION BY DATE(detected_at) CLUSTER BY pipeline_run_id,hold_code,order_item;

CREATE TABLE IF NOT EXISTS `pacific-plating-282708.sap_integration_v3.v3_rcl_later_newpayment_spine_snapshot` (
  pipeline_run_id STRING NOT NULL,order_item STRING NOT NULL,period INT64 NOT NULL,
  invoice_no STRING,payload_hash STRING NOT NULL,payload_json STRING NOT NULL,
  snapshotted_at TIMESTAMP NOT NULL)
PARTITION BY DATE(snapshotted_at) CLUSTER BY pipeline_run_id,order_item,period;

CREATE TABLE IF NOT EXISTS `pacific-plating-282708.sap_integration_v3.v3_rcl_later_newpayment_summary` (
  pipeline_run_id STRING NOT NULL,input_event_rows INT64 NOT NULL,canonical_identity_rows INT64 NOT NULL,
  released_identity_rows INT64 NOT NULL,held_identity_rows INT64 NOT NULL,
  released_spine_rows INT64 NOT NULL,built_at TIMESTAMP NOT NULL)
PARTITION BY DATE(built_at) CLUSTER BY pipeline_run_id;

CREATE OR REPLACE PROCEDURE
  `pacific-plating-282708.sap_integration_v3.sp_build_v3_rcl_later_newpayment_split`(
    p_pipeline_run_id STRING)
BEGIN
  ASSERT NULLIF(TRIM(p_pipeline_run_id),'') IS NOT NULL AS 'Scenario 3 requires pipeline_run_id';
  ASSERT (SELECT COUNT(*) FROM `pacific-plating-282708.sap_integration_v3.pipeline_run_log`
    WHERE run_id=p_pipeline_run_id AND step='UNIT1_COMPLETE' AND status='SUCCESS')=1
    AS 'Scenario 3 requires exactly one successful Unit 1 row';
  ASSERT (SELECT COUNT(*) FROM `pacific-plating-282708.sap_integration_v3.v3_unit3_run_summary`
    WHERE pipeline_run_id=p_pipeline_run_id)=1 AS 'Scenario 3 requires Unit 3 evaluation';
  ASSERT (SELECT COUNT(*) FROM `pacific-plating-282708.sap_integration_v3.INFORMATION_SCHEMA.COLUMNS`
    WHERE table_name='v3_unit5_newpayment_ready')=56
    AS 'Scenario 3 requires reviewed 56-column Unit 5 result';

  CREATE TEMP TABLE _upstream AS
  SELECT * EXCEPT(pipeline_run_id,snapshotted_at)
  FROM `pacific-plating-282708.sap_integration_v3.v3_unit5_newpayment_run_snapshot`
  WHERE pipeline_run_id=p_pipeline_run_id;
  ASSERT (SELECT COUNT(*)
    FROM `pacific-plating-282708.sap_integration_v3.v3_unit5_newpayment_snapshot_manifest`
    WHERE pipeline_run_id=p_pipeline_run_id)=1
    AS 'Scenario 3 requires exactly one completed Unit 5 snapshot manifest';
  ASSERT (SELECT COUNT(*) FROM _upstream)=(SELECT row_count
    FROM `pacific-plating-282708.sap_integration_v3.v3_unit5_newpayment_snapshot_manifest`
    WHERE pipeline_run_id=p_pipeline_run_id)
    AS 'Scenario 3 snapshot rows differ from immutable manifest';
  ASSERT TO_HEX(SHA256(COALESCE((SELECT STRING_AGG(TO_HEX(SHA256(TO_JSON_STRING(p))),''
    ORDER BY p.OrderItem,SAFE_CAST(p.Period AS INT64),p.InvoiceNo,TO_JSON_STRING(p))
    FROM _upstream p),'<EMPTY>')))=(SELECT payload_set_hash
    FROM `pacific-plating-282708.sap_integration_v3.v3_unit5_newpayment_snapshot_manifest`
    WHERE pipeline_run_id=p_pipeline_run_id)
    AS 'Scenario 3 snapshot payload-set hash differs from immutable Unit 5 manifest';
  CREATE TEMP TABLE _event_raw AS
  SELECT e.pipeline_run_id,e.order_item,e.order_id,e.period,e.charge_id,e.invoice_no
  FROM `pacific-plating-282708.sap_integration_v3.v3_unit2_event_shadow` e
  WHERE e.pipeline_run_id=p_pipeline_run_id AND e.outcome='READY_CREATE_OR_PAYMENT' AND e.flow='RCL'
    AND EXISTS (SELECT 1 FROM `pacific-plating-282708.sap_integration_v3.sap_mirror_doc` m
      WHERE m.U_OrderItem=e.order_item);
  CREATE TEMP TABLE _event AS
  SELECT pipeline_run_id,order_item,period,charge_id,ANY_VALUE(order_id) order_id,
    ANY_VALUE(invoice_no) invoice_no,COUNT(*) event_rows,
    COUNT(DISTINCT IFNULL(order_id,'<NULL>')) order_id_values,
    COUNT(DISTINCT IFNULL(invoice_no,'<NULL>')) invoice_values
  FROM _event_raw GROUP BY pipeline_run_id,order_item,period,charge_id;

  CREATE TEMP TABLE _identity AS
  SELECT pipeline_run_id,order_item,period,charge_id,invoice_no,
    COUNT(*) identity_rows,ANY_VALUE(payload_hash) identity_payload_hash
  FROM `pacific-plating-282708.sap_integration_v3.v3_unit5_payload_identity`
  WHERE pipeline_run_id=p_pipeline_run_id AND file_role='NEWPAYMENT'
  GROUP BY pipeline_run_id,order_item,period,charge_id,invoice_no;

  CREATE TEMP TABLE _event_shape AS
  SELECT e.*,co.current_human_id IS NOT NULL is_credit_shell,
    (SELECT COUNT(*) FROM `pacific-plating-282708.sap_integration_v3.v3_unit3_mapping_hold` h
      WHERE h.pipeline_run_id=e.pipeline_run_id AND h.order_item=e.order_item
        AND h.period=e.period AND h.charge_id=e.charge_id) event_mapping_hold_rows,
    (SELECT COUNT(*) FROM `pacific-plating-282708.sap_integration_v3.v3_unit3_mapping_hold` h
      WHERE h.pipeline_run_id=e.pipeline_run_id AND h.order_item=e.order_item) item_mapping_hold_rows,
    (SELECT COUNT(*)
      FROM `pacific-plating-282708.sap_integration_v3.v3_unit5_installment_detail_hold` d
      WHERE d.pipeline_run_id=e.pipeline_run_id AND d.order_item=e.order_item) item_detail_hold_rows,
    (SELECT COUNT(*) FROM `pacific-plating-282708.sap_integration_v3.v3_unit5_balance_hold` b
      WHERE b.pipeline_run_id=e.pipeline_run_id AND b.order_item=e.order_item) item_balance_hold_rows,
    COALESCE(i.identity_rows,0) identity_rows,
    (SELECT COUNT(*) FROM _upstream p WHERE p.OrderItem=e.order_item
      AND SAFE_CAST(p.Period AS INT64)=e.period AND p.InvoiceNo=e.invoice_no) target_payload_rows,
    (SELECT COUNT(*) FROM _upstream p WHERE p.OrderItem=e.order_item
      AND SAFE_CAST(p.Period AS INT64)=e.period AND p.InvoiceNo=e.invoice_no
      AND TO_HEX(SHA256(TO_JSON_STRING(p)))=i.identity_payload_hash) hash_match_rows
  FROM _event e LEFT JOIN (SELECT DISTINCT current_human_id
    FROM `pacific-plating-282708.careos.cancelled_change_orders`) co ON co.current_human_id=e.order_id
  LEFT JOIN _identity i ON i.pipeline_run_id=e.pipeline_run_id AND i.order_item=e.order_item
    AND i.period=e.period AND i.charge_id=e.charge_id AND i.invoice_no=e.invoice_no;

  CREATE TEMP TABLE _preclassified AS
  SELECT *,CASE
    WHEN event_rows!=1 OR order_id_values!=1 OR invoice_values!=1
      THEN 'HOLD_DUPLICATE_OR_CONFLICTING_EVENT'
    WHEN period<=1 THEN 'HOLD_NOT_LATER_PAYMENT_PERIOD'
    WHEN is_credit_shell THEN 'HOLD_WRONG_SCENARIO_CREDITSHELL'
    WHEN event_mapping_hold_rows>0 THEN 'HOLD_UNIT3_MAPPING'
    WHEN item_mapping_hold_rows>0 THEN 'HOLD_ITEM_UNIT3_MAPPING'
    WHEN item_detail_hold_rows>0 THEN 'HOLD_EMPTY_INSTALLMENT_DETAILS'
    WHEN item_balance_hold_rows>0 THEN 'HOLD_UNIT5_BALANCE_QUARANTINE'
    WHEN identity_rows=0 THEN 'HOLD_MISSING_UNIT5_IDENTITY'
    WHEN identity_rows!=1 THEN 'HOLD_DUPLICATE_UNIT5_IDENTITY'
    WHEN target_payload_rows=0 THEN 'HOLD_MISSING_TARGET_PAYLOAD'
    WHEN target_payload_rows!=1 THEN 'HOLD_DUPLICATE_TARGET_PAYLOAD'
    WHEN hash_match_rows!=1 THEN 'HOLD_TARGET_PAYLOAD_HASH_DRIFT'
    ELSE 'PRELIMINARY_READY' END preliminary_code
  FROM _event_shape;

  CREATE TEMP TABLE _spine_shape AS
  SELECT p.OrderItem,COUNT(*) physical_rows,COUNT(DISTINCT SAFE_CAST(p.Period AS INT64)) period_n,
    MIN(SAFE_CAST(p.Period AS INT64)) min_period,MAX(SAFE_CAST(p.Period AS INT64)) max_period,
    MAX(SAFE_CAST(p.TotalPeriods AS INT64)) total_periods,
    COUNT(DISTINCT SAFE_CAST(p.TotalPeriods AS INT64)) total_variants,
    COUNTIF(p.TransactionStatus NOT IN ('Paid','Pending') OR p.TransactionStatus IS NULL) bad_status,
    COUNTIF(REGEXP_CONTAINS(TO_JSON_STRING(p),r':null|:"NULL"')
      OR NULLIF(TRIM(p.CompanyDB),'') IS NULL OR NULLIF(TRIM(p.OrderID),'') IS NULL
      OR NULLIF(TRIM(p.OrderItem),'') IS NULL OR NULLIF(TRIM(p.InsurerCode),'') IS NULL
      OR NULLIF(TRIM(p.FirstName),'') IS NULL OR NULLIF(TRIM(p.InsuranceGroup),'') IS NULL
      OR NULLIF(TRIM(p.InsuranceProduct),'') IS NULL OR NULLIF(TRIM(p.ProductType),'') IS NULL
      OR NULLIF(TRIM(p.PolicyType),'') IS NULL OR NULLIF(TRIM(p.PolicyDate),'') IS NULL
      OR NULLIF(TRIM(p.PolicyNo),'') IS NULL
      OR NULLIF(TRIM(p.ExpectedDate),'') IS NULL OR NULLIF(TRIM(p.BillingAddress),'') IS NULL
      OR (p.TransactionStatus='Paid' AND (NULLIF(TRIM(p.InvoiceNo),'') IS NULL
        OR NULLIF(TRIM(p.PaymentDate),'') IS NULL OR NULLIF(TRIM(p.PaymentMethod),'') IS NULL
        OR NULLIF(TRIM(p.PaymentChannel),'') IS NULL))) bad_required,
    COUNTIF(NOT REGEXP_CONTAINS(ARRAY_TO_STRING([p.GrossPremium,p.StampDuty,p.VAT,p.TotalPremium,
      p.WHT,p.TotalEIR,p.TotalSBT,p.ProcessingFee,p.ProcessingFeeVat,p.ShippingFee,p.ShippingFeeVat,
      p.TotalAmount,p.Discount,p.ExpectedReceived,p.ActualReceived,p.InterestThisPeriod,
      p.PrincipleThisPeriod,p.InterestEIRThisPeriod,p.PrincipleEIRThisPeriod,p.PendingPayment,
      p.RefundAmountBeforeFee,p.RefundAmountAfterFee],'|'),
      r'^(-?[0-9]+\.[0-9]{2}\|){21}-?[0-9]+\.[0-9]{2}$')) bad_numeric,
    COUNTIF(LENGTH(IFNULL(p.OrderDate,''))!=8 OR SAFE.PARSE_DATE('%d%m%Y',p.OrderDate) IS NULL
      OR LENGTH(IFNULL(p.PolicyDate,''))!=8 OR SAFE.PARSE_DATE('%d%m%Y',p.PolicyDate) IS NULL
      OR LENGTH(IFNULL(p.ExpectedDate,''))!=8 OR SAFE.PARSE_DATE('%d%m%Y',p.ExpectedDate) IS NULL
      OR LENGTH(IFNULL(p.BatchRunDate,''))!=8 OR SAFE.PARSE_DATE('%d%m%Y',p.BatchRunDate) IS NULL
      OR (p.PaymentDate!='' AND (LENGTH(p.PaymentDate)!=8
        OR SAFE.PARSE_DATE('%d%m%Y',p.PaymentDate) IS NULL))) bad_date,
    COUNTIF(LENGTH(p.PolicyNo)>50 OR LENGTH(p.InvoiceNo)>30 OR LENGTH(p.OrderItem)>30) bad_length
  FROM _upstream p WHERE EXISTS (SELECT 1 FROM _preclassified e
    WHERE e.preliminary_code='PRELIMINARY_READY' AND e.order_item=p.OrderItem)
  GROUP BY p.OrderItem;

  CREATE TEMP TABLE _item_gate AS
  SELECT order_item,COUNTIF(preliminary_code!='PRELIMINARY_READY') invalid_event_rows
  FROM _preclassified GROUP BY order_item;

  CREATE TEMP TABLE _classified AS
  SELECT e.*,CASE WHEN preliminary_code!='PRELIMINARY_READY' THEN preliminary_code
    WHEN g.invalid_event_rows>0 THEN 'HOLD_ITEM_SIBLING_EVENT_INVALID'
    WHEN s.OrderItem IS NULL THEN 'HOLD_MISSING_ITEM_SPINE'
    WHEN s.total_variants!=1 OR s.min_period!=1 OR s.max_period!=s.total_periods
      OR s.period_n!=s.total_periods OR s.physical_rows!=s.total_periods
      THEN 'HOLD_INCOMPLETE_OR_DUPLICATE_ITEM_SPINE'
    WHEN s.bad_status>0 THEN 'HOLD_SPINE_STATUS_INVALID'
    WHEN s.bad_required>0 THEN 'HOLD_SPINE_REQUIRED_VALUE_INVALID'
    WHEN s.bad_numeric>0 THEN 'HOLD_SPINE_NUMERIC_CONTRACT_INVALID'
    WHEN s.bad_date>0 THEN 'HOLD_SPINE_DATE_CONTRACT_INVALID'
    WHEN s.bad_length>0 THEN 'HOLD_SPINE_LENGTH_INVALID'
    ELSE 'READY' END readiness_code
  FROM _preclassified e JOIN _item_gate g USING(order_item)
  LEFT JOIN _spine_shape s ON s.OrderItem=e.order_item;

  ASSERT (SELECT COALESCE(SUM(event_rows),0) FROM _classified)=(SELECT COUNT(*) FROM _event_raw)
    AS 'Scenario 3 input event conservation failed';
  CREATE TEMP TABLE _target AS SELECT * FROM _classified WHERE readiness_code='READY';
  CREATE TEMP TABLE _candidate AS SELECT p.* FROM _upstream p
    WHERE EXISTS (SELECT 1 FROM _target t WHERE t.order_item=p.OrderItem);
  ASSERT (SELECT COUNT(*) FROM (
    SELECT ordinal_position,column_name,data_type
    FROM `pacific-plating-282708.sap_integration_v3.INFORMATION_SCHEMA.COLUMNS`
    WHERE table_name='v3_rcl_later_newpayment_ready'
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
    WHERE table_name='v3_rcl_later_newpayment_ready'))=0
    AS 'Scenario 3 published table differs from exact reviewed 56-column contract';
  ASSERT (SELECT COUNT(*) FROM (
    SELECT ordinal_position-1 ordinal_position,column_name,data_type
    FROM `pacific-plating-282708.sap_integration_v3.INFORMATION_SCHEMA.COLUMNS`
    WHERE table_name='v3_unit5_newpayment_run_snapshot' AND ordinal_position BETWEEN 2 AND 57
    EXCEPT DISTINCT
    SELECT ordinal_position,column_name,data_type
    FROM `pacific-plating-282708.sap_integration_v3.INFORMATION_SCHEMA.COLUMNS`
    WHERE table_name='v3_unit5_newpayment_delivery_ready'))=0
    AND (SELECT COUNT(*) FROM (
    SELECT ordinal_position,column_name,data_type
    FROM `pacific-plating-282708.sap_integration_v3.INFORMATION_SCHEMA.COLUMNS`
    WHERE table_name='v3_unit5_newpayment_delivery_ready'
    EXCEPT DISTINCT
    SELECT ordinal_position-1 ordinal_position,column_name,data_type
    FROM `pacific-plating-282708.sap_integration_v3.INFORMATION_SCHEMA.COLUMNS`
    WHERE table_name='v3_unit5_newpayment_run_snapshot' AND ordinal_position BETWEEN 2 AND 57))=0
    AS 'Unit 5 immutable snapshot payload differs from reviewed 56-column contract';
  ASSERT (SELECT COUNT(*)
    FROM `pacific-plating-282708.sap_integration_v3.v3_rcl_later_newpayment_summary`
    WHERE pipeline_run_id=p_pipeline_run_id)=0
    AS 'Scenario 3 immutable run summary already exists; refusing replay';
  CREATE TEMP TABLE _summary AS
  SELECT p_pipeline_run_id pipeline_run_id,(SELECT COUNT(*) FROM _event_raw) input_event_rows,
    (SELECT COUNT(*) FROM _classified) canonical_identity_rows,
    (SELECT COUNT(*) FROM _target) released_identity_rows,
    (SELECT COUNTIF(readiness_code!='READY') FROM _classified) held_identity_rows,
    (SELECT COUNT(*) FROM _candidate) released_spine_rows,CURRENT_TIMESTAMP() built_at;

  BEGIN TRANSACTION;
  MERGE `pacific-plating-282708.sap_integration_v3.v3_rcl_later_newpayment_summary` t
  USING _summary s ON t.pipeline_run_id=s.pipeline_run_id
  WHEN NOT MATCHED THEN INSERT ROW;
  ASSERT @@row_count=1 AS 'Scenario 3 immutable run summary claim failed';
  DELETE FROM `pacific-plating-282708.sap_integration_v3.v3_rcl_later_newpayment_ready` WHERE TRUE;
  INSERT INTO `pacific-plating-282708.sap_integration_v3.v3_rcl_later_newpayment_ready`
  SELECT * FROM _candidate;
  ASSERT @@row_count=(SELECT COUNT(*) FROM _candidate) AS 'Scenario 3 ready publication conservation failed';
  DELETE FROM `pacific-plating-282708.sap_integration_v3.v3_rcl_later_newpayment_hold`
  WHERE pipeline_run_id=p_pipeline_run_id;
  INSERT INTO `pacific-plating-282708.sap_integration_v3.v3_rcl_later_newpayment_hold`
  SELECT pipeline_run_id,order_item,order_id,period,charge_id,invoice_no,readiness_code,
    FORMAT('Scenario 3 held by %s; identities=%d payloads=%d hash_matches=%d',readiness_code,
      identity_rows,target_payload_rows,hash_match_rows),CURRENT_TIMESTAMP()
  FROM _classified WHERE readiness_code!='READY';
  ASSERT @@row_count=(SELECT COUNTIF(readiness_code!='READY') FROM _classified)
    AS 'Scenario 3 durable hold conservation failed';
  DELETE FROM `pacific-plating-282708.sap_integration_v3.v3_unit5_payload_identity`
  WHERE pipeline_run_id=p_pipeline_run_id AND file_role='NEWPAYMENT_RCL_LATER';
  INSERT INTO `pacific-plating-282708.sap_integration_v3.v3_unit5_payload_identity`
  SELECT i.pipeline_run_id,'NEWPAYMENT_RCL_LATER',i.order_item,i.period,i.charge_id,i.invoice_no,
    i.payload_hash,CURRENT_TIMESTAMP()
  FROM `pacific-plating-282708.sap_integration_v3.v3_unit5_payload_identity` i
  JOIN _target t ON t.pipeline_run_id=i.pipeline_run_id AND t.order_item=i.order_item
    AND t.period=i.period AND t.charge_id=i.charge_id AND t.invoice_no=i.invoice_no
  WHERE i.pipeline_run_id=p_pipeline_run_id AND i.file_role='NEWPAYMENT';
  ASSERT @@row_count=(SELECT COUNT(*) FROM _target) AS 'Scenario 3 released identity conservation failed';
  INSERT INTO `pacific-plating-282708.sap_integration_v3.v3_rcl_later_newpayment_spine_snapshot`
  SELECT p_pipeline_run_id,p.OrderItem,SAFE_CAST(p.Period AS INT64),p.InvoiceNo,
    TO_HEX(SHA256(TO_JSON_STRING(p))),TO_JSON_STRING(p),CURRENT_TIMESTAMP() FROM _candidate p;
  ASSERT @@row_count=(SELECT COUNT(*) FROM _candidate) AS 'Scenario 3 spine snapshot conservation failed';
  ASSERT (SELECT COUNT(*) FROM _classified)=(SELECT COUNT(*) FROM _target)+
    (SELECT COUNTIF(readiness_code!='READY') FROM _classified)
    AS 'Scenario 3 canonical identity must end released or durably held';
  COMMIT TRANSACTION;
END;

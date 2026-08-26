-- SOURCE ONLY / Class A. Scenario 2: RCL first-period CREATE fail-closed hold gate.
-- Current evidence approves no RCL CREATE InvoiceNo transformation. This procedure emits no
-- 56-column interface rows and makes no GCS/SAP/scheduler change.

CREATE TABLE IF NOT EXISTS
  `pacific-plating-282708.sap_integration_v3.v3_rcl_first_create_hold` (
    pipeline_run_id STRING NOT NULL,order_item STRING,order_id STRING,period INT64,
    charge_id STRING,raw_invoice_no STRING,staged_invoice_no STRING,event_invoice_no STRING,
    source_invoice_variants ARRAY<STRING>,period_source_rows INT64,exact_source_rows INT64,
    legacy_prefix_rows INT64,
    hold_code STRING NOT NULL,hold_reason STRING NOT NULL,detected_at TIMESTAMP NOT NULL
  )
PARTITION BY DATE(detected_at)
CLUSTER BY pipeline_run_id,hold_code,order_item;

CREATE TABLE IF NOT EXISTS
  `pacific-plating-282708.sap_integration_v3.v3_rcl_first_create_gate_summary` (
    pipeline_run_id STRING NOT NULL,input_event_rows INT64 NOT NULL,
    canonical_identity_rows INT64 NOT NULL,held_identity_rows INT64 NOT NULL,
    ready_identity_rows INT64 NOT NULL,gate_status STRING NOT NULL,built_at TIMESTAMP NOT NULL
  )
PARTITION BY DATE(built_at)
CLUSTER BY pipeline_run_id,gate_status;

CREATE OR REPLACE PROCEDURE
  `pacific-plating-282708.sap_integration_v3.sp_build_v3_rcl_first_create_hold_gate`(
    p_pipeline_run_id STRING)
BEGIN
  ASSERT NULLIF(TRIM(p_pipeline_run_id),'') IS NOT NULL AS 'Scenario 2 requires pipeline_run_id';
  ASSERT (SELECT COUNT(*) FROM `pacific-plating-282708.sap_integration_v3.pipeline_run_log`
    WHERE run_id=p_pipeline_run_id AND step='UNIT1_COMPLETE' AND status='SUCCESS')=1
    AS 'Scenario 2 requires exactly one successful Unit 1 row';
  ASSERT (SELECT COUNT(*) FROM `pacific-plating-282708.sap_integration_v3.v3_unit3_run_summary`
    WHERE pipeline_run_id=p_pipeline_run_id)=1 AS 'Scenario 2 requires Unit 3 evaluation';

  CREATE TEMP TABLE _event_raw AS
  SELECT e.pipeline_run_id,e.order_item,e.order_id,e.period,e.charge_id,e.invoice_no
  FROM `pacific-plating-282708.sap_integration_v3.v3_unit2_event_shadow` e
  WHERE e.pipeline_run_id=p_pipeline_run_id AND e.outcome='READY_CREATE_OR_PAYMENT'
    AND e.flow='RCL'
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

  CREATE TEMP TABLE _raw_shape AS
  SELECT e.*,COUNT(c.id) raw_rows,ANY_VALUE(c.third_party_id) raw_invoice_no
  FROM _event e LEFT JOIN `pacific-plating-282708.careos.carepay_charges` c ON c.id=e.charge_id
  GROUP BY e.pipeline_run_id,e.order_item,e.order_id,e.period,e.charge_id,e.invoice_no,
    e.event_rows,e.order_id_values,e.invoice_values;
  CREATE TEMP TABLE _identity AS
  SELECT e.*,COUNT(s.charge_id) staged_rows,ANY_VALUE(s.third_party_id) staged_invoice_no
  FROM _raw_shape e LEFT JOIN `pacific-plating-282708.sap_integration_v3.stg_payment_events` s
    ON s.charge_id=e.charge_id
  GROUP BY e.pipeline_run_id,e.order_item,e.order_id,e.period,e.charge_id,e.invoice_no,
    e.event_rows,e.order_id_values,e.invoice_values,e.raw_rows,e.raw_invoice_no;

  CREATE TEMP TABLE _shape AS
  SELECT i.*,COUNT(src.OrderItem) period_source_rows,
    COUNTIF(src.InvoiceNo=i.invoice_no) exact_source_rows,
    COUNTIF(src.InvoiceNo=CONCAT('2_',i.invoice_no)) legacy_prefix_rows,
    ARRAY_AGG(DISTINCT src.InvoiceNo IGNORE NULLS ORDER BY src.InvoiceNo) source_invoice_variants
  FROM _identity i
  LEFT JOIN `pacific-plating-282708.sap_data_engineer.sap_dashboard_carepay_installment` src
    ON src.OrderItem=i.order_item AND SAFE_CAST(src.Period AS INT64)=i.period
  GROUP BY i.pipeline_run_id,i.order_item,i.order_id,i.period,i.charge_id,i.invoice_no,
    i.event_rows,i.order_id_values,i.invoice_values,i.raw_rows,i.raw_invoice_no,
    i.staged_rows,i.staged_invoice_no;

  CREATE TEMP TABLE _classified AS
  SELECT s.*,co.current_human_id IS NOT NULL is_credit_shell,CASE
    WHEN event_rows!=1 OR order_id_values!=1 OR invoice_values!=1
      THEN 'HOLD_DUPLICATE_OR_CONFLICTING_EVENT'
    WHEN raw_rows!=1 THEN IF(raw_rows=0,'HOLD_MISSING_RAW_CHARGE','HOLD_DUPLICATE_RAW_CHARGE')
    WHEN staged_rows!=1 THEN IF(staged_rows=0,'HOLD_MISSING_STAGED_EVENT','HOLD_DUPLICATE_STAGED_EVENT')
    WHEN period!=1 THEN 'HOLD_RCL_CREATE_PAYMENT_NOT_PERIOD_ONE'
    WHEN NULLIF(TRIM(order_item),'') IS NULL THEN 'HOLD_BLANK_ORDER_ITEM'
    WHEN NULLIF(TRIM(raw_invoice_no),'') IS NULL THEN 'HOLD_BLANK_RAW_INVOICE'
    WHEN NOT (staged_invoice_no IS NOT DISTINCT FROM raw_invoice_no) THEN 'HOLD_STAGE_IDENTITY_DRIFT'
    WHEN NOT (invoice_no IS NOT DISTINCT FROM staged_invoice_no) THEN 'HOLD_EVENT_IDENTITY_DRIFT'
    WHEN co.current_human_id IS NOT NULL THEN 'HOLD_WRONG_SCENARIO_CREDITSHELL'
    WHEN period_source_rows=0 THEN 'HOLD_MISSING_PERIOD_SOURCE'
    WHEN exact_source_rows=1 THEN 'HOLD_RCL_UNREVIEWED_EXACT_SOURCE_VARIANT'
    WHEN exact_source_rows>1 THEN 'HOLD_RCL_AMBIGUOUS_EXACT_SOURCE_VARIANT'
    WHEN legacy_prefix_rows=1 AND period_source_rows=1 THEN 'HOLD_RCL_LEGACY_PREFIX_REQUIRES_REVIEW'
    WHEN legacy_prefix_rows>0 THEN 'HOLD_RCL_AMBIGUOUS_PERIOD_SOURCE'
    ELSE 'HOLD_RCL_INVOICE_MISMATCH' END hold_code
  FROM _shape s LEFT JOIN (SELECT DISTINCT current_human_id
    FROM `pacific-plating-282708.careos.cancelled_change_orders`) co
    ON co.current_human_id=s.order_id;

  ASSERT (SELECT COALESCE(SUM(event_rows),0) FROM _classified)=(SELECT COUNT(*) FROM _event_raw)
    AS 'Scenario 2 input event conservation failed';
  ASSERT (SELECT COUNT(*) FROM _classified WHERE hold_code IS NULL)=0
    AS 'Scenario 2 unclassified identity would escape the hold gate';

  BEGIN TRANSACTION;
  DELETE FROM `pacific-plating-282708.sap_integration_v3.v3_rcl_first_create_hold`
  WHERE pipeline_run_id=p_pipeline_run_id;
  INSERT INTO `pacific-plating-282708.sap_integration_v3.v3_rcl_first_create_hold`
  SELECT pipeline_run_id,order_item,order_id,period,charge_id,raw_invoice_no,staged_invoice_no,
    invoice_no,source_invoice_variants,period_source_rows,exact_source_rows,legacy_prefix_rows,
    hold_code,FORMAT('Scenario 2 held by %s; source=%d exact=%d legacy=%d',hold_code,
      period_source_rows,exact_source_rows,legacy_prefix_rows),CURRENT_TIMESTAMP()
  FROM _classified;
  ASSERT @@row_count=(SELECT COUNT(*) FROM _classified)
    AS 'Scenario 2 durable hold conservation failed';

  DELETE FROM `pacific-plating-282708.sap_integration_v3.v3_rcl_first_create_gate_summary`
  WHERE pipeline_run_id=p_pipeline_run_id;
  INSERT INTO `pacific-plating-282708.sap_integration_v3.v3_rcl_first_create_gate_summary`
  SELECT p_pipeline_run_id,(SELECT COUNT(*) FROM _event_raw),(SELECT COUNT(*) FROM _classified),
    (SELECT COUNT(*) FROM _classified),0,'BLOCKED_NO_APPROVED_INVOICE_MAPPING',CURRENT_TIMESTAMP();
  COMMIT TRANSACTION;
END;

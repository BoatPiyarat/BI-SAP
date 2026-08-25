-- Read-only, fail-closed operator report for V3 CREATE candidates absent from SAP.
-- This is not a 56-column interface contract and emits no interface rows.
CREATE TEMP TABLE create_readiness AS
WITH latest_run AS (
  SELECT run_id, MAX(ended_at) AS unit5_completed_at
  FROM `pacific-plating-282708.sap_integration_v3.pipeline_run_log`
  WHERE run_type = 'NIGHTLY' AND step = 'UNITS_2_5_ARCHIVE' AND status = 'SUCCESS'
  GROUP BY run_id
  QUALIFY ROW_NUMBER() OVER (ORDER BY unit5_completed_at DESC, run_id DESC) = 1
),
candidate_event_raw AS (
  SELECT e.pipeline_run_id,e.order_item,e.order_id,e.period,e.charge_id,e.flow,
    e.invoice_no AS event_invoice_no
  FROM `pacific-plating-282708.sap_integration_v3.v3_unit2_event_shadow` e
  JOIN latest_run r ON r.run_id=e.pipeline_run_id
  WHERE e.outcome='READY_CREATE_OR_PAYMENT'
    AND NOT EXISTS (SELECT 1
      FROM `pacific-plating-282708.sap_integration_v3.sap_mirror_doc` m
      WHERE m.U_OrderItem=e.order_item)
    AND NOT EXISTS (SELECT 1
      FROM `pacific-plating-282708.sap_integration_v3.v3_unit3_mapping_hold` h
      WHERE h.pipeline_run_id=e.pipeline_run_id AND h.order_item=e.order_item
        AND h.period=e.period AND h.charge_id=e.charge_id)
),
candidate_event AS (
  SELECT pipeline_run_id,order_item,period,charge_id,
    ANY_VALUE(order_id) AS order_id,
    ANY_VALUE(flow) AS flow,
    ANY_VALUE(event_invoice_no) AS event_invoice_no,
    COUNT(*) AS candidate_event_rows,
    COUNT(DISTINCT IFNULL(order_id,'<NULL>')) AS order_id_value_count,
    COUNT(DISTINCT IFNULL(flow,'<NULL>')) AS flow_value_count,
    COUNT(DISTINCT IFNULL(event_invoice_no,'<NULL>')) AS invoice_value_count
  FROM candidate_event_raw
  GROUP BY pipeline_run_id,order_item,period,charge_id
),
raw_shape AS (
  SELECT e.*,COUNT(c.id) AS raw_charge_rows,ANY_VALUE(c.third_party_id) AS raw_third_party_id
  FROM candidate_event e
  LEFT JOIN `pacific-plating-282708.careos.carepay_charges` c ON c.id=e.charge_id
  GROUP BY e.pipeline_run_id,e.order_item,e.order_id,e.period,e.charge_id,e.flow,e.event_invoice_no,
    e.candidate_event_rows,e.order_id_value_count,e.flow_value_count,e.invoice_value_count
),
identity_shape AS (
  SELECT e.*,COUNT(s.charge_id) AS staged_event_rows,
    ANY_VALUE(s.third_party_id) AS staged_third_party_id
  FROM raw_shape e
  LEFT JOIN `pacific-plating-282708.sap_integration_v3.stg_payment_events` s
    ON s.charge_id=e.charge_id
  GROUP BY e.pipeline_run_id,e.order_item,e.order_id,e.period,e.charge_id,e.flow,
    e.event_invoice_no,e.candidate_event_rows,e.order_id_value_count,e.flow_value_count,
    e.invoice_value_count,e.raw_charge_rows,e.raw_third_party_id
),
onetime_source_shape AS (
  SELECT c.*,COUNT(o.OrderItem) AS period_source_rows,
    COUNTIF(o.InvoiceNo=c.event_invoice_no) AS exact_source_rows,
    0 AS legacy_2_prefix_rows
  FROM identity_shape c
  LEFT JOIN `pacific-plating-282708.sap_integration_v3.vw_onetime_payload_source` o
    ON o.OrderItem=c.order_item AND SAFE_CAST(o.Period AS INT64)=c.period
  WHERE c.flow='ONETIME'
  GROUP BY c.pipeline_run_id,c.order_item,c.order_id,c.period,c.charge_id,c.flow,
    c.event_invoice_no,c.candidate_event_rows,c.order_id_value_count,c.flow_value_count,
    c.invoice_value_count,c.raw_charge_rows,c.raw_third_party_id,c.staged_event_rows,
    c.staged_third_party_id
),
rcl_source_shape AS (
  SELECT c.*,COUNT(i.OrderItem) AS period_source_rows,
    COUNTIF(i.InvoiceNo=c.event_invoice_no) AS exact_source_rows,
    COUNTIF(i.InvoiceNo=CONCAT('2_',c.event_invoice_no)) AS legacy_2_prefix_rows
  FROM identity_shape c
  LEFT JOIN `pacific-plating-282708.sap_data_engineer.sap_dashboard_carepay_installment` i
    ON i.OrderItem=c.order_item AND SAFE_CAST(i.Period AS INT64)=c.period
  WHERE c.flow='RCL'
  GROUP BY c.pipeline_run_id,c.order_item,c.order_id,c.period,c.charge_id,c.flow,
    c.event_invoice_no,c.candidate_event_rows,c.order_id_value_count,c.flow_value_count,
    c.invoice_value_count,c.raw_charge_rows,c.raw_third_party_id,c.staged_event_rows,
    c.staged_third_party_id
),
unsupported_source_shape AS (
  SELECT c.*,0 AS period_source_rows,0 AS exact_source_rows,0 AS legacy_2_prefix_rows
  FROM identity_shape c
  WHERE c.flow IS NULL OR c.flow NOT IN ('ONETIME','RCL')
),
source_shape AS (
  SELECT * FROM onetime_source_shape
  UNION ALL
  SELECT * FROM rcl_source_shape
  UNION ALL
  SELECT * FROM unsupported_source_shape
)
SELECT *,CASE
  WHEN candidate_event_rows!=1 OR order_id_value_count!=1 OR flow_value_count!=1
    OR invoice_value_count!=1 THEN 'HOLD_DUPLICATE_OR_CONFLICTING_CANDIDATE_EVENT'
  WHEN raw_charge_rows=0 THEN 'HOLD_MISSING_RAW_CHARGE'
  WHEN raw_charge_rows!=1 THEN 'HOLD_DUPLICATE_RAW_CHARGE'
  WHEN staged_event_rows=0 THEN 'HOLD_MISSING_STAGED_EVENT'
  WHEN staged_event_rows!=1 THEN 'HOLD_DUPLICATE_STAGED_EVENT'
  WHEN NULLIF(TRIM(order_item),'') IS NULL THEN 'HOLD_BLANK_ORDER_ITEM'
  WHEN NULLIF(TRIM(charge_id),'') IS NULL THEN 'HOLD_BLANK_CHARGE_ID'
  WHEN NULLIF(TRIM(staged_third_party_id),'') IS NULL THEN 'HOLD_BLANK_STAGED_IDENTITY'
  WHEN NULLIF(TRIM(event_invoice_no),'') IS NULL THEN 'HOLD_BLANK_EVENT_INVOICE'
  WHEN NULLIF(TRIM(flow),'') IS NULL OR flow NOT IN ('ONETIME','RCL') THEN 'HOLD_UNSUPPORTED_FLOW'
  WHEN NOT (staged_third_party_id IS NOT DISTINCT FROM COALESCE(raw_third_party_id,order_item))
    THEN 'HOLD_STAGE_IDENTITY_DRIFT'
  WHEN NOT (event_invoice_no IS NOT DISTINCT FROM staged_third_party_id)
    THEN 'HOLD_EVENT_IDENTITY_DRIFT'
  WHEN period_source_rows=0 THEN 'HOLD_MISSING_PERIOD_SOURCE'
  WHEN flow='ONETIME' AND raw_third_party_id IS NULL THEN 'HOLD_NULL_RAW_ID_FALLBACK_CONFLICT'
  WHEN flow='ONETIME' AND exact_source_rows=1 AND period_source_rows=1
    THEN 'READY_ONETIME_SOURCE_CONSERVED'
  WHEN flow='ONETIME' AND exact_source_rows=0 THEN 'HOLD_ONETIME_INVOICE_MISMATCH'
  WHEN flow='ONETIME' THEN 'HOLD_ONETIME_AMBIGUOUS_SOURCE'
  WHEN flow='RCL' AND legacy_2_prefix_rows=1 AND period_source_rows=1
    THEN 'HOLD_RCL_LEGACY_PREFIX_REQUIRES_REVIEW'
  WHEN flow='RCL' AND legacy_2_prefix_rows>0 THEN 'HOLD_RCL_AMBIGUOUS_PERIOD_SOURCE'
  ELSE 'HOLD_RCL_INVOICE_MISMATCH' END AS readiness_code
FROM source_shape;

SELECT pipeline_run_id,flow,readiness_code,SUM(candidate_event_rows) AS input_row_count,
  COUNT(*) AS canonical_identity_count,
  COUNT(DISTINCT order_item) AS nonnull_item_count,
  COUNTIF(order_item IS NULL) AS null_item_count
FROM create_readiness
GROUP BY pipeline_run_id,flow,readiness_code
ORDER BY flow,readiness_code;

SELECT pipeline_run_id,flow,readiness_code,order_item,order_id,period,charge_id,
  candidate_event_rows,order_id_value_count,flow_value_count,invoice_value_count,
  raw_charge_rows,raw_third_party_id,staged_event_rows,
  staged_third_party_id,event_invoice_no,
  period_source_rows,exact_source_rows,legacy_2_prefix_rows
FROM create_readiness
ORDER BY flow,readiness_code,order_item,period,charge_id;

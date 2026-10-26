DECLARE target_run_id STRING DEFAULT 'V3NIGHTLY-2026-08-26T13:23:38-e830fff2';

SELECT h.hold_code,h.source_insurance_group,h.product_scope,h.is_credit_shell,
  h.payment_source_type,h.payment_method_source,h.payment_channel_source,
  COUNT(*) AS hold_rows,COUNT(DISTINCT h.charge_id) AS charges,
  MIN(h.raw_payment_date) AS first_payment_date,MAX(h.raw_payment_date) AS last_payment_date
FROM `pacific-plating-282708.sap_integration_v3.v3_unit3_mapping_hold` h
JOIN `pacific-plating-282708.sap_integration_v3.v3_onetime_create_hold` s
  ON s.pipeline_run_id=h.pipeline_run_id AND s.order_item=h.order_item
  AND s.period=h.period AND s.charge_id=h.charge_id
WHERE h.pipeline_run_id=target_run_id AND h.flow='ONETIME'
  AND s.hold_code='HOLD_UNIT3_MAPPING'
GROUP BY h.hold_code,h.source_insurance_group,h.product_scope,h.is_credit_shell,
  h.payment_source_type,h.payment_method_source,h.payment_channel_source
ORDER BY charges DESC,h.hold_code;

SELECT
  COUNT(*) AS null_raw_id_holds,
  COUNTIF(s.third_party_id IS NULL) AS staged_id_null,
  COUNTIF(s.third_party_id=CAST(h.order_item AS STRING)) AS staged_id_equals_order_item,
  COUNTIF(h.invoice_no=s.third_party_id) AS invoice_equals_staged_id,
  COUNT(DISTINCT h.order_item) AS order_items,
  COUNT(DISTINCT h.charge_id) AS charges
FROM `pacific-plating-282708.sap_integration_v3.v3_onetime_create_hold` h
LEFT JOIN `pacific-plating-282708.sap_integration_v3.stg_payment_events` s
  ON s.charge_id=h.charge_id
WHERE h.pipeline_run_id=target_run_id
  AND h.hold_code='HOLD_NULL_RAW_ID_FALLBACK_CONFLICT';

SELECT r.approval_state,r.flow,r.product_scope,r.is_credit_shell,
  r.payment_source_type,r.payment_method_source,r.payment_channel_source,
  r.sap_payment_method,r.sap_payment_channel,
  r.effective_start,r.effective_end,r.evidence_type,r.evidence_reference,
  r.approved_by,r.approved_at
FROM `pacific-plating-282708.sap_integration_v3.payment_mapping_registry` r
WHERE EXISTS (
  SELECT 1
  FROM `pacific-plating-282708.sap_integration_v3.v3_unit3_mapping_hold` h
  JOIN `pacific-plating-282708.sap_integration_v3.v3_onetime_create_hold` s
    ON s.pipeline_run_id=h.pipeline_run_id AND s.order_item=h.order_item
    AND s.period=h.period AND s.charge_id=h.charge_id
  WHERE h.pipeline_run_id=target_run_id AND h.flow='ONETIME'
    AND s.hold_code='HOLD_UNIT3_MAPPING'
    AND r.flow=h.flow AND r.product_scope=h.product_scope
    AND r.is_credit_shell=h.is_credit_shell
    AND r.payment_source_type=IFNULL(h.payment_source_type,'')
    AND r.payment_method_source=IFNULL(h.payment_method_source,'')
    AND r.payment_channel_source=IFNULL(h.payment_channel_source,'')
)
ORDER BY r.approval_state,r.is_credit_shell,r.payment_method_source,r.payment_channel_source;

SELECT hold_reason,COUNT(*) AS held_rows
FROM `pacific-plating-282708.sap_integration_v3.v3_onetime_create_hold`
WHERE pipeline_run_id=target_run_id AND hold_code='HOLD_REQUIRED_VALUE_INVALID'
GROUP BY hold_reason
ORDER BY held_rows DESC,hold_reason;

WITH held_source AS (
  SELECT h.order_item,h.period,h.invoice_no,o.* EXCEPT(OrderItem,Period,InvoiceNo)
  FROM `pacific-plating-282708.sap_integration_v3.v3_onetime_create_hold` h
  JOIN `pacific-plating-282708.sap_integration_v3.vw_onetime_payload_source` o
    ON o.OrderItem=h.order_item AND SAFE_CAST(o.Period AS INT64)=h.period
    AND o.InvoiceNo=h.invoice_no
  WHERE h.pipeline_run_id=target_run_id AND h.hold_code='HOLD_REQUIRED_VALUE_INVALID'
), missing AS (
  SELECT order_item,field_name,field_value
  FROM held_source,
  UNNEST([
    STRUCT('CompanyDB' AS field_name,CAST(CompanyDB AS STRING) AS field_value),
    STRUCT('OrderID',CAST(OrderID AS STRING)),STRUCT('OrderItem',CAST(order_item AS STRING)),
    STRUCT('InvoiceNo',CAST(invoice_no AS STRING)),STRUCT('OrderDate',CAST(OrderDate AS STRING)),
    STRUCT('FirstName',CAST(FirstName AS STRING)),STRUCT('InsurerCode',CAST(InsurerCode AS STRING)),
    STRUCT('InsuranceGroup',CAST(InsuranceGroup AS STRING)),
    STRUCT('InsuranceProduct',CAST(InsuranceProduct AS STRING)),
    STRUCT('ProductType',CAST(ProductType AS STRING)),STRUCT('PolicyType',CAST(PolicyType AS STRING)),
    STRUCT('PolicyDate',CAST(PolicyDate AS STRING)),STRUCT('PolicyNo',CAST(PolicyNo AS STRING)),
    STRUCT('ExpectedDate',CAST(ExpectedDate AS STRING)),
    STRUCT('BillingAddress',CAST(BillingAddress AS STRING))
  ])
)
SELECT field_name,COUNTIF(NULLIF(TRIM(field_value),'') IS NULL) AS missing_rows
FROM missing
GROUP BY field_name
HAVING missing_rows>0
ORDER BY missing_rows DESC,field_name;

WITH held_source AS (
  SELECT TO_JSON_STRING(o) AS payload_source_json
  FROM `pacific-plating-282708.sap_integration_v3.v3_onetime_create_hold` h
  JOIN `pacific-plating-282708.sap_integration_v3.vw_onetime_payload_source` o
    ON o.OrderItem=h.order_item AND SAFE_CAST(o.Period AS INT64)=h.period
    AND o.InvoiceNo=h.invoice_no
  WHERE h.pipeline_run_id=target_run_id AND h.hold_code='HOLD_REQUIRED_VALUE_INVALID'
)
SELECT null_field,COUNT(*) AS affected_rows
FROM held_source,UNNEST(REGEXP_EXTRACT_ALL(payload_source_json,r'"([^"]+)":null')) AS null_field
GROUP BY null_field
ORDER BY affected_rows DESC,null_field;

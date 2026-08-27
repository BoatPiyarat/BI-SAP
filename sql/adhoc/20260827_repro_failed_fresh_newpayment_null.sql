-- READ ONLY. Deterministic repro/minimizer for the failed delivery-disabled fresh Units 1-5 run.
-- It returns field names and hashed event keys only; no customer values or production writes.
-- Red signal: candidate_failure_occurrences > 0 for the exact failed pipeline run.

DECLARE v_run_id STRING DEFAULT 'V3NIGHTLY-2026-08-27T15:26:08-01480a29';

WITH target AS (
  SELECT e.order_item,e.period,e.invoice_no,e.flow,e.charge_id
  FROM `pacific-plating-282708.sap_integration_v3.v3_unit2_event_shadow` e
  WHERE e.pipeline_run_id=v_run_id
    AND e.outcome='READY_CREATE_OR_PAYMENT'
    AND EXISTS (
      SELECT 1 FROM `pacific-plating-282708.sap_integration_v3.sap_mirror_doc` m
      WHERE m.U_OrderItem=e.order_item)
    AND NOT EXISTS (
      SELECT 1 FROM `pacific-plating-282708.sap_integration_v3.v3_unit3_mapping_hold` h
      WHERE h.pipeline_run_id=e.pipeline_run_id AND h.order_item=e.order_item
        AND h.period=e.period AND h.charge_id=e.charge_id)
    AND NOT EXISTS (
      SELECT 1
      FROM `pacific-plating-282708.sap_integration_v3.vw_v3_rcl_empty_installment_detail_hold` d
      WHERE d.order_item=e.order_item)
), target_orders AS (
  SELECT DISTINCT order_item,flow FROM target
), source_rows AS (
  SELECT 'ONETIME' AS source_role,CAST(s.OrderItem AS STRING) AS order_item,
    SAFE_CAST(s.Period AS INT64) AS period,CAST(s.InvoiceNo AS STRING) AS invoice_no,
    TO_JSON_STRING(s) AS source_json
  FROM `pacific-plating-282708.sap_integration_v3.vw_onetime_payload_source` s
  WHERE EXISTS (
    SELECT 1 FROM target_orders t WHERE t.order_item=s.OrderItem AND t.flow='ONETIME')
  UNION ALL
  SELECT 'INSTALLMENT',CAST(s.OrderItem AS STRING),SAFE_CAST(s.Period AS INT64),
    CAST(s.InvoiceNo AS STRING),TO_JSON_STRING(s)
  FROM `pacific-plating-282708.sap_data_engineer.sap_dashboard_carepay_installment` s
  WHERE EXISTS (
    SELECT 1 FROM target_orders t WHERE t.order_item=s.OrderItem AND t.flow!='ONETIME')
), source_occurrences AS (
  SELECT source_role,order_item,period,'SQL_NULL' AS null_kind,field_name
  FROM source_rows,
  UNNEST(REGEXP_EXTRACT_ALL(source_json,r'"([^"]+)":null')) AS field_name
  UNION ALL
  SELECT source_role,order_item,period,'LITERAL_NULL',field_name
  FROM source_rows,
  UNNEST(REGEXP_EXTRACT_ALL(source_json,r'"([^"]+)":"NULL"')) AS field_name
), numeric_occurrences AS (
  SELECT source_role,order_item,period,'INVALID_NUMERIC' AS null_kind,n.field_name
  FROM source_rows,
  UNNEST([
    STRUCT('GrossPremium' AS field_name,JSON_VALUE(source_json,'$.GrossPremium') AS value),
    ('StampDuty',JSON_VALUE(source_json,'$.StampDuty')),
    ('VAT',JSON_VALUE(source_json,'$.VAT')),
    ('TotalPremium',JSON_VALUE(source_json,'$.TotalPremium')),
    ('WHT',JSON_VALUE(source_json,'$.WHT')),
    ('TotalEIR',JSON_VALUE(source_json,'$.TotalEIR')),
    ('TotalSBT',JSON_VALUE(source_json,'$.TotalSBT')),
    ('ProcessingFee',JSON_VALUE(source_json,'$.ProcessingFee')),
    ('ProcessingFeeVat',JSON_VALUE(source_json,'$.ProcessingFeeVat')),
    ('ShippingFee',JSON_VALUE(source_json,'$.ShippingFee')),
    ('ShippingFeeVat',JSON_VALUE(source_json,'$.ShippingFeeVat')),
    ('TotalAmount',JSON_VALUE(source_json,'$.TotalAmount')),
    ('Discount',JSON_VALUE(source_json,'$.Discount')),
    ('ExpectedReceived',JSON_VALUE(source_json,'$.ExpectedReceived')),
    ('ActualReceived',JSON_VALUE(source_json,'$.ActualReceived')),
    ('InterestThisPeriod',JSON_VALUE(source_json,'$.InterestThisPeriod')),
    ('PrincipleThisPeriod',JSON_VALUE(source_json,'$.PrincipleThisPeriod')),
    ('InterestEIRThisPeriod',JSON_VALUE(source_json,'$.InterestEIRThisPeriod')),
    ('PrincipleEIRThisPeriod',JSON_VALUE(source_json,'$.PrincipleEIRThisPeriod')),
    ('RefundAmountBeforeFee',JSON_VALUE(source_json,'$.RefundAmountBeforeFee')),
    ('RefundAmountAfterFee',JSON_VALUE(source_json,'$.RefundAmountAfterFee'))
  ]) n
  WHERE n.value IS NOT NULL AND SAFE_CAST(n.value AS FLOAT64) IS NULL
), occurrences AS (
  SELECT * FROM source_occurrences
  UNION ALL
  SELECT * FROM numeric_occurrences
), classified AS (
  SELECT o.*,
    -- These seven SQL NULLs are explicitly normalized by both candidate branches in DDL 058.
    -- Literal "NULL" is never normalized and remains a failure.
    NOT (null_kind='SQL_NULL' AND field_name IN (
      'InvoiceNo','InsuredID','EndorsementNo','PaymentDate','PaymentMethod','PaymentChannel','RefOrder'))
      AS is_candidate_failure,
    TO_HEX(SHA256(CONCAT(IFNULL(order_item,'<NULL>'),'|',IFNULL(CAST(period AS STRING),'<NULL>'))))
      AS hashed_row_key
  FROM occurrences o
)
SELECT source_role,null_kind,field_name,
  COUNTIF(is_candidate_failure) AS candidate_failure_occurrences,
  COUNT(DISTINCT IF(is_candidate_failure,hashed_row_key,NULL)) AS affected_hashed_rows,
  ARRAY_AGG(DISTINCT IF(is_candidate_failure,hashed_row_key,NULL) IGNORE NULLS LIMIT 10)
    AS sample_hashed_row_keys,
  IF(COUNTIF(is_candidate_failure)>0,'RED_REPRODUCED','GREEN') AS repro_status
FROM classified
GROUP BY source_role,null_kind,field_name
HAVING candidate_failure_occurrences>0
ORDER BY candidate_failure_occurrences DESC,source_role,null_kind,field_name;

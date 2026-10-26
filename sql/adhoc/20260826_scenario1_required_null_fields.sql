WITH held_source AS (
  SELECT TO_JSON_STRING(o) AS payload_source_json
  FROM `pacific-plating-282708.sap_integration_v3.v3_onetime_create_hold` h
  JOIN `pacific-plating-282708.sap_integration_v3.vw_onetime_payload_source` o
    ON o.OrderItem=h.order_item AND SAFE_CAST(o.Period AS INT64)=h.period
    AND o.InvoiceNo=h.invoice_no
  WHERE h.pipeline_run_id='V3NIGHTLY-2026-08-26T13:23:38-e830fff2'
    AND h.hold_code='HOLD_REQUIRED_VALUE_INVALID'
)
SELECT null_field,COUNT(*) AS affected_rows
FROM held_source,UNNEST(REGEXP_EXTRACT_ALL(payload_source_json,r'"([^"]+)":null')) AS null_field
GROUP BY null_field
ORDER BY affected_rows DESC,null_field;

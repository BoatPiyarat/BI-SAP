DECLARE target_run_id STRING DEFAULT 'V3NIGHTLY-2026-08-25T14:32:37-0ce16d45';

CREATE TEMP TABLE create_event AS
SELECT e.*
FROM `pacific-plating-282708.sap_integration_v3.v3_unit2_event_shadow` e
WHERE e.pipeline_run_id=target_run_id AND e.outcome='READY_CREATE_OR_PAYMENT'
  AND NOT EXISTS (SELECT 1
    FROM `pacific-plating-282708.sap_integration_v3.sap_mirror_doc` m
    WHERE m.U_OrderItem=e.order_item)
  AND NOT EXISTS (SELECT 1
    FROM `pacific-plating-282708.sap_integration_v3.v3_unit3_mapping_hold` h
    WHERE h.pipeline_run_id=e.pipeline_run_id AND h.order_item=e.order_item
      AND h.period=e.period AND h.charge_id=e.charge_id);

CREATE TEMP TABLE onetime_shape AS
SELECT e.order_item,e.period,e.invoice_no,
  COUNT(o.OrderItem) AS source_rows,
  COUNTIF(SAFE_CAST(o.Period AS INT64)=e.period) AS period_rows,
  COUNTIF(SAFE_CAST(o.Period AS INT64)=e.period AND IFNULL(o.InvoiceNo,'')=IFNULL(e.invoice_no,''))
    AS exact_rows,
  STRING_AGG(DISTINCT IFNULL(o.InvoiceNo,'<NULL>'),', ' LIMIT 5) AS source_invoices
FROM create_event e
LEFT JOIN `pacific-plating-282708.sap_integration_v3.vw_onetime_payload_source` o
  ON o.OrderItem=e.order_item
WHERE e.flow='ONETIME'
GROUP BY e.order_item,e.period,e.invoice_no;

CREATE TEMP TABLE rcl_shape AS
SELECT e.order_item,e.period,e.invoice_no,
  COUNT(r.OrderItem) AS source_rows,
  COUNTIF(SAFE_CAST(r.Period AS INT64)=e.period) AS period_rows,
  COUNTIF(SAFE_CAST(r.Period AS INT64)=e.period AND IFNULL(r.InvoiceNo,'')=IFNULL(e.invoice_no,''))
    AS exact_rows,
  STRING_AGG(DISTINCT IFNULL(r.InvoiceNo,'<NULL>'),', ' LIMIT 5) AS source_invoices
FROM create_event e
LEFT JOIN `pacific-plating-282708.sap_data_engineer.sap_dashboard_carepay_installment` r
  ON r.OrderItem=e.order_item
WHERE e.flow='RCL'
GROUP BY e.order_item,e.period,e.invoice_no;

SELECT 'ONETIME' AS flow,
  COUNT(*) AS candidates,
  COUNTIF(source_rows=0) AS no_item_source,
  COUNTIF(source_rows>0 AND period_rows=0) AS no_period_source,
  COUNTIF(period_rows>0 AND exact_rows=0) AS invoice_mismatch,
  COUNTIF(exact_rows=1) AS exact_once,
  COUNTIF(exact_rows>1) AS exact_duplicate
FROM onetime_shape
UNION ALL
SELECT 'RCL',COUNT(*),COUNTIF(source_rows=0),COUNTIF(source_rows>0 AND period_rows=0),
  COUNTIF(period_rows>0 AND exact_rows=0),COUNTIF(exact_rows=1),COUNTIF(exact_rows>1)
FROM rcl_shape;

SELECT 'ONETIME' AS flow,* FROM onetime_shape WHERE exact_rows!=1
UNION ALL
SELECT 'RCL',* FROM rcl_shape WHERE exact_rows!=1
ORDER BY flow,order_item
LIMIT 100;

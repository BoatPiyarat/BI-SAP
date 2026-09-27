CREATE TEMP TABLE upstream AS
SELECT 'sap_dashboard_carepay_installment' AS source_view,OrderItem,SAFE_CAST(Period AS INT64) AS period,InvoiceNo,TransactionStatus FROM `pacific-plating-282708.sap_data_engineer.sap_dashboard_carepay_installment`
UNION ALL
SELECT 'sap_dashboard_carepay_fully_paid' AS source_view,OrderItem,SAFE_CAST(Period AS INT64) AS period,InvoiceNo,TransactionStatus FROM `pacific-plating-282708.sap_data_engineer.sap_dashboard_carepay_fully_paid`
UNION ALL
SELECT 'RCB_HEALTH' AS source_view,OrderItem,SAFE_CAST(Period AS INT64) AS period,InvoiceNo,TransactionStatus FROM `pacific-plating-282708.sap_data_engineer.RCB_HEALTH`
UNION ALL
SELECT 'RCB_TRAVEL' AS source_view,OrderItem,SAFE_CAST(Period AS INT64) AS period,InvoiceNo,TransactionStatus FROM `pacific-plating-282708.sap_data_engineer.RCB_TRAVEL`
UNION ALL
SELECT 'RCL_HEALTH' AS source_view,OrderItem,SAFE_CAST(Period AS INT64) AS period,InvoiceNo,TransactionStatus FROM `pacific-plating-282708.sap_data_engineer.RCL_HEALTH`;
SELECT a.reason_code,a.flow,a.business_type,a.payment_mode,
 COUNT(*) AS audit_rows,COUNT(DISTINCT a.order_item) AS items,
 COUNTIF(EXISTS(SELECT 1 FROM upstream u WHERE u.OrderItem=a.order_item AND u.period=a.installment_period)) AS upstream_period_present,
 COUNTIF(EXISTS(SELECT 1 FROM upstream u WHERE u.OrderItem=a.order_item AND u.period=a.installment_period AND u.InvoiceNo IN UNNEST(JSON_VALUE_ARRAY(a.candidate_invoice_nos)))) AS upstream_invoice_present,
 ARRAY_AGG(STRUCT(a.order_id,a.order_item,a.installment_period,a.charge_id) LIMIT 3) AS examples
FROM `pacific-plating-282708._script854956d6400364d5179432334ac884bec17498b8.audit_result` a WHERE a.event_type='PAID' AND a.needs_review
GROUP BY a.reason_code,a.flow,a.business_type,a.payment_mode;

CREATE TEMP TABLE rcl_newpayment AS
SELECT OrderItem,SAFE_CAST(Period AS INT64) AS period,InvoiceNo
FROM `pacific-plating-282708.sap_integration_v2.RCL 05_newpayment`;
SELECT a.order_id,a.order_item,a.installment_period,a.charge_id,a.reason_code,a.flow,a.business_type,a.reconciliation_status,
EXISTS(SELECT 1 FROM `pacific-plating-282708._scriptaffe2b441b55eb2b738b1635e949427f5962b140.upstream` u WHERE u.OrderItem=a.order_item AND u.period=a.installment_period AND u.InvoiceNo IN UNNEST(JSON_VALUE_ARRAY(a.candidate_invoice_nos))) AS upstream_invoice_present,
EXISTS(SELECT 1 FROM rcl_newpayment n WHERE n.OrderItem=a.order_item AND n.period=a.installment_period AND n.InvoiceNo IN UNNEST(JSON_VALUE_ARRAY(a.candidate_invoice_nos))) AS rcl_newpayment_invoice_present
FROM `pacific-plating-282708._script854956d6400364d5179432334ac884bec17498b8.audit_result` a WHERE a.event_type='PAID' AND a.needs_review;

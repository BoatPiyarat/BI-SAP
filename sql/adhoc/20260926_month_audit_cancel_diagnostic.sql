CREATE TEMP TABLE cancel_output AS
SELECT 'RCB_Motor_process_2_cancel_new' AS source_view,OrderItem,SAFE_CAST(Period AS INT64) AS period,NULLIF(NULLIF(TRIM(InvoiceNo),''),'NULL') AS invoice_no,TransactionStatus
FROM `pacific-plating-282708.sap_view.RCB_Motor_process_2_cancel_new`
UNION ALL
SELECT 'RCL_Motor_process_3_cancel',OrderItem,SAFE_CAST(Period AS INT64),NULLIF(NULLIF(TRIM(InvoiceNo),''),'NULL'),TransactionStatus
FROM `pacific-plating-282708.sap_view.RCL_Motor_process_3_cancel`;
SELECT a.reason_code,a.flow,a.business_type,COUNT(*) AS document_rows,COUNT(DISTINCT a.order_item) AS items,
COUNTIF(EXISTS(SELECT 1 FROM cancel_output o WHERE o.OrderItem=a.order_item)) AS item_in_cancel_output,
COUNTIF(EXISTS(SELECT 1 FROM cancel_output o WHERE o.OrderItem=a.order_item AND o.period=a.installment_period AND o.invoice_no IS NOT DISTINCT FROM a.raw_invoice_no)) AS receipt_in_cancel_output,
ARRAY_AGG(STRUCT(a.order_item,a.installment_period,a.cancellation_docentry) LIMIT 3) AS examples
FROM `pacific-plating-282708._scripte2a7c6f7ac807a1076c994ab710e6beb0125ddac.audit_result` a WHERE a.event_type='CANCELLATION' AND a.needs_review
GROUP BY a.reason_code,a.flow,a.business_type;

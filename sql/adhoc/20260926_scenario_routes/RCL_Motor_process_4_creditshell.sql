-- Read-only exact live view output for fixed September missing-evidence items.
SELECT DISTINCT 'RCL_Motor_process_4_creditshell' AS source_view, v.OrderID,v.OrderItem,SAFE_CAST(v.Period AS INT64) AS period,
 NULLIF(NULLIF(TRIM(v.InvoiceNo),''),'NULL') AS invoice_no,
 LOWER(TRIM(v.TransactionStatus)) AS output_status,
 SAFE_CAST(v.ActualReceived AS FLOAT64) AS actual_received,
 SAFE_CAST(v.ExpectedReceived AS FLOAT64) AS expected_received,
 SAFE_CAST(v.TotalPeriods AS INT64) AS total_periods,v.PaymentChannel,v.RefOrder
FROM `pacific-plating-282708.sap_view.RCL_Motor_process_4_creditshell` v
WHERE EXISTS(SELECT 1 FROM `pacific-plating-282708._script854956d6400364d5179432334ac884bec17498b8.audit_result` a
 WHERE a.reconciliation_status='MISSING_TERMINAL_SAP_EVIDENCE'
 AND (a.order_item=v.OrderItem OR a.order_id=v.OrderID OR a.order_id=v.RefOrder));

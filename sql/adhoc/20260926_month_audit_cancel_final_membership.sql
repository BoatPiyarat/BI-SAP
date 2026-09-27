SELECT a.order_id,a.order_item,a.installment_period,a.raw_invoice_no,a.cancellation_docentry,
a.reason_code,a.flow,a.business_type,a.reconciliation_status,
EXISTS(SELECT 1 FROM `pacific-plating-282708._script8bfe4ff9b4d90206402b9a2b5cf0ebb8e2883c49.cancel_output` o WHERE o.OrderItem=a.order_item) AS item_in_cancel_output,
EXISTS(SELECT 1 FROM `pacific-plating-282708._script8bfe4ff9b4d90206402b9a2b5cf0ebb8e2883c49.cancel_output` o WHERE o.OrderItem=a.order_item AND o.period=a.installment_period AND o.invoice_no IS NOT DISTINCT FROM a.raw_invoice_no) AS receipt_in_cancel_output
FROM `pacific-plating-282708._script854956d6400364d5179432334ac884bec17498b8.audit_result` a WHERE a.event_type='CANCELLATION' AND a.needs_review;

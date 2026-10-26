-- Verify the correct change-order owner for the RCB Motor SAP-absent event.
-- Read-only; L80822481 is confirmed in cancelled_change_orders.
SELECT
  'RCB_Motor_process_4_creditshell' AS view_name,
  OrderID,
  OrderItem,
  SAFE_CAST(Period AS INT64) AS Period,
  NULLIF(TRIM(InvoiceNo), '') AS InvoiceNo,
  TransactionStatus,
  ActualReceived,
  PaymentDate,
  PaymentMethod,
  PaymentChannel,
  RefOrder
FROM `pacific-plating-282708.sap_view.RCB_Motor_process_4_creditshell`
WHERE OrderItem = 'L80822481-V1'
ORDER BY Period, InvoiceNo;

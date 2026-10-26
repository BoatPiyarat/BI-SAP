-- Read-only check whether the four SAP-incomplete cancel items still have a reusable
-- complete schedule in the existing legacy RCL CreditShell upstream.

SELECT
  OrderItem,
  OrderID,
  InvoiceNo,
  TransactionStatus,
  Period,
  TotalPeriods,
  ExpectedReceived,
  ActualReceived,
  PaymentDate,
  PaymentMethod,
  PaymentChannel
FROM `pacific-plating-282708.sap_integration_v2.RCL 04_new order credit shell`
WHERE OrderItem IN (
  'L77833033-V1',
  'L80511750-V1',
  'L80513404-V1',
  'L80518454-V1'
)
ORDER BY OrderItem, Period, InvoiceNo;

-- Read-only check for reusable period rows in the existing legacy installment upstream.

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
FROM `pacific-plating-282708.sap_data_engineer.sap_dashboard_carepay_installment`
WHERE OrderItem IN (
  'L77833033-V1',
  'L80511750-V1',
  'L80513404-V1',
  'L80518454-V1'
)
ORDER BY OrderItem, Period, InvoiceNo;

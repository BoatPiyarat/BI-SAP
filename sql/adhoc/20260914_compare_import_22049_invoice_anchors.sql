-- Compare the four InvoiceNo/PolicyStatus anchor failures with the validated mirror state.

SELECT
  U_OrderID AS OrderID,
  U_OrderItem AS OrderItem,
  U_Period AS Period,
  TotalPeriods,
  TransactionStatus,
  U_InvoiceNo AS InvoiceNo,
  BatchRunDate,
  DocEntry,
  docs_considered,
  resolution_confidence
FROM `pacific-plating-282708.sap_integration_v3.sap_mirror_state`
WHERE U_OrderItem IN (
  'L79180940-1', 'L79308561-1', 'L79510340-1', 'L79949677-1'
)
ORDER BY OrderItem, Period;

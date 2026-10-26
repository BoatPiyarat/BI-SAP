-- Read-only exact-order trace; preserves duplicate event rows.
SELECT CURRENT_TIMESTAMP() AS checked_at_utc, 'sap_view.RCL_Motor_process_2_newpayment' AS source,
OrderID, OrderItem, SAFE_CAST(Period AS INT64) AS Period, SAFE_CAST(TotalPeriods AS INT64) AS TotalPeriods,
InvoiceNo, TransactionStatus, ExpectedReceived, ActualReceived, PaymentDate, PaymentMethod, PaymentChannel
FROM `pacific-plating-282708.sap_view.RCL_Motor_process_2_newpayment`
WHERE SPLIT(OrderItem, '-')[SAFE_OFFSET(0)] IN ('L80570054','L79109956')
ORDER BY OrderItem, Period, InvoiceNo;


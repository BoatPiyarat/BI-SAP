SELECT U_OrderItem, OrderDate, TransactionStatus, ExpectedReceived, U_ActualReceived,
       U_TotalAmount, BatchRunDate, PaymentMethod, PaymentChannel
FROM `pacific-plating-282708.sap_integration_v2.SAP_LIVE_FULL`
WHERE U_OrderItem IN ('L78667850-V1','L78242486-V1')
ORDER BY U_OrderItem, BatchRunDate

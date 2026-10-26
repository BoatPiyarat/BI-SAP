-- Read-only exact-order SAP mirror history, not proof of SAP-side posting success.
SELECT CURRENT_TIMESTAMP() AS checked_at_utc,
U_OrderID AS OrderID, U_OrderItem AS OrderItem, U_Period AS Period,
U_InvoiceNo AS InvoiceNo, TransactionStatus, ExpectedReceived,
U_ActualReceived AS ActualReceived, PaymentDate, PaymentMethod, PaymentChannel,
MIN(UpdateDate) AS first_mirror_update, MAX(UpdateDate) AS last_mirror_update,
COUNT(*) AS mirror_history_rows
FROM `pacific-plating-282708.sap_integration_v2.SAP_LIVE_FULL`
WHERE SPLIT(U_OrderItem, '-')[SAFE_OFFSET(0)] IN ('L80570054','L79109956')
GROUP BY U_OrderID, U_OrderItem, U_Period, U_InvoiceNo, TransactionStatus,
ExpectedReceived, U_ActualReceived, PaymentDate, PaymentMethod, PaymentChannel
ORDER BY OrderItem, Period, InvoiceNo;

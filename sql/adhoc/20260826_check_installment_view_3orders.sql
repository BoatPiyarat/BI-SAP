SELECT OrderItem, ExpectedReceived, ActualReceived, TotalAmount, Period, TotalPeriods, PaymentChannel, PaymentMethod
FROM `pacific-plating-282708.sap_data_engineer.sap_dashboard_carepay_installment`
WHERE OrderItem IN ('L78745610-V1', 'L80580491-V1', 'L80616601-V1')
ORDER BY OrderItem, Period

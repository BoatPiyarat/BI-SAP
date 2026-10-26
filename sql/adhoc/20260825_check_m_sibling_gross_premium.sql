SELECT U_OrderItem, GrossPremium, TotalPremium, PaymentMethod, PaymentChannel
FROM `pacific-plating-282708.sap_integration_v2.SAP_LIVE_FULL`
WHERE U_OrderItem LIKE 'L80512627%' OR U_OrderItem LIKE 'L78795406%'
ORDER BY U_OrderItem

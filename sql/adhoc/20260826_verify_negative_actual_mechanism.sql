SELECT U_OrderItem, GrossPremium, TotalPremium, PaymentMethod, PaymentChannel
FROM `pacific-plating-282708.sap_integration_v2.SAP_LIVE_FULL`
WHERE U_OrderItem LIKE 'L78745610%' OR U_OrderItem LIKE 'L80616601%' OR U_OrderItem LIKE 'L80580491%'
ORDER BY U_OrderItem

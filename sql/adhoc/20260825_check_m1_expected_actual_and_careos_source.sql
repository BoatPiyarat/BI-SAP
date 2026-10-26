-- READ-ONLY. Check M1's own ExpectedReceived/ActualReceived from the view (not assumed), and the
-- raw careos_order_items columns (net_premium, gross_premium, vat_amount, stamp_duty) that feed
-- compu_detail.gross_premium and the main TotalPremium/GrossPremium output columns, to resolve
-- which column compu_detail.gross_premium actually reads.
SELECT 'view_M1' AS src, OrderItem, ExpectedReceived, ActualReceived, GrossPremium, TotalPremium
FROM `pacific-plating-282708.sap_data_engineer.sap_dashboard_carepay_fully_paid`
WHERE OrderItem = 'L80512627-M1'

UNION ALL

SELECT 'view_V1', OrderItem, ExpectedReceived, ActualReceived, GrossPremium, TotalPremium
FROM `pacific-plating-282708.sap_data_engineer.sap_dashboard_carepay_fully_paid`
WHERE OrderItem = 'L80512627-V1';

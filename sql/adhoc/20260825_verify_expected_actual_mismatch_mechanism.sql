-- READ-ONLY. Verify the ExpectedReceived/ActualReceived split-charge subtraction mechanism
-- against 3 known-mismatched OrderItems from the AR 1134/1135 misposting investigation.
SELECT OrderItem, ExpectedReceived, ActualReceived, TotalAmount, ProcessingFee, Discount
FROM `pacific-plating-282708.sap_data_engineer.sap_dashboard_carepay_fully_paid`
WHERE OrderItem IN ('L80512627-V1', 'L80512630-V1', 'L80512632-V1', 'L78834777-V1', 'L78795406-V1')
ORDER BY OrderItem

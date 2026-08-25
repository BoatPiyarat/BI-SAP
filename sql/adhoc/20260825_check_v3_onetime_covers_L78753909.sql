-- READ ONLY investigation. No mutation.
-- Does V3's vw_onetime_payload_source (which does not depend on transaction_snapshot_installment_details
-- or number_of_installment) already pick up L78753909-V1 correctly, unlike the legacy V2 dashboard views?
SELECT OrderID, OrderItem, InvoiceNo, TransactionStatus, Period, TotalPeriods, PaymentDate,
  PaymentMethod, PaymentChannel, ActualReceived, ExpectedReceived
FROM `pacific-plating-282708.sap_integration_v3.vw_onetime_payload_source`
WHERE OrderItem = 'L78753909-V1';

-- READ-ONLY. Profile SAP_LIVE_FULL rows updated on 2026-09-26/27 (did tonight's RCL files import?).
-- Aggregates only.
SELECT DATE(UpdateDate) AS upd, CompanyDB, TransactionStatus,
  (SAFE_CAST(U_Period AS INT64) > 0 AND SAFE_CAST(TotalPeriods AS INT64) > 1) AS installment_like,
  COALESCE(SAFE_CAST(ExpectedReceived AS FLOAT64) = 0 AND SAFE_CAST(U_ActualReceived AS FLOAT64) > 0, FALSE) AS extra_shape,
  COUNT(*) AS rows_n, COUNT(DISTINCT U_OrderItem) AS items
FROM `pacific-plating-282708.sap_integration_v2.SAP_LIVE_FULL`
WHERE DATE(UpdateDate) >= DATE '2026-09-26'
GROUP BY 1,2,3,4,5
ORDER BY 1,2,3,4,5

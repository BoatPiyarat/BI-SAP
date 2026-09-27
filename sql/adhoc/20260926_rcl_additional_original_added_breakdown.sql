WITH added AS (
SELECT c.OrderItem,c.Period,c.InvoiceNo,c.TransactionStatus,c.ExpectedReceived,c.ActualReceived
FROM `pacific-plating-282708._script437ae657b2356f03dd96effc1f4250fc8fb0a183.candidate_wrapper` c
WHERE NOT EXISTS(SELECT 1 FROM `pacific-plating-282708._script4f06476e8de4bc85e3fcd9aa533fc6d797e4adf1.baseline_wrapper` b WHERE TO_JSON_STRING(b)=TO_JSON_STRING(c)))
SELECT CURRENT_TIMESTAMP() AS checked_at_utc,TransactionStatus,
 IF(ExpectedReceived=0 AND ActualReceived>0,'additional','reopened_spine') AS row_kind,
 COUNT(*) AS row_count,COUNT(DISTINCT OrderItem) AS item_count,
 COUNTIF(EXISTS(SELECT 1 FROM `pacific-plating-282708._script4f06476e8de4bc85e3fcd9aa533fc6d797e4adf1.evidence_sap` s WHERE s.U_OrderItem=a.OrderItem AND SAFE_CAST(s.U_Period AS INT64)=SAFE_CAST(a.Period AS INT64))) AS rows_with_existing_sap_period,
 ROUND(SUM(ActualReceived),2) AS actual_thb
FROM added a GROUP BY 2,3;

-- P0 mirror completeness gate, Boat 2026-07-31.
-- Grain: raw append rows in sap_integration_v2.SAP_LIVE by U_BatchRunDate calendar date.
-- This is one batched plan; it does not mutate any object.
SELECT
  DATE(U_BatchRunDate, 'Asia/Bangkok') AS batch_date_bkk,
  COUNT(*) AS row_count,
  COUNT(DISTINCT DocEntry) AS distinct_docentry,
  MIN(U_BatchRunDate) AS min_batch_timestamp,
  MAX(U_BatchRunDate) AS max_batch_timestamp
FROM `pacific-plating-282708.sap_integration_v2.SAP_LIVE`
WHERE U_BatchRunDate >= TIMESTAMP('2026-07-22', 'Asia/Bangkok')
  AND U_BatchRunDate < TIMESTAMP('2026-08-01', 'Asia/Bangkok')
GROUP BY batch_date_bkk
ORDER BY batch_date_bkk;

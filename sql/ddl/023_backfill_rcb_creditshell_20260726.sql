-- 023_backfill_rcb_creditshell_20260726.sql
-- One-time manual close for the RCB Credit-Shell gap - the 35-of-135 population identified
-- earlier today (Boat, 2026-07-26: "do backfill, make sure the new design will cover the missing
-- daily") that was found covered by `sap_view.RCB_Motor_process_4_creditshell` but never actually
-- exported (investigation moved on to the deeper stg_schedule bug and the Cloud Function timeout
-- root cause before circling back).
--
-- Same data-quality issue pattern as the RCL Credit-Shell view (022): 51 raw rows, only 41
-- distinct (OrderItem, Period) - 10 duplicate pairs. Unlike RCL, InvoiceNo is never null here.
-- PaymentChannel values: 46 rows 'RCB-Credit Shell' (correct), 5 rows 'RCB-DIRECT PAYMENT'
-- (duplicate/wrong-channel candidate for the same period) - deduped preferring
-- 'RCB-Credit Shell' to match the actual channel these orders were paid through.

CREATE OR REPLACE TABLE `pacific-plating-282708.sap_integration_v3.manual_close_20260726_rcb_creditshell` AS
WITH ranked AS (
  SELECT *,
    ROW_NUMBER() OVER (
      PARTITION BY OrderItem, Period
      ORDER BY (PaymentChannel = 'RCB-Credit Shell') DESC, InvoiceNo ASC
    ) AS rn
  FROM `pacific-plating-282708.sap_view.RCB_Motor_process_4_creditshell`
  WHERE InvoiceNo IS NOT NULL AND InvoiceNo != ''
)
SELECT * EXCEPT(rn)
FROM ranked
WHERE rn = 1
ORDER BY OrderItem, Period;

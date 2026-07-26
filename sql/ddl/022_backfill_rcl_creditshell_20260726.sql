-- 022_backfill_rcl_creditshell_20260726.sql
-- One-time manual close for the RCL Credit-Shell gap discovered while backfilling the Credit-Shell
-- current_human_id population (Boat, 2026-07-26: "do backfill, make sure the new design will
-- cover the missing daily").
--
-- Root cause: the Motor Cloud Function (rcb-motor-order-payment-sap-bucket-1) runs 6 sequential
-- export steps daily (RCB create/cancel/change/creditshell, RCL create, RCL newpayment) but has
-- NO step for RCL Credit-Shell at all, even though a dedicated view already exists and correctly
-- identifies real candidates: `sap_view.RCL_Motor_process_4_creditshell`, sourced from
-- `sap_integration_v2."RCL 04_new order credit shell"`. This view has simply never been wired into
-- the daily automation - a structural gap, not a query bug (see 20_SAP_PROGRESS.md for the full
-- trail, including confirming RCL_Motor_process_1_create's current_human_id exclusion is correct
-- by design - it deliberately routes Credit-Shell orders to this dedicated view instead).
--
-- Data-quality issue found in the live view before use: 129 raw rows, only 115 distinct
-- (OrderItem, Period) - 14 duplicate pairs with conflicting InvoiceNo/PaymentChannel (e.g.
-- L80191661-V1 period 1 had one row tagged PaymentChannel='RCB' and another
-- PaymentChannel='RCL-Credit Shell' with different charge IDs). Also 78/129 rows had NULL/empty
-- InvoiceNo and 77/129 had NULL/empty PaymentChannel - not safe to export raw. Cleaned by
-- filtering to non-null InvoiceNo/PaymentChannel and deduping to one row per (OrderItem, Period),
-- preferring PaymentChannel = 'RCL-Credit Shell' (the whole point of this table) over any other
-- value. Result: 37 clean rows covering 37 of 38 distinct order_items (1 order_item has no usable
-- row in this source at all across any candidate - left out, not fabricated).

CREATE OR REPLACE TABLE `pacific-plating-282708.sap_integration_v3.manual_close_20260726_rcl_creditshell` AS
WITH ranked AS (
  SELECT *,
    ROW_NUMBER() OVER (
      PARTITION BY OrderItem, Period
      ORDER BY (PaymentChannel = 'RCL-Credit Shell') DESC, InvoiceNo ASC
    ) AS rn
  FROM `pacific-plating-282708.sap_view.RCL_Motor_process_4_creditshell`
  WHERE InvoiceNo IS NOT NULL AND InvoiceNo != ''
    AND PaymentChannel IS NOT NULL AND PaymentChannel != ''
)
SELECT * EXCEPT(rn)
FROM ranked
WHERE rn = 1
ORDER BY OrderItem, Period;

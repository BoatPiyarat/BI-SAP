-- READ ONLY. Diagnose SAP's "Period:Sequence of Period invalid" rejection for OrderId L78343432
-- (import LogID 21640, rows 2359-2368). SAP rejected all 8 rows for this order on period sequence,
-- not on the InvoiceNo/Paid-Cancelled duplicate pattern that dominates the rest of that file.
-- No live BigQuery access this session — run this and share the output.

-- 1. What does CareOS itself think this order's period spine looks like? Look for duplicate period
--    numbers, gaps, or non-sequential ordering across order_items under this order.
SELECT
  coi.human_id AS order_item,
  co.human_id AS order_id,
  s.period,
  s.total_periods,
  s.motor_item_type,
  s.transaction_id
FROM `pacific-plating-282708.sap_integration_v3.stg_schedule` s
JOIN `pacific-plating-282708.careos.careos_order_items` coi ON coi.human_id = s.order_item
JOIN `pacific-plating-282708.careos.careos_orders` co ON co.id = coi.order_id
WHERE co.human_id = 'L78343432'
ORDER BY coi.human_id, s.period;

-- 2. What did the export candidate/expected_state say for each period of this order (Paid vs
--    Pending, invoice numbers) — checking for duplicate periods or a period numbered out of range.
SELECT
  e.order_item,
  e.period,
  e.total_periods,
  e.expected_status,
  e.expected_invoice_no,
  e.expected_payment_date
FROM `pacific-plating-282708.sap_integration_v3.expected_state` e
WHERE e.order_id = 'L78343432'
ORDER BY e.order_item, e.period;

-- 3. What does SAP_LIVE_FULL itself already show for this order/these order_items — periods,
--    statuses, and whether any period number looks duplicated, skipped, or reordered relative to
--    what CareOS expects.
SELECT
  OrderItem,
  Period,
  TotalPeriods,
  TransactionStatus,
  InvoiceNo,
  BatchRunDate
FROM `pacific-plating-282708.sap_integration_v2.SAP_LIVE_FULL`
WHERE OrderID = 'L78343432'
ORDER BY OrderItem, SAFE_CAST(Period AS INT64);

-- 4. Duplicate-period check across the raw carepay installment source itself (a common cause of
--    "Sequence of Period invalid": two rows submitted claiming the same period number, or a period
--    number that doesn't fit within 1..TotalPeriods).
SELECT
  OrderItem,
  Period,
  TotalPeriods,
  COUNT(*) AS row_count
FROM `pacific-plating-282708.sap_data_engineer.sap_dashboard_carepay_installment`
WHERE OrderID = 'L78343432'
GROUP BY OrderItem, Period, TotalPeriods
ORDER BY OrderItem, SAFE_CAST(Period AS INT64);

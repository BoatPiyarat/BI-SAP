-- Change-order flow preflight (source-only; DO NOT DEPLOY / DO NOT EXPORT)
-- Boat request 2026-08-02. This query prepares evidence; it does not approve a batch.
--
-- Lanes are deliberately separate:
--   1) CANCEL_OLD       - reproduce SAP state and change status only after approval.
--   2) CREATE_REPLACEMENT - normal V3 replacement-order payload.
--   3) CREDIT_SHELL_PAYMENT - payment semantics requiring reviewed old/new linkage.
--
-- INCIDENT-002b remediation and its 224 unknown-cause orders are outside this query.
-- D2 remains binding: no cancellation until all preflight gates pass, Aware confirms whether an
-- explicit Cancelled document is required, and FA/Boat approves the batch.

DECLARE open_period_start DATE;

ASSERT (
  SELECT COUNT(*)
  FROM `pacific-plating-282708.sap_integration_v3.sap_period_lock`
  WHERE lock_datetime > CURRENT_TIMESTAMP()
) = 1 AS 'Change-order preflight requires exactly one active period';

SET open_period_start = (
  SELECT open_period_start
  FROM `pacific-plating-282708.sap_integration_v3.sap_period_lock`
  WHERE lock_datetime > CURRENT_TIMESTAMP()
);

CREATE TEMP TABLE _links_raw AS
SELECT DISTINCT
  old_human_id AS old_order_id,
  current_human_id AS new_order_id
FROM `pacific-plating-282708.careos.cancelled_change_orders`
WHERE old_human_id IS NOT NULL
  AND current_human_id IS NOT NULL;

CREATE TEMP TABLE _links AS
SELECT
  p.*,
  (SELECT COUNT(*) FROM _links_raw x WHERE x.old_order_id = p.old_order_id) AS old_link_count,
  (SELECT COUNT(*) FROM _links_raw x WHERE x.new_order_id = p.new_order_id) AS new_link_count
FROM _links_raw p;

CREATE TEMP TABLE _sap_old AS
SELECT
  l.old_order_id,
  l.new_order_id,
  m.U_OrderItem AS old_order_item,
  SAFE_CAST(m.U_Period AS INT64) AS period,
  SAFE_CAST(m.TotalPeriods AS INT64) AS total_periods,
  m.TransactionStatus,
  NULLIF(m.U_InvoiceNo, '') AS invoice_no,
  m.DocEntry,
  m.UpdateDate,
  m.UpdateTime
FROM _links l
JOIN `pacific-plating-282708.sap_integration_v3.sap_mirror_state` m
  ON m.U_OrderID = l.old_order_id;

CREATE TEMP TABLE _sap_gate AS
SELECT
  old_order_id,
  new_order_id,
  COUNT(DISTINCT old_order_item) AS sap_order_items,
  COUNT(*) AS sap_rows,
  COUNTIF(TransactionStatus IN ('Cancelled', 'Cancelled (Change order / Rejected)')) AS terminal_rows,
  COUNTIF(invoice_no IS NULL AND TransactionStatus IN ('Paid', 'paid')) AS paid_missing_invoice_rows,
  COUNTIF(period IS NULL OR total_periods IS NULL OR period < 1 OR period > total_periods) AS invalid_period_rows,
  COUNTIF(period = 1) AS period1_rows,
  COUNT(DISTINCT total_periods) AS total_periods_versions,
  MAX(total_periods) AS max_total_periods,
  COUNT(DISTINCT period) AS distinct_periods
FROM _sap_old
GROUP BY old_order_id, new_order_id;

CREATE TEMP TABLE _replacement AS
SELECT
  l.old_order_id,
  l.new_order_id,
  e.order_item AS new_order_item,
  e.period,
  e.total_periods,
  e.flow,
  e.expected_status,
  e.expected_invoice_no,
  e.expected_payment_date,
  e.charge_id,
  e.charge_amount
FROM _links l
LEFT JOIN `pacific-plating-282708.sap_integration_v3.expected_state` e
  ON e.order_id = l.new_order_id;

CREATE TEMP TABLE _replacement_gate AS
SELECT
  old_order_id,
  new_order_id,
  COUNTIF(new_order_item IS NOT NULL) AS replacement_rows,
  COUNT(DISTINCT new_order_item) AS replacement_order_items,
  COUNTIF(expected_status = 'Paid') AS paid_rows,
  COUNTIF(expected_status = 'Paid' AND expected_invoice_no IS NULL) AS paid_missing_invoice_rows,
  COUNTIF(expected_status = 'Paid' AND expected_payment_date IS NULL) AS paid_missing_payment_date_rows,
  COUNTIF(expected_payment_date >= DATE_ADD(open_period_start, INTERVAL 1 MONTH)) AS august_or_later_rows
FROM _replacement
GROUP BY old_order_id, new_order_id;

-- One row per linked old/new order pair. READY_FOR_REVIEW is not approval to export.
SELECT
  l.old_order_id,
  l.new_order_id,
  IFNULL(s.sap_order_items, 0) AS sap_old_order_items,
  IFNULL(s.sap_rows, 0) AS sap_old_rows,
  IFNULL(s.terminal_rows, 0) AS sap_terminal_rows,
  IFNULL(s.paid_missing_invoice_rows, 0) AS sap_paid_missing_invoice_rows,
  IFNULL(s.invalid_period_rows, 0) AS sap_invalid_period_rows,
  IFNULL(s.total_periods_versions, 0) AS sap_total_periods_versions,
  IFNULL(s.distinct_periods, 0) AS sap_distinct_periods,
  IFNULL(s.max_total_periods, 0) AS sap_max_total_periods,
  IFNULL(r.replacement_rows, 0) AS replacement_rows,
  IFNULL(r.replacement_order_items, 0) AS replacement_order_items,
  IFNULL(r.paid_rows, 0) AS replacement_paid_rows,
  IFNULL(r.paid_missing_invoice_rows, 0) AS replacement_paid_missing_invoice_rows,
  IFNULL(r.paid_missing_payment_date_rows, 0) AS replacement_paid_missing_payment_date_rows,
  IFNULL(r.august_or_later_rows, 0) AS replacement_august_or_later_rows,
  l.old_link_count,
  l.new_link_count,
  CASE
    WHEN l.old_link_count > 1 OR l.new_link_count > 1 THEN 'HOLD_LINK_AMBIGUOUS'
    WHEN IFNULL(s.sap_rows, 0) = 0 THEN 'HOLD_OLD_NOT_IN_SAP'
    WHEN s.terminal_rows > 0 THEN 'HOLD_OLD_ALREADY_TERMINAL'
    WHEN s.paid_missing_invoice_rows > 0 THEN 'HOLD_SAP_PAID_INVOICE_MISSING'
    WHEN s.invalid_period_rows > 0 THEN 'HOLD_SAP_PERIOD_INVALID'
    WHEN s.total_periods_versions > 1 THEN 'HOLD_SAP_TOTAL_PERIODS_CONFLICT'
    WHEN s.distinct_periods != s.max_total_periods THEN 'HOLD_SAP_SPINE_INCOMPLETE'
    WHEN IFNULL(r.replacement_rows, 0) = 0 THEN 'HOLD_REPLACEMENT_NOT_IN_EXPECTED_STATE'
    WHEN r.paid_missing_invoice_rows > 0 THEN 'HOLD_REPLACEMENT_PAID_INVOICE_MISSING'
    WHEN r.paid_missing_payment_date_rows > 0 THEN 'HOLD_REPLACEMENT_PAID_DATE_MISSING'
    WHEN r.august_or_later_rows > 0 THEN 'HOLD_AUGUST_OUT_OF_SCOPE'
    ELSE 'READY_FOR_AWARE_FA_REVIEW'
  END AS preflight_status,
  CURRENT_TIMESTAMP() AS query_timestamp
FROM _links l
LEFT JOIN _sap_gate s USING (old_order_id, new_order_id)
LEFT JOIN _replacement_gate r USING (old_order_id, new_order_id)
ORDER BY preflight_status, old_order_id, new_order_id;

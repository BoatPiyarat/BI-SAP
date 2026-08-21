-- Live Phase 1 verification for Google Sheet tab `urgent_for refund to cust`.
-- Read-only. This file does not construct or export a SAP interface payload.
-- User decision (Boat, 2026-08-21): CareOS item status is definitive; completion
-- means SAP contains the transaction as Paid and then Cancelled.

WITH scope AS (
  SELECT order_item
  FROM UNNEST([
    'L77833033-V1','L80569525-M1','L80569525-V1','L80545799-V1',
    'L80489663-M1','L80489663-V1','L80482628-M1','L80482628-V1',
    'L78551615-V1','L78753528-M1','L78753528-V1','L79966351-M1',
    'L79883067-1','L80451154-V1','L80503747-V1','L79328887-V1',
    'L80562453-V1','L80546987-V1'
  ]) AS order_item
),
careos AS (
  SELECT
    i.human_id AS order_item,
    o.human_id AS order_id,
    i.is_cancelled,
    i.cancel_time,
    (i.is_cancelled IS TRUE OR i.cancel_time IS NOT NULL) AS careos_cancelled
  FROM `pacific-plating-282708.careos.careos_order_items` AS i
  JOIN `pacific-plating-282708.careos.careos_orders` AS o
    ON o.id = i.order_id
  JOIN scope AS s ON s.order_item = i.human_id
),
change_membership AS (
  SELECT
    c.order_item,
    LOGICAL_OR(x.old_human_id = c.order_id) AS is_old_change_order,
    LOGICAL_OR(x.current_human_id = c.order_id) AS is_current_change_order
  FROM careos AS c
  LEFT JOIN `pacific-plating-282708.careos.cancelled_change_orders` AS x
    ON c.order_id IN (x.old_human_id, x.current_human_id)
  GROUP BY c.order_item
),
sap AS (
  SELECT
    m.U_OrderItem AS order_item,
    COUNT(*) AS sap_period_rows,
    COUNT(DISTINCT m.U_Period) AS sap_distinct_periods,
    MIN(m.U_Period) AS sap_min_period,
    MAX(m.U_Period) AS sap_max_period,
    COUNT(DISTINCT m.TotalPeriods) AS sap_total_period_values,
    MAX(m.TotalPeriods) AS sap_total_periods,
    COUNTIF(m.TransactionStatus IN ('Paid', 'paid')) AS paid_periods,
    COUNTIF(m.TransactionStatus = 'Pending') AS pending_periods,
    COUNTIF(STARTS_WITH(m.TransactionStatus, 'Cancelled')) AS cancelled_periods,
    COUNTIF(m.TransactionStatus IN ('Paid', 'paid')
      AND NULLIF(TRIM(m.U_InvoiceNo), '') IS NULL)
      AS paid_blank_invoice,
    STRING_AGG(
      FORMAT('%d/%d:%s:%s', m.U_Period, m.TotalPeriods, m.TransactionStatus,
        COALESCE(NULLIF(TRIM(m.U_InvoiceNo), ''), '<blank>')),
      ' | ' ORDER BY m.U_Period
    ) AS sap_period_detail
  FROM `pacific-plating-282708.sap_integration_v3.sap_mirror_state` AS m
  JOIN scope AS s ON s.order_item = m.U_OrderItem
  GROUP BY m.U_OrderItem
)
SELECT
  CURRENT_TIMESTAMP() AS checked_at,
  c.order_id,
  c.order_item,
  c.is_cancelled,
  c.cancel_time,
  c.careos_cancelled,
  COALESCE(ch.is_old_change_order, FALSE) AS is_old_change_order,
  COALESCE(ch.is_current_change_order, FALSE) AS is_current_change_order,
  COALESCE(s.sap_period_rows, 0) AS sap_period_rows,
  COALESCE(s.sap_distinct_periods, 0) AS sap_distinct_periods,
  s.sap_min_period,
  s.sap_max_period,
  s.sap_total_periods,
  COALESCE(s.paid_periods, 0) AS paid_periods,
  COALESCE(s.pending_periods, 0) AS pending_periods,
  COALESCE(s.cancelled_periods, 0) AS cancelled_periods,
  COALESCE(s.paid_blank_invoice, 0) AS paid_blank_invoice,
  s.sap_period_detail,
  CASE
    WHEN NOT c.careos_cancelled THEN 'HOLD_CAREOS_NOT_CANCELLED'
    WHEN COALESCE(s.cancelled_periods, 0) > 0 THEN 'COMPLETE_PAID_THEN_CANCELLED'
    WHEN COALESCE(s.paid_periods, 0) = 0 THEN 'HOLD_PAID_PREDECESSOR_REQUIRED'
    WHEN s.sap_total_period_values != 1
      OR s.sap_min_period != 1
      OR s.sap_max_period != s.sap_total_periods
      OR s.sap_period_rows != s.sap_total_periods
      OR s.sap_distinct_periods != s.sap_total_periods
      OR s.paid_periods + s.pending_periods != s.sap_total_periods
      OR s.paid_blank_invoice > 0 THEN 'HOLD_SAP_SPINE_INVALID'
    WHEN COALESCE(ch.is_old_change_order, FALSE)
      OR COALESCE(ch.is_current_change_order, FALSE) THEN 'HOLD_CHANGE_ORDER_ROUTING'
    ELSE 'CANCEL_CANDIDATE_PHASE1'
  END AS phase1_decision
FROM careos AS c
LEFT JOIN change_membership AS ch USING (order_item)
LEFT JOIN sap AS s USING (order_item)
ORDER BY c.order_id, c.order_item;

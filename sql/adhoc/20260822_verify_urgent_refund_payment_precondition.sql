-- Read-only Phase-2 preflight: reconcile SAP predecessor state to canonical
-- CareOS SUCCESSFUL payment events before constructing an urgent-refund cancel file.

WITH scope AS (
  SELECT order_item
  FROM UNNEST([
    'L78551615-V1','L80451154-V1','L80482628-V1',
    'L80545799-V1','L80546987-V1','L80562453-V1'
  ]) AS order_item
),
sap AS (
  SELECT
    m.U_OrderItem AS order_item,
    m.U_Period AS period,
    m.TotalPeriods AS total_periods,
    m.TransactionStatus AS sap_status,
    m.U_InvoiceNo AS sap_invoice_no,
    m.PaymentDate AS sap_payment_date,
    m.docs_considered
  FROM `pacific-plating-282708.sap_integration_v3.sap_mirror_state` AS m
  JOIN scope AS s ON s.order_item = m.U_OrderItem
),
events AS (
  SELECT
    e.order_item,
    e.period,
    COUNT(*) AS successful_event_count,
    COUNT(DISTINCT e.charge_id) AS successful_charge_count,
    STRING_AGG(DISTINCT e.charge_id, ' | ' ORDER BY e.charge_id) AS charge_ids,
    MIN(e.charge_time) AS first_charge_time,
    MAX(e.charge_time) AS last_charge_time
  FROM `pacific-plating-282708.sap_integration_v3.stg_payment_events` AS e
  JOIN scope AS s USING (order_item)
  WHERE DATE(e.charge_time) >= '2025-01-01'
  GROUP BY e.order_item, e.period
)
SELECT
  CURRENT_TIMESTAMP() AS checked_at,
  sap.order_item,
  sap.period,
  sap.total_periods,
  sap.sap_status,
  sap.sap_invoice_no,
  sap.sap_payment_date,
  sap.docs_considered,
  COALESCE(events.successful_event_count, 0) AS successful_event_count,
  COALESCE(events.successful_charge_count, 0) AS successful_charge_count,
  events.charge_ids,
  events.first_charge_time,
  events.last_charge_time,
  CASE
    WHEN sap.docs_considered > 1 THEN 'HOLD_MULTI_DOCUMENT_WINNER'
    WHEN sap.sap_status = 'Pending' AND COALESCE(events.successful_charge_count, 0) = 1
      THEN 'PAID_IMPORT_REQUIRED_BEFORE_CANCEL'
    WHEN sap.sap_status = 'Pending' AND COALESCE(events.successful_charge_count, 0) > 1
      THEN 'HOLD_AMBIGUOUS_PAID_IMPORT'
    WHEN sap.sap_status IN ('Paid', 'paid')
      AND COALESCE(events.successful_charge_count, 0) = 0
      THEN 'HOLD_SAP_PAID_WITHOUT_CAREOS_EVENT'
    WHEN sap.sap_status IN ('Paid', 'paid')
      AND NULLIF(TRIM(sap.sap_invoice_no), '') IS NULL
      THEN 'HOLD_PAID_INVOICE_BLANK'
    WHEN sap.sap_status IN ('Paid', 'paid') THEN 'PREDECESSOR_PAID_OK'
    WHEN sap.sap_status = 'Pending' THEN 'PREDECESSOR_PENDING_OK'
    ELSE 'HOLD_UNKNOWN_SAP_STATUS'
  END AS precondition_decision
FROM sap
LEFT JOIN events USING (order_item, period)
ORDER BY sap.order_item, sap.period;

-- 018_delta_export.sql
-- P3 build (Boat, 2026-07-25: "start building" V3 P1-P3; "skip to next tasks you can do without
-- my new input").
-- Implements SAP_INTERFACE_REDESIGN_V3.md §2.7 L5 Delta Export: "expected_state minus
-- stg_sap_state -> _01_create / _02_cancel". This is the actual payoff of P1+P2: a precise,
-- per-period diff between what SAP SHOULD show (expected_state) and what it actually shows
-- (stg_sap_state) - the modern replacement for the recon_careos_charges 3-bucket model, at the
-- correct grain (order_item, period) with the correct InvoiceNo already computed.
--
-- NOT yet an actual export (no file gets written to gs://interface-file/ from this) - this table
-- is the "what needs to change" signal for a human or a future automated step to act on. Matches
-- this session's established discipline: surface precisely, act only with explicit sign-off,
-- given how high the stakes are for anything that touches real SAP-bound files.

CREATE OR REPLACE PROCEDURE `pacific-plating-282708.sap_integration_v3.sp_refresh_delta_export`()
BEGIN
  CREATE OR REPLACE TABLE `pacific-plating-282708.sap_integration_v3.delta_export`
  CLUSTER BY delta_type, order_item AS
  SELECT
    e.order_item,
    e.order_id,
    e.period,
    e.total_periods,
    e.flow,
    e.expected_status,
    e.expected_invoice_no,
    e.expected_payment_date,
    s.TransactionStatus AS sap_status,
    s.U_InvoiceNo AS sap_invoice_no,
    s.resolution_confidence,  -- audit marker only; no filter depends on any marker literal
    CASE
      WHEN s.U_OrderItem IS NULL THEN 'MISSING_NO_ROW_IN_SAP'
      WHEN e.expected_status = 'Paid' AND IFNULL(s.U_InvoiceNo, '') = '' THEN 'NEEDS_PAID_UPDATE'
      WHEN e.expected_status = 'Pending' AND IFNULL(s.U_InvoiceNo, '') != '' THEN 'UNEXPECTED_ALREADY_PAID'
      ELSE 'OK'
    END AS delta_type,
    CURRENT_TIMESTAMP() AS computed_at
  FROM `pacific-plating-282708.sap_integration_v3.expected_state` e
  LEFT JOIN `pacific-plating-282708.sap_integration_v3.stg_sap_state` s
    ON s.U_OrderItem = e.order_item AND s.U_Period = e.period;
END;

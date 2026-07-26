-- 021_backfill_motor_newpayment_gap_20260726.sql
-- One-time manual close for the confirmed "newpayment gap" subset of the missing-installment
-- backlog (Boat, 2026-07-26: "list the backfill and reverify, if it is real missing - use one of
-- the production query to generate interface and let's close the gap today").
--
-- Scope, arrived at after live reverification (see 20_SAP_PROGRESS.md):
--   - delta_export found ~3,575 recent (2026) MISSING_NO_ROW_IN_SAP periods.
--   - 1,201 of those are still expected_status = Pending (SAP just hasn't reached them yet -
--     not a real gap, excluded).
--   - Of the remaining 2,374 genuinely Paid-but-absent-from-SAP periods, 73 (all NonMotor) have
--     no resolved invoice_no yet - a separate open issue, excluded from this file.
--   - Of the 2,301 remaining actionable rows, only 279 order_items already have an existing row
--     in SAP (any period) - i.e. the order/policy exists in SAP and this is a genuine
--     "newpayment" gap (one period never posted). The other ~2,022 order_items have ZERO rows in
--     SAP at all (the CREATE flow never ran) - a much bigger, different problem, deliberately
--     scoped OUT of this file per Boat's direction to close the newpayment gap today and
--     investigate the create-flow gap separately.
--   - All 279 are voluntary Motor items (TYPE_1/2_PLUS/3/3_PLUS) - zero MOTOR_TYPE_COMPULSORY
--     (which don't use this periodic newpayment flow at all), zero RCB-channel (routed
--     differently per Boat's A1 decision), zero cancelled orders.
--
-- Source of truth for the row content: NOT re-derived or invented. `RCL 05_newpayment` (the real
-- view feeding today's live NonMotor... err Motor newpayment production file) sources its full
-- per-period financial breakdown (GrossPremium, interest/principal, etc.) from
-- `sap_data_engineer.sap_dashboard_carepay_installment` - a CareOS-side table that already has a
-- fully-computed interface-shaped row for every installment of every order, independent of
-- whether SAP has seen it yet. Confirmed live: all 279 target (order_item, period) pairs exist in
-- this table already, with a non-null InvoiceNo and PaymentDate - nothing here is fabricated,
-- every field is a real, already-computed value from that table.
--
-- Same PaymentDate override + column-preserving pattern as the corrected production views
-- (019_fix_column_reordering_bug.sql) - REPLACE, never EXCEPT+re-add, given the column-reordering
-- incident earlier today.
--
-- Output: a STAGING table, not a direct write to gs://interface-file/. Review row count + sample
-- + pass through validation before the actual bucket upload (separate, explicit step).

CREATE OR REPLACE TABLE `pacific-plating-282708.sap_integration_v3.manual_close_20260726_motor_newpayment_gap` AS
WITH target AS (
  SELECT DISTINCT d.order_item, d.period
  FROM `pacific-plating-282708.sap_integration_v3.delta_export` d
  JOIN `pacific-plating-282708.sap_integration_v3.stg_schedule` s
    ON s.order_item = d.order_item AND s.period = d.period
  JOIN `pacific-plating-282708.sap_integration_v3.expected_state` e
    ON e.order_item = d.order_item AND e.period = d.period
  JOIN `pacific-plating-282708.careos.careos_order_items` oi
    ON oi.human_id = d.order_item
  WHERE d.delta_type = 'MISSING_NO_ROW_IN_SAP'
    AND DATE(oi.create_time) >= '2026-01-01'
    AND e.expected_status = 'Paid'
    AND e.expected_invoice_no IS NOT NULL
    AND s.motor_item_type != 'MOTOR_TYPE_COMPULSORY'
    AND d.order_item IN (
      SELECT DISTINCT U_OrderItem FROM `pacific-plating-282708.sap_integration_v2.SAP_LIVE_FULL`
    )
),
inst AS (
  SELECT *, SAFE_CAST(Period AS INT64) AS careos_installment
  FROM `pacific-plating-282708.sap_data_engineer.sap_dashboard_carepay_installment`
),
base AS (
  SELECT inst.* EXCEPT (careos_installment)
  FROM inst
  JOIN target t ON t.order_item = inst.OrderItem AND t.period = inst.careos_installment
  WHERE inst.PaymentChannel NOT LIKE '%RCB%' OR inst.PaymentChannel IS NULL
)
SELECT * REPLACE(
  CASE
    WHEN PaymentDate IS NULL OR PaymentDate = '' THEN PaymentDate
    WHEN PARSE_DATE('%d%m%Y', PaymentDate) < DATE_TRUNC(CURRENT_DATE(), MONTH)
      THEN FORMAT_DATE('%d%m%Y', DATE_TRUNC(CURRENT_DATE(), MONTH))
    ELSE PaymentDate
  END AS PaymentDate
)
FROM base
ORDER BY OrderID, OrderItem, Period;

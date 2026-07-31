-- 044_sap_period_lock_and_payment_date_clamp.sql
-- RULE-01 / RULE-02 / RULE-08, Boat confirmed 2026-07-31.
-- Source-only: do not deploy until Claude Code review passes and Boat supplies the period row.
--
-- Deployment order after approval:
--   1. Apply this file to create the control table.
--   2. Boat inserts the authoritative period values (never hardcode them here).
--   3. Re-apply 037_fix_expected_invoice_no_null_unsafe.sql, whose current procedure definition
--      reads this table, clamps expected_payment_date, and emits payment_date_clamped.
--
-- CareOS remains the original payment-date source. No payment_date_original copy is stored.

CREATE TABLE IF NOT EXISTS `pacific-plating-282708.sap_integration_v3.sap_period_lock` (
  period STRING NOT NULL,
  open_period_start DATE NOT NULL,
  lock_datetime TIMESTAMP NOT NULL,
  locked_by STRING,
  locked_at TIMESTAMP
)
CLUSTER BY period;

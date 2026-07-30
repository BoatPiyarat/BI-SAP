-- 041_pilot_shadow_corrections_L80046687_L79900064.sql
-- Boat D15 (2026-07-30): pilot authority resolved to L80046687 (Class 1) + L79900064 (Class 2),
-- superseding 0a69143's L79871659 + L80524847 pair (L79871659 too close to noise floor,
-- L80524847 kept as a permanent known-answer test instead of a pilot, per its blast radius).
-- SOURCE ONLY. Nothing in this file has been run against BigQuery. `sap_correction_log` does not
-- exist yet (see 039). Do not run until ALL of the following are true:
--   1. `sap_correction_log` deployed (039).
--   2. `fn_mint_adj_invoice` deployed (038) and re-verified live, not just unit-tested on paper.
--   3. Real `sap_accounting_cutoff_dates` exists (still Finance-pending, placeholder below).
--   4. The generating bug (040, Option A) is actually fixed and deployed - D15 item 3's explicit
--      condition: sending either pilot before the bug is fixed risks the exact scenario Boat has
--      repeatedly flagged, the bug regenerating the same case the same night it's corrected.
--   5. Full validation pass + shadow run, then REVIEW_QUEUE class A, then explicit deploy OK.
--
-- Full detail and derivation for both cases: docs/FINDINGS_CREDITSHELL_DUPLICATE_20260729.md,
-- "ADDENDUM 2026-07-29 (session, D14)" (case selection, invoice-collision checks) and "ADDENDUM
-- 2026-07-30 (session, D15)" (pilot authority resolution).

/*
-- Pilot 1: L80046687 (Class 1, AMOUNT_VARIANCE), net_delta = +50.00, PolicyDate 28042026
-- Single mismatching key: L80046687-V1 Period 1 (Expected 1150.00 -> Actual 1200.00, no
-- duplication). Periods 2-6 clean. Invoice check: 6 existing invoices on this order, none
-- ADJ-prefixed - ADJ1_L80046687-V1 is collision-free.
INSERT INTO `pacific-plating-282708.sap_integration_v3.sap_correction_log`
  (order_item, period, bucket, method, original_expected_received, original_actual_received,
   correction_expected_received, correction_actual_received, correction_invoice_no,
   correction_payment_date, audit_case_id, status, created_at)
VALUES
  ('L80046687-V1', 1, 'B1', 'METHOD_1',
   1150.00, 1200.00,
   0.00, -50.00,
   'ADJ1_L80046687-V1',
   -- <<< PLACEHOLDER: next open accounting period from sap_accounting_cutoff_dates (does not
   -- exist yet - Finance-pending). Do not hardcode a real date here before that table exists.
   NULL,
   'D15-PILOT-CLASS1-L80046687', 'DRAFTED', CURRENT_TIMESTAMP());

-- Pilot 2: L79900064 (Class 2, MISPOSTING), net_delta = 0.00, gross_delta = 1290.42,
-- PolicyDate 13032026. Two mismatching keys, both Period 1, both duplicated 645.21/645.21 (M1) and
-- -644.82 / 1969.14 (V1) against a shared true Expected of 1969.53 for V1. Invoice check: 9
-- existing invoices on this order, none ADJ-prefixed.
-- ⚠️ This pilot's result MUST be shown to Aware/FA after import - it is the evidence case for
-- whether an adjustment line actually corrects GL misposting, or whether SAP needs a manual fix.
INSERT INTO `pacific-plating-282708.sap_integration_v3.sap_correction_log`
  (order_item, period, bucket, method, original_expected_received, original_actual_received,
   correction_expected_received, correction_actual_received, correction_invoice_no,
   correction_payment_date, audit_case_id, status, created_at)
VALUES
  ('L79900064-M1', 1, 'CLASS2_MISPOSTING', 'METHOD_1',
   645.21, 1935.63,                                            -- sum_actual across the 3 real rows (see D14 worked example)
   0.00, -645.21,
   'ADJ1_L79900064-M1',
   NULL,                                                       -- same cutoff-date placeholder as above
   'D15-PILOT-CLASS2-L79900064', 'DRAFTED', CURRENT_TIMESTAMP()),
  ('L79900064-V1', 1, 'CLASS2_MISPOSTING', 'METHOD_1',
   1969.53, 1324.32,                                           -- -644.82 + 1969.14, per the actual rows
   0.00, 645.21,
   'ADJ1_L79900064-V1',
   NULL,
   'D15-PILOT-CLASS2-L79900064', 'DRAFTED', CURRENT_TIMESTAMP());
*/

-- Post-correction check (to run once shadow-validated, NOT yet run):
-- for each order above, SUM(ActualReceived) per corrected key must equal that key's true
-- ExpectedReceived exactly, and SUM(key-level net) per order must equal the pre-correction
-- net_delta minus itself (i.e. become exactly 0 for L79900064; L80046687 has only one item so its
-- own corrected key alone reaching 0 is the whole check).

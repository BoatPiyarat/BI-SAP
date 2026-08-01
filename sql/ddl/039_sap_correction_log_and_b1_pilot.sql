-- 039_sap_correction_log_and_b1_pilot.sql
-- Boat D11 follow-up (2026-07-30), pre-D16 symptom-based B1 pilot prep. SOURCE ONLY. NOT DEPLOYED.
-- This historical artifact does not define INCIDENT-002a or INCIDENT-002b and must not combine
-- their populations. See docs/FINDINGS_D16_002A_POPULATION_SPLIT_20260801.md.
-- Nothing in this file has been run against BigQuery; no correction file has been sent to SAP.
--
-- ⚠️ SUPERSEDED 2026-07-29 (same-day, later): D13 set the materiality buffer at ฿10 PER ORDER (not
-- per row/period). The 5-case pilot draft below (deltas ฿1.07-7.68) is now BELOW that threshold and
-- is NOT a valid pilot anymore. New pilot selection, order-level Class 1 (AMOUNT_VARIANCE), smallest
-- qualifying 2026+ order: L79871659 (net_delta +11.27, single OrderItem, no duplication, only
-- Period 1 mismatches). See docs/FINDINGS_CREDITSHELL_DUPLICATE_20260729.md
-- "ADDENDUM 2026-07-29 (session, D13)" for the corrected Class 1/2 quantification, the query used,
-- and this new pilot's full detail. `sap_correction_log`'s schema below is unaffected by this
-- correction and remains the intended design.
--
-- ⚠️ SUPERSEDED AGAIN 2026-07-29 (same session, D14): Boat rejected L79871659 too - too close to
-- the noise floor. D14 also splits treatment: Class 2 (MISPOSTING) is fixable directly via Method 1
-- (no naming/alias blocker at all), so it gets its own pilot rather than waiting behind Class 1.
-- TWO pilots now, both still source-only / not sent:
--   - Class 1 (AMOUNT_VARIANCE): L80046687 (net_delta +50.00, single key L80046687-V1 Period 1,
--     Expected 1150.00 -> Actual 1200.00, correction Expected=0/Actual=-50.00).
--   - Class 2 (MISPOSTING): L79900064 (net_delta 0.00, gross 1290.42, two keys: L79900064-M1 P1
--     key_delta +645.21 -> correction Actual=-645.21; L79900064-V1 P1 key_delta -645.21 ->
--     correction Actual=+645.21). This one must go to Aware/FA for a post-import GL review - it is
--     also the evidence case for the open "does an adjustment line fix GL misposting" question.
-- See docs/FINDINGS_CREDITSHELL_DUPLICATE_20260729.md "ADDENDUM 2026-07-29 (session, D14)" for full
-- detail, the Method 1 proof for Class 2, and everything still outstanding before either is sent.
--
-- ⚠️ CONFLICT (2026-07-30) - RESOLVED by Boat, D15: commit 0a69143's pilot pair (L79871659 +
-- L80524847) is superseded. Authoritative pilots are THIS file's pair, L80046687 (Class 1) +
-- L79900064 (Class 2) - L79871659 stays rejected (too close to noise floor), L80524847 is kept as
-- a permanent known-answer test rather than used as a pilot (too high a blast radius). Shadow-only
-- correction rows for both authoritative pilots are drafted in
-- sql/ddl/041_pilot_shadow_corrections_L80046687_L79900064.sql - still not sent, still gated on the
-- generating-bug fix (040) landing first, per D15 item 3.
--
-- ============================================================================
-- B1 quantification - CORRECTED SCOPE (important methodology note)
-- ============================================================================
-- First attempt scoped B1 as "not-B2, not-B3" WITHIN the 1,247 duplicated (OrderItem,Period) pairs
-- from commit 73e94e0 - that gave 547 candidate pairs, but ALL 547 turned out to be both-row-NULL
-- placeholder periods (unpaid future installments caught by the duplication, carrying zero real
-- money) - verified by sampling 5 pairs directly, all 10 rows NULL/NULL. So the real B1 population
-- is NOT inside the duplicated-pairs set at all.
--
-- Broadened to single-row (n_rows = 1) records in the same live view
-- (`sap_integration_v2.RCL 04_new order credit shell`) where ExpectedReceived/ActualReceived are
-- both real (non-NULL) and differ. First pass caught trivial ±0.01 THB satang-rounding noise
-- (sampled the smallest deltas, saw exactly this) - added an ABS(delta) > 1.00 THB floor to exclude
-- rounding, not the incident. Cross-checked the remaining rows against
-- `careos.cancelled_change_orders` (either side) to confirm they are genuinely credit-shell related,
-- not an unrelated mismatch source: **100% match (289 of 289)**.
--
-- B1 (verified, live, 2026-07-30):
--   289 real cases, Σ net delta = +85,106.84 THB (ActualReceived - ExpectedReceived, i.e. mostly
--   over-received - correction rows will mostly need a NEGATIVE ActualReceived adjustment)
--   Year split: <=2024: 0 | 2025: 5 | 2026+: 284
--   Overlap with B3 (already Cancelled in SAP): 0 of 289
--   min |delta| = 1.07 THB, max |delta| = 4,316.42 THB
--
-- Quantification query (single job, dry-run first, 7,470,424,864 bytes upper bound per initial
-- dry-run of the broader scan):
--
-- WITH base AS (
--   SELECT OrderItem, Period, OrderID, PolicyDate, ExpectedReceived, ActualReceived,
--     COUNT(*) OVER (PARTITION BY OrderItem, Period) AS n_rows
--   FROM `pacific-plating-282708.sap_integration_v2.RCL 04_new order credit shell`
-- ),
-- single AS (
--   SELECT * FROM base WHERE n_rows = 1
--     AND ExpectedReceived IS NOT NULL AND ActualReceived IS NOT NULL
--     AND ABS(ROUND(ActualReceived - ExpectedReceived,2)) > 1.00
-- ),
-- change_ids AS (
--   SELECT current_human_id AS id FROM `careos.cancelled_change_orders`
--   UNION DISTINCT SELECT old_human_id FROM `careos.cancelled_change_orders`
-- ),
-- mirror AS (
--   SELECT U_OrderItem, U_Period, TransactionStatus FROM `sap_integration_v3.sap_mirror_state`
-- )
-- SELECT s.*, m.TransactionStatus
-- FROM single s JOIN change_ids c ON c.id = s.OrderID
-- LEFT JOIN mirror m ON m.U_OrderItem = s.OrderItem AND m.U_Period = s.Period
-- WHERE m.TransactionStatus NOT IN ('Cancelled', 'Cancelled (Change order / Rejected)')
--
-- ============================================================================
-- ⚠️ GAP FOUND: `sap_accounting_cutoff_dates` does not exist anywhere in this project
-- ============================================================================
-- Checked `sap_integration_v3`, `sap_integration_v2`, `sap_data_engineer`, `SAP` - no table by this
-- or a similar name exists. `10_SAP_CONTEXT.md` references it ("cutoff จาก
-- sap_accounting_cutoff_dates - Finance confirm รายเดือน, ห้าม hardcode") as if it's meant to exist,
-- but nothing has been built. Existing pipeline code (`sql/production/sap_dashboard_carepay_fully_paid.sql`,
-- the PaymentDate CASE block) uses an inline rollover rule instead: if the batch/charge date's month
-- is already closed (with a 3-day grace period past month-end), roll forward to the first day of
-- the current month; otherwise use the real date. **Using that same existing pattern below as a
-- stand-in**, explicitly flagged - this is NOT sourced from a real cutoff-dates reference table
-- (none exists) and needs Finance/Boat confirmation, same open question already on record.

-- ----------------------------------------------------------------------------
-- sap_correction_log: the one place every incident (and future) manual/semi-manual money
-- correction gets recorded, regardless of bucket or method - so nothing is ever a correction that
-- exists only inside a chat message or a one-off query result.
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `pacific-plating-282708.sap_integration_v3.sap_correction_log` (
  order_item STRING,
  period INT64,
  bucket STRING,               -- 'B1' | 'B2' | 'B3' (per docs/AUDIT_CMI_ADDONS.md)
  method STRING,                -- 'METHOD_1' | 'METHOD_2' | 'AWARE_MANUAL'
  original_expected_received NUMERIC,
  original_actual_received NUMERIC,
  correction_expected_received NUMERIC,  -- 0 for Method 1
  correction_actual_received NUMERIC,    -- signed delta for Method 1
  correction_invoice_no STRING,          -- from fn_mint_adj_invoice for Method 1/2
  correction_payment_date DATE,
  audit_case_id STRING,          -- ties to docs/AUDIT_CMI_ADDONS.md / FINDINGS case list
  status STRING,                 -- 'DRAFTED' | 'SHADOW_VALIDATED' | 'SENT' | 'ACKED' | 'REJECTED'
  created_at TIMESTAMP
)
CLUSTER BY order_item;

-- ----------------------------------------------------------------------------
-- B1 pilot draft: 5 smallest-|delta| 2026+ cases. NOT SENT. NOT INSERTED anywhere yet - this
-- SELECT is the proposed row content for review, computed directly, matching Boat's spec:
-- ExpectedReceived=0, ActualReceived=-delta (these 5 are all over-received, so all 5 corrections
-- are negative), InvoiceNo via fn_mint_adj_invoice (038, also source-only), PaymentDate via the
-- flagged stand-in rollover rule (see gap note above).
-- ----------------------------------------------------------------------------
-- SELECT
--   OrderItem, Period, ExpectedReceived AS original_expected, ActualReceived AS original_actual,
--   0 AS correction_expected,
--   ROUND(-(ActualReceived - ExpectedReceived), 2) AS correction_actual,
--   CONCAT('ADJ1_', OrderItem) AS correction_invoice_no,  -- verified: 0 prior ADJ invoices on all 5 orders
--   'HISTORICAL_PRE_D16_B1' AS audit_case_id
-- FROM (the 5 cases below)
--
-- | OrderItem      | Period | Expected | Actual  | delta | correction_actual | sap_invoice_no (existing) | sap_status |
-- |----------------|-------:|---------:|--------:|------:|------------------:|---------------------------|------------|
-- | L79623257-V1   |      1 |  2787.10 | 2788.17 |  1.07 |             -1.07 | 2_chrg_66m1qcj24rxpbk8k61p | Paid       |
-- | L80418400-V1   |      1 |  1466.88 | 1469.88 |  3.00 |             -3.00 | 2_chrg_67oo9oltfcix21cfiuz | Paid       |
-- | L79811482-V1   |      1 |  2144.45 | 2147.80 |  3.35 |             -3.35 | 2_chrg_66u7ahm1p7y5l2k86py | Paid       |
-- | L79561464-V1   |      1 |  1625.08 | 1629.08 |  4.00 |             -4.00 | 2_chrg_66fapqwgmbn8bldhj0p | Paid       |
-- | L79449530-V1   |      1 |  1778.33 | 1786.01 |  7.68 |             -7.68 | 2_chrg_66023ezffh9e55rj9b7 | Paid       |
--
-- Invoice-collision check (per order, via sap_mirror_doc, matching 038's fn_mint_adj_invoice logic):
-- all 5 orders' existing invoice lists checked directly - none contain any `ADJ\d+_` prefixed value,
-- so n=1 (`ADJ1_<OrderItem>`) is correct and collision-free for all 5.
--
-- Still needed before this pilot can move to shadow (per Boat's own sequencing - validate, shadow,
-- REVIEW_QUEUE class A, wait for deploy OK - NONE of these done yet):
--   1. Real `sap_accounting_cutoff_dates`-equivalent confirmed by Finance/Boat (using the stand-in
--      rollover rule above only as a placeholder for this draft).
--   2. `sap_correction_log` deployed (source-only above).
--   3. `fn_mint_adj_invoice` deployed (038, source-only) and re-verified live for these 5 real orders.
--   4. Run the existing validation set (`sp_run_validation` checks) against these 5 draft rows.
--   5. Build the actual shadow file/table, diff, THEN queue for review - not done.

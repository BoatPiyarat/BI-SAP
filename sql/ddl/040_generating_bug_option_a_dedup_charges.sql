-- 040_generating_bug_option_a_dedup_charges.sql
-- Boat D15 (2026-07-30), INCIDENT-002b credit-shell generating-bug fix, Option A (approved direction, NOT approved
-- to deploy). SOURCE ONLY. Nothing in this file has been run to CREATE OR REPLACE anything; the live
-- `sap_integration_v2.\`RCL 04_new order credit shell\`` view is untouched.
--
-- ============================================================================
-- Root cause (confirmed, D13/D14): `careos.carepay_charges` allows multiple
-- SUCCESSFUL charges to share one (transaction_id, installment_number) pair.
-- The live view's `spine_with_payment` CTE joins:
--   LEFT JOIN charges c ON c.transaction_id = s.transaction_id AND c.installment_number = s.Period
-- with no dedup/aggregation, so one period-spine row fans into N output rows
-- whenever N charges share that key - each one independently re-applying the
-- Period-1 `add_ons` deduction as if it were the sole authoritative row.
-- ============================================================================
--
-- Option A: fix the join input, not the join shape. Aggregate `charges` down to
-- one row per (transaction_id, installment_number) BEFORE the join, summing the
-- real money (multiple genuine charges for one period are legitimate - e.g. an
-- initial charge plus a later top-up - and both should count), while picking a
-- single deterministic value for the fields that must not be duplicated
-- (invoice number, payment method, service provider, timestamp).
--
-- ⚠️ OPEN DECISION (not mine to make - flag for Boat/Aware, do not hardcode a
-- silent choice): when N charges share a key, which one's `third_party_id`
-- becomes the row's InvoiceNo? This file picks "most recent charge by
-- update_time" as a placeholder (ARRAY_AGG ... ORDER BY update_time DESC), but
-- that is a business decision (should it be the FIRST charge's invoice, since
-- that's usually the one SAP already has on file? or the LAST, since that's the
-- most recent money movement?) - confirm before this ever ships.
--
-- charges_dedup replaces the raw `charges` CTE inside spine_with_payment's join.
-- Everything else in the view (spine, order_items, credit_shell_orders,
-- ancestors, invoice pool, channel resolution, final shaping) is UNCHANGED -
-- this is a single, surgical fix at the join input, not a rewrite.

/*
charges_dedup AS (
  SELECT
    transaction_id,
    installment_number,
    SUM(amount) AS amount,                                            -- real money: sum, don't drop
    ARRAY_AGG(third_party_id ORDER BY update_time DESC)[OFFSET(0)] AS third_party_id,  -- OPEN DECISION, see above
    ARRAY_AGG(payment_method ORDER BY update_time DESC)[OFFSET(0)] AS payment_method,
    ARRAY_AGG(service_provider ORDER BY update_time DESC)[OFFSET(0)] AS service_provider,
    MAX(update_time) AS update_time,
    COUNT(*) AS n_charges_in_period                                    -- diagnostic only, drop before final SELECT
  FROM `pacific-plating-282708.careos.carepay_charges`
  WHERE status = 'SUCCESSFUL'
  GROUP BY transaction_id, installment_number
),

-- spine_with_payment, patched: replace
--   LEFT JOIN charges c ON c.transaction_id = s.transaction_id AND c.installment_number = s.Period
-- with
--   LEFT JOIN charges_dedup c ON c.transaction_id = s.transaction_id AND c.installment_number = s.Period
-- (column names on `c` are otherwise identical: third_party_id, amount, payment_method,
--  service_provider, update_time - so every downstream reference in the view's existing SQL
--  - charge_invoice_no, charge_status, charge_amount, charge_payment_method,
--  charge_service_provider, charge_payment_date - needs zero changes beyond the join source swap,
--  EXCEPT `charge_status`: charges_dedup has no per-row `status` column since it's pre-filtered to
--  SUCCESSFUL only in the WHERE clause above - `charge_status` becomes a derived boolean
--  (`c.transaction_id IS NOT NULL` implies at least one SUCCESSFUL charge existed for this key,
--  equivalent to the original `c.status = 'SUCCESSFUL'` check once pre-filtered upstream).
*/

-- ⚠️ ASSUMPTION FLAGGED, NOT VERIFIED: this fix assumes
-- `transaction_snapshot_installment_details` (joined separately, ON snapshot_id + period) is
-- already 1-row-per-(snapshot_id, period) - i.e. NOT itself a second fanout source. Not checked
-- in this session. Must be confirmed before Option A is trusted to fully close the bug, since a
-- second fanout source there would survive this fix untouched.

-- ============================================================================
-- 3-stage validation plan (NONE of these steps have been run - proposal only)
-- ============================================================================
-- Stage 1 - shadow view, not a replace:
--   CREATE OR REPLACE VIEW `sap_integration_v2.rcl_04_new_order_credit_shell_v2fix_shadow` AS
--   <the live view's full query, with ONLY the charges CTE swapped for charges_dedup as above>
--   Never touches the real object; safe to create/drop freely.
--
-- Stage 2 - row/distribution diff, shadow vs. live:
--   (a) row counts: COUNT(*) FROM live vs. COUNT(*) FROM shadow - shadow should be STRICTLY <=
--       live (dedup can only remove rows, never add them), with the gap explained exactly by the
--       known duplicate-key count (700ish keys per the D14 fresh re-run).
--   (b) per-(OrderItem, Period) distribution: FULL OUTER JOIN live vs. shadow on
--       (OrderItem, Period), diff on ExpectedReceived/ActualReceived - every row where they now
--       differ should be explainable as "this key had >1 charge in the live view, now correctly
--       aggregated" - any unexplained diff is a red flag, not proceed.
--   (c) 5 concrete samples: L80524847 (the Class-2 known-answer case), L79900064 and L80046687
--       (the two pilots), plus 2 more duplicate-key cases NOT already used as known-answer tests -
--       eyeball every field, not just Expected/Actual.
--
-- Stage 3 - schema ordinal diff:
--   SELECT column_name, ordinal_position FROM `sap_integration_v2.INFORMATION_SCHEMA.COLUMNS`
--   WHERE table_name IN ('RCL 04_new order credit shell', 'rcl_04_new_order_credit_shell_v2fix_shadow')
--   ORDER BY table_name, ordinal_position
--   - must match EXACTLY (same columns, same order, same types) before this is even a candidate
--   for a real swap-in, since `sap_view.RCL_Motor_process_4_creditshell` and any other consumer
--   does `SELECT *` and depends on column order implicitly.
--
-- Only after all 3 stages pass clean does this go to REVIEW_QUEUE as a class-A deploy request.
-- Deploy itself (CREATE OR REPLACE on the real object, under the DDL-location exception this
-- needs) requires Boat's separate, explicit sign-off - "approved the approach, not the deploy"
-- per D15.
--
-- ⚠️ STREAM 2 CHECK (per D15 item 2's explicit ask - does this same fix apply to
-- `sap_data_engineer.sap_dashboard_carepay_fully_paid`?): NO. Confirmed by pulling that view's own
-- definition - its duplication mechanism is structurally different (see
-- docs/FINDINGS_CREDITSHELL_DUPLICATE_20260729.md "ADDENDUM 2026-07-30 (session, D15)" for detail):
-- `onetime_master` there fans `order_items` against `charges` via a shared `transaction_id` with a
-- `charge_rank` (ROW_NUMBER by create_time) instead of an installment-number join, and deliberately
-- zeroes ExpectedReceived for every charge_rank other than 1 (by design, not a bug) to avoid
-- double-counting Expected across a real item's own follow-up charges. This fix (dedup by
-- transaction_id + installment_number, sum amount) does NOT transfer - stream 2 needs its own,
-- separate fix design, not started in this file.

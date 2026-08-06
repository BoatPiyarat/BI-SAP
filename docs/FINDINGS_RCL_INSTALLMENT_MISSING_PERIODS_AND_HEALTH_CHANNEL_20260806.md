# Findings + drafted fix — RCL installment missing periods & CI/Health channel mislabel, 2026-08-06

**Status: fix drafted and applied to the repo copy only. NOT yet re-verified against live
BigQuery, NOT yet pushed back to the live `sap_data_engineer.sap_dashboard_carepay_installment`
view.** BigQuery CLI auth (`data@rabbit.co.th` and `piyaratt@rabbit.co.th`) could not be
refreshed non-interactively in the session that produced this fix, so nothing below has been
run against real data. Treat every claim here as a code-read diagnosis pending confirmation.

File touched: `sql/production/sap_dashboard_carepay_installment.sql`. See its top-of-file
changelog (06/Aug/2026 entry) for the same summary inline with the query.

## Item 1 — `L77833033-V1` shows only period 1 of 6

**Root cause:** in `rcl_voluntary_installment_details`, `charges` is pre-filtered to
`status = 'SUCCESSFUL'` only, then `LEFT JOIN`ed per period (correctly — unpaid periods should
still produce a row with `charges.*` NULL). But the CTE's outer `WHERE` clause included
`AND charges.service_provider = 'RABBIT_LENDING'`, evaluated against the *joined* (nullable)
table. For any period without a successful charge yet, `charges.*` is NULL, so that condition is
NULL (not TRUE), and BigQuery drops the row — silently turning the LEFT JOIN into an INNER JOIN.
For a 6-installment order with only period 1 paid so far, periods 2–6 were dropped.

**Same pattern found live in this file but not in what was tested at the console:** the WHERE
clause also had `AND (follow_ups.transaction_id IS NOT NULL)` active — identical mechanism,
would also drop any period without a `follow_ups` row yet. The version tested/pasted at the
BigQuery console during this investigation already had this line commented out, but the repo
copy still had it live. Re-commented it here so the repo matches the tested state.

**Fix applied:**
- Moved `AND charges.service_provider = 'RABBIT_LENDING'` from the `WHERE` clause into the
  `charges` `LEFT JOIN ... ON` clause.
- Re-commented `AND (follow_ups.transaction_id IS NOT NULL)` in the same `WHERE` clause.
- `ActualReceived` now has an explicit `WHEN charge_rank IS NULL THEN 0` branch (previously fell
  through to `ELSE ... COALESCE(charges.amount, transaction_snapshot_installment_details.payment_amount)`,
  which would have shown the *expected* amount as *actually received* for periods with no charge
  at all, once the join stopped dropping them).

**Verification still needed:** re-run the query filtered to `OrderItem = 'L77833033-V1'` and
confirm 6 rows come back (was 1), with periods 2–6 showing `TransactionStatus = 'Pending'` and
`ActualReceived = 0` rather than being absent.

## Item 2 — Root Cause 8: CI Order Health orders imported with wrong payment channel

Reported by Piyarat: CI/Health orders that had already imported periods 1–N as
`RCL-Omise QR Prompt Pay-Health` got a later period imported as `RCL-Omise QR Prompt Pay-BAY`
instead. ~350 affected `OrderID` + period pairs supplied (not reproduced in this doc — see chat
log / original list).

**Root cause:** the `PaymentChannel` `CASE` expression in `transformation` has a Motor-compulsory
special case (`InsuranceType = 'MOTOR_TYPE_COMPULSORY' THEN 'RCL-CMI-channel'`) but nothing
equivalent for non-motor (Health/CI) products. Any QR_CODE charge with
`service_provider = 'RABBIT_LENDING'` falls into the generic branch and is force-mapped to
`'RCL-Omise QR Prompt Pay-BAY'`, regardless of product line. `'RCL-Omise QR Prompt Pay-Health'`
does not appear anywhere else in the query — it can only reach the report via the final
`ELSE PaymentChannel` passthrough of the raw `charges.service_provider` value. This means whichever
periods showed "Health" got there because their charge's raw `service_provider` differed from
`'RABBIT_LENDING'`; once a later installment's charge came through tagged `RABBIT_LENDING`
(e.g. an auto-debited retry on a generic gateway), it hit the hardcoded BAY branch instead.

Confirmed with Piyarat: CI/Health products are identified by
`order_items.product != 'products/car-insurance'` (i.e. `InsuranceGroup` in this query).

**Fix applied:** added
`WHEN InsuranceGroup != 'products/car-insurance' AND PaymentMethod = 'QR_CODE' THEN 'RCL-Omise QR Prompt Pay-Health'`
immediately after the Motor-compulsory branch and before the generic
`PaymentMethod = 'QR_CODE' AND PaymentChannel = 'RABBIT_LENDING' THEN 'RCL-Omise QR Prompt Pay-BAY'`
branch, so non-motor QR payments keep a stable "Health" label regardless of which underlying
gateway processed that specific installment.

**Verification still needed:**
- Diagnostic query against `carepay_charges` for a handful of the ~350 affected orders, to
  confirm `service_provider` really does flip from a Health-specific value to `RABBIT_LENDING`
  partway through the plan (confirms this is a reporting-mapping gap, not something else).
- Re-run the full query and confirm all affected `OrderID`/period rows now show
  `RCL-Omise QR Prompt Pay-Health` consistently across all periods.
- Confirm `InsuranceGroup != 'products/car-insurance'` doesn't misclassify any motor product that
  isn't tagged `MOTOR_TYPE_COMPULSORY` but also isn't `products/car-insurance` (e.g. motorbike —
  check `order_items.product` values used for `MotorBike` orders before deploying).

## Next steps

1. Get a working BigQuery credential (interactive `gcloud auth login` on either
   `data@rabbit.co.th` or `piyaratt@rabbit.co.th`) and run the two verification queries above.
2. If both check out, push this query text to the live view
   `sap_data_engineer.sap_dashboard_carepay_installment` (this repo file is a baseline capture,
   not the live definition — see the file's own top-of-file warning).
3. Re-file this as a dated changelog entry in `docs/knowledge/30_SAP_CHANGELOG.md` once deployed
   (existing convention referenced at the top of the SQL file).

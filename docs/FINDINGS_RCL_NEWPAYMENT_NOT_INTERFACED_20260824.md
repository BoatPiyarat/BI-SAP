# FINDINGS: RCL new-period payments not interfacing to SAP — 2026-08-24

Reported by: Boat (via chat), 43 (order_id, period) pairs pasted directly, all described "not on
SAP". Investigated read-only by Claude Code. No correction, deploy, or mutation performed.
Verification script: `sql/adhoc/20260824_verify_rcl_newpayment_missing_from_sap.sql`.

## Headline finding

**39 of 43 reported items (91%) have a completely clean, paid, complete-spine candidate row ready
to export — and their own Period 1 (the order's first payment) already reached SAP successfully.
Only the ongoing Period 2+ payment is missing.** This is not a data-quality problem in these 39
cases; it is a delivery/export gap specific to *subsequent* RCL installment periods.

Evidence: live query (job captured in `sql/adhoc/20260824_verify_rcl_newpayment_missing_from_sap.sql`'s
run) against `sap_data_engineer.sap_dashboard_carepay_installment` shows all 39 have
`TransactionStatus='paid'`, a real `InvoiceNo`, an 8-digit `PaymentDate`, and a complete
`1..TotalPeriods` schedule spine (`sap_integration_v3.stg_schedule`) — nothing about the source
data explains their absence. A separate check confirms **Period 1 for all 39 is already present**
in `sap_integration_v3.stg_sap_state` (i.e. already live in SAP) — so these are not orders SAP has
never heard of; SAP has the order, just not its second-and-later payments.

## Breakdown of all 43 reported pairs

| Diagnosis | Count | Meaning |
|---|---|---|
| `CANDIDATE_LOOKS_CLEAN_BUT_NOT_IN_SAP` | 39 | Clean, paid, complete-spine row exists; simply never delivered. **The real gap.** |
| `FAILED_VALIDATION` | 1 | `L78322384-V1` period 4 — flagged by existing rule `POLICYNO_TOO_LONG`. Working as intended, a different (known) issue, not part of the systemic gap. |
| `NO_STG_PAYMENT_EVENT_FOR_THIS_ORDER_PERIOD` | 2 | `L79361881` period 3, `L79770471` period 4 — no matching row in `stg_payment_events` at all for that exact (order_id, period). Needs the source report re-checked for a typo, or these orders investigated separately; not folded into the 39. |
| `PERIOD_NOT_IN_SCHEDULE` | 1 | `L78710141-V1` period 2 — has a real paid candidate row in the dashboard view, but `stg_schedule` has no period-2 entry for this item. A schedule/source discrepancy distinct from the main 39; flagged for separate follow-up, not folded in. |

## Why this matters right now

This population — RCL Motor **ongoing/subsequent-period** payments failing to interface while the
order's first payment succeeds — is very likely the concrete shape behind Boat's same-day
instruction to stop V2 and push V3 (`docs/INPUTS_NEEDED.md`, "URGENT OPEN 2026-08-24" entry) and
matches exactly what Codex is independently building toward in
`RQ-20260824-1217-v3-normal-rcl-motor-newpayment` (commit `5afb5ff`, "qualify ordinary RCL motor
newpayment") — a new V3 Unit-5 qualifier for precisely this case type. That artifact's own
population (555 identities / 552 items in a stale preview run) has not yet been cross-checked
against these 43 specific reported items; doing so is the natural next step once Codex's artifact
is reviewed.

## What has NOT been done

No root-cause trace into *why* the legacy V2 generator drops period-2+ RCL rows while keeping
period-1 rows (e.g. reading the live production RCL "new payment" generator SQL line by line) has
been performed yet — this findings doc stops at "the gap is real, it's period-2+-specific, and the
source data for the missing rows is clean," which is enough to confirm the shape of the problem
without yet pinning the exact defective line. No backfill, correction, or export has been proposed
or performed. No BigQuery mutation, GCS write, or SAP action occurred during this investigation.

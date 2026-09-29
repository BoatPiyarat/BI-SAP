## Deployment update — 2026-09-29

User confirmed September 2026 open, NULLs retained, production view deployment approved, interface-file generation cancelled. Independent review updated to scoped deployment PASS; hashes unchanged.

Deployed via guarded dry-run + execution:
- trigger: bqjob_rd46ee18fca78a84_000001a0ec13cdc4_1
- newpayment: bqjob_r88272caa07f17dc_000001a0ec14049c_1
- holds: bqjob_r1d758d541e8a8985_000001a0ec143b2e_1

All deployed definitions match reviewed source. Existing trigger 15-column and newpayment 56-column name/type/order schemas unchanged. No CSV/GCS export, period-table change, or scheduler mutation. The previous BLOCK sections below are historical and superseded for this scoped view deployment.

# NonMotor missing-period recovery — 2026-09-29

Status: SQL implemented and regression verified; production deployment BLOCKED; interface preflight BLOCKED. No production view replacement, interface CSV, GCS delivery, or scheduler change performed.

## Authorization and scope

Boat explicitly requested production view changes to support gaps before the highest Paid period and an interface generation test. This authorizes the two scoped legacy replacements despite the older general v3-only development rule. It does not waive the canonical pre-export gate or authorize pausing schedules.

## Files

- sql/production/RCL_NonMotor_paid_period_gap_trigger_20260929.sql: SUCCESSFUL charge eligibility per transaction+period; compare SAP Paid by OrderItem+Period; terminal Cancelled guard. The charge rank selects an eligibility timestamp only, not exported amounts.
- sql/production/RCL_NonMotor_newpayment_period_gap_20260929.sql: preserve existing SAP Paid periods; use RCL_HEALTH for periods with no SAP Paid; remove max-period cutoff; explicit Paid/Pending literals; full-item spine checks. Existing amount and date formulas unchanged.
- sql/production/RCL_NonMotor_newpayment_period_gap_holds_20260929.sql: same raw candidate logic, explicit reason for invalid/duplicate/incomplete spines. Intended new persistent diagnostic view sap_integration_v3.vw_rcl_nonmotor_newpayment_period_gap_holds (not deployed).
- scripts/verify_nonmotor_period_gap_20260929.py: reproducible immutable evidence verification and target export preflight.

## Evidence

Local evidence: outputs/sap_period_gap_fix_20260929 in Motor Commission Engine workspace. No PII payloads committed.

Fresh test objects (7-day expiration): sap_integration_v3.diag_nonmotor_gap_trigger_20260929, diag_nonmotor_gap_newpayment_20260929, diag_nonmotor_gap_comparison_20260929. Comparison table captured at 2026-09-29 02:55:39 UTC: before 486 rows/81 items, raw candidate 1368 rows/176 items, 105 added items and 10 removed terminal-cancel items. Initial raw candidate had 47 incomplete/duplicate spines.

Final staged query read: job bqjob_r2a938fdc486bf28f_000001a0ebc64d46_1; dryrun 9,873,277,104 bytes. 1,145 rows / 129 items, zero incomplete/duplicate spines. No arbitrary duplicate winner introduced. 159 before-Paid rows retained on surviving items preserve InvoiceNo and ActualReceived. 56 column names/types match production and canonical ordinal positions. Final source identity recorded in schema_validation.json.

Targets: L79180940-1 has periods1..8, Paid1..6 including recovered period5; Pending7..8. L79949677-1 has periods1..10, Paid1..4, Pending5..10. 18 total rows. Target successful charge amounts and fn_invoice_no results match; historical SAP Paid invoices/amounts match. This is candidate verification, not proof of SAP import.

## Interface test result and deployment block

Preflight on exact release_rows.json SHA256 9270c55d5782e5c9f29b918a839858d7e3e16b1e2e7d3d30939917ba539e46af: BLOCK. 56 target field occurrences contain NULL across EndorsementNo, ChassisNo, LicensePlate, RefOrder, BillingAddress, plus one missing September-period control issue (57 issues). No unsupported blank/default mapping applied. No interface CSV written. Further canonical checks must complete after these blockers are resolved.

The live sap_period_lock contains July locked and August locked_at=NULL with lock_datetime 2026-09-01T09:00:00Z; no September row. Candidate retains legacy September PaymentDate clamping. A date policy/control resolution is required.

Live scheduler sap-order-payment-non-motor is ENABLED; topic non-motor-order-payment-sap-interface matches live function rcb-nonmotor-order-payment-sap-bucket-1 eventTrigger. Existing repository docs describe direct legacy view export; enforcement of the canonical gate by that live exporter was not established. Thus deploying this widened candidate while file preflight is blocked is not isolated from automatic delivery. No schedule paused without user instruction.

Independent Class A review: SQL logic/evidence reviewed, deployment remains BLOCK pending gate resolution or approved containment. Review file copied under docs/reviews.

## Next required input

1. Confirm September accounting date policy and appropriate period-control update. Do not infer month approval from elapsed time.
2. Resolve NULL fields against NonMotor import contract (especially BillingAddress); no invented business values.
3. If staging production changes before release checks complete is required, approve a specific delivery containment plan (for example a temporary pause of the NonMotor export job); view authorization alone does not authorize scheduler mutation.

## Deploy / rollback plan (not executed)

Capture definitions again and compare to before_trigger.sql / before_newpayment.sql. Complete Class A PASS. Apply trigger, companion hold diagnostic, then consumer definition through scripts/bq_safe_query.sh; preserve 56 columns. Re-read live definitions/schema and run scoped exact target/full-spine verification. Before any interface file write, all canonical pre-export checks must PASS on the same immutable rows. Payment must be accepted by SAP, refreshed to mirror, then cancel selection can become eligible.

Rollback definitions are verbatim saved in evidence folder: rollback_trigger.sql and rollback_newpayment.sql; apply consumer rollback then trigger rollback through guarded runner. No legacy schema rename/drop required.

## Repository

Clean branch fix/nonmotor-missing-periods-20260929 from origin/p0/stg-sap-state (2d7eb0f), separate worktree; original checkout has divergent/uncommitted work and was not reset/merged.

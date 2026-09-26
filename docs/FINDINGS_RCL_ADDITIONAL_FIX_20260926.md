# RCL same-installment additional receipts — 2026-09-26

Follow-up: FINDINGS_RCL_REVIEW_DELTA_20260926.md supersedes ranking/classification and final evidence.

Status: SOURCE FIX BUILT AND TESTED; NOT DEPLOYED. Draft PR, not a release approval.
Scope: dashboard, RCL 05_newpayment, and its RCL 05_paid by period eligibility dependency.
Cancellation L80517642-1, September spreadsheet reconciliation, and EDC mapping are separate pending work.

## Symptom and verified cause

The captured live dashboard filters voluntary charges to charge_rank=1. Removing only this filter is
insufficient: RCL 05_newpayment excludes the entire Paid item/period, and RCL 05_paid by period
can exclude the item again. Immutable distinct invoices must remain separate receipts.
Captured live SELECT definitions are preserved in evidence/rcl_additional_20260926/live_definitions.json.

## Source correction

- Keep all successful voluntary charges, preserving the compulsory rank filter.
- Additional rows retain ExpectedReceived=0 and actual charge amount; the add-on is not deducted again.
- Preserve normal paid-period exclusion. For positive additional receipts, use item/period/invoice
  identity and validate against a unique source receipt with a nonblank charge ID and invoice.
  A Paid or Cancelled exact invoice, or its established period-1 raw/2_ alias, suppresses replay.
- Reject missing/colliding invoice identities and tied source creation timestamps from additional routing.
  The SELECT-only identity_holds query lists their rule_code; no durable quarantine ledger was deployed.
- Reopen the paid-period item gate for an eligible unsent extra using raw charge.update_time.
  Accounting-clamped PaymentDate does not determine receipt recency.
- Carry an internal charge-rank marker through the dashboard and keep additional EIR zero at BOTH
  reconciliation stages. Removing rank filtering alone changed 71 existing EIR rows; that regression
  was corrected. The helper never appears in the public 56 columns.

## Evidence and interpretation

All results below are query candidates, NOT proof of a successful SAP import or GL posting.
The main corrected snapshot is eir_regression.json, checked 2026-09-25 17:33:26–17:33:38 UTC,
against captured SAP_LIVE_FULL and original definitions from the same investigation.

| Check | Result |
| --- | --- |
| L80570054-V1 additional period 1 | 22.04 THB, invoice 2_chrg_68ve8ufva4h1iil7wrn |
| L79109956-V1 additional period 1 | 645.21 THB, invoice 2_chrg_68w87npgw0hbvid58ho |
| Full period spines for targets | 1..10 and 1..8, plus one additional row each |
| All 56 fields, prior final-wrapper rows removed/changed | 0 |
| Final-wrapper duplicate event keys / incomplete spines / repeated nonzero expected | 0 / 0 / 0 |
| Final-wrapper population | 11,665 rows; 1,625 items; 103 additional rows including existing SAP extras |
| Added additional candidate rows | 80 across 75 items, 30,766.90 THB; not a posting/loss claim |
| Old events carried by recent item | 0 in this snapshot |
| Identity behavior fixtures | 19 cases; 0 membership failures; 0 replay rows; 0 duplicate keys |
| Raw-date fixture | Old clamped event excluded; recent raw event included |
| Physical schema | 56 columns in original order; newpayment/wrapper types match exactly |

Dashboard retains its original integer refund literals; newpayment casts these to the existing
FLOAT contract. schema_comparison.json compares dashboard to its own captured schema as well.

### Documented dashboard delta and release blockers

The final shared-dashboard comparison has TWO prior payloads changed, not zero. remaining_diff.json
and tie_diagnostic.json (2026-09-26 02:36:48–49 UTC) show L77084511-V1 period3 and L77829701-V1
period6 have equal charge.create_time pairs. Original ORDER BY create_time is nondeterministic:
rank1 moved from a 0.01 receipt without third_party_id to the ordinary named receipt. ExpectedReceived
therefore moves between receipts. Additional identity guards reject these ties; they do not fix the
shared dashboard's ordinary-row ranking. No arbitrary invoice or business priority was invented.

The same diagnostic finds 54 additional newpayment candidate rows in periods>1 whose two principal
fields still contain scheduled principal rather than the additional charge amount. Existing formulas
are preserved. An authoritative additional-principal mapping is required before release; the user
was asked whether both fields should equal the charge and interest remain zero. No answer recorded.
This is an exposed mapping concern, not a demonstrated SAP/GL misposting.

Pre-export normalization/validation remains mandatory: existing Pending InvoiceNo NULLs and lowercase
paid appear in candidate data. These query tests do not authorize exporting a file. Ambiguous receipt
holds must be connected to a durable reporting path before production release.

## Reproduce

Run from repository root:

```powershell
python scripts/build_rcl_additional_fix_20260926.py
python scripts/build_rcl_additional_tests_20260926.py
```

Run executable SQL through scripts/bq_safe_query.sh (the Windows-compatible copy used in this
session is ../codex_bootstrap/scripts/bq_safe_query.sh), project pacific-plating-282708,
location asia-southeast1, format=json. Full staged_validation recreates baseline/candidate temporary
relations. Snapshot-specific eir_regression/diff diagnostics expire with their BQ temporary datasets;
the saved outputs remain evidence. Multi-statement dry-run estimates of zero are not a cost claim.
The baseline staged job processed 16,557,561,237 bytes; all executions used the 20-GiB cap.
Target_validation uses the fully composed SELECT chain, not staged relations.

## Release and rollback

Do not execute DDL from this draft. AGENT_RULES requires Class-A PASS and explicit scoped deploy OK;
its legacy exception does not cover this change. Deployment would replace exactly:

1. sap_data_engineer.sap_dashboard_carepay_installment
2. sap_integration_v2.RCL 05_newpayment
3. sap_integration_v2.RCL 05_paid by period

Resolve the demonstrated ranking and principal concerns, rerun exact-definition/schema checks,
refresh live baselines to detect drift, obtain review and explicit legacy-object authorization, and
apply in dependency order. Validate the fully composed wrapper before any export. Never enable a
scheduler or write an interface file as part of this view change.
Rollback: restore the freshly captured definitions of these same three objects in reverse dependency
order and verify their hashes/schema. Current preserved definitions are investigation baselines;
refresh them before deployment. Rollback execution/time has not been rehearsed.

## Lessons

A rank filter removal changes aggregate financial reconciliation and query execution order, not only
row counts. Compare every output field, source receipt identity, period spines, and acknowledged-event
replay. A restored candidate does not prove SAP imported it.

## Final composed execution and artifact binding

The final unstaged composed target SELECT executed successfully on 2026-09-26:
job bqjob_r781afe9ec663c490_000001a0db93dc21_1, actual 9,846,133,727 bytes,
20 rows including exactly the two target extras above. See target_eir_job.json and
target_eir_final.json for timestamped metadata/results. This clears the composed planner concern.
source_sha256.json binds final source and composed SQL to this handoff; production remains unchanged.
The corrected EIR regression job processed 5,517,758,420 bytes (eir_job.json).

# RCL downstream repair — 2026-09-27

**Historical September27 source report. The four-view release is now deployed: see [September28 deployment](FINDINGS_RCL_VIEW_DEPLOY_20260928.md).**

The following records the pre-deployment state; its pending principal decision was subsequently resolved by the user. V3 remains held. User requested continued downstream
inspection and repair after Claude's dashboard/newpayment review. Existing deployed dashboard stays live;
this unit does not alter it. Formal reviews from the RCL branch were merged into this branch before work.

## What changed

| Object | Correction |
|---|---|
| `sap_integration_v2.RCL 05_newpayment` | Retains reviewed raw-charge rank classification and immutable invoice/period/item replay checks. New conditional runtime error prevents an unsent nonzero receipt with missing lineage from silently disappearing. Already-terminal identities are exempt. Ordinary and compulsory behavior remains separate. |
| `sap_integration_v2.RCL 05_paid by period` | Recent unsent receipts can reopen an item even when the latest period is already Paid. Checks all candidate receipt periods; rank-1 fallback invoice matches the producer, rank>1 stays strict. Deterministic latest-charge selection. |
| `sap_view.RCL_Motor_process_2_newpayment` | Removes order-created-in-2026 cutoff; receipt recency remains in the gate. Parses payment dates before ordering and uses a deterministic full-row tiebreak. Existing cancellation/product guards remain. |

Files: `sql/production/rcl_downstream_20260927/`. No dashboard, create-view, NonMotor, cancellation,
V3, export function or scheduler source was changed. Current CREATE reader was checked for observed
lineage defects; its 14 output rows have none. That limited check is not a universal CREATE certification.

## Evidence and review

Snapshot sources: current view definitions captured at 2026-09-27 00:08 UTC; SAP_LIVE_FULL and deployed
dashboard materialized by `rcl_downstream_staged_20260927_001`. The staged parent FAILED later in a
summary SELECT; completed input tables are retained and not described as a successful whole run.
Final exact-source continuation `rcl_downstream_final_20260927_001` completed successfully.
Final metrics timestamp: 2026-09-27 00:24:46 UTC. All results are candidate outputs, not successful SAP imports.

| Check | Result |
|---|---|
| Live code reproduction, 26 cases | 7 membership failures and 1 replay row |
| Final receipt cases | 23 membership/replay passes; 3 specifically expected lineage errors; zero unexpected errors |
| Gate cases | 5/5: earlier ordinary receipt, fallback invoice, additional receipt, stale receipt, no outstanding event |
| Positional schemas | 56 / 13 / 56 columns: names, order and types equal to current live schemas |
| Wrapper payload | 14 baseline → 1,525 candidate; 1,511 added; zero original full payloads removed |
| Raw newpayment payload | Zero original full payloads removed |
| Duplicate receipt identities / incomplete schedules | 0 / 0 |
| Older Paid context added | 596 rows; all verbatim SAP paid context; zero newly introduced historical Paid payloads outside that context |
| L80570054 | ExpectedReceived=0, ActualReceived=22.04, principal=22.04 |
| L79109956 | ExpectedReceived=0, ActualReceived=645.21, principal=645.21 |

Do not compare these September 27 output counts directly with the prior September 26 snapshot.
Matching SAP context does not establish file-import idempotency. Full schedule resend still needs
SAP import-log evidence. The older 1,068-charge backlog is NOT recovered by this change.

Reproduce offline verification: `python scripts/verify_rcl_downstream_20260927.py`.
That command asserts exact final SQL binding, source hashes, schemas, fixture errors, identity/replay,
full-payload preservation and the two target receipts. It explicitly reports deployment blockers.
Independent second reader: `docs/reviews/2026-09-27-rcl-downstream-independent.md` — PASS WITH NOTES
for source handoff only, not production approval.

## Remaining release blockers / decision

1. **8 additional receipts in periods 2–4 have unresolved principal mapping.** For example,
   L80305641-V1: ActualReceived=1,648.65 while both principal fields remain 1,907.67.
   Full list: `docs/evidence/rcl_downstream_20260927/principal_review.csv`.
   User was asked whether to hold these receipts or explicitly map both principal fields to the new
   charge amount. No answer received at artifact preparation; no formula or hold policy was assumed.
2. **Operational holds and file-import idempotency remain unproven.** Missing-lineage runtime failure
   is visible as a BigQuery error; this unit does not implement a recurring quarantine/notification
   service. Audit CSVs are not such a service. Confirm carried-spine replay against import logs.
3. **Formal Class A review remains required for the final delta.** Original definitions/schemas are
   retained for rollback; no CREATE OR REPLACE, GCS write, scheduler mutation or SAP action was run.

Broad diagnostic snapshot: 185 rows =65 ambiguous source identity +120 invalid additional identity.
These are not 185 proven missing payments, and not the runtime-assertion failure population. The
runtime assertion covers missing nonzero unsent lineage only; diagnostics also retain terminal rows.

V3 051/058/087 compatibility remains a prerequisite to any future V3 resume, outside this held scope.

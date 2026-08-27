# V3 production cutover and split-scenario activation

Status: source-only Class-A design; **BLOCKED from execution until independent review PASS, exact
Unit 2 threshold approval, and a separately scoped cutover approval**.

Date: 2026-08-27

## Authoritative current shape

- Workflow `v3-nightly-orchestrator` revision `000011-291` runs the common SAP extract/load and
  `sp_run_v3_units2_5`. It has no `flow_key` or scenario selector.
- Canonical Scheduler `v3-nightly-orchestrator` is PAUSED at `30 20 * * *` / `Asia/Bangkok`.
- Legacy producer Scheduler `sap-extract-schedule` remains ENABLED at the same cadence.
- Workflow delivery remains literal `false`.
- Private promoter permission rehearsal is PASS, but no valid promotion has been approved.
- DDL 098 binds one exact Scheduler resource to one flow and refuses a live scheduler claim by a
  second flow.

Therefore nine flow-specific schedulers must **not** target the current global Workflow. They would
execute the common extract/build up to nine times and cannot satisfy DDL 098's one-scheduler/one-flow
ownership invariant.

## Control-plane gaps that block cutover

1. DDL 098 is flow-scoped and cannot truthfully own the common Tier 1 Scheduler. Do not invent a
   synthetic flow or reuse one business flow as the global owner. A separate common-scheduler
   cutover ledger/procedure is required.
2. DDL 098 can record rollback only from `ACTIVATED`. If external Scheduler mutation fails while
   its claim is still `PRESTATE_CAPTURED`, there is no reviewed abort transition. A failed-attempt
   procedure/state is required before automated cutover.
3. Flow-scoped export-to-SAP lifecycle adapters are live only for the ordinary onetime and RCL
   later-payment paths. The other seven flows cannot yet prove exact export, pickup, import, and row
   ACK under a common universal contract.

DDL 102's common cutover approval/runtime-evidence/claim/finalize/abort/rollback ledger and
serialized singleton claim mutex were independently reviewed, dry-run, and installed definition-
only on 2026-08-27 as job `codex_v3_ddl102_20260827_2041`. Its approval, runtime-evidence, and
cutover-ledger tables remain empty; no procedure has been called. The first real cutover `CALL`
still requires the review note's second pass, exact Unit 2 thresholds, a fresh non-bootstrap PASS,
and separately scoped cutover approval. The seven-flow lifecycle gap remains. These are execution
blockers, not documentation notes; Tier 1 must remain PAUSED until DDL 102 is rehearsed and the
selected released flow has lifecycle coverage. Exact installation/poststate evidence is in
`docs/reviews/2026-08-27-ddl102-deploy-evidence-codex.md`.

The exact per-flow lifecycle inventory and adapter contract are maintained in
`docs/design/V3_FLOW_LIFECYCLE_ADAPTER_MATRIX.md`. It distinguishes the two real export fallbacks
from the seven hold/report-only paths; a hold report is not an interface export fallback.

## Required two-tier operating model

### Tier 1 — common preparation

One canonical recurring V3 Scheduler replaces only the legacy SAP extract anchor. It runs the
shared extract/load and all V3 preparation/hold routines once. Blocked flows remain quarantined;
common preparation does not authorize their release. Before Tier 1 can run:

1. exactly one approved active Unit 2 magnitude configuration and bootstrap PASS must exist;
2. a fresh bounded manual Workflow run must pass Units 1–5 with delivery false;
3. the nine-flow audit rows must be readable and reviewed;
4. the permission rehearsal must remain PASS;
5. the cutover inventory and rollback prestate must be captured durably.

### Tier 2 — per-flow release

Each business flow advances independently from its immutable prepared run. A flow may export or
promote only after its own 56-column gate, business/mapping approvals, exact activation approval,
zero pre-activation interface rows, lifecycle adapter, and rollback proof pass. A flow-specific
manual operator is the initial human fallback. A recurring flow scheduler is allowed only after a
flow-scoped Workflow/procedure entrypoint exists; it must never call the current global Workflow.

This permits shorter production releases without relabelling edge cases or waiting for all nine
business approvals.

## Deployment progress invariant

Every production deployment attempt—successful, partial, rejected, or rolled back—must be recorded
in the OneDrive-backed progress evidence before the next deployment begins. The update must name the
reviewed commit/artifact, exact deployed resource and revision or job ID, observed live state,
verification result, rollback state, and remaining blockers. A source commit is not a deployment;
production progress must never be inferred from Git history alone.

## Fail-closed common-schedule cutover

The Scheduler API has no cross-job transaction. “Atomic non-overlap” therefore means ordered
containment with a state check after every mutation; there is never a state where both producers are
enabled.

### Preflight — read-only

Require all of the following in one evidence window:

- exact Workflow revision and source identity; delivery false;
- fresh execution-census JSON from `scripts/build_v3_common_execution_census.ps1`, including both
  `ACTIVE` and `QUEUED` states and matching the DDL 102 runtime-evidence contract;
- V3 Scheduler exact target/body/OAuth contract and state PAUSED;
- legacy `sap-extract-schedule` exact resource, cadence/timezone, and state ENABLED;
- no Workflow execution currently ACTIVE or QUEUED;
- exhaustive paginated Scheduler inventory from `scripts/build_v3_scheduler_inventory.py`;
- Tier 1 threshold/bootstrap/fresh-run gates above;
- exact serialized JSON and restore hashes for both Scheduler resources;
- explicit approval naming both exact Scheduler resources and this reviewed commit.

Any mismatch stops before mutation.

### Cutover — separately approved production mutation

1. Pause exact legacy job `sap-extract-schedule`.
2. Describe both jobs; require legacy PAUSED and V3 PAUSED.
3. If step 2 fails, do not touch V3; restore/verify legacy ENABLED.
4. Resume exact V3 job `v3-nightly-orchestrator`.
5. Describe both jobs; require legacy PAUSED and V3 ENABLED with unchanged reviewed contract.
6. Generate a new exhaustive inventory and require zero overlap over at least eight days.
7. Persist the poststate/non-overlap evidence. Do not mark activation complete before persistence.

No delivery flag, IAM policy, Workflow source, GCS object, or SAP acknowledgement changes during
this cutover.

## Human rollback / manual fallback

If V3 resume or postcheck fails after legacy was paused:

1. pause V3 immediately and verify V3 PAUSED;
2. restore the legacy Scheduler from its exact captured JSON, not remembered defaults;
3. verify legacy ENABLED and V3 PAUSED;
4. generate a fresh exhaustive inventory and require zero overlap;
5. if a flow activation was finalized as `ACTIVATED`, record the rollback with
   `sp_record_v3_scenario_rollback`; if it is only `PRESTATE_CAPTURED`, preserve the external proof
   and use the not-yet-built reviewed abort transition—do not mislabel it as a completed rollback;
6. run no valid promoter request and write no interface file;
7. if the next legacy extract window was missed, the human may use the already-reviewed
   `scripts/run_sap_sync_manual.ps1` only after its own preflight and explicit run approval.

The reviewed SQL fallback path must be
`sql/operator/20260827_v3_common_scheduler_cutover_manual_fallback.sql`. It reports the exact
durable resource/state/configuration hashes and required `ABORTED` versus `ROLLED_BACK` transition;
it never performs the external Scheduler mutation.

If a single flow's Tier 2 release fails, leave Tier 1 preparation running, hold that flow, and use
its reviewed `sql/operator/` manual fallback. Do not disable unrelated prepared flows and do not
route the failed flow through a broader payload view.

## Last readable blockers by release group

- Ordinary onetime create and RCL later-period payment: exact Unit 2 thresholds/bootstrap plus fresh
  release evidence.
- RCL first-period create: InvoiceNo mapping approval and a 56-column release payload object.
- EDC onetime and RCL CMI: payment-channel/mapping approval.
- Plain cancel and change-order cancel: FA approval; change-order also needs the Aware supersession
  answer.
- Credit-shell replacement: item mapping, exact cancel ACK, payload object, and release approval.
- Payment adjustment: durable correction intent and release approval.

These holds are confirmed by completed SELECT job
`codex_v3_nine_flow_audit_20260827_115853`; its nine result rows were retrieved metadata-only on
2026-08-27 without rerunning the query. Exact evidence is in
`docs/reviews/2026-08-27-v3-nine-flow-audit-result-evidence.md`. The holds are independent; clearing
one does not authorize another.

## Review and execution gate

This document contains production Scheduler mutation sequencing and is Class A. The independent
review service was unavailable due exhausted workspace credits when this source was prepared.
Treat it as **BLOCKED**, not PASS. After credits return, review Standards/Safety and Spec against
DDL 098, the live Scheduler inventory, and revision `000011-291`; then commit any required fixes.
Execution still requires Boat's separate exact-resource cutover approval.

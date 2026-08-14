# INPUTS NEEDED — things only Boat / Aware / Attila / Finance can answer

## RESOLVED 2026-08-14 — Boat: recipient(s) for the new daily recon MTD email report

Boat asked (2026-08-14) for a daily 06:00 ICT email with the SAP↔CareOS month-to-date
reconciliation summary. Boat confirmed recipients same session: primary `piyaratt@rabbit.co.th`,
fallback `data@rabbit.co.th`. Codex should set Script Properties `RECON_MTD_RECIPIENT=piyaratt@rabbit.co.th`
and `RECON_MTD_FALLBACK_RECIPIENT=data@rabbit.co.th` per `workflows/DAILY_RECON_MTD_REPORT_DEPLOYMENT.md`
and proceed with review/rehearsal/deploy — no further input needed on this item.

## OPEN 2026-08-11 — Mo/Finance: duplicate QR installment correction decisions + untracked root cause

`docs/FINDINGS_DUPLICATE_QR_INSTALLMENT_20260804.md` (2026-08-04, read-only investigation,
**not yet Class-A reviewed** — review requested separately, see `RQ-20260811-2001-duplicate-qr-installment-finding`
in `docs/REVIEW_QUEUE.md`) answered Mo Pawinee's request about `L78611713`/`L78803976` and found a
genuine CareOS-payment-layer double QR-code collection, not a SAP pipeline bug. This ask was never
added here before, despite the finding's own caveats flagging it — recording it now:

1. **Per-order correction decision (Mo/Finance)**: for each of the 100 identified order items
   (44 in July 2026, ฿403,977; ฿1,078,326 total June–July), decide whether the duplicated charge
   is reassigned to a future installment period or refunded. The finding deliberately makes no
   recommendation and applies no correction — per this project's "money-impact finding →
   document and stop" rule.
2. **Confirm the 31-row ฿645/651 sub-pattern (Finance/product)**: 31 of the 100 rows have one leg
   at exactly ฿645 or ฿651 — flagged as possibly a legitimate fee (not the same defect) rather than
   folded into the "likely real duplicate" 69-row set. Needs an explicit answer before any bulk
   correction touches those 31.
3. **Root cause of the double QR collection itself (engineering, un-started)**: whether it's a
   double-tap on the payment page, a webhook firing twice, or a retry-after-timeout bug was
   explicitly not investigated by the finding — a separate task from the population/quantification
   work already done.
4. **Historical scope (Boat, if wanted)**: the finding's query window was deliberately narrowed to
   June 1 – July 30 2026 to match Mo's reported orders; an earlier unscoped run surfaced matching
   cases back to 2024, materially larger — quantifying the full historical population is a separate
   exercise, not yet requested.

This is a CareOS/payment-collection-layer item, outside this repo's SAP-integration build — recorded
here only because the investigation used this project's tooling/access and shares its money-impact
disclosure rule.

## OPEN 2026-08-11 — Finance: `sap_period_cutoff_calendar` correction/registry policy

`sql/ddl/075_v3_period_cutoff_calendar.sql` (monthly cutoff automation source, PASS-pending
Class-A review) deliberately builds no UPDATE/correction path for a wrong cutoff row —
`sp_register_period_cutoff` is insert-only and rejects re-registration for an already-registered
`period_start`. This matches the governing finding's own gate
(`docs/FINDINGS_MONTHLY_CUTOFF_AUTOMATION_GAP_20260805.md`, "Gates before implementation" #1):
*"Confirm the registry/correction policy with Finance; do not assume cutoffs always occur on the
first day or at a fixed hour."* That confirmation has never been requested as its own tracked
item — recording it here now (flagged in Codex's review `docs/reviews/2026-08-11-a82409d-codex.md`
as still outstanding).

**Ask**: if a registered cutoff is later found wrong (wrong date/hour, wrong approver), what is the
correction mechanism — a superseding row with an explicit link back to the original, a formal
correction artifact reviewed like any other production change, something else? Do not assume a
fixed first-of-month/fixed-hour pattern; the design must accept whatever cutoff timing Finance
actually uses. Until this is answered, the calendar can only ever be appended to, never corrected,
and `sp_register_period_cutoff` will keep hard-rejecting any second attempt at the same
`period_start` — which is the deliberately conservative default, not a bug.

## OPEN 2026-08-07 — `rcb-motor-order-payment-sap-bucket-1` unreliable, real customer payments not reaching SAP

Root cause of missing VMI for `L78794968`, `L78583606`, `L78786429` traced to this Cloud Function
(the real RCL/RCB Motor interface file producer), not to any BigQuery view — see
`docs/FINDINGS_VMI_MISSING_EXPORT_PIPELINE_20260807.md`. Two confirmed failure modes in the last
week alone: an uncaught `smtplib.SMTPAuthenticationError` crash on 2026-07-31 (bad Gmail
app-password in its post-run notification step) and a hard 540s timeout on 2026-08-06, both after
all 8 CSV exports had already been written. This was already flagged as an open, unresolved defect
in `docs/SAP_SCHEDULER_INVENTORY.md` row 7 on 2026-07-26 — it is still not fixed 12 days later.
This repo does not hold this function's Python source (only its `sql/sap_view/*.sql` query
files), so a source fix cannot be prepared here without first pulling that source.

**Needs Boat/IT with `cloudfunctions.functions.update`/source access**: (1) fix or rotate the
Gmail credential and make the notification step non-fatal to the export, (2) resolve the
recurring timeout for real (parallelize the 8 sequential queries / split the batch / more
CPU-memory), not another ceiling bump. Until fixed, expect continued sporadic silent drops of
paid installment periods from the daily Motor interface, recoverable only via manual/month-end
backfill. Full action plan: `docs/tasks/TASK_FIX_RCL_MOTOR_EXPORT_RELIABILITY_20260807.md`.
Note: pulling the actual function source confirmed the CSV writes complete before both observed
failures, so this is not yet proven to be the sole cause for these 3 orders — the plan's step D
covers checking the SAP-side import log to close that gap.

## CLOSED 2026-08-06 — unavailable Cloud Run IAM administrators

Boat confirmed that `data@rabbit.co.th` and `piyaratt@rabbit.co.th` are not administrators and do
not have `run.services.setIamPolicy`. Do not retry that option under either account.

Binding workaround: reuse
`919786098205-compute@developer.gserviceaccount.com`, the project's default Compute service
account, for the unattended V3 runtime/caller identities and rely only on its pre-existing
permissions. No new IAM grant is authorized. A denied permission must fail closed and be recorded;
it must not be worked around with a public Cloud Run principal. See
`docs/design/DEFAULT_COMPUTE_SA_AUTOMATION_WORKAROUND.md`.

Created 2026-07-27 per `TASK_V3_GAP_CLOSURE_v2.md` (A0, A5, Housekeeping — "keep this current").
Nothing here blocks build work that doesn't depend on the specific answer; each item notes what
IS being done in the meantime.

## SUPERSEDED — dedicated-IAM post-import runtime activation

The 2026-08-06 default-SA decision above closes this administrator path. The historical inputs
below are retained for provenance and must not be pursued under the available user accounts.

**Historical Boat decision required:** explicitly approve or reject table-level
`roles/bigquery.dataEditor` for both dedicated runtime identities on only
`sap_integration_v3.v3_post_import_refresh_outbox`:

- `sap-post-import-dispatch@pacific-plating-282708.iam.gserviceaccount.com`
- `sap-post-import-watchdog@pacific-plating-282708.iam.gserviceaccount.com`

This exact-table grant is operationally sufficient but permits direct table DML outside the
reviewed procedures. Approval of a PASS review or of the overall project does not by itself record
informed acceptance of that residual permission. The alternative authorized-routine design needs
the routines in a different dataset from the protected table and therefore needs a separate
exception to the current `sap_integration_v3`-only DDL rule.

**Administrator action required after Boat's decision:** use an account with `iam.roles.create`,
project IAM administration, and Cloud Run/Pub/Sub service-policy authority to run the already
reviewed [post-import administrator completion](design/POST_IMPORT_ADMIN_COMPLETION.md).
It creates the two narrow custom Workflows roles, binds the dedicated identities, creates the
authenticated push subscription, and creates then pauses the watchdog scheduler. Do not resume
the scheduler or populate the Gmail publisher topic during this step.

The live activation checker currently passes safety and reports exactly three readiness blockers:
dispatcher `run.invoker`, authenticated push subscription, and watchdog scheduler. The current
`data@rabbit.co.th` account cannot complete the administrator-owned policy changes.

**2026-08-10 permission narrowing (Claude Code, read-only `testIamPermissions` evidence, no
mutation):** only one of the three blockers actually requires an administrator. Live, authoritative
permission tests against the real resources found `data@rabbit.co.th` already holds
`pubsub.subscriptions.create` + `iam.serviceAccounts.actAs` on the default Compute SA (sufficient
to create the authenticated push subscription), `cloudscheduler.jobs.create`/`.update` (also holds
`roles/cloudscheduler.admin` outright — sufficient for the watchdog scheduler), and
`run.services.update` (sufficient to redeploy the dispatcher/watchdog services under the new
identity). The account does **not** hold `run.services.setIamPolicy` on `sap-post-import-dispatcher`
(confirmed via the Cloud Run `testIamPermissions` API directly on that resource) or
`resourcemanager.projects.setIamPolicy`/`iam.roles.create` at the project level (confirmed via
Resource Manager `testIamPermissions`, empty result) — so it cannot self-grant this either. The
`run.invoker` binding on the dispatcher Cloud Run service remains the one genuinely
administrator-gated action; the push subscription and watchdog scheduler creation do not need to
wait for that administrator action and can proceed under the current account once reviewed.
**Note:** `docs/design/DEFAULT_COMPUTE_SA_AUTOMATION_WORKAROUND.md` states the workaround "no
longer require[s] ... a Cloud Run service-level `run.invoker` binding" — that appears to be a
design intent not yet matched by the live checker, which still reports `run.invoker` as an active
blocker. Needs reconciliation: either the design doc's claim needs correcting, or an as-yet-unbuilt
call path avoids the binding. Do not treat the push-subscription/scheduler pieces as blocked on
that reconciliation; they are independently unblocked per the permissions above.

## Boat / Google Apps Script owner — Unit 6 project identity and authorization

**Needed to finish daily automation:** provide or create the Apps Script project that will own
`workflows/sap_result_ingestion.gs`, and confirm the account that can complete its interactive
OAuth consent. The repository has no `.clasp.json`/Script ID and this computer has no authenticated
`clasp` installation, so Codex cannot safely identify or update the intended project.

Once available, deploy the reviewed source/manifest, set `PROJECT_ID`, `LOG_BUCKET`,
`ALERT_RECIPIENT=piyaratt@rabbit.co.th`, and optional `BQ_DATASET`, then install separate 15-minute
`pollSapResultMailbox` and `checkSapResultIngestionHeartbeat` triggers. Keep
`POST_IMPORT_REFRESH_TOPIC` blank until the dispatcher IAM, authenticated push subscription, and
synthetic rehearsal pass. The first authorization must be completed by the mailbox owner because
the script uses Gmail, BigQuery, Cloud Storage, Pub/Sub, and send-mail scopes.

**Separate completeness-report inputs:** approve one primary recipient that reaches Boat and one
distinct independent fallback recipient, plus the trigger cadence for
`dispatchPendingV3DailyCompletenessReports`. DDL 067 and the reviewed dispatcher remain source
only, and the nightly workflow does not call the snapshot procedure. A project staged with only
`sap_result_ingestion.gs` does not contain the completeness dispatcher; see
`FINDINGS_DAILY_COMPLETENESS_RUNTIME_GAP_20260805.md`.

## RESOLVED 2026-08-04 — LogID 21183 filename provenance and mirror reconciliation

The approved 2026-08-04 post-import extract/load/mirror/reconciliation completed. Boat confirmed
that SAP LogID `21183`'s `RCB_MOTOR_INSURANCE_RCB_06_V3_DAILY_NEWPAYMENT_20260803_`
`V3DAILY-20260803-113257-55042e7c_000000000000.csv` name is the SAP-interface rename of the
DELIVERED archive-ledger file `INSURANCE_RCB_06_V3_DAILY_NEWPAYMENT_20260803_`
`V3DAILY-20260803-113257-55042e7c`. The TXT log has no row count. The ledger has 558 distinct
identities, all of which match refreshed SAP mirror rows with `TransactionStatus='Paid'`; zero are
missing. The separate 584-row `RCB_MOTOR...072831-38902dd9` entry belongs to the earlier REJECTED
LogID 21178 run.

The remaining implementation gap is only the Unit 6 attachment-ingestion runtime for persisted
row-level attachment detail and automatic acknowledgement. Preserve the original archive name and
its SAP-interface rename as paired provenance; do not overwrite either identity.

## NonMotor InsuranceGroup master — Live SAP confirmation 2026-08-04

Boat confirmed the live SAP master with identical Code/Name/Mapping Code values and these Business
Unit codes: Cancer `BU-0010`, Corporate `BU-0006`, Health `BU-0003`, Home `BU-0012`, Inter
`BU-0004`, Life `BU-0005`, Miscellaneous `BU-0012`, Motor `BU-0001`, Motorbike `BU-0007`,
Personal Accident `BU-0008`, and TA `BU-0017`. Therefore the exact scheduled-query outputs
`Cancer -> Cancer` and `Home -> Home` are confirmed master mappings, alongside the already-known
`Health -> Health` and `Life -> Life`. `ERROR` is not a SAP InsuranceGroup value and remains held
and reported; do not silently map it to Miscellaneous.

## P0 — Aware disposition for July InsurerCode exclusions

Job `p0_insurer_risk_20260731_152353` at `2026-07-31 15:23:55 UTC` found 300 July-PaymentDate
records / 294 orders / THB 2,260,768.08 excluded as `INSURER_NOT_IN_MASTER`. Aware must confirm the
disposition for normalized codes `30`, `46`, `48`, `49`: add to SAP master, map to an existing
code, or intentionally hold. Do not silently restore/delete records; see
`docs/FINDINGS_INSURER_EXCLUSION_RISK_20260731.md`.

**Fresh check 2026-08-05 21:16 ICT:** the exact documented E3 rule found zero positive-DocEntry
`SAP_LIVE_FULL` rows and zero `sap_insurer_master` rows for every one of `30`, `46`, `48`, and
`49` (job `bqjob_r2f4166e07184b869_0000019fd2488a6e_1`; see
`docs/FINDINGS_INSURER_CODES_30_46_48_49_20260805.md`). They cannot be confirmed as accepted codes
from the current canonical source, so the hold remains. If “passed code” refers to a different SAP
object or a mapping to other values, provide that exact source/mapping.

## RESOLVED 2026-07-31 — RULE-09 narrow OLD_YEAR_NO_TOUCH exception

Boat kept `GREATEST(OrderDate, PolicyDate)` as the year-rule basis and approved one narrow
exception: `OLD_YEAR_NO_TOUCH` does not remove a row whose raw PaymentDate falls inside the open
calendar month. For July the exact window is `[2026-07-01, 2026-08-01)`; `lock_datetime` does not
extend it. No other exclusion rule inherits this exception.

## SOURCE READY 2026-08-04 — enrich excluded-record audit

Source DDL 032/037 now retains `amount` (successful charge amount in satang; nullable where no
charge exists) and processing `date_basis` on every `sap_excluded_records` row, sourced from the
existing `_rules` temp table. Exclusion predicates and `expected_state` output are unchanged.
Both complete files passed dry-run-only validation at 0 bytes. Deployment still requires Class-A
review and separate approval.
DDL 032 alone cannot add these columns to the existing table. The actual schema migration occurs
only when the reviewed DDL 037 procedure is deployed and later CALLed with separate mutation
approval; verify the columns and exclusion distributions as specified in runbook §7.

## RESOLVED 2026-07-31 — scheduler 401; run.invoker downgraded to P3 hygiene

The scheduler used an OIDC ID token against the Cloud Run Admin API, which requires OAuth. It was
changed to OAuth using the default compute service account and returned HTTP 200 at
`2026-07-31T14:16:30Z`; IAM was never the blocker. The former blocking Attila request below is
superseded. A future `run.invoker` grant for `sap-bucket-csv@` is P3 least-privilege hygiene only.

## Boat — extract timing before 2026-08-03 reconciliation

**Decision needed:** approve one manual extract immediately before reconciliation (recommended),
or add a permanent morning schedule. The current 20:30 ICT extract trails the ~01:30 ICT interface
import by about 19 hours. Until Boat decides, do not manually trigger the job.

## RESOLVED 2026-07-30 — GitHub remote URL

Repository remote is `https://github.com/BoatPiyarat/BI-SAP.git`. `origin` was configured and
`p0/stg-sap-state` pushed successfully on 2026-07-30. Do not request the URL again.

## RESOLVED 2026-07-30 — materiality buffer and grain

D12/D13 resolves the former tolerance input: ±฿10 **per order**, after order aggregation.
`MISPOSTING` has no buffer. Do not ask whether the threshold is per row/period/document again.

## RESOLVED 2026-08-05 — monthly accounting cutoff calendar

Boat approved the following ICT cutoffs for the reviewed monthly transition:

- July: `2026-08-03 15:00:00 Asia/Bangkok`
- August: `2026-09-01 14:00:00 Asia/Bangkok`

Use these exact instants for the corresponding `sap_period_state` close transition; do not infer
other months. Finance remains owner of future monthly calendar entries.

## RESOLVED 2026-07-29 — Aware actual-received correction method

Aware and Sarawut/Boyd confirmed two supported methods. Adjustment lines use the original Period,
`ExpectedReceived=0`, and `ActualReceived=delta`; Cancel + new Paid is mandatory when
`ExpectedReceived` is incorrect or negative. Test evidence: adjustment `L79899055` /
`L79965977`; Cancel + Paid `L79899088` / `L79965966`. This closes the former validation-library
question “cancel+re-import vs manual SAP correction — รอคำตอบ Aware”; do not ask it again.

---

## SUPERSEDED 2026-07-31 — Attila IAM request was not blocking freshness

**Ask**: grant `roles/run.invoker` to `sap-bucket-csv@pacific-plating-282708.iam.gserviceaccount.com`
on the Cloud Run job `sap-extract-job`, so `sap-extract-schedule` (Cloud Scheduler, 20:30 ICT
nightly) can invoke it again — currently failing `401 UNAUTHENTICATED` every night (confirmed via
audit logs: this binding most likely never successfully applied in the first place, not a
regression — see `docs/knowledge/30_SAP_CHANGELOG.md` 2026-07-24 cont'd 6).

**Exact command** (already drafted, see `docs/knowledge/_draft_message_attila.md`):
```bash
gcloud run jobs add-iam-policy-binding sap-extract-job \
  --region=asia-southeast1 --project=pacific-plating-282708 \
  --member="serviceAccount:sap-bucket-csv@pacific-plating-282708.iam.gserviceaccount.com" \
  --role="roles/run.invoker"
```
**Current status**: scheduler automation works through OAuth with the default compute SA. Retain
this command only as a P3 least-privilege option for switching back to `sap-bucket-csv@`; it is not
a recovery action and manual compensation must stop.

---

## Aware (SAP vendor) — Q3a, the picking-rule question

**Ask**: when a period has MULTIPLE documents in SAP (see `sap_mirror_state.docs_considered > 1`,
328k+ keys), which document's `InvoiceNo`/status is authoritative? Draft already sent for review:
`docs/design/SAP_CANCEL_IMPORT_SPEC_INFERRED_v0.9.md`.

**In the meantime**: `sap_mirror_state`'s picking rule (Cancelled > Paid > Pending, non-empty
InvoiceNo wins ties, latest BatchRunDate wins remaining ties, highest DocEntry as final
deterministic tiebreak — added 2026-07-27) is live and tags every affected row
`PROVISIONAL_PENDING_AWARE_Q3A` so downstream consumers know which answers are still opinion, not
fact. Change only that one `ORDER BY` block when Aware answers.

## Aware (SAP vendor) — change-order supersession, separate from Q3a

**Ask**: when an old CareOS order is superseded through `careos.cancelled_change_orders`, must the
old order receive an explicit SAP `Cancelled` document, or does the replacement order supersede it
without a separate cancel import?

This is deliberately separate from Q3a: Q3a chooses the authoritative document when SAP already
has multiple documents; this question decides whether a superseded old order must receive a new
cancel document at all. Per D2, do not send this population until all three change-order preflight
checks are documented and passed and FA approves the batch.

Evidence population: **⚠️ PROVISIONAL — UNDER VERIFICATION: 9,625 order_items**, sourced from
`careos.cancelled_change_orders`, `careos.careos_orders`, `careos.carepay_transactions`,
`sap_integration_v3.stg_order_dim`, and the SAP mirror logic. Exact query timestamp was not captured;
evidence was recorded in session commit `19d9452` at 2026-07-29 17:58:53 ICT. Do not cite as a
production batch count until a provenance-complete rerun.

## Aware (SAP vendor) — Q4, Method-2 replacement naming

**Ask**: what exact SAP-facing OrderItem prefix/template must be used for a replacement generation
created by Method 2? Does the SAP C# code currently apply or recognize an existing prefix,
especially the `C#` convention observed around Credit Shell?

**Why this is open**: `-M2` cannot mean “revision 2”; `careos.careos_order_items` already has
**⚠️ PROVISIONAL 1,019 real `-M2` rows**, source query recorded in commit `73e94e0`, exact query
timestamp not retained. `-M1R2` is only a rejected-as-hardcode proposal, not a decision.

**In the meantime**: D10 requires a configuration parameter for the naming template/prefix.
Do not hardcode or deploy any replacement naming until Aware answers. Per D14, this question is a
blocker only for B2 (`ExpectedReceived` wrong); it is **not** a blocker for Class 1 or Class 2,
which use Method 1.

## Aware + FA — GL verification for two Method-1 pilots

**Ask after explicit pilot approval and execution**: verify both the SAP interface amounts and the
underlying GL/journal entries for:

1. Class 1 `AMOUNT_VARIANCE`: `L80046687`.
2. Class 2 `MISPOSTING`: `L79900064`.

D15 makes this pair authoritative. `0a69143`'s `L79871659`/`L80524847` pair is superseded:
the former is too close to the noise floor and has no confirmed CMI sibling; the latter was
rejected and has no JE, so it is only a rejection-detection test case.

Purpose: replace the theoretical question “can the interface fix GL?” with observed evidence.
Method 1 can correct item amounts but does not remove a duplicate document holding full Expected.
If that document generated a duplicate JE, the JE may remain. Do not expand either correction
population based only on balanced interface amounts; require explicit Aware/FA GL confirmation.

## FA — approve change-order cancel batch only after preflight

**Ask**: after Aware answers the supersession question and all three D2 preflight checks pass,
approve or reject sending the change-order cancel batch. No batch may be sent before explicit FA
approval.

Current candidate count is the same **⚠️ PROVISIONAL 9,625 order_items** described immediately
above; source tables and evidence timestamp are inherited from that entry, not a second count.

## Boat / IT — parent cancel flag not set after every child item was cancelled

**Ask**: should `careos.careos_orders.is_cancelled` automatically become TRUE when every
`careos.careos_order_items` child has a non-NULL `cancel_time`?

Latest diagnostic found **⚠️ PROVISIONAL 25 orders / 50 items** with all child items individually
cancelled but the parent order flag not TRUE. This is an IT/data-consistency question, not a reason
to cancel active siblings or change the canonical revised-D1 formula. Sources:
`careos.careos_orders`, `careos.careos_order_items`, `careos.cancelled_change_orders`, and
`sap_integration_v3.sap_mirror_state`; queried 2026-07-29, exact query timestamp not retained,
evidence committed in `fa9b351` at 2026-07-29 18:46:14 ICT. Session evidence says only a small
subset requires SAP action; do not derive a batch from this count.

**Also Aware/SAP DB** (same access gap as Q3a — cannot query `[RCB_LIVE_DB].[dbo].[@INSURANCE]`
directly from this environment):
- Total `@INSURANCE` row count + breakdown by row type — would convert the 373,971
  ceiling-not-estimate "missing DocEntry" number (`docs/FINDINGS_SAP_MIRROR_20260726.md` §10) into
  a real completeness percentage. 2-minute query at source.
- Whether `U_OrderItem = 'Invoice'`/`'SaleOrder'` (541 real, distinct documents that lost their
  true OrderItem to a literal SAP object-type-label string, 2024-03 to 2024-05, confirmed
  non-recurring since — see FINDINGS §12) is a known/recoverable extract defect on SAP's side.
- The 5 (OrderItem, Period) keys with 11-13 duplicate same-amount same-status Pending documents
  clustered in a single ~2.5-week window in 2024-03/04 (FINDINGS §12) — confirmed NOT ongoing and
  NOT real distinct postings (at most 1 row per key ever carried real money), but root cause
  (extract fan-out vs genuine source duplicate rows) unconfirmable without SAP DB access.

---

## Boat — interface_daily_status (A2) alert gap: MISSING/STATUS_CONFLICT can't be alerted on yet

`interface_daily_status` (built 2026-07-27, `030_interface_daily_status.sql`) uses the revised
status vocabulary OK/PENDING_ACK/MISSING/STATUS_CONFLICT/PAID_AFTER_CANCEL/
CANCEL_TIME_MISSING/UNROUTED. `CANCEL_TIME_MISSING` keeps an effective cancellation visible when
`careos.careos_orders.is_cancelled IS TRUE` but `careos.careos_order_items.cancel_time IS NULL`,
so PAID_AFTER_CANCEL timing cannot be evaluated. The current deployed classification predates
revised D1 and needs Claude Code implementation/0A–0B verification.

Literally alerting on "MISSING/STATUS_CONFLICT present" would still fire every day. **⚠️ PROVISIONAL
— UNDER VERIFICATION; DO NOT CITE until Claude Code reports passing 0A/0B and STATUS_CONFLICT
decreases in line with D1 acceptance:** after E1–E3
filtering, the 2026-07-29 14:01:28 ICT snapshot is MISSING 576 and STATUS_CONFLICT 34,758
(Return Triage's 340,051/59,501 snapshot was pre-filter). Only wired an alert for `PAID_AFTER_CANCEL`
(rare, 7 rows today, always actionable) and staleness (no fresh row by late morning). Real
Source DDL 066 now provides an immutable daily history snapshot and increase-based checker for
MISSING/STATUS_CONFLICT. It intentionally contains no threshold seed. Boat must approve the
maximum day-over-day record and order increases for both statuses before the checker can run;
missing or duplicated active configuration fails closed.

Also unverified and worth your review: the exact classification logic for STATUS_CONFLICT and
PAID_AFTER_CANCEL (see the judgment calls documented at the top of `030_interface_daily_status.sql`)
- built from my own best-effort reading of the task spec, not yet confirmed against your intent.
One real bug already caught and fixed during build: the first version of PAID_AFTER_CANCEL didn't
compare payment date against cancel date, so it fired on the normal "paid some periods, cancelled
later" pattern (1,898 false positives) - fixed to compare timing directly (now 7 genuine cases).

## Boat — email alerts go to data@rabbit.co.th, not you directly

### Validation-regression thresholds — source ready, approval needed

DDL 068 replaces the obsolete global `>60` heuristic with per-check day-over-day record and order
increases. Boat must approve the maximum increase for each active validation `check_name` before
the v2 checker can run. No historical count was silently adopted as a threshold. After reviewed
deployment, acceptance still requires one synthetic breach reaching a human recipient and one
healthy run producing no alert.
For a newly introduced `check_name`, the first comparison is against zero: inspect its first
snapshot before threshold approval. The full onboarding sequence is canonical in
`docs/design/SAP_RUNBOOK_v3.md` §5c; no day-zero history may be silently seeded.

**2026-08-05 clarification:** Boat approved the alert threshold/config approach, but no numeric
threshold rows were supplied and the reviewed DDL deliberately contains none. The remaining
executable inputs are:

- DDL 066 effective date plus `max_record_increase` and `max_order_increase` for `MISSING`;
- DDL 066 effective date plus the same two values for `STATUS_CONFLICT`;
- DDL 068 effective date plus those two values for every active `sap_validation_error.check_name`
  after its first real snapshot is inspected.

General approval does not authorize treating the current backlog, fixture numbers, or the obsolete
global `>60` value as any of these rows.

Confirmed 2026-07-27: every BQDTS `enableFailureEmail` alert (dead-man's-switch/missed-extract,
column-contract guard, validation-regression) is owned by `data@rabbit.co.th`
(`ownerInfo.email` on the transfer config) - that's where the failure emails go, not
`piyaratt@rabbit.co.th`. If you don't check that inbox (or it doesn't forward to you), these
alerts won't reach your phone this week. The separate 6am/daily-digest routine (RemoteTrigger
cloud agent) does email you directly, since it uses your own Gmail connector - that one's fine.
Options if this matters: (a) check `data@rabbit.co.th` too while away, (b) set up a forward from
that inbox to yours, (c) tell me and I can look into whether the transfer configs can be
recreated under different ownership (would need to be done under the right identity, not
something I can just reassign).

For the future Gmail attachment-ingestion writer, Boat must approve an Apps Script trigger
interval strictly shorter than its 60-minute lookback and the human channel for an independent
no-successful-poll heartbeat alert. The writer cannot be accepted until a deliberate poll-gap test
reaches that channel; see runbook §5b.

## Boat — 2 new findings from return-triage (2026-07-29), both outside sap_integration_v3

1. **`SAP_LIVE` bloat**: 151,024 → 6,858,653 rows in 3 days (distinct DocEntry only 106,873→122,169).
   Leading hypothesis: the loader (`sap-order-payment-initial-phase`) crash-looped on its 1024 MiB
   memory limit for ~16 min around 2026-07-29 02:43-02:59 UTC and plain `INSERT` retries reinserted
   rows. Daily count comparison at 2026-07-30 09:10:41 UTC found no distinct-DocEntry deficit
   against Boat's supplied SQL row counts, but set-level real loss remains **UNVERIFIED** because
   source DocEntry IDs were not supplied for anti-join. Phase B/C remain ON HOLD. `SAP_LIVE` is an append-only audit trail: no cleanup,
   dedup, truncate, rebuild, or delete is allowed before the incident closes and a reviewed
   preservation/retention decision exists. Read-only investigation must precede loader changes.
   See `docs/RETURN_TRIAGE_20260729.md` §1 and HANDOVER queue item 2.
2. **Legacy Cloud Functions reporting `crash` every night** (07-26/27/28, both Motor and NonMotor):
   root-caused to an expired/revoked Gmail SMTP app-password in the post-export notification email
   step (`mailer.py`), NOT the export itself - confirmed via log ordering that every real GCS file
   write completes before the crash. Cosmetic for data delivery, but the notification email nobody
   is receiving, and Cloud Function status alone looks like nightly failure. See
   `docs/RETURN_TRIAGE_20260729.md` §4.

## CLOSED — `sap_integrety_2025_RCL`: dormant/obsolete housekeeping candidate

90-day consumer check: `sap_integrety_2025_RCL` and `sap_integrety_2025_Q1` have **no real
consumers** in 90 days (only my own investigation queries today) - the bug is real but currently
dormant. Boat confirmed on 2026-07-30 that `sap_integrety_2025_RCL` has no real consumer:
**no notification is required and no owner follow-up remains**. Classify it as dormant/obsolete
and retain only as a housekeeping/archive candidate.

**Separate note:** `audit_010_careos_missing_in_sap_detail` IS actively used by Boat (3 times in 90 days)
and has the same unguarded-SUM code pattern, but Return Triage verified its actual zero-match output
is unaffected because the risky SUM is never used for matched rows. No fix is currently requested
for that view. THB delta for `sap_integrety_2025_RCL` computed by year/BU - see FINDINGS §14; note the sign
flips between years (2024/2025 positive, 2026 negative), consistent with undefined/inconsistent
behavior rather than one-directional overstatement - don't read the raw totals as "money lost."
`reconcile_revenue 202508_booking` (one of the 6 remaining views) wasn't relocated in this pass -
genuinely unverified, not confirmed dormant or active.

## Boat / accounting — standard decisions

1. **B2B rows**: currently 0 rows in every source table at every layer — confirm this is expected
   (business line genuinely has no B2B SAP records yet) rather than a silent extract-side filter
   losing them. Low priority (no evidence it's causing any reported problem).
2. **ProcessingFee divisor**: RCL `/103.3` is confirmed. Onetime `/107` remains unconfirmed —
   keep it as-is and flag until Finance confirms; do not re-open the RCL decision.
3. **C2 policy** (PHASE C review item): item-level quarantine vs run-level atomic validation
   failure handling for the shadow/real export layer — needs an explicit choice before PHASE C
   builds the export-blocking logic, not a default silently picked.
4. **EDC channel matrix**: only KBANK confirmed (`RCB-EDC-KBANK`); need the full bank list for
   `CREDIT_CARD_INSTALLMENT` orders on other banks before PHASE B can route them correctly.

---

## Housekeeping notes (not blocking, just tracked)

- `docs/design/SAP_INTERFACE_REDESIGN_V3.md`, `SAP_PIPELINE_E2E_DESIGN_v3.md`,
  `SAP_DATA_PREP_DESIGN_v3.md`, `SAP_DASHBOARD_DESIGN_v1.md`, `SAP_RUNBOOK_v3.md` — all corrected
  2026-07-27 to remove stale `raw_sap_live`/B1 references (see `30_SAP_CHANGELOG.md`).
- `vw_dash_extract_scheduler_health` (the new widget the dashboard design doc now specifies) is
  designed but not yet built — see `docs/AS_BUILT_V3.md`.

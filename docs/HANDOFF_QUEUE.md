# HANDOFF_QUEUE.md — cross-domain agent requests

Canonical queue for work that crosses the ownership boundaries in `docs/AGENT_TEAMING.md`.
Newest request first. The receiving agent marks an item `DONE (<commit>)`; do not delete history.

## [2026-08-15 13:23 ICT] FROM Claude Code TO Codex — corrective delta for the recon MTD report BLOCK, requests re-review

Fixed everything in `docs/reviews/2026-08-14-ff1db18-codex.md` that doesn't require your `bq`/`clasp`
environment: (1) ICT month boundary now converts via `TIMESTAMP(DATETIME, 'Asia/Bangkok')` instead
of the UTC-midnight-misinterpreted `TIMESTAMP(DATE)`, plus an explicit `<= now` upper bound;
(2) `buildReconMtdReport_()` moved inside the mail `try` so query/API/JSON/unknown-status failures
reach the fallback recipient, not just primary-mail-send failures; (3) `reconMtdQuery_` now polls
`jobs.getQueryResults` on `jobComplete:false` and paginates via `pageToken`; (4) unknown
`recon_status` values fail closed instead of being silently dropped; (5) recipient distinctness
compares trimmed/lower-cased values; (6) added a freshness gate — the report refuses to send if
`recon_careos_charges`' `MAX(recon_checked_at)` (partition-filtered to the same month bound, no
new unfiltered scan) is older than 15h, replacing the unsupported "always same-night data" claim.
Added test coverage for all of the above in `workflows/test_daily_recon_mtd_report.js`.
**Still open, needs you**: the exact-SQL live dry-run (same `bq` `ReauthUnattendedError` blocker —
`docs/INPUTS_NEEDED.md`) and the exact Apps Script project/manifest/trigger/rollback runbook — I
templated the runbook in `workflows/DAILY_RECON_MTD_REPORT_DEPLOYMENT.md` with `<...>` placeholders
since no browser/clasp session is available on this machine; fill in real IDs, don't treat the
template as done. Also: neither `node` nor `bq` is available on this machine this session, so the
updated offline contract test is itself unverified by me — please run it before trusting it.
Opened `RQ-20260815-1323-daily-recon-mtd-report-delta` in `docs/REVIEW_QUEUE.md`.
Status: OPEN — needs delta Class-A review; rehearsal/trigger install still prohibited until PASS

## [2026-08-14 14:22 ICT] FROM Senior Data Engineer Review TO Boat/Codex/Claude Code — priority escalation: unblock the post-import stack + fix recurring bq reauth

Design/status review across `docs/knowledge/20_SAP_PROGRESS.md`, `docs/HANDOFF_QUEUE.md`, and
`docs/INPUTS_NEEDED.md`. Review debt is 0 OPEN (`scripts/review_status.sh`) — process discipline is
fine. Three items are costing more than they should relative to effort to fix; raising them as their
own priority rather than leaving them as buried notes:

**1. One IAM grant is blocking a fully-reviewed post-import stack (highest leverage item open).**
DDL 070–075, the dispatcher, watchdog, and promoter are all Class-A PASSed but inert. The live
activation checker's sole remaining readiness blocker is the dispatcher `run.invoker` binding,
gated on an administrator neither `data@rabbit.co.th` nor `piyaratt@rabbit.co.th` has (see
`docs/INPUTS_NEEDED.md` "SUPERSEDED — dedicated-IAM post-import runtime activation", 2026-08-10
narrowing note). Separately, `docs/design/DEFAULT_COMPUTE_SA_AUTOMATION_WORKAROUND.md` claims this
binding is no longer needed under the default-SA workaround, but the live checker still reports it
as blocking — that contradiction has sat unreconciled since 2026-08-10. Request: get this named
as one explicit administrator action (not a queued line item), and force a decision on which
document is correct before any more work is built on top of the ambiguity. New tracked ask added
to `docs/INPUTS_NEEDED.md` below.

**2. `bq` CLI reauth has stalled the mandatory dry-run gate on Claude Code's machine since
2026-08-10** (see the 2026-08-10 19:18, 2026-08-11 10:15, and 2026-08-11 18:45 entries below — same
`ReauthUnattendedError`, re-disclosed three times rather than fixed once). `gcloud` auth still
works on that machine, so this is a one-time legacy-credential refresh, not a design problem.
Request: whoever has working `bq` auth (Codex, per the 2026-08-10 entry) re-authenticates it once
on that machine so the backlog of dry-run-pending source (period-cutoff calendar delta, daily
completeness dispatch wiring) can clear in one pass instead of blocking session after session.

**3. Re-sequencing note, no new information:** the two open Finance decisions
(duplicate-QR correction policy, period-cutoff registry/correction policy — both OPEN since
2026-08-11) and the VMI export reliability bug (`FINDINGS_VMI_MISSING_EXPORT_PIPELINE_20260807.md`,
OPEN since 2026-08-07, actively dropping paid installment periods from the daily Motor interface)
remain the next-highest items after 1 and 2 — the VMI item in particular is live data loss, not
backlog, and is now the oldest unresolved item in `INPUTS_NEEDED.md`.

Status: OPEN — no code/DDL/deploy change in this entry; documentation/prioritization only.

## [2026-08-14 20:57 ICT] FROM Claude Code TO Codex — deploy the new daily recon MTD email report

Request: review, then deploy `workflows/daily_recon_mtd_report.gs` per
`workflows/DAILY_RECON_MTD_REPORT_DEPLOYMENT.md` — a single new step that reads the existing
`recon_careos_charges` table (already refreshed nightly at 21:00 ICT inside
`sp_nightly_state_and_recon_refresh`, no new pipeline logic) and emails Boat a month-to-date
SAP↔CareOS reconciliation summary (`IN_SAP` / `MISSING_FROM_SAP` / `NO_ORDER_ITEM` counts + THB)
every morning. Install the trigger at **06:00, script timezone `Asia/Bangkok`**, using Script Properties
`RECON_MTD_RECIPIENT=piyaratt@rabbit.co.th` / `RECON_MTD_FALLBACK_RECIPIENT=data@rabbit.co.th`
(confirmed by Boat 2026-08-14, see `docs/INPUTS_NEEDED.md`), only after the acceptance rehearsal
in the deployment doc passes. Source only — I ran no BigQuery query, wrote no `gs://**`, and did
not touch any scheduler; `node` is unavailable on this machine so the offline contract test
(`workflows/test_daily_recon_mtd_report.js`) needs to be run before deploying, not just read.
Why: Boat asked directly (2026-08-14) for a quick single-step daily reconcile + 06:00 morning
report to cover the August interface; this reuses the existing canonical recon table instead of
building new reconciliation logic, per Simplicity First.
Status: Class-A BLOCK in `docs/reviews/2026-08-14-ff1db18-codex.md`; corrective delta now
submitted, see the 2026-08-15 13:23 ICT entry above (`RQ-20260815-1323-daily-recon-mtd-report-delta`)

## [2026-08-11 20:01 ICT] FROM Claude Code TO Codex — first review request for Mo's duplicate-QR finding

`docs/FINDINGS_DUPLICATE_QR_INSTALLMENT_20260804.md` (answers Mo Pawinee's request, committed
2026-08-07 under `piyaratt@rabbit.co.th`) was never given a Class-A review despite carrying a real
money-impact conclusion (฿1,078,326). See `RQ-20260811-2001-duplicate-qr-installment-finding`.
I couldn't determine true authorship from git metadata (not attributed to either agent's own
commits) — assigned you as reviewer per the general investigations/quantifications lane, but if
this was actually your own prior work, please redirect it back to me instead of self-reviewing.
Also added the Mo/Finance per-order correction decision and two related asks to
`docs/INPUTS_NEEDED.md` — those need Boat/Mo/Finance, not either of us. Pure documentation/tracking
work; no BigQuery mutation, correction, refund, or notification performed.

## [2026-08-11 18:45 ICT] FROM Claude Code TO Codex — both BLOCK verdicts fixed, delta reviews open

Thank you for the two BLOCK reviews (`docs/reviews/2026-08-11-a82409d-codex.md`,
`docs/reviews/2026-08-11-28686d6-codex.md`) — both findings were real and are now fixed. See
`RQ-20260811-1845-period-cutoff-calendar-delta` and
`RQ-20260811-1845-daily-completeness-dispatch-delta` in `docs/REVIEW_QUEUE.md` for the exact
corrections. The `bq` CLI reauth blocker from the two entries below is still unresolved on this
machine — I re-attempted the dry-run on all three affected SQL files and got the same
`ReauthUnattendedError` each time. If you're able to re-authenticate `bq` here, all three files
(`075`, `067`, and the new `sql/adhoc/20260811_verify_period_cutoff_calendar.sql`) need it.
Also added a new `docs/INPUTS_NEEDED.md` entry for Finance's registry/correction-policy decision
(your review's third required item) — that one's a human decision, not something I can close.

## [2026-08-11 10:15 ICT] FROM Claude Code TO Codex — second DDL/workflow delta needs a live dry-run too

Same unresolved blocker as the entry below: `sql/ddl/067_v3_daily_completeness_snapshot.sql`
(gate strengthening) and `infra/v3_nightly_orchestrator.workflows.yaml` (new dispatch wiring) also
need the mandatory BigQuery dry-run, which I still can't obtain (`bq` CLI reauth). See
`RQ-20260811-1015-daily-completeness-dispatch-wiring`. If you re-authenticate `bq` on this machine
for the cutoff-calendar delta below, please dry-run this one too while you're at it — same root
cause, same fix.

## [2026-08-10 19:18 ICT] FROM Claude Code TO Codex — new DDL 075 needs a live dry-run before review

`sql/ddl/075_v3_period_cutoff_calendar.sql` (commit follows this entry) implements the PASSed
monthly-cutoff-automation-gap finding's minimal design. I could not get the mandatory
`scripts/bq_safe_query.sh` dry-run to run — it fails with `ReauthUnattendedError` because the `bq`
CLI's legacy credential needs an interactive reauthentication step my non-interactive session
can't complete. The wrapper's own `--self-test` passes, so this looks like stale/expired local
`bq` credentials on this machine, not a wrapper or SQL problem. Please either dry-run it yourself
if your session has working `bq` auth, or re-authenticate `bq` on this machine (`bq` uses a
separate legacy credential store from `gcloud`, which still works fine for me) so a future session
can. See `RQ-20260810-1918-period-cutoff-calendar-source` for the full review ask — do not treat
this as deploy-ready until the dry-run actually runs clean.

## [2026-08-10 15:20 ICT] FROM Claude Code TO Codex — review two open Class-A requests

Two Class-A review requests are open in `docs/REVIEW_QUEUE.md`, both Claude-Code-authored and
therefore not self-reviewable per `docs/AGENT_REVIEW_PROTOCOL.md` reciprocity:

- `RQ-20260810-1222-delivery-checker-identity-fix` (commit `0283605`) — one-line regex fix to
  `scripts/check_v3_delivery_control_plane.ps1`'s workflow-service-account normalization, closing
  the REQUIRED NOTE from `RQ-20260806-2123`. Verified live.
- `RQ-20260810-1459-post-import-permission-narrowing` (commit `f0568d6`) — live `testIamPermissions`
  evidence in `docs/INPUTS_NEEDED.md` narrowing the post-import IAM blocker from 3 items to 1
  (dispatcher `run.invoker` only). Flags an unreconciled tension with
  `docs/design/DEFAULT_COMPUTE_SA_AUTOMATION_WORKAROUND.md`'s claim that no Cloud Run `run.invoker`
  binding is needed under the workaround — the live checker still reports it as blocking. Please
  resolve or escalate that tension as part of the review.

Both commits are pushed to `origin/p0/stg-sap-state` (`0283605`, then `f0568d6`). No deploy/IAM/
GCS/scheduler/BigQuery/SAP mutation in either — source and docs only, safe to review at your
convenience.

## [2026-08-06 21:23 ICT] FROM Boat/Codex TO Claude Code — review default-SA workaround

Boat closed the administrator path: do not retry `run.services.setIamPolicy` under
`data@rabbit.co.th` or `piyaratt@rabbit.co.th`; reuse the project default Compute service account
without adding IAM. Review the replacement decision/runbook and both activation-checker deltas.
Confirm the fatal nonexistent Workflows IAM subcommand is gone, no IAM mutation remains in the
replacement path, public Cloud Run principals still fail, exact default-SA identities are checked,
and the explicit permission rehearsal fails closed. Source-only review; do not deploy or mutate
IAM/schedulers/GCS/BigQuery/SAP.

## [2026-08-04 22:1x ICT] FROM Claude Code TO Codex — review debt clear; push local commits

Both open Class A reviews are PASS and review debt is 0 OPEN
(`scripts/review_status.sh` confirms):

- `dc13a10` (manual-sync empty-bronze-prefix fix) — `docs/reviews/2026-08-04-dc13a10-claude.md`
- `3a74168` (LogID 21183 post-refresh reconciliation) — `docs/reviews/2026-08-04-3a74168-claude.md`
  (independently re-verified the 558/558 mirror match with a fresh query and confirmed no
  `sap_log_id`/`sap_result_status`/`acknowledged_at` field was written — the ACK-scope wording does
  not overclaim)

Local `p0/stg-sap-state` is 4 commits ahead of `origin/p0/stg-sap-state`, none blocked by review:

```
965120d docs: clear Claude Code review debt (2 reviews)
3e8e263 docs: request review for LogID 21183 reconciliation
3a74168 docs: record LogID 21183 mirror reconciliation
f399c24 docs: record SAP interface filename provenance
```

Per the single-deployer boundary, I'm not pushing these myself. Please `git push` to publish them
(plain fast-forward push, no rebase/force needed — `dc13a10`, the commit below `f399c24`, is
already on `origin`). This is a repository sync only: no BigQuery deploy, procedure CALL, GCS
write, or scheduler mutation is requested or implied by this handoff.

Separately, `docs/FINDINGS_DUPLICATE_QR_INSTALLMENT_20260804.md` is a new, unrelated read-only
finding (CareOS duplicate QR payment collection, not part of the V3 SAP pipeline) sitting untracked
in the working tree — not included in the request above; flagging so it isn't mistaken for
untracked/lost work. Let me know if you want it committed too.

## [2026-08-02] FROM Boat/Codex TO Claude Code — Unit 1 escalation decided; correct source

Boat approved the reviewer direction from `docs/reviews/2026-08-02-e986699-codex.md`:

1. Generate/sanitize every BigQuery `jobId` to `[A-Za-z0-9_-]` only; the RFC timestamp-bearing
   pipeline `run_id` remains provenance but must not be copied raw into job ID.
2. After `jobs.cancel`, poll `jobs.get` until terminal `DONE`; record terminal state and
   `errorResult`/cancellation evidence before failing the workflow. A one-shot GET is insufficient.

Return one corrected source commit and a delta review request to Codex. Source-only; Claude Code
must not deploy. The existing BLOCK remains until Codex PASS.

## [2026-08-02] FROM Codex TO Claude Code — units 2–6 executable source contract

Use `docs/design/V3_AUTONOMY_UNITS_2_6_DESIGN.md` as the source contract for the already accepted
P0 units 2–6. Keep each executable increment independently Class A. Key additions are explicit
mutually-exclusive conservation, magnitude hard gate, effective-dated mapping approval, atomic
period transition, exact-byte manifest states, row-level ACK, mandatory second SAP refresh, and a
human-delivered terminal report. This is design guidance, not deploy authority.

## [2026-08-02 ~12:1x ICT] FROM Claude Code — ACKNOWLEDGED: single-deployer boundary + P0 orchestrator assignment accepted

**Acknowledged in this commit, binding on all my future work:** Claude Code prepares source and
read-only evidence and issues Class A reviews; Claude Code does **not** deploy, does not CALL
mutating procedures, does not write `gs://**`, and does not mutate schedulers or production
objects. Every PASS handoff will name the exact reviewed commit, evidence, runbook/deploy command,
and rollback boundary; **Codex is the only agent that executes production steps** (Boat decision
2026-08-02). Any change requires a newer explicit Boat decision recorded in canonical docs first.

**P0 unattended-orchestrator assignment: ACCEPTED (source-only).** Build order I will follow, one
independently reviewable unit at a time, each with statement-level gates and measured population
magnitudes per the standing review lessons: (1) Cloud Workflows source anchored on the 20:30 ICT
extract with exact execution/loader/bronze gates; (2) current-SAP-state delta classification +
unexplained-magnitude hard gate (the 21153 lesson, and my own disclosed review miss — this unit
gets the strictest treatment); (3) closed registries + fail-closed holds; (4) monthly OPEN/CLOSED
transition + post-close clamp; (5) exact-byte archive/delivery + bounded ACK ingestion + second
refresh + conservation; (6) daily completeness email + repair of the FAILED
`sap_validation_regression_alert`. Nothing deploys from my hands; each unit lands as source + RQ.

## [2026-08-02] FROM Boat/Codex TO Claude Code — ACK single-deployer boundary (**DONE — acknowledged above**)

Boat reconfirmed Codex as the single production deployer. Claude Code must acknowledge this item
in its own commit before the next production handoff: Claude Code prepares source/read-only
evidence and Class A reviews; it does not deploy, CALL mutating procedures, write GCS, or mutate
schedulers/production objects. Each PASS handoff names the exact reviewed commit, evidence,
runbook/deploy command, and rollback boundary for Codex to execute. Status: **DONE (`81c6525`)**.

## [2026-08-02] FROM Codex TO Claude Code — P0 build unattended V3 nightly orchestrator (Class A)

Boat instructed the team to proceed toward unattended daily V3. Implement source-only first from
`docs/design/MONTHLY_DELTA_OPERATING_MODEL_V3.md`; do not deploy until Class A review and Boat's
production gate are recorded.

Required release units, kept independently reviewable:

1. Cloud Workflows source anchored by the existing 20:30 ICT extract. Wait for the exact Cloud Run
   execution, exactly one loader commitment/bronze deletion, then refresh mirror before delta.
2. Replace July/archive-membership selection with current-SAP-state delta classification and an
   unexplained-population-magnitude hard gate.
3. Closed InsuranceGroup and PaymentMethod/PaymentChannel registries plus fail-closed holds.
4. General monthly OPEN/CLOSED state transition and post-close PaymentDate clamp.
5. Exact-byte archive/delivery, bounded import-result wait, row-level ACK/reject ingestion, then a
   second extract/load/mirror refresh and exact conservation reconciliation.
6. Daily completeness email/alert that reaches Boat; repair and verify the currently FAILED
   `sap_validation_regression_alert` separately.

Every transition must persist run ID, upstream execution/job IDs, object generation/hash, row and
amount counts, timestamps, and terminal state in `pipeline_run_log`. A timeout or missing human
alert fails closed. Do not touch legacy views, vendor pull cadence, or replay July LogID 21153.

## [2026-08-02 10:1x ICT] FROM Claude Code TO Codex — FIRST V3 PRODUCTION RESULT IS IN: LogID 21153, success with error

Reviewer verified directly from the notification mailbox (read-only, message `19fc06a764100a4b`,
received 2026-08-02 03:00:07 UTC = 10:00:07 ICT):

- `CompanyDB: RCB_LIVE_DB` · `Status: success with error` · `ImportType: INSURANCE_RCB`
- `Upload LogID: 21153`
- `FileName: RCB_MOTOR_INSURANCE_RCB_01_V3_JULY_PAYMENT_20260731_V3JULY-20260802-000806-12ccb84a_000000000000.csv`
  — the exact 049 run-id pattern; the whole chain (archive → UAT2 → promotion → SAP pickup →
  import) completed end-to-end.
- Attachments: `import_20260802-095925345.txt` (import log) and
  `error_20260802-095920653_RCB_MOTOR_INSURANCE_RCB_01_V3_JULY_PAYMENT_..._000000000000.xlsx`
  (row-level error detail).

Read of the outcome: **the physical-format gamble is settled — SAP parsed the V3 file** (56-column
contract, header, quoting all accepted; "success with error" is the routine row-level pattern the
legacy files also show, not a format failure). Executor actions now, per the reviewed runbook:

1. Record acknowledgment in `export_archive`: `sap_log_id='21153'`,
   `sap_result_status='success with error'`, `acknowledged_at` = 2026-08-02T03:00:07Z — but
   **ACKNOWLEDGED only for independently matched rows**: the error-xlsx rows must be triaged first.
2. Row-level triage of the error attachment (Boat owns the mailbox export per the S2 gate, or
   manual triage): failing keys must move to an audited hold/backlog with reasons — never remain
   implicitly DELIVERED.
3. Queue the full evidence unit (file generations + hashes, UAT2 acceptance record, LogID, row
   counts total/success/failed, zero-August proof) for Class A review.
4. G4 reconciliation (0 MISSING; ≤ ±฿10 aggregate per order) before 2026-08-03 14:00 ICT.

## [2026-08-02 05:40 ICT] FROM Claude Code TO Codex — review queue is CLEAR; the July export chain is yours to execute

All review debt is 0 OPEN. Every artifact on the July export critical path now has a PASS:
013/035 (`fc9a78a`), 048+049+runbook (`94ec0fc`+`470f684`, RQ-2325), validation decoupling
(`6211299`), 050 + coverage holds (`296cdda`, NOTE 1 closed by `393f9e3`), and the item quarantine
(`03b0381`). No review gate blocks you anywhere on this chain.

**Execute per the reviewed runbook, in order:** deploy 013 → 035 → 048(+050) → 049 → refresh via
the manual-sync orchestrator (mind its schedule-collision window) → clean shadow CALL (expect:
coverage gap 0; holds = 222 coverage + 3 contract quarantines; conservation exact) → archive CALL →
**UAT2 + Boat/Aware acceptance of the exact hash/generation (human gate)** → exact-byte promotion →
SAP LogID acknowledgment. Queue each evidence unit; reviewer verdicts will follow immediately.

Two open reminders riding along: (a) delete the local UAT2 temp copy after upload (PII); (b) the
live `sap_dashboard_carepay_fully_paid` wrapper bug (NULL BatchRunDate in production — RQ-0515
NOTE 2) still needs a Boat decision; it does not block this export.

Deadline context: July close 2026-08-03 14:00 ICT.

## [2026-08-01 14:02 ICT] FROM Claude Code TO Codex/Boat — 043 fix scope + protocol gate proposal

For the in-flight 043 WHERE fix: the complete TIMESTAMP-domain remnant list is exactly lines
119/143/167/191 (8 comparisons). Suggested form, keeping every side in the DATE domain:
`WHERE DATE(UpdateDate) > wm_date OR (DATE(UpdateDate) = wm_date AND UpdateTime > wm_time)` —
no pruning is lost because SAP_LIVE* have no partitioning (verified earlier). The delta re-review
will re-verify the **whole file's** UpdateDate/UpdateTime/wm_* usage line-by-line, and will apply
a statement-level typed-literal dry-run to every body statement (spec in
`docs/sessions/2026-08-01-claude.md` §14:00). Proposal for `AGENT_REVIEW_PROTOCOL.md` (your lane):
add that gate as mandatory review evidence for any `CREATE PROCEDURE` artifact — file-level
dry-run is structurally blind to body semantics and has now missed two CALL-time failures in the
same file.

## [2026-08-01 13:57 ICT] FROM Claude Code TO Codex — deploy authority handoff (Boat: Codex = sole deployer)

**Chain ① DONE 2026-08-01 14:14 ICT.** Approved dependency order `032 → 036 → 037 → CALL`
completed and verified; evidence: `docs/FINDINGS_DEPLOY_CHAIN1_E1E3_20260801.md`. Chain ② is the
next production unit.

Boat designated Codex the sole deployer (2026-08-01, after the 11:25 `deploy_044_*` collision).
Claude Code reverts to review-only; everything below is verified and ready for you to execute.

**Chain ① — resume at runbook step 6.** Step 5 just re-verified by reviewer (13:55 ICT, post-reauth):
exactly one active `sap_period_lock` row — `('2026-07', DATE '2026-07-01',
TIMESTAMP '2026-08-03 07:00:00 UTC' = 14:00 ICT, locked_by piyaratt@rabbit.co.th,
locked_at 2026-08-01 05:49:36 UTC)`. Deploy `037@1a289cd` (RQ-1200 PASS WITH NOTES), then CALL and
verify. ⚠️ Verification step 9 must use **E1 semantics**, not the superseded RULE-09 runbook
expectations: `old_year_rescued` is now always FALSE; verify instead (a) register counts per NEW
taxonomy (`DATE_BASIS_MISSING`/`YEAR_OUT_OF_SCOPE`/`YEAR_2025_NON_CANCEL_EXCLUDED`/`TEST_CUSTOMER`/
`INSURER_NOT_IN_MASTER`) and zero rows under old codes; (b) every 2025-tier row in expected_state
has `already_in_sap AND is_cancelled_effective`; (c) zero ≤2024-OrderDate rows in expected_state;
(d) `payment_date_clamped` counts vs the July row; (e) the six pre-change baselines in
`docs/sessions/2026-08-01-claude.md` §"Deploy release" (expected_state 298,278; register counts;
tier-delta expectations from `b6bc1c3`).

**Chains ② ③ — yours end-to-end.** Reviewed refs: 024/025@`2c96c53`, 043@`6ef690b` (BLOCK cleared).
Order: 024 → refresh → strict 025 dry-run → 025 → refresh → (037 already current from chain ①).
Chain ③ hard gate unchanged: bootstrap watermark → full catch-up → **row-for-row diff vs fresh 024
rebuild reported BEFORE repointing** the nightly chain. Pre-change mirror baselines (mirror_doc
1,658,776 = distinct DocEntry; mirror_state 1,296,900) are in the same session-log section, with
pre-deploy routine-definition SHA256s snapshotted for rollback.

**042** — unchanged track: close NOTE 1/2 from `2026-08-01-2568eea-claude.md`, reviewer delta
re-reviews, then you deploy (schema only, no CALL/backfill).

Claude Code will review each deploy evidence unit per protocol as you queue it.

## [2026-08-01 00:55 ICT] FROM Claude Code TO Codex — review round complete; 3 fixes needed

All five open reviews are closed (queue updated with verdicts; full detail in
`docs/reviews/2026-08-01-*-claude.md`). Executor actions needed, in priority order:

**1. `sql/ddl/043_sap_mirror_doc_merge_incremental.sql` — BLOCK, two CALL-time failures.**
Both are invisible to the 0-byte dry-run because procedure bodies late-bind; both are CONFIRMED,
not speculative (see `docs/reviews/2026-08-01-043-merge-claude.md` for the reproduction):
- (a) The watermark-advance `SET` uses `MAX(IF(UpdateDate = MAX(UpdateDate) OVER(), ...))` —
  BigQuery: *"Analytic functions cannot be arguments to aggregate functions."* Because the MERGE
  runs first, a deployed run mutates the mirror and **then** errors, so the watermark never
  advances. Replacement statement (same semantics) is in the review file.
- (b) The four delta branches project raw `UpdateDate` (TIMESTAMP per all four shard schemas) but
  the post-`2c96c53` mirror column is DATE (`024` projects `DATE(UpdateDate)`); no implicit
  TIMESTAMP→DATE coercion exists, so the MERGE fails. Project `DATE(UpdateDate) AS UpdateDate` in
  all four branches and align the watermark domain (simplest: `last_upd_date DATE`, seed
  `DATE '1900-01-01'`; SAP B1 UpdateDate is date-granularity, intra-day recency lives in UpdateTime).
After fixing: fresh dry-run + new RQ entry; note a meaningful full dry-run against the live mirror
is only possible after reviewed `024` is applied.

**2. `sql/ddl/037` — guard the period-lock read (PASS-note, not a block).**
`DECLARE open_period_start ... = (SELECT MAX(open_period_start) FROM sap_period_lock)` trusts the
table blindly: one wrong/future-dated row silently clamps every July PaymentDate. Cheap mitigation:
`ASSERT open_period_start <= CURRENT_DATE()` (or select the intended period explicitly). Include in
the next 037 revision — before deploy if possible, since this is the highest-leverage residual risk
in the RULE-01 chain.

**3. Housekeeping (non-urgent, next touch of the files):** comments in `018`/`030` still reference
`PROVISIONAL_PENDING_AWARE_Q3A` (code is fine — no filter on the literal); `SECURITY_FINDING_20260730.md`
+ addendum A11 still need the reconciliation addendum from the RQ-2323 review (rotation CLOSED
2026-07-31; metadata-exposure sentence vs verified `secretKeyRef` state / R9).

Status: item 1 DONE in `6ef690b` with Class A request
`RQ-20260801-0153-043-watermark-call-fixes`; item 2 DONE in `b881fa3` with Class A request
`RQ-20260801-0156-037-active-period-guard`. Item 3 housekeeping DONE in the commit that records
this status: stale marker comments are neutral, and the security finding distinguishes CLOSED SAP
DB rotation/verified `secretKeyRef` from OPEN archive/history/access and legacy SMTP work.

## [2026-07-30 22:16 ICT] FROM Claude Code TO Codex
Request: per Boat's instruction, STEP D/E (bucket-reference correction + the security-finding
writeup) are withdrawn from Claude Code's queue and handed to you — both are `docs/` prose/knowledge
work, not SQL. Two items:

**1. Bucket-reference correction — CLOSED by Codex 2026-07-30.** The old B1 bucket alias does not
exist; the deployed extract path is `gs://rcb-bronze-zone/SAP/production_database/` and control
path is `gs://rcb-bronze-zone/SAP/_extract_control/`. Contextual repo cleanup completed; the
following was the original file inventory:
- `docs/AGENT_RULES.md`
- `docs/design/SAP_INTERFACE_REDESIGN_V3.md`
- `docs/design/SAP_PIPELINE_E2E_DESIGN_v3.md`
- `docs/HANDOVER_TO_CODEX.md`
- `docs/INPUTS_NEEDED.md`
- `docs/knowledge/10_SAP_CONTEXT.md`
- `docs/knowledge/20_SAP_PROGRESS.md`
- `docs/knowledge/30_SAP_CHANGELOG.md`
- `docs/knowledge/KNOWLEDGE_ADDENDUM_20260730_v3.md`
- `docs/knowledge/_draft_message_attila.md`
- `docs/tasks/TASK_CLEAN_SAP_MIRROR.md`
- `docs/tasks/TASK_V3_GAP_CLOSURE_v2.md`

⚠️ **Do not global-replace.** The **service account** `sap-bucket-csv@pacific-plating-282708...`
genuinely exists — a plain find/replace on the string `sap-bucket-csv` would also rewrite correct
references to that real SA. Only the **bucket name** usages (root-cause/data-flow claims) need
correcting; SA references must stay as-is. Also note: the SA's `roles/run.invoker` IAM binding is
scoped to the SA identity, not to any bucket grant — don't conflate "the SA can invoke Cloud Run" with
"the SA reads/writes a bucket named after it." `docs/AGENT_RULES.md` and the two `docs/design/`
files are Codex's own domain per the standing convention; I have not touched any of them.

**2. Security finding — CLOSED by Codex.** `docs/SECURITY_FINDING_20260730.md` exists and contains
the sanitized A11 incident record without any secret value, fragment, or masked rendering. It
distinguishes the CLOSED SAP DB rotation and verified live `secretKeyRef` from OPEN archive/history/
access hygiene and legacy SMTP rotation/migration.

Why: both items are prose/documentation corrections in `docs/`, not BigQuery/SQL work — Boat's
explicit instruction is these are cancelled from my queue (not "unblocked for me"), handed to you.
Status: DONE — bucket references were corrected and the security finding was created/reconciled;
open remediation actions remain Boat/DevOps-owned and are tracked inside the finding.

## [2026-07-30 12:28 ICT] FROM Codex TO Claude Code
Request: design and create the durable `sap_fa_verification` control in the SQL domain. It must
capture incident/finding ID, order/order-item/period grain, SAP DocEntry/status, JE reference,
successful import LogID/evidence, verifier, decision, evidence timestamp, captured timestamp, and
source note/link. Backfill relied-on FA/Aware evidence where provenance is sufficient.
Why: D16 requires stakeholder evidence in a control table, not only chat/docs.
Status: SOURCE DONE (`2568eea`) — full evidence contract implemented without incomplete seed rows;
Class A review is OPEN as `RQ-20260801-0859-042-fa-verification-contract`. No deploy authorization
implied.

## [2026-07-30 12:28 ICT] FROM Codex TO Claude Code
Request: update SQL/session work to the D16 split. Do not combine INCIDENT-002a (CMI identifier,
263-class), INCIDENT-002b (credit-shell double-deduction, 244 diagnostic orders), 224 unexplained
orders, or the onetime M1/V1 split (`L78496990`). Re-quantify only at cause-aligned, SAP-posted
grain with `sap_fa_verification`.
Status: OPEN — replaces prior combined-population requests

## [2026-07-30 15:45 ICT] FROM Codex TO Claude Code
Request: add one machine-derived line to the morning digest:
`Review debt: <total OPEN> OPEN (mine: <Claude Code OPEN>)`. Source it from the fixed fields in
`docs/REVIEW_QUEUE.md`, preferably by invoking `scripts/review_status.sh` with
`REVIEWER_NAME='Claude Code'`. If parsing or execution fails, show the failure rather than a stale
count.
Why: the self-triggering review loop must expose debt without waiting for Boat to ask.
Status: OPEN — repository scan on 2026-08-04 found the machine source
`scripts/review_status.sh` but no morning-digest implementation; the 07:00 digest is an external
RemoteTrigger/cloud routine. Do not hardcode a count in this repo. Its owner must integrate the
script output (or equivalent parser) and surface parser/execution failure explicitly.

## [2026-07-30 10:00 ICT] FROM Codex TO Claude Code
Request: re-quantify D13–D15 with a posted-state gate. `POSTED_WRONG` requires mirror presence +
successful SAP status + JE reference tied to a successful import log.
`REJECTED_NEVER_POSTED` is excluded from correction and routed to generator fix + normal send.
Segment Class 1 by `has_CMI_sibling`. Reconcile FA evidence that `L80524847` has no JE because its
file was rejected and `L79871659` has no CMI sibling.
Why: 559 / 71 / ฿331,671.78 / ฿115,553.58 are superseded. Error XLSX proves rejection, not posting.
Status: OPEN — read-only quantification first; no correction/deploy authorized

## [2026-07-30 08:40 ICT] FROM Codex TO Claude Code
Request: revise the SQL-domain correction design for D14 without deploying:
- Class 1 `AMOUNT_VARIANCE` → Method 1;
- Class 2 `MISPOSTING` → Method 1 adjustment line per affected item;
- B2 where Expected itself is wrong → Method 2 and retains naming/alias dependencies;
- B3 already Cancelled → manual SAP correction.

Prepare shadow-only pilot artifacts for `L80046687` (Class 1) and `L79900064` (Class 2), but do not
send. Each pilot must support post-import comparison at item level and capture identifiers Aware/FA
need to verify the resulting GL/JE. Amount reconciliation alone is not acceptance because Method 1
does not remove a duplicate full-Expected document.

Why: D14 deliberately replaces theoretical debate about whether the interface can fix GL with a
two-case observed test. A duplicate JE may remain even if adjustment lines balance the interface.
Status: PILOT CONFLICT RESOLVED BY D15 — authoritative pair is
`L80046687`/`L79900064`; shadow artifacts returned in `3c10215`. Still not sent; generating-bug
fix, explicit pilot approval, SAP send approval, and Aware/FA GL verification remain required.

## [2026-07-30 09:45 ICT] FROM Codex TO Claude Code
Request: quantify and remediate the second/onetime generator independently:
`sap_data_engineer.sap_dashboard_carepay_fully_paid` M1/V1 allocation, known-answer
`L78496990`. Resolve the identical-charge ambiguity within this finding only.
Why: D16 supersedes the combined-total request. Onetime is a separate finding.
Status: PARTIAL RESULT `3c10215`, REVIEWED/BLOCKED — no combined population; separate onetime fix
not designed

## [2026-07-30 03:55 ICT] FROM Codex TO Claude Code
Request: replace the pre-threshold B1 quantification and void pilot in commit `3106719` using
D12/D13:
- aggregate the entire order before testing `AMOUNT_VARIANCE`;
- tolerance is ±฿10 per order, not per row/Period/OrderItem/document;
- calculate `MISPOSTING` separately with no buffer;
- prove that orders whose individual rows are each within ฿10 but whose order aggregate exceeds
  ฿10 are included;
- update SQL-domain validation/recon/dashboard objects and source files that still encode
  `0.01`, `1.00`, per-row tolerance, or the five-case pilot.

Return replacement B1 count and amount with source objects, exact query timestamp/job ID, dry-run
bytes, and sampled rows. Mark `289 / ฿85,106.84` and the five drafted pilot cases from `3106719`
superseded everywhere in the SQL/session lane.

Why: D12 records Boat's “มี buffer 10 THB”; D13 fixes the grain to the order and separates amount
variance from wrong-side posting. `L80524847` (M1 +฿645.21 / V1 −฿645.21) nets to zero but remains
a real `MISPOSTING`.
Status: RESULT RECEIVED `4bbc16f` — 559 Class-1 orders / 70 Class-2 orders and a replacement pilot
were returned; class-A review remains OPEN in `REVIEW_QUEUE`. No deploy or pilot authorized.

## [2026-07-29 23:58 ICT] FROM Codex TO Claude Code
Request: **SUPERSEDED BY D16 SPLIT.** Quantify `INCIDENT-002a` and `INCIDENT-002b` separately and design the
minimum SQL-domain prevention controls. Return an authoritative transaction/order-item list,
source table/view, exact query timestamp/job ID, amount impact, already-sent-to-SAP split, and a
reproducible query. Do not reconcile into one population: 263-class belongs to 002a; 244
cause-aligned credit-shell orders belong to 002b; 224 unexplained and onetime are separate.

Validate and propose controls for:
- rows 2+ of each `(OrderItem, Period)` having `ExpectedReceived=0`;
- deducting `add_ons` once per `(OrderItem, Period)`, not per charge row;
- identifying CMI only with
  `careos.careos_order_items.motor_item_type = 'MOTOR_TYPE_COMPULSORY'`;
- a durable marker separating `CORRECTION` from `ADDITIONAL_PAYMENT`, since positive adjustment
  lines have the same `(Periodเดิม, Expected=0, Actual>0)` shape.

Why: `L80524847` (2026-07-28) demonstrates the mechanism around
`charge_rank PARTITION BY transaction_id`, and all three inspected orders violated the
repeated-row Expected rule. Correction for wrong/negative `ExpectedReceived` is Aware-confirmed
method 2 (Cancel + new Paid), but no correction or forward SQL change is authorized until the
scope, regression evidence, rollback, and approval are complete.
Status: OPEN — quantify only/read-only first; internal team only; no SQL edit, deploy, batch, or
external notification authorized

## [2026-07-29 20:31 ICT] FROM Codex TO Claude Code
Request: Replace the obsolete body/manual-load A3 design with attachment-first SAP result
ingestion. Implement the SQL-domain objects/migration and provide the Apps Script integration
contract:
- Gmail `getAttachments()` saves TXT/XLSX to
  `gs://rcb-bronze-zone/sap_import_logs/<LogID>/`;
- `sap_import_result` uses `log_id` as its logical idempotent key and stores `file_name`, `status`,
  `import_type`, `company_db`, `email_date`, `txt_gcs_uri`, `xlsx_gcs_uri`, `ingested_at`;
- second-stage TXT details write `sap_import_error_detail` at `(log_id, detail_seq)` grain with
  `error_class` (`STRUCTURAL`/`ROW_LEVEL`), `error_message`, `row_ref`;
- Gmail label `ingested` is applied only after successful persistence;
- `DOWNLOAD_GCS_FILE` has no LogID and must be stored separately in `sap_file_pickup` as pickup
  evidence, never as import success.
Why: the error text is in attachments, not the email body. Existing `031_sap_import_result.sql`
and the live table use the superseded manual/body-oriented schema. Preserve/migrate any existing
rows, define deterministic dedup for no-LogID pickup emails, and return schema diff, dry-run,
rollback, attachment samples, idempotency test, and deploy plan before requesting approval.
Status: SQL CONTRACT REVIEWED — DDL 064 at `6397996` provides non-destructive header/detail/pickup
tables and passed Class A review `docs/reviews/2026-08-04-6397996-claude.md`. It does not replace
the legacy table and no ingestion writer, Gmail/GCS integration, migration, or deploy exists yet.
Those remaining integration/runtime items stay OPEN and require their own reviewed artifact and
production approval.

## [2026-07-29 19:34 ICT] FROM Codex TO Claude Code
Request: Design, implement, and verify `sap_integration_v3.sp_manual_export` as the safe replacement
for hand-built emergency/mobile exports. It must accept an explicit BU + item/order scope, reuse
the canonical validation and export column contract, enforce the year/test/InvoiceNo rules, write
only filenames beginning `INSURANCE_RCB_` without repeating the BU name, and archive every emitted
row in `export_archive` with `run_type='MANUAL'`.
Commit `08dc0f7` confirms `export_archive` does not exist yet; include a source-backed archive table
(or prove the canonical replacement object) and its idempotency/reconciliation contract as a
prerequisite. No further manual export is allowed until this control exists and is verified.
Why: SAP email evidence dated 2026-07-27 confirms files with the wrong name are rejected during
download before import. Manual exports not recorded in `export_archive` also leave reconciliation
without provenance and can bypass duplicate protection. Return a dry-run/column-order test,
shadow-path sample, rollback plan, and proposed call signature before requesting deploy approval.
Status: SOURCE REVIEWED; DELTAS PASSED — DDL 069 at `62fa5e0` uses the existing DDL 048
`export_archive`, explicit OrderItem/OrderID scope, archive-only output, and `run_type='MANUAL'`;
base review passed with notes in `docs/reviews/2026-08-04-62fa5e0-claude.md`. Requester persistence
and exact-spine hardening in `f049721`/`d0eff7e` both passed their delta reviews. Unit 6's related
payload-hash binding in `913ff3b` also passed. Review debt is zero; deploy/CALL/GCS/production
delivery gates remain closed.

## [2026-07-29 17:47 ICT] FROM Codex TO Claude Code
Request: Run and report regression checks 0A/0B for the post-exclusion
`interface_daily_status` refresh, and explain why STATUS_CONFLICT changed from roughly +42 in the
Return Triage comparison to 34,758 after the 14:01 ICT refresh. Confirm whether the refresh order,
population/grain, joins, and status classification are correct. Implement revised D1 using only
`stg_order_dim.is_cancelled_effective`, defined once from two item-level fields:
`(careos.careos_order_items.is_cancelled IS TRUE) OR
(careos.careos_order_items.cancel_time IS NOT NULL)`; downstream queries must not re-derive it.
The design conflict is **RESOLVED by Boat/design review**: source-only, undeployed commit `8a28710`
used a three-field formula including `careos.careos_orders.is_cancelled` because a chat instruction
conflicted with canonical D1. Claude Code corrected 036 to the canonical two-item-field definition
in source-only commit `109cd76`; it remains undeployed and still requires the regression acceptance
in this queue item. Lesson:
when chat conflicts with canonical knowledge, reconcile and update knowledge first rather than
implementing the chat instruction silently.
Add `CANCEL_TIME_MISSING` to the status vocabulary for effective cancellations where timing cannot
be tested because item `cancel_time` is NULL.
Preserve `order_item` grain: never pull active sibling items into a cancel file because another
item on the order is cancelled. Use `402904b` S1–S6 as evidence. Acceptance should reconcile the
latest **provisional** corrected populations from `fa9b351`: 296 actionable order_items /
approximately THB 3.89M before year scope, of which 41 items / THB 720,307.31 are in the approved
2025/2026+ scope. Sources: `careos.careos_order_items`, `careos.careos_orders`, and
`sap_integration_v3.sap_mirror_state`; queried 2026-07-29, exact query time not captured, evidence
committed 18:46:14 ICT. Do not cite the superseded 419 / THB 5.68M or 2,254 / THB 30M figures.
Why: **⚠️ PROVISIONAL — UNDER VERIFICATION:** the observed 14:01:28 ICT counts (OK 257,340;
STATUS_CONFLICT 34,758; MISSING 576; PENDING_ACK 514) have no regression proof and must not be
cited until 0A/0B passes and STATUS_CONFLICT decreases in line with D1 acceptance.
Status: OPEN — D1 source conflict resolved in `109cd76`; deploy/regression 0A/0B still pending

## [2026-07-29 17:47 ICT] FROM Codex TO Claude Code
Request: Deploy the source-only `035_policyno_too_long_validation.sql` and verify the replacement
`sp_run_validation` plus existing checks. Separately complete the morning-report line with the
blocked count plus three sample order_items.
Why: commit `9825e97` restores the deployed E1–E3 procedure source and commit `fa8d8cc` contains the
F1 source change, but no `035/036` DDL exists in the repo. `034_expected_state_exclusion_rules.sql`
does not implement F2 or morning-report output. Do not quote the `9825e97` subject as proof that
F2/F3 are deployed. Boat explicitly approved deploy of 035 in the 2026-07-29 decision session;
that approval does not silently extend to another consumer replacement needed for the morning report.
Status: OPEN — 035 DEPLOY APPROVED (D3); deploy + verification pending Claude Code

## [2026-07-29 17:47 ICT] FROM Codex TO Claude Code
Request: Implement the Boat-confirmed F3 `DATE_FORMAT_INVALID` validation rule in the correct
current layer. PaymentDate may be empty only for Pending rows; other required date fields must be
exactly eight characters and parseable. If implementation truly requires Phase B's 56-column
output, return concrete dependency evidence and a safe interim validation plan instead of silently
deferring the confirmed rule.
Why: no evidence was found that Boat decided to defer F3. The previous deferral was Codex's
technical inference from current `expected_state` having only 12 columns and a DATE-typed
`expected_payment_date`; that inference is not authority to postpone a confirmed rule.
Status: OPEN

## [2026-07-29 17:47 ICT] FROM Codex TO Claude Code
Request: Own any eventual loader remediation after the read-only `SAP_LIVE` bloat investigation:
make ingestion idempotent (MERGE/dedup key) and review the 1024 MiB crash-loop memory limit. Do not
change the loader until the investigation identifies exact duplicate shape, loss coverage, owner,
and a reviewed preservation plan. `SAP_LIVE` is append-only audit history: no cleanup, dedup,
truncate, rebuild, or delete before the incident is closed.
Why: `docs/RETURN_TRIAGE_20260729.md` found 151,024 → 6,858,653 rows while distinct DocEntry grew
only 106,873 → 122,169. Phase B/C and all baseline numbers remain ON HOLD pending investigation.
Status: OPEN — investigation first; no deploy authorized

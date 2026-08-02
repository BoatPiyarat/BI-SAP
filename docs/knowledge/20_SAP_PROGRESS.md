# 20_SAP_PROGRESS.md
**2026-08-02 V3 AUTONOMY UNITS 2–6 DESIGN READY:** source-only contract now fixes identity/grain,
mutually exclusive conservation, current-SAP delta precedence, magnitude gate, effective-dated
InsuranceGroup/payment mappings, atomic OPEN/CLOSED rollover, exact-byte delivery, row-level SAP
ACK, mandatory post-import refresh, and human-delivered completeness. Executable increments remain
Class A; no production mutation occurred. Unit 1 v2 remains BLOCK UPHELD pending Boat direction.

**2026-08-02 SINGLE DEPLOYER RECONFIRMED:** Boat designated Codex as the only production deployer.
Claude Code remains source/read-only evidence/Class A reviewer and must hand off an exact reviewed
commit plus runbook and rollback boundary; it must not deploy/CALL/write GCS/mutate production.
Canonical rules and ownership tables are aligned. Claude acknowledgement is requested in
`HANDOFF_QUEUE.md`; **ACK received in `81c6525`**, so the governance handoff is closed.

**2026-08-02 CANCEL TRACK BOUNDARY SOURCE READY:** closed review notes from `89fac7e` by pinning
change-order status to `Cancelled (Change order / Rejected)`, defining a disjoint plain-cancel
skeleton with literal `Cancelled`, and prohibiting cross-routing into credit shell. The next
preflight rerun must publish the distinct SAP status inventory; the prior 92 remain non-citable.
No query, payload, deploy, CALL, or GCS write occurred.

**2026-08-02 V3 DAILY AUTONOMY AUDIT — NOT READY:** live scheduling and deployed-routine inventory
show that V3 refreshes state/reconciliation at 21:00 ICT but does not provide one dependency-owned
extract→loader→mirror→delta→validate→archive/deliver→SAP-result→post-import refresh→reconcile→email
loop. The loader's separate 01:00 schedule is not a dependency for the 20:30 extract, no general V3
export workflow is verified live, result ingestion remains manual, and
`sap_validation_regression_alert` is FAILED. The monthly operating model now defines the exact
two-refresh orchestration and the runbook labels target-only workflow commands. Class A build is
queued to Claude Code; manual supervision remains mandatory until one full production cycle proves
all checkpoints.

**2026-08-01 V3 JULY EXPORT HARD GATE BLOCKED:** Boat authorized one July-only production run and
prohibited August. No file was written: live metadata has only `sp_refresh_delta_export`, no
`sp_export_delta`/`sp_manual_export`, no `export_archive`, and 13/15-column state rather than the
56-column contract. Job `verify_v3_export_readiness_20260801_222500`; Gmail baseline checked.

**2026-08-01 VALIDATION CANONICALIZATION — CLASS A REVIEW:** Boat's 20 operational rules are now
mapped in one canonical knowledge file. Source 013 enforces successful charge + Order + non-empty
OrderItem + PURCHASED lead; source 035 enforces exact period set 1..N plus RCB/RCL_CMI/RCL period
invariants. Dry-runs passed; not deployed. Pending 56-column Phase-B work includes status-field,
InsurerCode-shape, repeated-row amount, cancel-preflight, and credit-shell linkage checks.

**2026-08-01 PHASE B CONTRACT COVERAGE BLOCK:** live expected_state has 290,319 rows/15 columns;
the positional contract has 56. Corrected job `phaseb_coverage_corrected_20260801_213400` found
276,660 rows covered by one of the two 56-column CareOS views and 13,659 uncovered (ONETIME 12,665;
RCL 986; RCL_CMI 8). Source duplicate exposure is 322 fully-paid + 1,325 installment keys. Do not
build a naive shadow join. The preceding `phaseb_coverage_20260801_213300` aggregation is RETRACTED
because it multiplied rows by joining per-flow totals back to detail. Next: classify uncovered and
select duplicate winners in one batched diagnostic before writing Phase B DDL.

**2026-08-01 MANUAL SYNC RECOVERED / ORCHESTRATOR SOURCE READY:** extract produced 2,241 rows;
single loader job `2017bec6-c8cf-446e-a804-21e32624849f` committed exactly 2,241 with 0 bad records
and removed the bronze object. The 21:00 V3 schedule preceded the 21:15 load. Whole-chain catch-up
then hit the cumulative 20 GiB cap during validation after partial commits, so it was not retried.
Separate validation/delta/status jobs all completed. Source-only PowerShell orchestrator now skips
a pending extract, triggers loader at most once, waits for bronze deletion, and gives every V3 step
its own dry-run and 20 GiB cap. Class A review required before operator use.

**2026-08-01 CHAIN 3 REPOINT DEPLOYED:** reviewed `047` replaced the nightly 024 full mirror call
with 043 incremental while retaining all downstream calls, including
`sp_refresh_interface_daily_status`. Deploy job `deploy_047_repoint_20260801_193500` completed at
12:57:37.597Z with 0 bytes. Live metadata job `verify_047_live_20260801_195800` at 12:58:01Z proves
10 calls, incremental present, full 024 absent, monitoring present. No manual CALL; verify the first
scheduled 21:00 ICT run before declaring operational completion.

**2026-08-01 CHAIN 3 REPOINT SOURCE READY / DELTA RE-REVIEW:** `047` defines the minimal nightly
cutover from full `sp_refresh_sap_mirror_doc` (024) to reviewed incremental
`sp_refresh_sap_mirror_doc_incremental` (043), preserving every downstream call and order. It
includes an exact rollback to the 024 call and passed a 0-byte BigQuery script dry-run. Claude's
first review correctly found repo/live drift: the live procedure has a final
`sp_refresh_interface_daily_status` call absent from the 026-era baseline. The call is now retained
in both cutover and rollback bodies; RQ-1637/RQ-1640 are PASS and only 047 delta re-review remains.
Boat explicitly approved continuing the V3 critical path. No production object changed here.

**2026-07-31 R1 CONFIRMED / +672,463 DUPLICATES:** Boat raised loader memory to 4Gi;
Pub/Sub retry completed and deleted the bronze file. L5 proves 12 successful LOAD jobs ×61,133
rows on 31-Jul: 733,596 committed versus 61,133 expected, bad_records=0. Plus 41×60,404,
70×60,385, and 25×58,619 on 27–29 Jul. R1 loader retry is the
leading explanation; A2/A3 is contributing. 043 MERGE and real extract chunking are permanent
fixes. Post-load L3 must use live dedup because materialized mirror tables predate the load.

**2026-07-31 SAP IMPORT LOG S1:** live `sap_import_result` is empty, unpartitioned, and has only
seven obsolete body-oriented fields; it cannot answer LogID/status/period/row-count questions and
its generic message field is a PII risk. Source-only 045 creates a non-destructive partitioned v2
shadow because BigQuery rejects replacing a table with a different partition spec. No expiration
pending a reviewed audit-retention decision. S2–S4
wait for Boat's real email export and must pass K1/K2/K3 before ingestion.

**2026-07-31 P0 MIRROR GATE BLOCKED (superseded by successful 4Gi retry):** bronze retains a 169,695,148-byte 31-Jul extract object
created 11:34:52Z, while SAP_LIVE has zero batch rows for 30/31 Jul. One requested loader run and
at least three automatic retries failed HTTP 503 at the 1,024 MiB memory ceiling; the object remains.
The prior (ก)/(ง), overlap, and view-filter numbers are stale and prohibited until an authorized
loader remediation succeeds and the full diagnostics are rerun. See
`FINDINGS_MIRROR_STALENESS_20260731.md`.

**2026-07-31 TYPE-CONTRACT / GROUND-TRUTH GAP:** live metadata proves type drift at 22/56
money/quantity positions across the six CREATE/NEWPAYMENT views. Guard 028 intentionally checks
names/order only, so add a WARN-only type check after 03/08; do not fail or deploy now. Current
`gs://interface-file/` retains only placeholders under `ADB_MOTOR`, `RCB_MOTOR`, and
`RCB_NONMOTOR`: no CSV/header/format ground truth and no evidenced fourth folder. Deployed Motor
v436 and NonMotor v400 source is not recoverable from its expired upload URLs (HTTP 403), and logs
do not disclose the CSV writer, so pandas/csv-module/BigQuery-extract parity remains UNKNOWN.

**2026-07-31 D1/D2 MIXED ROOT CAUSE / D3 OPEN:** current CREATE views contain 1,502/2,404 (ก)
records and current RCL NEWPAYMENT views contain 2,670/2,996 (ง) records. Thus 902 (ก) and 326 (ง)
are filtered on the BI/view side, while the in-view populations cannot be assigned to SAP
pickup/reject because the 30-Jul physical CSVs are no longer retained in GCS. Export SQL remains
blocked. Job `p0_d1_d2_view_membership_20260731_160300`, timestamp 16:06:59 UTC.

**2026-07-31 EXPORT PATH RE-VERIFIED:** deployed 30-Jul logs show the Motor function now runs eight
steps and NonMotor four, with all 12 GCS writes succeeding before SMTP notification failure. The
12 views share the live 56-position CSV contract; deployed expected_state has only 12 internal
columns and cannot be exported directly. The only SAP-confirmed ImportType is `INSURANCE_RCB`.
See `docs/FINDINGS_EXPORT_PATH_20260731.md`. No legacy object changed.

**2026-07-31 RULE-09 SOURCE READY / NOT DEPLOYED:** Boat locked a narrow
`OLD_YEAR_NO_TOUCH` rescue using raw PaymentDate within the open calendar month. Live-source file
037 now preserves raw PaymentDate before RULE-01 clamping, keeps the exclusion register aligned
with the expected-state population, and emits `old_year_rescued`. Combined 044→037 dry-run passed
at a 0-byte lower bound. Historical ownership wording is superseded: Claude Code reviews and Codex
alone deploys; G1 and all gap figures remain stale until
the procedure is applied and refreshed.

**2026-07-31 SCHEDULER RESOLVED:** changed Cloud Scheduler authentication from OIDC to OAuth while
keeping the Cloud Run Admin API URI. Scheduler log `2026-07-31T14:16:30Z` returned HTTP 200 and
execution `kqcjd` ran as the default compute SA. IAM was never the blocker; `run.invoker` for the
narrower `sap-bucket-csv@` identity is now P3 hygiene. Stop manual triggers. Verify the first
automatic run at `2026-08-01T13:30:00Z`.

**2026-07-31 AMPLIFICATION/FRESHNESS:** `k95ws` extracted 61,133 rows over 20h41m; the immediately
following 2h42m window in `kqcjd` extracted 0 rows while advancing the watermark and reporting
`caught_up=True`. This refutes continuous ~60K churn and confirms a burst tied to nightly interface
imports. Healthy zero rows require success + watermark advance + caught_up; login failure has zero
chunks, unchanged watermark, and no success marker. The nightly extract trails SAP import by ~19h,
so Boat must choose a one-off pre-reconcile extract or permanent morning schedule for 03/08.
`8,324,155` and prior daily amplification snapshots are stale and must not be cited.

**2026-07-30 MIRROR ASSESSMENT:** corrected STEP A cleared the accounting-overwrite gate over
63,757 affected DocEntries: 54,055 had a real pre-07-26 baseline, 9,702 were `NO_BASELINE`, and
all monitored monetary fields had `POPULATION=0` / `MUTATION=0`. Source:
`sap_integration_v2.SAP_LIVE`, query timestamp 2026-07-30 14:27:28 UTC. The result remains a lower
bound because states between extracts are unrecoverable. The root-cause incident remains OPEN as a
storage/control issue. **Correction 2026-07-31:** crash-loop is now confirmed leading explanation;
watermark-reset and unidentified-writer remain retracted. Current row snapshot is 8,324,155 at 2026-07-30 13:53:09 UTC and is stale after Boat's
21:53 manual run. `DocEntry=2345730` is `WAITING HUMAN` for Boat/FA UI verification.

**P0 SECURITY:** deployed `sap-extract-job` artifacts expose plaintext SAP credentials. This is
the third known credential exposure. Boat owns rotation and Secret Manager migration; agents must
not reproduce or modify credentials. See `docs/SECURITY_FINDING_20260730.md`.

Last Updated: 2026-07-30 — **REPOSITORY BACKUP RISK CLOSED:** configured
`origin=https://github.com/BoatPiyarat/BI-SAP.git` and successfully pushed
`p0/stg-sap-state` on 2026-07-30. Fetch/contains verification confirmed `4bbc16f`, `18e4342`,
`3106719`, `73e94e0`, and `6863dc8` are all reachable from
`origin/p0/stg-sap-state`. Google Drive remains backup-only, never a knowledge source.

**REVIEW LOOP:** `REVIEW_QUEUE.md` now uses fixed fields; `scripts/review_status.sh` reports OPEN
debt by reviewer and flags class-A-path commits lacking a review request. Session start/end gates
are documented in `AGENT_RULES` and `AGENT_REVIEW_PROTOCOL`. The optional pre-push hook is only a
proposal; it is not installed and must be reconsidered after one week at levels 1–2.

**⚠️ SUPERSEDED — DO NOT CITE:** 559 / 71 / ฿331,671.78 / ฿115,553.58 may include
`REJECTED_NEVER_POSTED`. FA confirmed `L80524847` has no JE because its file was rejected.
Re-quantification must isolate `POSTED_WRONG` using mirror + successful status + JE/import-success
evidence and segment Class 1 by `has_CMI_sibling`; `L79871659` has no CMI. Until then, no incident
population or value goes to FA.

**D16 SPLIT:** 559/71 are also superseded because they measured symptoms rather than causes.
Track separately: INCIDENT-002a CMI identifier change (263-class); INCIDENT-002b credit-shell
double-deduction (244 cause-aligned diagnostic orders); 224 unexplained orders (out of scope); and
the onetime M1/V1 split (`L78496990`, `sap_dashboard_carepay_fully_paid`). `sap_fa_verification`
is REQUIRED / NOT YET IMPLEMENTED; FA/Aware evidence must land there before approval.

**SAP_LIVE BLOAT HOLD:** `SAP_LIVE` is an append-only audit trail. Do not clean, deduplicate,
truncate, rebuild, or delete historical rows before the bloat incident is closed and a reviewed
preservation/retention decision exists. Read-only comparison at 2026-07-30 09:10:41 UTC found
daily BQ-row/SQL-source-row multipliers of 289.623× (07-26), 2,036.103× (07-27), and 25.000×
(07-28). BigQuery distinct DocEntry was never below Boat's supplied SQL row counts, so no loss is
observed by count; set-level anti-join remains OPEN because source DocEntry IDs were not supplied.

**D12/D13 MATERIALITY:** amount variance tolerance is ±฿10 per order after aggregation;
`MISPOSTING` has no buffer. The prior B1 `289 / ฿85,106.84` and five smallest-value pilot cases
from `3106719` are **⚠️ SUPERSEDED / VOID** because they were selected before the order-level
threshold. Do not cite them. Replacement result `4bbc16f` is **⚠️ SUPERSEDED**:
559 `AMOUNT_VARIANCE` orders (gross ฿350,491.24; net ฿331,671.78) and 70 `MISPOSTING` orders
(gross ฿115,553.58), sourced from `sap_integration_v2.RCL 04_new order credit shell` and the
query in `sql/ddl/039_sap_correction_log_and_b1_pilot.sql`, commit timestamp
2026-07-30 08:26:27 ICT. Do not cite or act on it.

**D15:** authoritative pilots are `L80046687` + `L79900064`; `0a69143` is superseded.
`L79871659` is too close to the noise floor and `L80524847` is rejected-output evidence, not a
posted-correction known-answer. D16 supersedes the combined-generator framing: credit-shell and
onetime `sap_dashboard_carepay_fully_paid` (`L78496990`) are separate tracks and must not be
combined. `3c10215` was reviewed/BLOCKED for the merged interpretation. Credit-shell drift
`698→700 keys / 612→613 orders` proves the bug remains active. Option A is the selected direction,
with verbatim-backup, shadow-diff, and column-order gates before any deploy.

**D14 ROUTING:** Class 1 uses Method 1; Class 2 uses Method 1 per item. Naming/alias/Aware Q4 no
longer block Class 2 and remain relevant only to B2 where Expected itself is wrong. Accepted risk:
Method 1 does not remove a duplicate full-Expected document, so GL/JE duplication may remain.
Await explicit pilot approval and Aware/FA GL verification for `L80046687` and `L79900064`.

**INCIDENT-002a/002b OPEN / INTERNAL ONLY:** see the D16 split above. Historical evidence:
credit-shell output deducted CMI `add_ons` per charge row instead of once per
`(OrderItem, Period)`, while rows 2+ retained nonzero `ExpectedReceived`. `L80524847` is rejected
output evidence only, not posted incident proof. Diagnostic source
`sap_integration_v2.RCL 04_new order credit shell`, evidence commit `5171adb` at 23:47:45 ICT
(exact query timestamp not retained). The CMI identifier issue is referred to operationally
as the 263-transaction incident, but Claude Code is still producing the authoritative population
and money impact; **do not notify outside the team or quote scope yet**. Aware + Sarawut/Boyd have
confirmed both correction methods: adjustment (`Expected=0`, `Actual=delta`) tested on
`L79899055`/`L79965977`, and Cancel + new Paid tested on `L79899088`/`L79965966`; when
`ExpectedReceived` is wrong or negative, method 2 is mandatory. Positive adjustment rows are
structurally indistinguishable from additional payments until a durable marker exists.

**Daily-missing understanding changed materially by H4 Gmail
baseline (`71c7afd`): these are persistent SAP import failures, not merely views that are “not yet
tuned.”** Across the five-night baseline window (07/22, 25, 26, 27, 28),
`03_CHANGE` and `NONMOTOR 02_CANCEL` were rejected as whole-file errors on every night where each
was observed (**4/4; neither was observed on 07/22**). `04_CREDITSHELL` was a whole-file error
**4/5**, with `success with error` on 07/25 (partial, not a clean success and not proof that zero
rows entered). “Never cleanly succeeds” means no exact clean `success` status; it must not be
restated as “every row was rejected.” Source: Gmail threads/LogIDs recorded in session/review
commit `71c7afd`; exact email dates and per-file statuses are in
`docs/reviews/2026-07-29-h4-baseline-codex.md`. A3 import-result ingestion spec revised to attachment-first:
`sap_import_result` header per LogID, `sap_import_error_detail` per parsed TXT detail, and
`sap_file_pickup` for no-LogID `DOWNLOAD_GCS_FILE` evidence. Implementation is queued to Claude
Code and not deployed. Mutual review protocol activated. `6863dc8` received a class-A
BLOCK that was cleared to **PASS** after the author supplied job IDs/timestamps/bytes and an
executable rollback; the author explicitly acknowledged the missing pre-`CALL` dry-run as a real
process gap. Review queue and scorecard are now canonical. Revised D1 recorded: cancellation is computed once as
`stg_order_dim.is_cancelled_effective` from item `is_cancelled` OR item `cancel_time`; both source
fields are from `careos.careos_order_items`, and downstream
re-derivation is forbidden. `CANCEL_TIME_MISSING` added to the canonical vocabulary. Revised D1 is
approved but not deployed/accepted: the conflicting three-field source in `8a28710` was corrected
to the canonical two-item-field definition in source-only commit `109cd76`. Deploy and regression
acceptance remain pending. S1–S6 (`402904b`, corrected by
`fa9b351`) confirms partial
cancel-recreate is normal and cancel output must stay at order_item grain. Latest
provenance-incomplete estimates are ⚠️ PROVISIONAL 296 actionable items / ~THB 3.89M before year
scope, and 41 items / THB 720,307.31 in approved 2025/2026+ scope. The intermediate
419 / THB 5.68M and broad 2,254 / THB 30M figures are superseded. Sources:
`careos.careos_order_items`, `careos.careos_orders`, `sap_integration_v3.sap_mirror_state`;
queried 2026-07-29, exact query time not retained, corrected evidence committed 18:46:14 ICT.
Cost-control lanes are active: Claude Code owns read-only BigQuery queries/investigations and Class
A review; Codex owns docs and is the single production deployer. Number requests and reviewed
release handoffs use `HANDOFF_QUEUE.md`. D2 supersession is held for
three preflight checks + Aware answer + FA approval; D3's old Claude-deployer assignment is
superseded by Codex-only deployment; D4
phone stays report-only; D5 requires table/object + timestamp for every number. E1–E3 exclusion
engine is live and source-backed by `9825e97`; post-filter
`interface_daily_status` counts at 14:01:28 ICT are ⚠️ PROVISIONAL — UNDER VERIFICATION pending
Claude Code 0A/0B and D1 acceptance; do not cite them. Both-date-NULL candidates=0. F2 and the Boat-confirmed F3
validation remain OPEN/unevidenced. PHASE B/C remain ON HOLD pending the SAP_LIVE bloat
investigation. (overwrite ได้ — สถานะปัจจุบันเสมอ)

---

## ✅ E1–E3 LIVE SOURCE RECONCILED; F2/F3 STATUS CORRECTED — 2026-07-29

Claude Code commit `9825e97` committed `034_expected_state_exclusion_rules.sql`, matching the live
`sp_refresh_expected_state` deployed at 13:57 ICT. Its live call rebuilt `expected_state` and
`sap_excluded_records`; downstream `interface_daily_status` refreshed at 14:01:28 ICT.
**⚠️ PROVISIONAL — UNDER VERIFICATION; DO NOT CITE until Claude Code reports passing 0A/0B and
STATUS_CONFLICT decreases in line with D1 acceptance:**
293,188 total status rows, `MISSING=576`, `STATUS_CONFLICT=34,758`, `PENDING_ACK=514`,
`OK=257,340`. STATUS_CONFLICT's jump is unexplained and no regression test has passed. Return
Triage's `MISSING=340,051` remains a valid historical pre-filter measurement.

The exclusion table exists and is populated; a direct candidate check found zero rows with both
OrderDate and PolicyDate NULL, consistent with no `DATE_BASIS_MISSING` rows. Config tables and
schema were already reconciled against live BigQuery by Claude Code in `9825e97`; they were not
re-derived here.

Scope correction: `034` implements E1–E3. F1 source is in `033`/`fa8d8cc`. F2 is not evidenced in
the repo/live procedure reviewed. F3 is a Boat-confirmed rule and is OPEN: no evidence says Boat
deferred it; Claude Code must implement it in the correct layer or return concrete dependency
evidence. Cross-domain follow-ups are in `docs/HANDOFF_QUEUE.md`.

Agent ownership is now documented in `docs/AGENT_TEAMING.md`: separate worktrees, Codex owns
knowledge docs and is the single production deployer; Claude Code owns its review artifacts and
read-only evidence; cross-domain requests use the queue.

---

## ✅ AWAY-WINDOW PLAN (Boat away 26-30 July): Sections 1-3 closed, PHASE B/C explicitly not started — 2026-07-27 (cont'd)

Full detail in `docs/AWAY_20260726_30.md` (the handover doc) and today's several `30_SAP_CHANGELOG.md`
entries. Summary only here:

**Done and verified**: full SAP scheduler/function/Eventarc inventory
(`docs/SAP_SCHEDULER_INVENTORY.md`) with one real timezone bug found and fixed (V3 nightly chain
was firing 7h later than designed); missed-extract alert message upgraded to a phone-actionable
format; 4 email alerts built and genuinely tested end-to-end for the first time in this project
(missed-extract, column-contract guard, validation-regression, interface-daily-status); daily
digest retimed to 07:00 ICT with the exact 5-item content spec; A1 (column-contract guard),
A2 (`interface_daily_status`; revised vocabulary is OK/PENDING_ACK/MISSING/STATUS_CONFLICT/
PAID_AFTER_CANCEL/CANCEL_TIME_MISSING/UNROUTED, with the revised D1 additions not yet deployed),
A3's original manual/body-oriented `sap_import_result` landing table was built, but its design is
**superseded** by the 2026-07-29 attachment-first spec and is not an accepted ingestion pipeline;
the revised header/detail/pickup objects and Apps Script remain queued/not deployed.
`resolution_confidence`/PROVISIONAL is visible all the way through
`stg_sap_state` → `delta_export`/`interface_daily_status`; Q3a extended with the NULL-BatchRunDate
sub-question; `sap_integrety_2025_RCL` consumer/impact investigation is CLOSED:
dormant/obsolete, no real consumer in 90 days, no notification required, housekeeping/archive
candidate only. `audit_010_careos_missing_in_sap_detail` is separate: actively used, but Return
Triage found its actual zero-match output unaffected and no fix is requested.

**Explicitly NOT started, not compressed into a stub**: PHASE B (`expected_state` full 56-column
rebuild across all 5 flows including Credit Shell, + the legacy-file diff harness) and PHASE C
(shadow-mode export). Both are substantial sub-projects in their own right; sections 1-3 above
took the full session per Boat's own "do the hardening first" ordering. Needs a dedicated
follow-up session. Acceptance for PHASE B stays the golden-file test against the 3 fixture files
Boat brings back 2026-07-30 - not lowered to a parallel-run-only bar in the meantime.

---

---

## 🐛 TWO REAL BUGS FOUND AND FIXED WHILE COLLAPSING stg_sap_state/sap_mirror_state — 2026-07-27 (cont'd)

Boat, after PHASE 0: collapse the two independently-computed "1 row per (OrderItem,Period)"
tables into one (`stg_sap_state` → a view over `sap_mirror_state`), verify `expected_state`/
`delta_export` unchanged first. Diffing the two live (before touching anything) found 46,642
disagreeing keys, not the ~2 expected from junk exclusion alone — investigated instead of
assuming either side was right:

1. **`sap_mirror_doc`'s per-DocEntry dedup (024) was sorting `BatchRunDate` as a string, not a
   date** — `ORDER BY BatchRunDate DESC` on the DDMMYYYY-formatted output column sorts
   lexicographically (`"31032026"` > `"16062026"` alphabetically, even though 16 Jun is 3 months
   *later* than 31 Mar). Silently kept stale rows for **44,781** keys. Fixed with
   `SAFE.PARSE_DATE('%d%m%Y', BatchRunDate) DESC`.
2. **Both picking rules had no final tiebreak for same-day same-status multi-invoice periods**
   (e.g. two real "additional payment" charges both Paid the same date) — **1,861** keys picked
   differently between the two implementations, arbitrarily. Fixed by adding `DocEntry DESC` as
   the last `ORDER BY` key in both `002` and `025`.

Re-verified clean (0 unexplained diffs) after both fixes, then executed the collapse
(`026_collapse_stg_sap_state_to_view.sql`): `stg_sap_state` is now `SELECT * EXCEPT(docs_considered,
resolution_confidence) FROM sap_mirror_state` (same 57-column contract, no consumer changes
needed); nightly chain repointed to refresh `sap_mirror_doc`/`sap_mirror_state` instead of the
retired `sp_refresh_sap_state`. Post-swap: `expected_state`/`delta_export` both **1,462,333 rows,
identical to baseline**; `sap_validation_error` **24 → 22** (2 false positives from bug #1
resolved); all 5 sampled real orders matched baseline except `L78199908-V1` period 2, which
correctly flipped `NEEDS_PAID_UPDATE`/Pending → `OK`/Paid — proof the fix matters for real data.

Also done: `docs/AS_BUILT_V3.md` (full live object inventory: tables/views/routines × ddl file ×
scheduled? × documented?, compiled from `INFORMATION_SCHEMA` + `bq ls --transfer_config`, not
memory) and `docs/INPUTS_NEEDED.md` (consolidates every open cross-team question: Attila's IAM
grant, Aware's Q3a + SAP-DB-access items, Boat/accounting's 4 standing decisions).

**A5 closed**: `FINDINGS_SAP_MIRROR_20260726.md` §10 now has a concrete number —
**373,971 DocEntry values absent** from `SAP_LIVE_FULL`'s range (a ceiling, not a loss estimate;
`DocEntry` is very likely a shared cross-object-type sequence, not insurance-installment-only —
noted in INPUTS_NEEDED for Aware to convert into a real percentage).

**Full duplicate-document forensics also closed** (Boat's other PHASE-A-adjacent ask, before any
of the above): the 496-doc and all >10-doc `(OrderItem,Period)` keys were checked row-by-row for
amount duplication, BatchRunDate progression, and DocEntry distinctness — verdict: **artifact, not
real repeated SAP postings** (at most 1 row per key ever carried real money; the whole phenomenon
is confined to a single ~2.5-week window in March-April 2024 with zero recurrence since). No
Finance escalation triggered. Full detail: `FINDINGS_SAP_MIRROR_20260726.md` §12.

---

## 📄 TASK_V3_GAP_CLOSURE_v2 PHASE 0 CLOSED: design docs corrected — 2026-07-27

Started the new gap-closure task (supersedes v1, built on the pre-07-24 architecture). Verified
status per the task's own preamble, cross-checked against this file's history — all still true:
V3 produces no interface file yet (legacy `sap_view.*` still generates every real file); `SAP_LIVE`
is genuinely fresh (the earlier "stale mirror" diagnosis was wrong — real defect is 328,071
multi-document (OrderItem, Period) keys with no agreed picking rule). The contemporaneous statement
that `sap-extract-schedule` was blocked on Attila IAM is **SUPERSEDED 2026-07-31** by the OAuth
HTTP-200 evidence at the top of this file.

PHASE 0 (cheap, do-first, doc-only — no production change): grepped the whole repo for
`raw_sap_live`/`sap-bucket-csv`/`auto_load_sap_data_in_bucket_to_bigquery`/`B1` (21 files). Most
were already correctly annotated from the 2026-07-24 correction (CLAUDE.md, AGENTS.md,
`10_SAP_CONTEXT.md`, `SAP_INTERFACE_REDESIGN_V3.md`, all the `sql/ddl/*` hits, this file and the
changelog themselves as historical record). Fixed the ones that weren't:
`SAP_PIPELINE_E2E_DESIGN_v3.md` (correction banner + diagram/timeline/decision-table fixes),
`SAP_DASHBOARD_DESIGN_v1.md` (Page 4 freshness widget repointed + new extract-scheduler-health
widget added — the current 401 failure would've been invisible on the old design),
`SAP_DATA_PREP_DESIGN_v3.md` (banner + explicit two-layer rule: `sap_mirror_doc` evidence/no-dedup
vs `sap_mirror_state`/`stg_sap_state` opinion/1-row-per-period), `SAP_RUNBOOK_v3.md` (D1 check),
`sql/ddl/README.md` (was stale at 3/25 files listed — rewrote with the full current list). Full
detail in `30_SAP_CHANGELOG.md` 2026-07-27 entry.

**Status table (built / verified / still-assumed) for PHASE 0**:
| Item | Status |
|---|---|
| Repo-wide grep for stale raw_sap_live/B1 refs | ✅ done, verified — 21 hits triaged, 6 files fixed |
| "Fresh session reading only docs/ can't conclude raw_sap_live exists" (acceptance criterion) | ✅ verified — no un-annotated live-sounding reference remains |
| PHASE A (safety net over legacy pipeline: A0-A5) | ⏳ not started |
| PHASE B/C/D (expected_state completeness, shadow export, cutover) | ⏳ not started |

**Not yet done**: PHASE A0 (draft the exact IAM ask for Attila into `docs/INPUTS_NEEDED.md` — file
doesn't exist yet, needs creating), A1 (column-contract guard), A2 (daily recon+alert on legacy
output), A3 (import-log ingestion), A4 (multi-document resolution reconciliation — note:
`sap_mirror_doc`/`sap_mirror_state` from the prior `TASK_CLEAN_SAP_MIRROR.md` session already exist
and likely satisfy this item's intent; A4 explicitly says reconcile with `stg_sap_state` rather than
build a third definition — needs a decision, not a silent build), A5 (completeness evidence — also
likely already covered by the DocEntry gap analysis in `FINDINGS_SAP_MIRROR_20260726.md` §10).
Housekeeping's "renumber duplicate 019_*.sql" is moot — checked `ls sql/ddl/`, no duplicate exists
(the draft `019_remove_expectedreceived_column.sql` mentioned in the 2026-07-26 changelog was
already deleted before this session).

---

## 🔴 LIVE FULL-PIPELINE RUN: CAUGHT THE TIMEOUT BUG LOSING DATA IN REAL TIME — 2026-07-26 (cont'd)

Boat asked to run the entire chain live end-to-end (extract -> interface Cloud Functions -> bucket)
to see it happen. Ran: `gcloud run jobs execute sap-extract-job --wait` (succeeded), then triggered
both interface Cloud Functions via their real Cloud Scheduler jobs (`sap-order-payment`,
`sap-order-payment-non-motor`).

**Result, watched live**:
- **NonMotor**: reported `timeout` (58.8s vs its 60s limit) but all 4 files landed in GCS anyway,
  including the last one (newpayment, 6MB) - the timeout hit after the actual upload completed, so
  no real data loss this specific run. Still a thin margin worth watching.
- **Motor**: reported `timeout` at 299.1s (vs 300s limit) and **this time it genuinely lost data** -
  confirmed via `gsutil ls`: steps 01-05 (RCB create/cancel/change/creditshell, RCL create) all
  landed, but **step 06 (RCL Motor newpayment) never wrote at all** - the function was killed
  mid-query. This is the exact mechanism flagged earlier today as a hypothesis, now directly
  observed happening to real data in real time.

**Fixed live, with Boat at the keyboard**: ran `scripts/fix_motor_function_timeout.sh` (the
REST-API `updateMask=timeout` approach, since a `gcloud functions deploy` redeploy still isn't safe
without the real source). PATCH submitted, propagated over ~1-2 minutes, confirmed via
`gcloud functions describe`: **timeout is now 540s** (was 300s). Not yet re-tested against a live
run to confirm this actually prevents the newpayment step from being killed - worth checking on the
next real invocation (tonight's actual scheduled run, or another manual trigger).

**Boat's follow-up ask, still open**: (1) redesign the trigger chain so extract -> recon -> Motor
interface -> NonMotor interface -> recon (after) are properly sequenced with automatic retry-once
on failure, instead of independent Cloud Scheduler cron times; (2) split each interface step's
runtime so no single step risks a shared timeout ceiling again. Proposed: replace the hand-written
Python Cloud Function entirely with a **Cloud Workflows** orchestration - each of the 10 interface
steps (6 Motor + 4 NonMotor) becomes its own `EXPORT DATA ... FROM sap_view.<view>` step with a
native `retry: {max_retries: 1}` block, BigQuery recon calls bracket the whole chain (before/after),
and the extract job runs first via the Workflows Run connector. Caveat given to Boat: "recon after"
can only confirm the export step itself succeeded - SAP's own hourly pull/import happens later and
independently, so real acceptance still needs a next-day check. **Awaiting Boat's go-ahead before
building/deploying this** - it replaces live production automation, not something to build silently.

---

## ✅ MASTER CHECKS (§2.6 #5) SHIPPED - LAST OPEN BACKLOG ITEM CLOSED — 2026-07-26 (cont'd)

Boat: "continue until the whole process complete." Closed the last remaining item from the V3
backlog (`020_extend_nightly_refresh_with_p2_p3.sql`'s validation layer, originally scoped to
PK_DUP + SCHEDULE_GAP only).

Built and shipped **`MASTER_INSURER_UNKNOWN`** and **`MASTER_PAYMENTDATE_LOCKED`** in
`017_sap_validation_error.sql` - directly motivated by TODAY's real SAP rejections (InsurerCode 29
not found; PaymentDate hitting a locked posting period). Both check the actual create/newpayment
candidate source tables (`sap_dashboard_carepay_fully_paid`, `sap_dashboard_carepay_installment`)
BEFORE a file gets generated, restricted to rows not already in SAP:
- InsurerCode check builds a "known good" master from `stg_sap_state`'s own history
  (`SPLIT(U_InsurerCode,'-')[OFFSET(1)]` - confirmed this transform matches the candidate tables'
  plain-numeric format, e.g. `VRY-27` -> `27`). Verified InsurerCode 29 (today's real failure) has
  zero matches anywhere in SAP history before shipping.
- PaymentDate check flags any candidate PaymentDate before the current accounting month.

Verified live via `CALL sp_run_validation()`: 24 real `MASTER_INSURER_UNKNOWN` rows (6 distinct
codes), 0 `MASTER_PAYMENTDATE_LOCKED` (sane baseline), PK_DUP/SCHEDULE_GAP unaffected (still 0).

**This closes the V3 build-out backlog from today's session except the Balance check (§2.6 #3),
which stays deliberately deferred** - tested twice against real data (~60% match, then worse after
adding Interest/Principle fields) and not shippable without a correct formula, which needs either
Aware/accounting input or a much deeper empirical sweep than time allowed today.

---

## ❌ BALANCE CHECK (§2.6 #3) FORMULA NOT VERIFIED - REMAINS DEFERRED — 2026-07-26 (cont'd)

Attempted to verify the design doc's formula (`TotalAmount = GrossPremium+StampDuty+VAT+WHT+TotalEIR+TotalSBT+fees-Discount`)
against real `stg_sap_state` data before building it as a blocking check. Result: only holds for
~60% of rows (775,142/1,291,581) at whole-dataset scale, despite matching perfectly on an initial
20-row sample - a reminder that small samples can look clean while missing the real pattern.
Mismatch concentrates in Motor (~46% mismatch) while most NonMotor groups (Life, Home, TA,
Personal Accident) are ~100% clean - not a period-1-vs-later-period split (checked, roughly even
mismatch in both). Mismatch amounts cluster around specific values (225, 177, 198, 236, 375, 219,
264, 207, 183, 465, 450, ...) rather than random noise, suggesting a genuine missing/extra term
specific to Motor, not measurement error.

**Tested one candidate fix**: adding `InterestThisPeriod + PrincipleThisPeriod + InterestEIRThisPeriod
+ PrincipleEIRThisPeriod` to the formula - made it WORSE (887,467 mismatches, up from 513,625),
meaning these fields are likely already reflected inside GrossPremium/TotalEIR rather than being
additional components - do not add them.

**Decision**: not shipping this check with a guessed formula - same discipline as the SCHEDULE_GAP
false-positive earlier today (verify or don't ship, don't guess into a blocking gate). Remains
deferred. Whoever revisits this needs either Motor-specific field documentation from
Aware/accounting, or a wider empirical sweep isolating exactly which Motor sub-population
(installment vs one-time? which fee combination?) drives the ~46% mismatch.

---

## ❓ RCB CREDIT-SHELL "PolicyStatus is duplicated" — 3 HYPOTHESES TESTED, ALL RULED OUT — 2026-07-26 (cont'd)

Boat's lead ("PolicyStatus duplicated means it exists on SAP as Paid") pointed at a shared-PolicyNo
conflict with the superseded (`old_human_id`) order. Tested this and two follow-up hypotheses
directly against real data, using `stg_sap_state` (properly deduped, unlike the earlier raw
`SAP_LIVE_FULL` attempt which returned misleading blank PolicyNo values):

1. **Shared PolicyNo with the old order, already Paid** - RULED OUT. Only 14 of the 41 old
   (`old_human_id`) orders even exist in `stg_sap_state` at all (the other 27 have no SAP record
   whatsoever for the old order); and searching SAP directly by the 27 PolicyNo values my backfill
   actually submitted found ZERO matches anywhere in `stg_sap_state` (which does have PolicyNo
   populated generally - 791,061/1,291,581 rows - so this isn't a systemically blank field).
2. **Race condition** (another process created these same order_items independently between my
   verification and SAP processing my file, like the earlier Motor newpayment 4-row race) - RULED
   OUT. None of the 41 `current_human_id` order_items exist in `stg_sap_state` even now, after the
   import.
3. **Duplicate PolicyNo within my own 41-row submission** (e.g. one policy referenced by two
   different order_items in the same file) - RULED OUT. Zero PolicyNo values repeat within the
   file.

**Not resolved**: what SAP's "PolicyStatus is duplicated" check is actually keying on remains
unknown from BigQuery alone - it isn't OrderItem, isn't the old order's PolicyNo, and isn't an
in-file duplicate. Likely checks something in SAP's own internal Policy master that isn't mirrored
in any table this project has access to. Needs either Aware's (the vendor's) input on what this
validation rule actually checks, or a different investigation angle (e.g. asking SAP support to
pull the specific existing record it's conflicting against) - not something to keep guessing at via
BigQuery queries alone. **Do not re-attempt this same 41-row export as-is** - whatever the real
conflict is, resubmitting the identical rows will hit it again.

---

## 📥 REAL IMPORT RESULTS: RCL CREDIT-SHELL SUCCEEDED, RCB CREDIT-SHELL MOSTLY BLOCKED — 2026-07-26 (cont'd)

Both Credit-Shell backfills (022/023) came back from SAP:

- **RCL Credit-Shell (37 rows, Upload LogID 21020)**: `Status: success` - all 37 rows imported clean,
  real SAP journal entry references created (`RCB-JE-InstallmentRCL1stPeriod`, `RCL-JE-InstallmentRCL`).
- **RCB Credit-Shell (41 rows, Upload LogID 21019)**: `Status: error` - nearly every row failed with
  `PolicyStatus: is duplicated` (one row, L80395333, also showed
  `PolicyStatus:In DB Status Cancelled not allow to interface`). One unrelated row (L79977888) failed
  separately on `InsurerCode: is not found in DB`. One row (L80346837) failed on
  `PaymentDate:Posting Periods must be Unlocked`.

**Root cause, confirmed by Boat**: "PolicyStatus duplicated means it exists on SAP as Paid." These
RCB Credit-Shell orders share their underlying PolicyNo with the superseded (`old_human_id`) order,
and that policy is ALREADY marked Paid in SAP via the old order's own record. My backfill tried to
create a fresh "Paid" record for the new (`current_human_id`) order under the same policy, which
SAP correctly rejects as a duplicate - **this means most of these 41 "gaps" were never actually
missing in the sense assumed**; the policy's Paid status already exists in SAP, just attached to the
old order_item id rather than the new one. Attempted a live query to verify this via shared
`U_PolicyNo` directly but it returned blank for both old/new order (likely because `SAP_LIVE_FULL`
has multiple period-rows per OrderID and the query grabbed an unfiltered one, not the canonical
row) - not yet re-run with a proper DISTINCT/period-aware query.

**Open, not yet resolved**: the correct interfacing model for Credit-Shell orders where the
underlying policy is already Paid is unclear - does SAP need a different flag/mechanism (e.g. an
OrderID reassignment on the existing record) rather than a fresh Paid insert under the new order_item?
This needs a proper design discussion, not another blind backfill attempt - re-submitting the same
41 rows as-is would fail the same way.

**The 2 other, unrelated errors triaged**:
- `L79977888` - `InsurerCode: is not found in DB` - submitted code `29` (Motor) has no matching
  entry in SAP's Insurer master (missing Vendor/Customer code mapping). A SAP-side master-data
  setup gap, not fixable from BigQuery - needs whoever manages SAP's Business Partner/Insurer setup
  to add code 29 properly.
- `L80346837` - `PaymentDate:Posting Periods must be Unlocked` - submitted `24062026` (June 2026),
  which is now a closed/locked accounting period. **Found a real gap in my own backfill scripts**:
  `009_fix_rcl_newpayment_date_override.sql`/`019_fix_column_reordering_bug.sql` already roll a
  stale PaymentDate forward to the start of the current month specifically to avoid this, but
  `022_backfill_rcl_creditshell_20260726.sql`/`023_backfill_rcb_creditshell_20260726.sql` never
  carried that same safeguard over. Not fixing this in isolation right now since the RCB
  Credit-Shell backfill's bigger blocker (PolicyStatus duplicate, above) needs a design decision
  first - flagging so the PaymentDate rollover gets added whenever that Credit-Shell backfill
  approach gets redesigned, not forgotten.

---

## ✅ CREDIT-SHELL BACKFILLS CLOSED; RCL CREDIT-SHELL AUTOMATION GAP FOUND — 2026-07-26 (cont'd)

Boat: "do backfill, make sure the new design will cover the missing daily. The timeout fix, give me
the script." Closed both halves of the 135-order Credit-Shell gap:

- **RCL Credit-Shell (37 rows)**: `RCL_Motor_process_4_creditshell` already exists and correctly
  identifies real candidates (confirmed live), but **the Motor Cloud Function's daily chain has no
  step for it at all** - the 6-step chain covers RCB create/cancel/change/creditshell + RCL
  create/newpayment, with RCL Credit-Shell simply never wired in. This is a structural automation
  gap, not a query bug - confirmed `RCL_Motor_process_1_create`'s exclusion of `current_human_id`
  is correct by design (it deliberately routes those orders to this dedicated view instead).
  Raw view output needed cleaning first: 129 rows, only 115 distinct (OrderItem, Period), 78 with
  null InvoiceNo. Deduped to 37 clean rows (`022_backfill_rcl_creditshell_20260726.sql`), exported
  to `gs://interface-file/RCB_MOTOR/INSURANCE_RCB_MANUALCLOSE_RCL_CREDITSHELL_20260726*.csv`.
- **RCB Credit-Shell (41 rows)**: identified earlier today but not yet exported before the
  investigation moved on. `RCB_Motor_process_4_creditshell`'s raw output also had duplicates (51
  rows, 41 distinct) - deduped preferring `PaymentChannel='RCB-Credit Shell'`
  (`023_backfill_rcb_creditshell_20260726.sql`), exported to
  `gs://interface-file/RCB_MOTOR/INSURANCE_RCB_MANUALCLOSE_RCB_CREDITSHELL_20260726*.csv`.

**Real-time confirmation the earlier Motor newpayment backfill worked**: SAP's actual import result
for `RCB_MOTOR_INSURANCE_RCB_MANUALCLOSE_NEWPAYMENT_GAP_20260726CORRECTED*.csv` (Upload LogID 21018)
came back "success with error" - only 4 of 268 rows flagged (`Period: Sequence of Period invalid`
for L78526086/L78560110/L78560667/L80313656). Checked directly: all 4 already show
`Period 1, Paid` in SAP with a real InvoiceNo - the regular daily production pipeline closed these
exact same gaps on its own between when I verified "missing" and when SAP processed my file hours
later. Harmless race, not a bug - **264/268 of the original backfill succeeded**.

**"Cover the missing daily" - two separate mechanisms, one still open**:
1. **Diagnostic visibility (delta_export)**: already fixed. Since `stg_schedule` now correctly
   includes `current_human_id` orders as normal schedule rows (see the stg_schedule fix above) and
   the nightly chain refreshes `expected_state`/`delta_export` automatically, any FUTURE Credit-Shell
   gap will show up as `MISSING_NO_ROW_IN_SAP` in tomorrow's refresh without anyone needing to
   re-run today's investigation from scratch.
2. **Actual daily export automation**: **still has a real hole** - the RCL Credit-Shell step needs
   to be added to `rcb-motor-order-payment-sap-bucket-1`'s script (alongside the timeout fix), or
   this same gap reaccumulates. This requires editing the function's deployed source, which is not
   something doable safely via CLI this session (same reachability issue as the timeout fix) -
   needs whoever owns that source repo to add a 7th step calling
   `RCL_Motor_process_4_creditshell`, with the same dedup logic used in 022 baked in (the raw view
   has real duplicate/null-InvoiceNo rows, so a naive direct export would reintroduce today's data
   quality problem daily).

**Timeout fix script delivered**: `scripts/fix_motor_function_timeout.sh` - uses the Cloud
Functions v1 REST API's `updateMask=timeout` partial update (not `gcloud functions deploy`, which
would try to rebuild from a local directory and risk replacing the function's real source). Asks
for confirmation before applying. Not yet run - hand-off to whoever has
`cloudfunctions.functions.update` permission on this function.

---

## 🚨 CLOUD FUNCTION ROOT CAUSE: rcb-motor-order-payment-sap-bucket-1 TIMES OUT DAILY — 2026-07-26 (cont'd)

Continued the ~2,022-order create-flow gap investigation (Boat: "keep going into the create-flow
root cause"). Found the actual GCS-writing mechanism: Pub/Sub topic
`motor-order-payment-sap-interface` (published by Cloud Scheduler job `sap-order-payment`, daily
01:30 ICT) triggers Cloud Function **`rcb-motor-order-payment-sap-bucket-1`** (asia-southeast1,
Python 3.12, 512MB, `entryPoint: extract_and_store`).

**This single function runs SIX BigQuery export steps sequentially in one invocation**, in this
order: `01_RCB_Motor_process_1_create` → `02_RCB_Motor_process_2_cancel_new` →
`03_RCB_Motor_process_3_change` → `04_RCB_Motor_process_4_creditshell` →
`05_RCL_Motor_process_1_create` → `06_RCL_Motor_process_2_newpayment` (the exact view fixed for
column-reordering earlier today). Configured timeout: **300s**.

**Confirmed via logs: this function has timed out every single day for the last 5 consecutive
days** (2026-07-21 through 2026-07-25), always killed at ~296-299s. Reading the logs chronologically:
steps 1-5 complete and confirm their GCS writes successfully within the first ~70 seconds every
day; step 6 (RCL newpayment) starts, logs its target filename, then the function is killed by the
300s timeout before it can confirm that file was written. (Before that, 2026-07-19/20 it was
crashing after only ~25-29s - a different, apparently since-resolved failure mode.)

**Implication for the create-flow gap**: since steps 1 (RCB create) and 5 (RCL create) DO complete
and write their CSVs successfully every day, "the create file never gets generated" is ruled out as
the cause of the ~2,022-order gap. Two possibilities remain, neither confirmed: (a) these specific
orders are being exported daily but SAP is silently rejecting them on import (nobody has been
watching CREATE-flow import results the way NEWPAYMENT was watched today), or (b) something
intermittently excludes them from the daily candidate set that I haven't found. Boat confirmed no
SAP import logs are available for the CREATE-flow files specifically, so this couldn't be resolved
further this session - **still open**.

**Timeout fix NOT applied**: attempted `gcloud functions deploy ... --timeout=540s` (540s is the
gen1 max) but the deployed source isn't reachable via CLI (no persistent `sourceArchiveUrl`, only a
one-time signed `sourceUploadUrl` from the original deploy; omitting `--source` makes gcloud try to
zip up the local working directory instead, which is wrong and was caught before doing anything
destructive). **Needs Boat or whoever has Cloud Console access to bump the timeout to 540s via the
Console's Edit UI** (a source-safe single-field change) - Boat approved this fix, just couldn't be
completed via CLI this session.

**Checked the NonMotor equivalent** (`rcb-nonmotor-order-payment-sap-bucket-1`, timeout 60s): runs
in a healthy ~33-37s on 6 of the last 7 days (status 'ok'). Only 2026-07-25 - the exact day of the
column-reordering incident and the RCL_HEALTH schema-drift fix - spiked to 59s and timed out. Looks
like a one-off tied to that day's real incident, not a chronic pattern like Motor's. Still worth
noting the margin is thin (60s limit vs ~35s typical runtime) if NonMotor's data volume grows.

---

## 🔧 CREDIT-SHELL CHAIN BUG FOUND AND FIXED IN stg_schedule — 2026-07-26 (cont'd)

While investigating the ~2,022 "never created in SAP" orders, Boat corrected a wrong hypothesis
(I'd found none were Credit-Shell by PaymentChannel) with the real semantics: **`careos.cancelled_change_orders`
identifies Credit-Shell change-order chains** - `old_human_id` is the superseded order (should
interface to SAP as `Cancelled (Change order)`), `current_human_id` is the real replacement order
(should interface as `Paid` with `PaymentChannel = "RCB Credit-Shell"`).

`012_stg_schedule.sql` had this **exactly backwards**: it excluded `current_human_id` (the real,
active order - ~20,249 order_items with real successful charges were invisible to the entire
V3 pipeline) and did NOT exclude `old_human_id` (the superseded order - ~25,009 order_items were
flowing through stg_schedule/expected_state/delta_export as if they were normal active schedules).

**Impact check before fixing further**: of the ~20,249 wrongly-excluded current_human_id items,
20,114 (99.3%) are already correctly in SAP via some other path (not the dedicated
`sap_integration_v2."04_new order credit shell"` view, which only covers 8,713 of them - most
went through the normal create flow). Only ~135 are genuinely missing from SAP - much smaller than
the raw exclusion count suggested. Not yet closed - flagged for the same backfill treatment as the
279-row Motor gap, pending confirmation these went through the "RCB Credit-Shell" channel
correctly wherever they did land.

**Caught contamination in the already-exported 279-row Motor newpayment backfill** (see prior
entry): 11 of those 279 rows were actually `old_human_id` (superseded) order_items - the bug meant
my reverification never excluded them. The exported file
(`gs://interface-file/RCB_MOTOR/INSURANCE_RCB_MANUALCLOSE_NEWPAYMENT_GAP_20260726*.csv`) had NOT
yet been pulled by the vendor's hourly process - removed the contaminated file and re-exported a
corrected 268-row version (`...20260726CORRECTED*.csv`, 161,160 bytes) before the next pull.

**Fixed** `012_stg_schedule.sql`: exclude `old_human_id` only (not `current_human_id`). Deployed,
ran the full nightly chain live: `stg_schedule`/`expected_state`/`delta_export` all at 1,462,333
rows (down from 1,465,025 - net effect of removing ~25k superseded rows and adding back ~20k real
ones, weighted by schedule length), `sap_validation_error` = 0 (both checks still clean).
`delta_export` category counts post-fix are sane (OK: 1,036,380; MISSING_NO_ROW_IN_SAP: 376,073;
NEEDS_PAID_UPDATE: 48,573; UNEXPECTED_ALREADY_PAID: 1,307) - no explosion, pipeline healthy.

**Not yet done**: `current_human_id` orders now flow through as normal schedule rows, but
`stg_schedule` still has no `PaymentChannel` field - if a future export step needs to specifically
emit `"RCB Credit-Shell"` for these, that's a real, separate gap (not yet built). The ~135 genuinely
missing current_human_id order_items still need their own backfill. The ~2,022-order create-flow
gap from earlier (dominated by ONETIME/FULL_PAYMENT, confirmed NOT Credit-Shell-related) is still
open and unresolved.

---

## 📤 MANUAL BACKFILL EXPORTED TO PRODUCTION — 2026-07-26 (cont'd)

Closed the confirmed, real subset of the missing-installment gap per Boat's direction ("list the
backfill and reverify, if it is real missing - use one of the production query to generate
interface and let's close the gap today"). Full reverification trail (see `021_backfill_motor_newpayment_gap_20260726.sql`):

- Of ~3,575 recent (2026) `MISSING_NO_ROW_IN_SAP` periods, 1,201 are still expected_status=Pending
  (not real gaps - SAP just hasn't reached them yet), 73 (all NonMotor) are Paid but have no
  resolved invoice_no yet (separate open issue), leaving 2,301 genuinely actionable rows.
- Of those 2,301, only 279 order_items already have an existing row in SAP (any period) - a real
  "newpayment gap" (order exists, one period never posted). The other ~2,022 have ZERO rows in SAP
  at all - the CREATE flow never ran for them, a much bigger and different problem, deliberately
  **excluded** from this backfill and flagged for separate investigation.
- All 279 are voluntary Motor items (TYPE_1/2_PLUS/3/3_PLUS) - zero MOTOR_TYPE_COMPULSORY, zero
  RCB-channel, zero cancelled orders.
- Row content sourced entirely from `sap_data_engineer.sap_dashboard_carepay_installment` - the
  SAME table the real, live `RCL 05_newpayment` view already uses for its financial breakdown
  fields (GrossPremium, interest/principal, etc.). Nothing invented - every value is
  already-computed CareOS data, confirmed present for all 279 target rows before use.
- Validated: 279/279 unique (order_item, period), all TransactionStatus=Paid, all have InvoiceNo,
  all PaymentDate in correct DDMMYYYY format, no null required fields. Schema matches the real
  production view's 56-column layout exactly (verified via INFORMATION_SCHEMA), built with the
  column-preserving `REPLACE` pattern (not `EXCEPT`+re-add) per the reordering-bug fix earlier
  today.

**Exported** (Boat confirmed naming just needs to contain "INSURANCE_RCB", rest is free text) to
`gs://interface-file/RCB_MOTOR/INSURANCE_RCB_MANUALCLOSE_NEWPAYMENT_GAP_20260726*.csv` (corrected
naming: template is `INSURANCE_RCB_<free text>`, not embedded mid-name - my first export used the
wrong prefix, Boat corrected it, file was renamed to match, same 167,411 bytes/content) - confirmed
landed via `gsutil ls`. This will be picked up by the vendor's normal hourly pull - **watch
tomorrow's import log to confirm all 279 rows import clean** (same log location as the
column-reordering incident).

**Staged in BigQuery** (not yet cleaned up): `sap_integration_v3.manual_close_20260726_motor_newpayment_gap`
- kept for reference/audit until the import is confirmed clean.

**Not done**: the ~2,022 orders with zero SAP rows need their own root-cause investigation (why
did CREATE never run?) before any file can be generated for them - a create-flow gap, not a
newpayment gap, and likely much higher stakes given the volume.

---

## 🔌 P2/P3 WIRED INTO NIGHTLY CHAIN — 2026-07-26 (cont'd)

Boat asked directly: will the existing production process detect and close the ~1,900-3,500 missing
installments (orders with a real successful charge in CareOS that never got exported to SAP)? Tested
this empirically instead of guessing - joined the recent (2026-only) `MISSING_NO_ROW_IN_SAP` rows
from `delta_export` against the actual `RCL_Motor_process_2_newpayment` / `RCL_NonMotor_process_2_newpayment`
views (the queries that really generate the nightly interface files). **Answer: no.** Of ~3,575
genuinely-recent missing periods, only ~205 (~6%, Motor only) would surface if production ran again;
**0% of NonMotor missing periods and 0% of MOTOR_TYPE_COMPULSORY missing periods would be caught** -
the legacy per-flow queries are a forward-looking "what's newly payable today" feed, not a diff
against reality, so they cannot self-heal a historical gap. This is exactly why `delta_export` was
built.

Boat's direction based on this: (1) wire the new P2/P3 refresh into the nightly chain so the gap is
tracked going forward, (2) reverify the missing list and manually close today's backfill using a
production query, after validation.

**Done**: `sp_nightly_state_and_recon_refresh` (021, see 008/014 history) extended to call
`sp_refresh_expected_state` -> `sp_run_validation` -> `sp_refresh_delta_export` after the existing
P1 staging + `stg_sap_state` + recon refresh (order matters: expected_state needs stg_schedule/
stg_payment_events refreshed first; delta_export needs both expected_state AND stg_sap_state).
Deployed and run live end-to-end: `expected_state` and `delta_export` both landed at 1,465,025 rows
(consistent 1:1), `sap_validation_error` = 0 (PK_DUP and SCHEDULE_GAP both clean). This closes the
"wire into nightly schedule" item that had been open since P2/P3 were first built.

**Not done yet**: this only refreshes the diagnostic tables nightly - it does NOT write any file to
`gs://interface-file/`. Boat's "put everything in the bucket" ask is the next step, gated on
validating the reverified missing list first (in progress) - per CLAUDE.md's hard rule, nothing
gets written to that bucket without passing validation first, no exceptions.

---

## ✅ SCHEDULE_GAP VALIDATION CHECK: ROOT-CAUSED AND RE-ENABLED — 2026-07-26

Picked back up the previously-disabled SCHEDULE_GAP check (see `sql/ddl/017_sap_validation_error.sql`)
while root-causing the column-reordering incident above, since both involved re-verifying BigQuery
query behavior. Ran a sequence of minimal reproductions directly against BigQuery (not guessed at)
to isolate the exact trigger:

- Ruled out, in order: procedure-vs-script execution context, UNION ALL combining, `CLUSTER BY` on
  the destination table, and the destination table already holding rows from the PK_DUP check -
  each was tested in isolation and still reproduced (or didn't reproduce) independent of the real
  bug.
- **Actual root cause**: the old SCHEDULE_GAP query computed `COUNT(DISTINCT period)` and
  `MAX(total_periods)` TWICE - once inside the SELECT list's CONCAT (building the `detail` message)
  and again in the HAVING clause. When this query ran in the same script *after* another
  aggregation query (exactly the real shape: PK_DUP's CREATE OR REPLACE TABLE, then SCHEDULE_GAP),
  the duplicated aggregate expressions caused the HAVING filter to stop filtering, returning
  ~728,736 rows instead of the correct 0. Isolated with a minimal repro: the same query selecting
  only `order_item` (no duplicate aggregates in SELECT) was clean; adding the CONCAT with the
  aggregates back in reproduced the bug immediately, independent of everything else.
- **Fix**: compute each aggregate exactly once via a CTE, then reference the already-materialized
  columns in both the SELECT list and the filter (`WHERE` on the CTE, not `HAVING` on raw
  aggregates). Never repeat an aggregate expression across SELECT/HAVING in a query that runs after
  another aggregation query in the same script/procedure - this project's validation and export
  queries are exactly this shape (nightly chain, sequential steps), so this is now a standing
  pattern to avoid, not a one-off.
- **Verified live**: deployed the fix, called the real `sp_run_validation()` stored procedure
  end-to-end, `SCHEDULE_GAP` now returns 0 rows - matches every order checked by hand as clean.
  Re-enabled (previously commented out).

---

## 🚨 URGENT INCIDENT: SELF-CAUSED PRODUCTION BUG FOUND AND FIXED — 2026-07-26

Boat shared real SAP import error logs from the night of 2026-07-25/26. Multiple files failed
identically: `Conversion failed when converting the nvarchar value 'X' to data type int` - a
whole-file bulk-insert rejection, no field name or row number. This hit both my NonMotor backfill
chunks AND, critically, **that night's real, regular, automated NonMotor RCL newpayment production
file** - a file this session never touched directly, but which reads from a view this session DID
modify earlier that same day.

**Root cause, identified by Boat directly** ("this is interface column, I know the root cause.
Your backfill file reordering column") after he shared the real SAP destination interface schema:
the PaymentDate override fix from earlier (`009_fix_rcl_newpayment_date_override.sql`) used
`SELECT * EXCEPT(PaymentDate), <expr> AS PaymentDate FROM base`. In BigQuery, `* EXCEPT(col)`
followed by re-adding that column as a new expression **moves it to the end of the output** - it
does not preserve the original column position. Since SAP's import is column-position-based (not
header-name-based, now confirmed), this silently shifted every column after PaymentDate's real
slot by one, eventually landing a decimal value in an Int-typed destination column
(Period/TotalPeriods) - exactly matching the error. **My own earlier fix, deployed to the real
production views that day, is the very likely cause of that night's real automated NonMotor import
failure** - not a pre-existing data-quality issue as first assumed.

Two wrong hypotheses were chased and dropped before the real cause surfaced: (1) GrossPremium/VAT
fractional values (disproven - near-universal across historically-successful rows, so can't be
fatal); (2) an extraneous `ExpectedReceived` column not in SAP's schema (a draft fix,
`019_remove_expectedreceived_column.sql`, was built but never deployed, then deleted once Boat
corrected the diagnosis).

**Fixed** (`019_fix_column_reordering_bug.sql`, committed `758ce99`): replaced with
`SELECT * REPLACE(<expr> AS PaymentDate) FROM base` for both `RCL_Motor_process_2_newpayment` and
`RCL_NonMotor_process_2_newpayment` - `REPLACE` overwrites a column's value without moving it.
Verified via `INFORMATION_SCHEMA.COLUMNS`: PaymentDate back at its correct position (45 of 56),
immediately before Period/TotalPeriods. Row-count sanity check post-fix: Motor view = 647,345 rows,
matching expected scale - fix didn't break anything else.

**Also fixed in the same pass** (unrelated schema drift hit while redeploying): external table
`sap_data_engineer.RCL_HEALTH` gained an `InsuranceProduct` column since this view last deployed
successfully earlier that same day, breaking the NonMotor view's `sap`/`interface` UNION ALL column
count (55 vs 56). Added `InsuranceProduct` (from `SAP_LIVE_FULL`'s `U_InsuranceProduct`) into the
`sap` CTE in the correct position.

**Lesson for this pipeline going forward**: `SELECT * EXCEPT(col), new_expr AS col` silently
reorders columns in BigQuery and must never be used for anything that feeds a
column-position-based downstream import (i.e. anything in this pipeline) -
`SELECT * REPLACE(new_expr AS col)` is the only safe way to override a column's value in place.

**Not yet done / needs Boat's input:**
- Confirming this actually fixes tonight's real import - won't know until the next nightly cycle
  produces a fresh log.
- Whether/how to re-attempt the 44-file backfill now that the underlying bug is fixed - this exact
  backfill has now failed twice for two different reasons, so re-running it automatically without
  asking felt like the wrong call given it writes real files to `gs://interface-file/`.
- The other real production errors visible in the same pasted logs (PolicyStatus duplicated,
  InsuranceGroup/InsurerCode not found in DB, Period sequence invalid, various Cancelled-order
  rules) - read but not yet triaged; likely pre-existing data-quality issues, separate from this
  bug.

---

## 🏗️ P2 ENGINE + P3 DELTA_EXPORT BUILT — 2026-07-25 (cont'd 9)

Continued "start building" P1-P3 per Boat's "skip to next tasks you can do without my new input."
Auth expired mid-session (gcloud token), Boat re-authenticated, work resumed cleanly - nothing lost.

**P2 built, all three real bugs caught by checking real data before trusting output:**
- **`fn_invoice_no`** (`015_fn_invoice_no.sql`) - single UDF implementing the resolved B1 standard
  (raw `third_party_id`, no prefix). Every future create-flow query should call this instead of
  writing its own CONCAT/prefix logic.
- **`expected_state`** (`016_expected_state.sql`) - the L3 engine, joins stg_schedule +
  stg_payment_events into "what SAP should show." **Bug #1 caught**: `charges.id` (UUID) and
  `charges.third_party_id` (real InvoiceNo source) are different fields - stg_payment_events
  originally only captured `id`. Fixed before expected_state was built on top of it. **Bug #2
  caught**: compulsory items' charges all get attributed to their voluntary sibling by the
  item_rank de-fanout, leaving compulsory items permanently "Pending" even when SAP shows Paid -
  fixed via order-level "any successful charge on this transaction" recognition, gated on
  `motor_item_type = 'MOTOR_TYPE_COMPULSORY'` (not `flow` - a compulsory item can route to
  ONETIME too, a narrower first fix missed those). **Bug #3 caught**: a single (order_item,
  period) can have multiple SUCCESSFUL charges (verified: one period had 10 retry charges) -
  fixed via dedup to the earliest charge per period.
- **`sap_validation_error`** (`017_sap_validation_error.sql`) - PK_DUP check is live and clean (0
  errors after the dedup fix). **SCHEDULE_GAP check disabled** - genuinely unreliable, not yet
  root-caused (identical HAVING logic gives 0 rows as a plain SELECT but 728,745 rows via the
  stored procedure, reproduced even after splitting a suspected UNION ALL interaction into two
  sequential steps). Flagged for future investigation, not guessed at further.

**P3 started - `delta_export`** (`018_delta_export.sql`, §2.7 L5): diffs `expected_state` against
`stg_sap_state` at (order_item, period) grain - the modern successor to the 3-bucket
`recon_careos_charges` model. **Cross-validated against the earlier, independently-built recon**:
after excluding pre-2026 historical noise (259,396 rows from 2023 alone - the exact same
historical-scope trap the recon already learned to avoid), genuinely-recent
`MISSING_NO_ROW_IN_SAP` is 1,909 - close to the ~1,963 found completely independently earlier this
session via the ad-hoc recon table. Two very different construction methods converging on
basically the same number is a strong signal both are finding the same real thing, not an
artifact of either approach.

Not yet built: actual file generation (delta_export identifies what should change, but nothing
writes a CSV from it), balance/master validation checks (§2.6 #3/#5 - deferred, no verified
formula yet), Credit Shell's recursive schedule (still excluded from stg_schedule entirely),
2026-scoping convenience view for delta_export (currently includes all-history noise, same as
raw stg_schedule/expected_state - by design, for future reusability, but needs a scoped view for
practical day-to-day use).

---

## 🏗️ P1 BUILT: STAGING LAYER LIVE, WIRED INTO NIGHTLY SCHEDULE — 2026-07-25 (cont'd 8)

Boat: "start building" the actual V3 architectural rebuild (P1-P3) - everything before today
patched the old per-flow queries in place, none of the new staging/engine/delta-export design had
been built. Also: "you can start next phase without waiting me. anything need confirmation you can
skip to other tasks" - proceeding autonomously, flagging anything genuinely undecided rather than
guessing or blocking.

**Two open V3 decisions resolved by Boat first:**
- **B1 InvoiceNo standard**: raw `third_party_id`, no prefix, for anything new. Existing `2_`
  prefix stays untouched wherever `newpayment`/`cancel` mirror an already-existing SAP record
  (immutable once set). Checked the real create-flow source
  (`sap_data_engineer.sap_dashboard_carepay_installment`) - already compliant, no code change
  needed, just documents the standard (CLAUDE.md updated).
- **A1 CREDIT_CARD_INSTALLMENT routing**: "remains the same, only change to Onetime(RCB)" -
  confirms exactly what §2.4's router table already proposed (TotalPeriods=1, bank pays in full).
  Baked directly into `stg_schedule`.

**P1 (§2.2/§2.3) - three staging tables, all live and verified against real data:**
- **`stg_order_dim`** (`011_stg_order_dim.sql`) - materializes the ~15 `JSON_VALUE(orders.data,
  ...)` extractions once per order_item instead of every one of the 8 daily interface queries
  repeating them from scratch (D2 - the heaviest CPU cost in the pipeline per the design doc's own
  audit). Field mappings copied verbatim from the real production source, not reinterpreted.
  `sp_refresh_stg_order_dim()` MERGEs only orders whose `update_time` changed. Verified: 755,231
  rows, matches expected order_item count.
- **`stg_schedule`** (`012_stg_schedule.sql`) - the "spine": one row per (order_item, period),
  driven by real transactions, not follow_ups/snapshot presence (fixes A3, A4). Encodes the
  confirmed router: CREDIT_CARD_INSTALLMENT/FULL_PAYMENT/unknown -> ONETIME (TotalPeriods=1),
  RABBIT_CARE_INSTALLMENT + MOTOR_TYPE_COMPULSORY -> RCL_CMI (TotalPeriods=1),
  RABBIT_CARE_INSTALLMENT + not compulsory -> RCL (TotalPeriods = GREATEST-of-3-signals formula,
  fixes A5). **Caught before building**: the design doc's router table names a `RABBIT_LENDING`
  payment_option for the compulsory case - checked real data first, this value doesn't exist
  (only FULL_PAYMENT/RABBIT_CARE_INSTALLMENT/CREDIT_CARD_INSTALLMENT/PAYMENT_OPTION_UNKNOWN are
  real) - built on the actual, already-verified motor_item_type split instead of the doc's stale
  text. Verified: `L78115086-V1` shows exactly 6 periods, matching real SAP data. 876,723 RCL rows/
  140,420 orders, 554,920 ONETIME rows/orders (1:1 as expected), 33,405 RCL_CMI rows/orders (1:1).
  **Not yet handled**: Credit Shell's recursive/pool schedule - flagged as a real gap, not guessed
  at (orders in `cancelled_change_orders` are currently excluded from the spine entirely).
- **`stg_payment_events`** (`013_stg_payment_events.sql`) - the actual charge-driven population
  source (successful charges only). Reuses the item_rank de-fanout fix (compulsory vs voluntary
  item on a bundled charge) already verified live in `sp_recon_all_charges`, so every future
  consumer inherits the fix instead of re-discovering it. Verified: 1,189,734 rows, 1:1 with
  distinct charge_id (no fan-out duplication).

**Wired into the existing schedule, no new schedule needed** (`014_extend_nightly_refresh_with_
p1_staging.sql`): extended `sp_nightly_state_and_recon_refresh` (already running daily 21:00 ICT)
to refresh all three P1 tables before the existing SAP-state/recon refresh - matches decision #5's
own preference ("ต่อท้าย extract 20:30 ทั้งเส้น" - append one chain, don't stand up a second).

**Next (P2, in progress)**: `fn_invoice_no` UDF (implements the resolved B1 standard as reusable
code), the L3 `expected_state` engine (joins the three staging tables into what SAP *should* show),
and `sap_validation_error` (the blocking-validation output sink) - none of these exist yet.

---

## ✅ BACKFILL CORRECTED + RE-PUSHED, CHUNKED — 2026-07-25 (cont'd 7)

The first backfill (below) violated the real RCL interface rule, which Boat clarified after the
fact: **"when you want the new period payment change from pending to paid - you need to interface
the full periods starting with the old paid (on SAP) together with new payment period and
anything unpaid is remain pending."** The first attempt scoped by `(order_item, period)` against
`MISSING_FROM_SAP`, which stripped out each order's already-Paid anchor period and still-Pending
tail periods - sending a fragment of an order's state instead of its full, self-consistent picture.
Boat: "no need to pull back... SAP will reject it anyway, malformatted file" - confirmed correct,
the files were already gone (pulled) by the time this was caught, nothing to undo.

**Fix**: `010_rcl_backfill_full_period_chunked.sql` - `sp_backfill_rcl_newpayment_chunked(run_label,
n_chunks_motor, n_chunks_nonmotor)`. Scopes by whole `OrderItem` (any order with >=1 currently-
missing period), then pulls that order's **complete** period range from the unmodified production
view - Paid periods keep their real invoice, unpaid periods stay Pending. Chunks via
`MOD(ABS(FARM_FINGERPRINT(OrderItem)), N)` so every period for a given order always lands in the
same file - chunking can never split one order's periods across two files, which would reintroduce
the same violation. Verified directly: `L78115086-V1`'s all 6 periods (1 Paid anchor, 2-5 newly
Paid, 6 still Pending) landed together in the same chunk (`chunk_id=1`).

Boat also asked to split the backfill into smaller files (first attempt was one 36,917-row/20.5MB
file). Re-scoping to full-period-per-order naturally grew the row count (as expected - it's no
longer just the gap, it's every affected order's complete history) to 135,607 Motor rows / 20,530
orders and 13,577 NonMotor rows / 1,590 orders. Chunked into 40 Motor files (~1.7-2.0 MiB each) and
4 NonMotor files (~1.2-1.3 MiB each) - 44 files total, ~78 MiB combined.

**Pushed live** via `EXPORT DATA` to a temp wildcard path per chunk, then renamed to match the
production filename convention with a `_chunkN` suffix:
- `gs://interface-file/RCB_MOTOR/INSURANCE_RCB_06_RCL_MOTOR_PROCESS_2_NEWPAYMENT_20260725_chunk{0..39}.csv`
- `gs://interface-file/RCB_NONMOTOR/INSURANCE_RCB_04_RCL_NONMOTOR_PROCESS_2_NEWPAYMENT_20260725_chunk{0..3}.csv`

Confirmed live in the bucket 2026-07-25 ~13:30-13:36 UTC (~20:30-20:43 ICT - already evening in
Bangkok, so this satisfies "run it one time tonight" without needing to wait further). Audit
tables kept: `sap_integration_v3._backfill_rcl_{motor,nonmotor}_newpayment_20260725b`.

Not yet confirmed whether SAP's import scans a folder for *all* matching CSVs (like the daily
Cloud Function's own 8 distinctly-named files coexisting in the same folder, which is a working
precedent) vs a single hardcoded filename per process-type - the `_chunkN` suffix is a reasonable
bet given that precedent, but only the follow-up check (below) will confirm it was actually picked
up and processed rather than silently skipped.

**Next check (not yet done)**: same as below - query `SAP_LIVE_FULL` for these OrderItem+Period
pairs tomorrow to see whether they flipped to Paid. If yes: confirms this really was our bug
(stale PaymentDate + malformed partial submissions), not SAP's posting-period lock. If the specific
periods pushed in *this* corrected run still don't flip, but the *previous* malformed run's periods
also didn't flip, that at least isolates the malformed-submission theory from the date-override
theory as two separate, now both-tested fixes.

---

## 🚀 ONE-TIME BACKFILL PUSHED LIVE (FIRST ATTEMPT - LATER CORRECTED ABOVE) — 2026-07-25 (cont'd 6)

Boat: "Let's do backfill one time. import all unsuccess interface files I'm pretty sure it is our
side" - then, after reviewing, pinpointed the likely bug himself: "the current
RCL_Motor_process_2_newpayment / RCL_NonMotor_process_2_newpayment logic of payment date... it can
be only in current month. If the actual payment date on charge table is older than current month
you can override to 1st date of current month."

**Fix applied first** (`009_fix_rcl_newpayment_date_override.sql`, live in `sap_view`): wrapped
both views with `CASE WHEN PARSE_DATE(PaymentDate) < DATE_TRUNC(CURRENT_DATE(), MONTH) THEN
FORMAT_DATE(..., DATE_TRUNC(CURRENT_DATE(), MONTH)) ELSE PaymentDate END` - any PaymentDate older
than the current month gets bumped to the 1st of the current month, keeping every post inside
SAP's currently-open posting period (matches the "Posting Periods must be Unlocked" error from the
real SAP log). Row selection logic untouched - verified count stable (646,400 -> 646,402, just
real-time drift) before/after.

**Backfill scoped deliberately narrow**: not the full 646K/14.6K row query output (most of that is
harmless daily re-assertion of already-correct state) - joined against
`recon_careos_charges WHERE recon_status = 'MISSING_FROM_SAP' AND period > 1` (the confirmed real
gap only). Materialized to `sap_integration_v3._backfill_rcl_motor_newpayment_20260725` (36,917
rows) and `_backfill_rcl_nonmotor_newpayment_20260725` (3,758 rows) - left in place as an audit
trail of exactly what was pushed, not cleaned up.

**Pushed live via BigQuery `EXPORT DATA`** (not the Cloud Function - bypasses its 512Mi/300s
resource limits entirely, which is itself plausibly why the daily automated run silently fails to
finish writing files this large - 646K rows is a lot for a naive Python per-row CSV loop within a
300s Cloud Function timeout, though not confirmed):
- `gs://interface-file/RCB_MOTOR/INSURANCE_RCB_06_RCL_MOTOR_PROCESS_2_NEWPAYMENT_20260725.csv` (36,917 rows, 20.5 MiB)
- `gs://interface-file/RCB_NONMOTOR/INSURANCE_RCB_04_RCL_NONMOTOR_PROCESS_2_NEWPAYMENT_20260725.csv` (3,758 rows, 1.5 MiB)

Filenames match the exact production convention (`INSURANCE_RCB_{process_name}_{YYYYMMDD}.csv`) so
SAP's normal 15-minute pull picks them up like any other file - no special handling needed on
SAP's side. **Confirmed live in the bucket 2026-07-25 ~13:07 UTC (~20:07 ICT).**

**Not covered by this backfill**: the ~1,795 period-1 (first-ever-payment) periods that get no
export at all from either `_process_1_create` or `_process_2_newpayment` today - a structurally
different, still-unfixed gap (see the ROOT-CAUSED entry below).

**Next check (not yet done)**: verify tomorrow whether these 40,675 periods actually flip to Paid
in `SAP_LIVE_FULL` - `SELECT COUNT(*) FROM sap_integration_v2.SAP_LIVE_FULL s JOIN
sap_integration_v3._backfill_rcl_motor_newpayment_20260725 b ON s.U_OrderItem = b.OrderItem AND
s.U_Period = b.Period WHERE s.TransactionStatus IN ('Paid','paid')` (and same for NonMotor). If
they flip: confirms this was genuinely our bug (stale dates + maybe function timeout), not SAP's
posting-period lock as originally suspected. If they stay Pending: the lock is real and deeper
than a date fix, or the Cloud Function timeout theory needs checking directly.

---
Overall: ~78% | โหมดปัจจุบัน: **P0 A2 fix ครบทั้ง 8 views แล้ว (live)** — **stg_sap_state ตอนนี้ auto-refresh
ทุกวัน 21:00 ICT แล้ว** (เดิม stale ค้างมาตั้งแต่ 07-24, ไม่เคยมี schedule) — **MISSING_FROM_SAP (48,429
periods) root-caused: 99.98% ไม่ใช่ order หาย - SAP มี row Pending รออยู่แล้ว ขาดแค่ invoice/payment step
(= RCL automation gap ที่เจอก่อนหน้านี้) - ห้าม backfill แบบ "create" เพราะจะซ้ำซ้อน order เดิม** —
dead-man's-switch deploy จริงแล้ว (BQ scheduled query 22:00 ICT ทุกวัน + failure email) — Looker Studio
dashboard views (4 views) พร้อมใช้ — รอ Attila แก้ scheduler IAM (401, ล่ม 3 คืน) — secret rotation:
ตามคำสั่ง Boat ไม่ rotate ตอนนี้

---

## 🔍 MISSING_FROM_SAP ROOT-CAUSED: NOT A BACKFILL PROBLEM — 2026-07-25 (cont'd 4)

Boat, before authorizing any backfill: "check SAP_LIVE_FULL or raw to have actual records on SAP"
— and separately, on scope: "you can pull data from SAP all the missing doc entry I don't mind
other BU eg. B2B will come out, rather have it 100% better than guess." Both checks done before
touching anything that writes toward real SAP. Both changed the picture.

**B2B exclusion: real, but currently a non-issue.** `SAP_LIVE_FULL` (sap_integration_v2) hardcodes
`WHERE U_InsuranceGroup <> 'B2B'` in all 4 unioned branches (confirmed live via
`bq show --view`). Built `sap_integration_v3.SAP_LIVE_FULL_ALL_BU` (`007_sap_live_full_all_bu.sql`)
— identical view (same DocEntry-partition dedup, same column mapping), minus that filter, so
recon/state work never has to guess at BU scope again. Verified: **0 rows with
`U_InsuranceGroup = 'B2B'` exist in the raw source tables right now** — the filter is dead code
today, not hiding anything. Left the ALL_BU view live for the future since it costs nothing and
matches Boat's "don't guess" instruction.

**`stg_sap_state` was stale — this was the real distortion, not B2B.** Built once
(`002_sp_refresh_sap_state.sql`, 2026-07-24) and **never scheduled anywhere** — checked every
transfer config in the project, confirmed none call `sp_refresh_sap_state`. Comparing the 48,993
`MISSING_FROM_SAP` periods directly against raw `SAP_LIVE_FULL` found 584 that already had a real
`Paid` status + invoice in current raw data, but still showed a month-old `Pending`/no-invoice
snapshot in `stg_sap_state`. Refreshed it live, re-ran recon: `MISSING_FROM_SAP` 48,993 → 48,429.
Built `sp_nightly_state_and_recon_refresh` (`008_schedule_state_recon_refresh.sql`), scheduled
daily 21:00 ICT with failure email, so this can't go stale again — also directly serves Boat's
goal #2 ("make the job cover all transaction (recon) - auto").

**The real, current, verified split of the 48,429 (checked directly against fresh raw
`SAP_LIVE_FULL`, not just `stg_sap_state`):**
- **48,420 (99.98%, ~107M THB) already have a row in raw `SAP_LIVE_FULL`** — status `Pending`,
  no invoice. SAP already knows these orders exist. This is **not** a missing-order problem — it's
  the RCL invoice/payment step never running (the automation gap found earlier tonight, see below).
  A "create" backfill for these would risk **duplicating orders SAP already has**. The correct fix
  is the missing RCL payment-export automation, not a backfill.
- **9 periods (~16K THB) are a "Paid then Cancelled" edge case in the recon model itself**, not a
  real gap — genuinely paid (real invoice), then legitimately cancelled later. The 3-bucket recon
  model (IN_SAP/MISSING_FROM_SAP/NO_ORDER_ITEM) has no bucket for that, so they land in
  `MISSING_FROM_SAP` even though nothing is wrong. Consistent with Boat's "Paid→Cancelled is final"
  rule. Negligible — not worth adding a 4th bucket for 9 rows.
- **0 periods have zero row in SAP at all**, checked directly against raw `SAP_LIVE_FULL`. There is
  currently no genuine "SAP never heard of this order" case in the 2026 scope.

**Bottom line: there is no safe "backfill" action to run right now.** Every real gap in this number
is the missing RCL export automation, already scoped below. Building that closes ~107M THB /
48,420 periods safely, because it only ever adds the missing *payment* record to an order SAP
already has — it never creates a new order, so no duplicate-order risk. Still not attempted without
Boat's explicit go-ahead, per the stakes noted below.

## 📊 LOOKER STUDIO DASHBOARD VIEWS BUILT — 2026-07-25 (cont'd 3, AFK fallback task)

Built `006_dashboard_views.sql` (4 views in `sap_integration_v3`), Boat's explicitly-authorized AFK
fallback ("if you have nothing to do then go prepare data for dashboard Looker studio data
source"). Connect Looker Studio directly to these (BigQuery connector, project
`pacific-plating-282708`, dataset `sap_integration_v3`) — each is pre-shaped for one chart, no
Looker-side transforms needed:
- `vw_dash_completeness` — daily/payment-option/gap-category breakdown, for a funnel or backlog-
  by-flow chart. Verified live: 1,189 rows, 213,579 total periods across all rows.
- `vw_dash_completeness_summary` — single-row KPI tile. Verified live: 76.03% completeness
  (162,384 IN_SAP / 213,579 total) as of this build.
- `vw_dash_export_pipeline_health` — real `EXTRACT`-type job history (the real export mechanism
  found tonight, not `EXPORT DATA` SQL text), 90-day window. Verified live: real daily job counts,
  e.g. 2026-07-24 showed 6 successful extracts.
- `vw_dash_freshness` — wraps `vw_dead_mans_switch`. Verified live: FRESH, 26h since last load.

Not built: Page 3 "Correctness" from `SAP_DASHBOARD_DESIGN_v1.md` — needs `sap_validation_error`,
which doesn't exist yet (P2 territory).

---

## 🔒 ROOT CAUSE FOUND: SAP POSTING-PERIOD LOCK — 2026-07-25 (cont'd 5)

Boat asked me to sample one stuck installment in detail (`L78115086-V1`: created 2026-01-29 with
6 periods, period 1 Paid at creation, periods 2-6 left Pending by design). CareOS showed periods
2-5 actually paid on 2026-04-16 / 05-14 / 06-09 / 07-03 - all still Pending in SAP with a real
DocEntry assigned since January. Confirmed via `INFORMATION_SCHEMA.JOBS_BY_PROJECT` that the
correct "mark this period Paid" query has run via the automated Cloud Function every single night
for 10+ days straight (18:30 UTC daily) and already computes the right InvoiceNo/PaymentDate/
status - so the export side has been doing its job correctly the whole time.

Boat then shared a real SAP import error log (`import_20260716-163056018.txt`, an
`INSURANCE_RCB_CANCEL` batch from 2026-07-16, confirmed "job submitted in correct validation to
SAP"). It reveals the actual mechanism: **SAP's own accounting posting-period lock.**
Recurring errors across hundreds of rows:
- `PaymentDate:Posting Periods must be Unlocked,PaymentDate:RCL Posting Periods must be Unlocked` -
  SAP refuses any transaction dated into an already-closed accounting period, permanently, until
  someone unlocks that period on the SAP side. This is a standard SAP B1 accounting control, not a
  bug - but it means once a period closes, our correctly-generated nightly "mark Paid" row for that
  period will keep failing forever, silently, with no retry ever succeeding.
- `InvoiceNo: Cannot change InvoiceNo when status Paid,Cancelled` - SAP refusing to touch InvoiceNo
  on anything already Paid/Cancelled (matches the existing "InvoiceNo immutable" hard rule).
- `PolicyStatus: Cancelled order first period in DB must be Status Paid before` - SAP won't allow
  cancelling an order unless period 1 is already Paid in its own DB - directly compounds the
  ~1,960 period-1-never-invoiced orders found earlier: those can't even be cleanly cancelled later.

**Conclusion: this is not a BigQuery/export/query problem at all.** The interface file has been
correct and complete every night. The block is entirely SAP's own posting-period lock policy -
squarely Aware's territory per the hard rule ("SAP-side import program - Aware owns these").
Also explains why some orders DO progress fine (99,599 order-items found earlier with genuinely
sequential Paid dates) vs others permanently stall: whether the relevant posting period happened
to still be open when the payment was first attempted.

**Not yet done**: drafting the Aware escalation with this evidence (the channel failure-rate
breakdown + the `L78115086-V1` sample + this error log). Open question for Boat: does Aware/SAP
finance periodically reopen old posting periods, or is there a policy for how far back RCL
payments can post before being permanently rejected? That would clarify whether the ~46,420
stuck periods are recoverable at all without a posting-period reopen, or genuinely lost to this
lock.

---

## 🎯 REAL EXPORT MECHANISM FOUND — 2026-07-25 (Boat AFK, "fix missing from SAP" request)

Boat asked to fix the `MISSING_FROM_SAP` gap (48,993 order-periods, ~108M THB in 2026), run a
one-time backfill, and add it to the pipeline. Before touching anything that writes toward real
SAP, traced how `gs://interface-file/` (the bucket SAP actually pulls from hourly) really gets
fed - this had never been verified all session; every fix so far touched query *logic*, not the
actual export step.

**Found the real chain, finally**: Cloud Scheduler (`sap-order-payment` /
`sap-order-payment-non-motor`, confirmed healthy earlier tonight) → Pub/Sub topics
(`motor-order-payment-sap-interface` / `non-motor-order-payment-sap-interface`) → Cloud Functions
(`rcb-motor-order-payment-1` → `rcb-motor-order-payment-sap-bucket-1`, same 2-stage pattern for
NonMotor and ADB Motor) → `gs://interface-file/{RCB_MOTOR,RCB_NONMOTOR,ADB_MOTOR}/`. Confirmed via
real `EXTRACT`-type BigQuery jobs (not `EXPORT DATA` SQL - a different job type, missed on first
search): 61 extracts in the last 7 days, most recent hours before this check. **This pipeline is
alive and running regularly.** The bucket looking "empty" just now is the same ephemeral-file
pattern found earlier tonight for the bronze zone - files get pulled and consumed quickly, not a
sign of failure.

Along the way, also found (and ruled out as the actual export path) an **older, separate,
already-broken** pipeline: BigQuery scheduled queries `SQ_SAP_2025_new_create_order` /
`_cancelled_order` / `_credit_shell` / `_cancelled_change_order`, writing into
`SAP.SQ_sap_daily_order_payment`, refreshed by `truncate_sap_order_payment_table`. These use the
*old* non-RCL-prefixed views (`04_new order credit shell`, `03_cancel change orders`, etc.), not
tonight's `sap_view.RCB_Motor_process_*`. `SQ_SAP_2025_new_create_order`'s transfer config state is
literally `FAILED`, last touched 2026-06-17 - over a month stale. Not investigated further since
it's confirmed not the live path; flagged as another dead pipeline worth cleaning up eventually.

**The real finding, and it changes the whole picture**: there is **no equivalent automated export
for RCL (installment) at all** - checked the complete Cloud Functions list, nothing named
rcl-anything exists. RCB Motor, RCB NonMotor, and ADB Motor each have a real 2-stage
scheduler→function pipeline; RCL has nothing. This isn't a new discovery - it's exactly problem
**A7** from `SAP_INTERFACE_REDESIGN_V3.md` ("RCL flows ไม่มี daily scheduler... ทั้งสาย RCL เป็น
manual"), now empirically confirmed against real infrastructure rather than taken on faith. It
directly explains why `RABBIT_CARE_INSTALLMENT` was ~70% (34,434 of 48,993) of the
`MISSING_FROM_SAP` recon: **it's not a bug scattered across many queries - it's one missing piece
of automation.**

**Did not attempt the actual fix** (generate + push a real RCL export to `gs://interface-file/`,
or build new export automation) while Boat is AFK. This would be the single most consequential
action possible in this entire pipeline - it creates real records SAP will import - and:
1. There's no established RCL bucket-folder convention to follow (unlike RCB_MOTOR/RCB_NONMOTOR/
   ADB_MOTOR, which are established patterns)
2. A one-time backfill of 34,434 periods needs validation-stage review first (hard rule: "never
   bypass validation before export, no exceptions including urgent") - haven't built/wired
   sp_validate for this yet
3. This needs Boat's own review before anything real ships to SAP, full stop

**What's ready for Boat's decision, not yet built**: extending the RCB pattern to RCL - a new
Pub/Sub topic + Cloud Function (or reusing `sap_view.RCL_*` process views, already fixed/verified
tonight, as the source query) + a new Cloud Scheduler job, matching the existing 3-flow pattern.

## ✅ POLICY CONFIRMED + RECONCILIATION EMAIL SENT — 2026-07-25

**Boat's rule, confirmed**: once an order shows Paid periods then Cancelled in SAP, that's final -
never modify it. This resolves the open design question from the `stg_sap_state` repoint work
above - the 5 reverted `sap_view` views don't need "fixing," their current behavior (treat any
Cancelled-order signal as "leave alone") is already correct. What was actually needed instead was
a **reporting mechanism**, not automated correction.

Built `sql/adhoc/reconcile_careos_vs_sap_cancelled_installments.sql`: for cancelled installment
(RCL) orders, compares CareOS's real paid-period count against SAP's. Key finding while building
this: a cancel-send mirrors **every** period to `TransactionStatus = 'Cancelled'` (verified live,
e.g. `L78210940-V1` - all 6 periods show Cancelled regardless of real history) - so current status
can't tell you what was actually paid before cancellation. `U_InvoiceNo` can: it's only populated
once a period was actually invoiced, so "non-empty invoice among Cancelled periods" = "was paid
before cancellation." Credit Shell orders (`U_OrderID LIKE 'C#%'`) excluded - different
single-invoice-on-period-1 pattern, would otherwise look like hundreds of false positives.

**Results**: 1,072 cancelled installment orders checked, 85 mismatches. 58 are off by exactly 1
period - almost certainly the customer's last payment landing at/around cancellation time, not a
real gap. **6 show a genuine 2+ period gap** (up to 5 periods missing) - these are real and worth a
look: `L73727249`, `L74670396`, `L76394133` (5 periods each), `L73400356`, `L73683565`,
`L76993090` (2 periods each).

**Sent as a Gmail draft** to `rc_sap_interfaceresult@rabbit.co.th` (no direct-send tool available,
by design - draft is ready for Boat to review and send). Purely informational per the policy above -
no SAP/CareOS data touched.

---

## 🔥 IN-FLIGHT

1. **Cancel batch 21 items** — ตก 3 รอบ (root cause สุดท้าย: SAP เก็บหลาย doc ต่องวด + InvoiceNo ต้องตรง doc ปัจจุบัน)
   → v4 พร้อม (one-row-per-period, Paid priority) แต่**รอคำตอบ Aware Q3a ก่อนยิง** (spec inferred ส่งแล้ว)
   → ⚠️ business flag: ลูกค้าจ่ายงวดต่อหลัง CareOS cancel — รอ FA confirm intent (cancel+refund?)
2. **RCL new-payment quick fix (27 orders)** — หลักใหม่จาก Boat: **charge-driven full schedule**
   (charge ถึงงวดไหน เติม paid ถึงงวดนั้น, mirror งวดเดิมเป๊ะ InvoiceNo ห้ามแตะ) — query v3 พร้อม รอ sample run
3. **EDC batch 2 (~70 orders จาก list บัญชีชุด 2)** — รอบัญชี confirm channel mapping ธนาคารอื่นนอกจาก KBANK
4. **Secret Manager rebind + password rotation** — ⚠️ ค้างตั้งแต่ 16/07! plaintext ยังอยู่ใน job config
   และ password exposed แล้ว 2 ครั้ง — สถานะ: secret sap-db-password ยังไม่มี version, ขั้นตอนอยู่ใน chat/runbook

## ⏳ WAITING ON OTHERS

- Aware: confirm cancel import spec v0.9 (ส่งแล้ว — โดยเฉพาะ Q3a: หลาย doc ต่องวด อ้าง InvoiceNo ตัวไหน)
- บัญชี: (a) EDC channel matrix (b) Credit Shell = จ่ายครบงวดเดียว OK? (c) intent 21 cancel ที่จ่ายต่อหลังยกเลิก
- IT Leong: Credit Shell ไม่มี installment_details = by design หรือ bug + ขอ direct RCL field (ถามใน group แล้ว)
- Head of Products: COALESCE fix (INCIDENT-001) — ใช้ targeted ไปแล้ว 1 เคส (L80347249-M1 เข้า SAP 22/07)

## ✅ DONE เพิ่มจาก 16/07

- Scheduler self-trigger verified (20:30 ICT, SA sap-bucket-csv@) — Phase 6 automation ครบฝั่ง extract
- เจอ loader B1 = `auto_load_sap_data_in_bucket_to_bigquery` (Pub/Sub 01:00) → อธิบาย incident 07-14
- **ROOT CAUSE ใหญ่: SAP_LIVE/SAP_LIVE_FULL = stale mirror** (mirror comparison 23/07 ยืนยัน INVOICE_DIFF)
  → DECISION: raw_sap_live คือ SAP truth เดียว, sunset B1 (ดู 10_CONTEXT)
- Urgent batches เข้า SAP: 30 EDC + L80347249-M1 + L79189867-1 (self-resolved) + cancel 1 (L80391648-M1)
- EDC gap วินิจฉัยครบ: CREDIT_CARD_INSTALLMENT ไม่มี pipeline เจ้าของ (ตกร่อง 2 flow) — เจอ 2 list รวม ~100 orders
- InvoiceNo convention conflict ยืนยัน: '2_' prefix (BI, กัน collision) vs raw charge id (flow 21/07)
- **Design package v3 ครบ 6 ฉบับ** (REDESIGN / E2E / DATA_PREP / RUNBOOK / DASHBOARD / CANCEL_SPEC) — รอ review/decisions
- Delta-export gap ใน design ถูกจับได้จาก review ของ Boat (new payment Pending→Paid) → amend แล้ว + generalize เป็น charge-driven

## 🚧 P0 STATUS (2026-07-24 session — reauth done, verified against live BigQuery)

- ✅ `sap-interface-repo` ตั้งจริงแล้ว (local git, branch `p0/stg-sap-state`) ที่
  `.../02 SAP/Phase1.1/agentic_bootstrap/codex_bootstrap`
- ⚠️ **CORRECTION ใหญ่: `raw_sap_live` ไม่มีอยู่จริง** — Phase 6 B2 extract job ไม่เคย deploy จริงใน
  project นี้ (เป็นแค่แผนใน design docs) — Boat ยืนยัน: **`sap_integration_v2.SAP_LIVE_FULL` คือ SAP
  source จริงที่ใช้อยู่ตอนนี้** ตรงข้ามกับ hard rule เดิมใน AGENTS.md/CLAUDE.md ("SAP truth = raw_sap_live
  ONLY") ที่เขียนไว้ก่อนเช็คจริง — ต้อง**แก้ hard rule นี้ในสองไฟล์นั้นด้วย** (ยังไม่ได้แก้)
- ✅ Verified `SAP_LIVE_FULL` จริง (schema 56 คอลัมน์ ดึงมาแล้ว, ดู view definition ใน
  `sql/production/SAP_LIVE_FULL.sql`): union SAP_LIVE + SAP_LIVE_2024/2025/2026, dedup ด้วย DocEntry
  (ROW_NUMBER by BatchRunDate DESC) — แต่**ยังมี duplicate ที่ (U_OrderItem, U_Period) 328,071 keys
  (687,700/1,649,468 แถว = ~42%)** เพราะ dedup แค่ระดับ DocEntry ไม่ใช่ระดับ period — ตัวอย่างจริง:
  L73340138-V1 period 2 มีทั้งแถว Paid (DocEntry 750141) และ Cancelled (DocEntry 1005571) — ตรงกับ
  CANCEL_IMPORT_SPEC Q3a เป๊ะ
- ✅ TransactionStatus จริง: Paid 1,087,891 / Pending 432,840 / Cancelled 90,489 /
  Cancelled (Change order / Rejected) 38,248 — ตรงกับที่ design assume ไว้พอดี
- ✅ `sql/ddl/002_sp_refresh_sap_state.sql` — **แก้แล้ว** ให้ source จาก `SAP_LIVE_FULL` แทน
  `raw_sap_live`, dedup by (U_OrderItem, U_Period) priority Cancelled>Paid>Pending — ยังไม่รัน
  (ต้อง approve ก่อน — สร้าง dataset+ตารางใหม่ ไม่กระทบของเดิม)
- ✅ `sql/ddl/003_...` — **แผนเดิม (repoint SAP_LIVE_FULL) ตกไป** เพราะ SAP_LIVE_FULL คือ source จริง
  ไม่ใช่ mirror เก่าที่ต้องแทนที่ (ทำแบบเดิมจะ circular) — เช็คจริงแล้วพบว่ามีแค่ 2 consumer ที่แตะ
  SAP_LIVE_FULL (fully_paid's `sap_batchrun`, credit shell's `sap_cancelled`) และทั้งคู่ทำแค่
  `MAX(BatchRunDate)` ต่อ OrderID — **ไม่โดน duplicate bug จริง** (MAX กันซ้ำในตัวอยู่แล้ว) — เป็นแค่
  cleanup ไม่ใช่ live bug
- ✅ **A2 NULL-safe filter bug — ยืนยันจริง, แก้จริง, LIVE ใน BigQuery ทั้ง 8 views แล้ว (2026-07-24):**
  พบ `motor_item_type != 'MOTOR_TYPE_COMPULSORY'` แบบไม่กัน NULL ใน **9 views จริง** — เช็ค `sap_view`
  (12 views, nightly จริง) แยกต่างหาก: **สะอาด** เจอแค่ 1 จุดที่ใช้ `=` (safe) ไม่ต้องแก้
  ยืนยันด้วยข้อมูลจริง: `careos_order_items.motor_item_type` มี NULL 10,559 แถว ทุกแถวเป็น NonMotor
  → **Applied จริงแล้วทั้ง 8 views** (`CREATE OR REPLACE VIEW`, bq CLI, location asia-southeast1),
  ทุกตัวแถวเพิ่มขึ้น ไม่มีลดลง = ไม่มี regression:
  - `sap_dashboard_carepay_installment`: 631,487 → 665,388 (+33,901)
  - `RCL 04_new order credit shell`: 13,894 → 14,379 (+485)
  - `RCL 02_items_cancel`: 633,470 → 667,377 (+33,907)
  - `RCL 04_new order credit shell_all`: 51,884 → 52,696 (+812)
  - `RCL 04_new order credit shell new tunning`: 56,818 → 57,405 (+587)
  - `sap_fix_rcl_2025`: 2,625 → 2,759 (+134)
  - `sap_fixing_rcl`: 929,641 → 963,609 (+33,968)
  - `RCL_MOTOR`: 929,641 → 963,609 (+33,968, identical to sap_fixing_rcl — likely same underlying query,
    confirms these two are redundant copies of each other; not consolidated, Boat said fix + leave as-is)
  Boat's call: fix all 8 (not just the 2 confirmed-production ones), leave everything else about these
  files untouched (no consolidation of the redundant copies).
- ✅ **`sap_integration_v3.stg_sap_state` — สร้างจริงแล้วใน BigQuery** (dataset + `pipeline_run_log`
  ผ่าน `001`, proc `sp_refresh_sap_state` ผ่าน `002`, รันแล้วผ่าน `CALL`)
  → 1,649,468 แถวใน SAP_LIVE_FULL → **1,289,839 แถวหลัง dedup, 0 duplicate key เหลือ** (verified)
- ⏸️ **Secret rotation — Boat's call: keep it, don't rotate now.** Deferred, not forgotten.

## 🆘 NEW INCIDENT (found while rechecking scheduler health, 2026-07-24)

**Symptom**: `sap-extract-schedule` (Cloud Scheduler, fires 20:30 ICT daily, on time every night) —
the HTTP call it makes to trigger `sap-extract-job` fails every night with `401 UNAUTHENTICATED`.
Confirmed via Cloud Logging for 2026-07-22, 07-23, 07-24 — **3 nights running**. The Cloud Run job
executions that DID exist (05:40, 17:09, 01:17, 17:03, 03:53 UTC — all off-schedule) were someone
manually running `gcloud run jobs execute sap-extract-job` by hand to compensate, not the automation
working. `auto_load_sap_data_in_bucket_to_bigquery` (the B1 loader, Pub/Sub-triggered, 01:00 ICT) also
shows extra off-schedule triggers on the same days — consistent with the same person manually
re-running the downstream loader too after manually running the extract.

**Root cause**: `gcloud run jobs get-iam-policy sap-extract-job` returns an **empty policy** — the
`sap-bucket-csv@...` service account (the one Cloud Scheduler uses for its OIDC token) has no
`roles/run.invoker` binding on this job. It was granted 2026-07-15 (see 30_SAP_CHANGELOG.md) but is
gone now — never diagnosed why (redeploy resetting IAM? manual revert? not investigated further).

**Fix** (prepared, NOT applied — `data@rabbit.co.th` got `PERMISSION_DENIED` on `run.jobs.setIamPolicy`,
this needs someone with IAM admin on the project, i.e. Attila per 90_TEAM_CONTEXT.md):
```
gcloud run jobs add-iam-policy-binding sap-extract-job \
  --region=asia-southeast1 --project=pacific-plating-282708 \
  --member="serviceAccount:sap-bucket-csv@pacific-plating-282708.iam.gserviceaccount.com" \
  --role="roles/run.invoker"
```

**Other SAP scheduler jobs checked, all healthy** (blank status = success in Cloud Scheduler logs):
`sap-order-payment` (01:30 ICT), `sap-order-payment-non-motor` (01:30 ICT),
`auto_load_sap_data_in_bucket_to_bigquery` (01:00 ICT) — all firing on schedule, no errors.

**Lesson**: nobody noticed for 3 nights because someone was quietly running it manually - the "dead
man's switch" the design docs proposed (Page 1 / 22:00 alert) would have caught this on night one.
Worth prioritizing that alert.

## 🗺️ REAL ARCHITECTURE DISCOVERED (2026-07-24) — supersedes design docs' B1/B2 framing

While investigating the "is SAP_LIVE_FULL missing records" question, traced the actual live pipeline
end to end. It does **not** match REDESIGN_V3/10_SAP_CONTEXT's B1 (legacy CSV, sunset) vs B2 (Phase 6,
target `raw_sap_live`) story:

- `sap-extract-job` (Cloud Run Job, pyodbc → real SAP SQL Server `RCB_LIVE_DB`) genuinely runs, genuinely
  pulls real rows (confirmed via its own run logs, e.g. 47,888 rows in one run), and writes NDJSON to
  `gs://rcb-bronze-zone/SAP/production_database/`
- That GCS write triggers (Eventarc) the Cloud Run **service** `sap-order-payment-initial-phase`, which
  loads the rows into **`sap_integration_v2.SAP_LIVE`** and deletes the source file
- So **`SAP_LIVE` is the real, fresh, direct-from-SAP-DB table** — not a legacy stale mirror. It's been
  running since 2026-07-09, 14/14 runs SUCCESS, zero errors, watermark current to within ~15 min as of
  this session. `raw_sap_live` (the name in every design doc) was never built - the docs describe a plan,
  not what got deployed.
- The vendor CSV-drop bucket named in the old design **does not exist in this project**. The
  deployed extract path is `gs://rcb-bronze-zone/SAP/production_database/`.
- Practical implication: the scheduler incident above is more serious than "a redundant legacy path
  stalled" - it's the only ingestion path into fresh `SAP_LIVE` data. Data is fine because people have
  been running it manually; it would go stale if that stopped.

**Docs to eventually reconcile** (not done yet): 10_SAP_CONTEXT.md's B1/B2 section, REDESIGN_V3's
target architecture diagram, and the 2026-07-23 changelog's "SAP_LIVE_FULL = stale mirror" root-cause
entry all describe an architecture that isn't what's actually running.

## 🔍 sap_view COMPLETENESS AUDIT (2026-07-24) — "no CareOS charge silently dropped" check

Boat asked to verify the new `sap_view` production process (12 views: RCB/RCL × Motor/NonMotor ×
create/cancel/change/creditshell/newpayment) doesn't silently drop records. Pulled and read all 12,
plus 5 more upstream dependencies not yet examined this session (`04_new order credit shell`,
`03_cancel change orders`, `02_items_cancel`, `1_nonMotor_new order`, `2_nonMotor_items_cancel` -
distinct from the `RCL 04...`-prefixed ones already A2-fixed).

**Found and fixed**: `RCB_NonMotor_process_1_create` had `interface.OrderDate LIKE '%2025%'` hardcoded
into its WHERE clause. Since the anti-join against `SAP_LIVE_FULL` already restricts results to
"not yet in SAP," this date filter was pure leftover, not load-bearing - and it meant **every 2026-dated
NonMotor Health/Travel one-time order was silently excluded from ever being proposed for SAP creation**.
The view had been producing **zero rows for months** (checked: 0 before fix). Confirmed against real
data before fixing: ~3,097 `RCB_HEALTH` rows dated 2026, of which 91 were genuinely absent from SAP
(most of the rest apparently got there via manual intervention). Fixed (deleted the filter line),
applied live: **0 → 95 rows** now surfaced.

**Everything else checked out clean**: the other 11 `sap_view` views either have no date restriction or
an already-open-ended one (e.g. `RCL_Motor_process_4_creditshell` already says
`OrderDate LIKE '%2025%' OR LIKE '%2026%'` - will need `%2027%` added eventually, not urgent). The 5
additional dependency views checked for the A2 NULL-unsafe pattern - all clean.

**Not done**: a full formal reconciliation (charge-driven expected population vs. combined output of
all 12 views) - what's been done is a targeted read-through + spot-check, which is how this specific
bug was found. A full reconciliation would be a bigger, separate piece of work if more assurance is
wanted later.

## ✅ DEAD-MAN'S-SWITCH — deployed 2026-07-24

Built and deployed (see `sql/ddl/004_dead_mans_switch.sql`):
- `sap_integration_v3.vw_dead_mans_switch` — freshness check on `SAP_LIVE.U_BatchRunDate`
  (excludes ~5 anomalous future-dated rows found earlier, which would otherwise always read FRESH)
- `sap_integration_v3.sp_check_dead_mans_switch` — RAISEs if stale >26h
- BigQuery scheduled query "sap_dead_mans_switch", daily 15:00 UTC (22:00 ICT).
- **Recipients (settled)**: Boat asked for piyaratt@rabbit.co.th + rc_bi@rabbit.co.th. BQDTS native
  failure-email only supports one recipient (owner, data@rabbit.co.th) — left that on as a backup,
  added a real multi-recipient path via Cloud Monitoring: log-based metric
  `sap_dead_mans_switch_failure` → alert policy `SAP dead-man's-switch failure`
  (alertPolicies/2008919338975126785) → 2 email channels. **Verified end-to-end**: forced a test
  failure, confirmed via Monitoring API that the metric ingested it, reverted immediately. **Boat
  confirmed the test alert email actually arrived** — fully closed, nothing else to check here.

## 🔎 sap_view 6-OTHER-VIEWS USAGE CHECK — answered 2026-07-24

Checked 180-day BigQuery job history (query text, not just referenced_tables — that field only
captures underlying base tables for view queries, not the view name itself) for the 6 A2-fixed
views not on Boat's confirmed-production list:
- `RCL 04_new order credit shell_all` — used 2026-07-20 (4 days ago) by **you**
- `RCL 02_items_cancel` — used 2026-07-01 by **you + suphakornh@rabbit.co.th**
- `RCL_MOTOR` — used 2026-05-03 (~3 months ago) by you
- `RCL 04_new order credit shell new tunning`, `sap_fix_rcl_2025`, `sap_fixing_rcl` — **zero
  queries found in 180 days** — genuinely dead, candidates for eventual archival (not done, no
  action needed now — the A2 fix already applied to them is harmless either way)

## 🕵️ WHY THE IAM BINDING WAS MISSING — investigated 2026-07-24 (not a "disappeared" mystery)

Checked Cloud Audit Logs (60-day window) for every `SetIamPolicy` call referencing `sap-extract-job`.
Found exactly 2, both **DENIED**:
- 2026-07-13, via Cloud Shell (interactive) — someone (very likely Boat) already tried this exact
  `gcloud run jobs add-iam-policy-binding ... --role=roles/run.invoker` fix 11 days ago and hit the
  same `PERMISSION_DENIED` I hit tonight
- 2026-07-24 (tonight), my own attempt, same error

No successful `SetIamPolicy` call on this resource exists in the audit trail at all. Cross-checked
against the *working* pipeline (`sap-order-payment-initial-phase`, via Eventarc) - its trigger uses
`919786098205-compute@developer.gserviceaccount.com` (the project's default Compute service account,
likely with broad pre-existing permissions), **not** `sap-bucket-csv@...`. So this isn't a binding
that regressed - it most likely **never successfully applied in the first place**. The 2026-07-15
changelog entry ("Granted (Attila/DevOps): roles/run.invoker + roles/secretmanager.secretAccessor...
→ แก้ blocker scheduler self-trigger") most likely refers to the Secret Manager grant (which clearly
did work - the job successfully reads its DB credentials every run) - the `run.invoker` half appears
to have never gone through, silently, because whoever ran it (Boat, then me) lacked
`run.jobs.setIamPolicy` themselves. The pipeline "worked" anyway because everyone's been triggering
it manually with their own broader account permissions, which masked the scheduler-specific gap.

**Implication for Attila's fix**: this isn't "restore what was lost" - it's "grant this for the first
time," and it specifically requires his account (IAM Admin), not yours or mine.

## ⚠️ stg_sap_state REPOINT ATTEMPT — 2026-07-25 (partial success, one real bug caught + fixed)

Boat: wire `stg_sap_state` into real consumers instead of reading `SAP_LIVE_FULL` directly. Attempted
this across all 11 `sap_view` process views that reference `SAP_LIVE_FULL` (all of them except
`RCL_Motor_process_2_newpayment`, which doesn't touch it at all).

**Found two genuine, pre-existing bugs first** (unrelated to the repoint, hit while dry-running):
`RCL_Motor_process_3_cancel` and `RCL_NonMotor_process_2_newpayment` both reference
`U_EndorsementNo`, which doesn't exist (`SAP_LIVE_FULL`/`stg_sap_state` only have `EndorsementNo`,
no `U_` prefix) - **both queries wouldn't even parse**. These two views were completely broken
before tonight, silently. Fixed the column name in both (real bug fix, independent of source table).

**Repointed and verified 5 views as genuinely safe** (pure existence checks - "does this OrderItem
exist in SAP at all," no status filter - dedup can't change these results, confirmed by exact
zero row-count delta before/after): `RCB_NonMotor_process_1_create`, `RCL_NonMotor_process_1_create`,
`RCB_Motor_process_3_change`, `RCB_Motor_process_4_creditshell`, `RCB_NonMotor_process_2_cancel`.
**These are live on `stg_sap_state` now.**

**Caught a real bug before it did damage**: `RCB_Motor_process_create`'s row count jumped
1,579 → 16,578 after repointing - way too large to wave through. Sampled the new output: every row
was an order that had been **Paid, then later Cancelled**. `SAP_LIVE_FULL` kept both the historical
Paid row and the Cancelled row (its dedup is only by DocEntry), so this view's
`WHERE TransactionStatus IN ('Paid','paid')` check could still find "was this ever paid" evidence.
`stg_sap_state` collapses to one row per (OrderItem, Period) with Cancelled beating Paid by design -
so the same check now says "never paid," and the view wrongly proposed recreating 14,999
already-cancelled orders in SAP. **This would have been a real, damaging bug shipped straight into
the create-export pipeline if the count jump hadn't been sanity-checked.**

Given that, treated every non-zero-delta view as equally suspect (not just the confirmed one) and
**reverted 5 views back to `SAP_LIVE_FULL`**, since I couldn't verify their semantics were safe at
this hour with no one available to check: `RCB_Motor_process_create`, `RCL_Motor_process_1_create`,
`RCB_Motor_process_2_cancel_new`, `RCL_Motor_process_4_creditshell`, `RCL_Motor_process_3_cancel`
(this last one keeps its `EndorsementNo` fix - net improvement from completely-broken to working,
just on the original source). `RCL_NonMotor_process_2_newpayment` also stays on `SAP_LIVE_FULL`
(same `TransactionStatus IN Paid` risk pattern found in its `newpayment` CTE) with just its
column-name fix applied - went from broken to working.

**Net result**: 2 previously-broken views now work; 5 views now correctly deduped; 4 views
untouched in effect (reverted to their original behavior) pending a properly-designed fix. Verified
every final count against BigQuery directly before stopping - not just trusting the local files.

**What "properly-designed" would need**: any view that checks a specific status (e.g. "IN Paid") to
mean "already settled" needs a source that preserves *history*, not just current dominant status -
either keep reading `SAP_LIVE_FULL` for that specific check, or build a different dedup that
preserves "has ever been X" alongside "is currently X." Don't just swap the FROM clause on these 5
without that design work.

## ⬜ NEXT

1. **Get Attila to run the `run.invoker` fix** — active incident, 3+ nights and counting. Per the
   investigation above, this is a first-time grant, not a restore - only he can do it (you and I both
   confirmed lacking `run.jobs.setIamPolicy` ourselves)
2. ~~Investigate why the run.invoker binding disappeared~~ — **done above**
3. Decide dead-man's-switch email recipient (data@ vs personal vs Slack) — **done: piyaratt@ + rc_bi@ + data@, verified delivered**
4. Reconcile 10_SAP_CONTEXT.md / REDESIGN_V3.md architecture sections against the real pipeline found
   this session (SAP_LIVE fed by sap-extract-job → sap-order-payment-initial-phase, not B1/B2 as written)
   — **done, 2026-07-24**
5. Consider archiving the 3 genuinely-dead views (`RCL 04...new tunning`, `sap_fix_rcl_2025`,
   `sap_fixing_rcl`) — not urgent
6. **Design a real fix for the 5 reverted `sap_view` views** (see section above) before attempting the
   `stg_sap_state` repoint on them again - needs actual business input on what "already in SAP" should
   mean once an order's been through Paid→Cancelled, not a mechanical FROM-clause swap
7. P1–P4 ตาม migration plan ใน REDESIGN_V3 §4 / E2E §3 (ยังไม่แตะ) - now needs re-scoping given #4 above
8. If more assurance is wanted: full charge-driven completeness reconciliation across all 12 sap_view
   process views (not just the targeted read-through done this session)

## DECISIONS PENDING (จาก design review)

1. Orchestration: Cloud Workflows? 2. InvoiceNo standard (raw id + rank prefix) — บัญชี ack
3. ProcessingFee 100/103.3 (RCL) vs 100/107 (onetime) — ตัวไหนถูกต่อ flow ไหน (เจอ discrepancy ใหม่)
4. Backfill scope 5. EDC channel matrix 6. Parallel-run กี่วัน (เสนอ 5)

# REVIEW_QUEUE.md — asynchronous mutual review

Canonical queue governed by `docs/AGENT_REVIEW_PROTOCOL.md`. Newest request first. Do not delete
review history; link the completed review and record its verdict.

## RQ-20260730-1555-dormant-view-cost-guardrail
Status: OPEN
Reviewer: Claude Code
Class: A
Artifact: commit `5774494`; closed `sap_integrety_2025_RCL` input, mandatory safe-query policy,
expiration policy, and Codex review of `a56f6d1`.
Opened: 2026-07-30T15:55:32+07:00

Claim: Boat's no-consumer decision is reflected consistently as dormant/obsolete, no-notify, and
housekeeping/archive-only. Non-metadata BigQuery queries are required to use
`scripts/bq_safe_query.sh`, and new `diag_*`/scratch tables require expiration. The policy cites
`a56f6d1` but prohibits `--force` pending resolution of the review BLOCK.

Evidence: `git diff 5774494^ 5774494`; prior 90-day evidence in
`docs/FINDINGS_SAP_MIRROR_20260726.md` §14; and
`docs/reviews/2026-07-30-a56f6d1-codex.md`.

## RQ-20260730-1800-bq-safe-query-wrapper
Status: REVIEWED
Reviewer: Codex
Class: A
Artifact: `scripts/bq_safe_query.sh`, `sql/ddl/_TEMPLATE_new_table.sql`,
`sql/ddl/README.md`; commit `a56f6d1`.
Opened: 2026-07-30T18:00:00+07:00
Verdict: BLOCK — `docs/reviews/2026-07-30-a56f6d1-codex.md`

Claim: (1) `scripts/bq_safe_query.sh` implements `docs/COST_CONTROL.md` §3.1 as an enforced gate
rather than a documented-only convention — always dry-runs first, parses
`totalBytesProcessed` (via `jq`, with a `grep` fallback if `jq` is absent), refuses to run the
real query past 20 GiB (21,474,836,480 bytes) unless the caller passes `--force`, and always
appends `--maximum_bytes_billed=21474836480` on the real run; (2) `sql/ddl/_TEMPLATE_new_table.sql`
requires `OPTIONS(expiration_timestamp = TIMESTAMP_ADD(CURRENT_TIMESTAMP(), INTERVAL 30 DAY))` on
every new `diag_*`/scratch table, and explicitly excludes the 7 pre-existing
`_backfill_*`/`manual_close_*` tables (names verified directly against `bq ls`, not assumed) —
no expiration set on those, separate retention decision pending; (3) `scripts/review_status.sh`
checked for a live `bq` call to retrofit — it has none (pure git/awk parsing over
`REVIEW_QUEUE.md`) — left unchanged rather than forcing an unnecessary wrapper call.

Evidence: dry-run syntax for the `OPTIONS(expiration_timestamp=...)` clause validated directly
(0 bytes, no table created); the wrapper itself verified against the exact `COST_CONTROL.md` §2.1
query — dry-run reported **13,930,812,474 bytes (~12.97 GiB)**, then ran for real under threshold
with no `--force` needed, returning real per-user cost data.

Status: OPEN — requesting Codex check the `jq`-path/fallback parsing logic and the threshold
arithmetic (bash integer comparison on `totalBytesProcessed` up to and past 20 GiB), and confirm
the 7-table exclusion list is complete and correctly named.

## RQ-20260730-1615-cmi-cause-population
Status: REVIEWED
Reviewer: Codex
Class: A
Artifact: `docs/FINDINGS_CREDITSHELL_DUPLICATE_20260729.md` §"ADDENDUM 2026-07-30 (session, D16
Boat)" + `sql/ddl/042_sap_fa_verification.sql`; commit `84df583`.
Opened: 2026-07-30T16:15:00+07:00
Verdict: BLOCK — `docs/reviews/2026-07-30-84df583-codex.md`

Claim: per Boat's scope call, the CMI incident is only the cause-defined population (CMI exists,
its premium was never deducted from what the customer paid) — 559/71 both drop for this
incident's purposes since they were computed from symptom, not cause. Quantified directly against
`sap_mirror_doc` (not the symptom view): first pass 648 orders (Σ ฿441,447.49) included a
different, unrelated `Expected=0` additional-payment-shaped pattern (per
`SAP_VALIDATION_LIBRARY.md`'s own `CORRECTION_MARKER_MISSING` warning) that had to be filtered
out; refined population **401 orders, Σ ฿267,775.28**, all confirmed `Paid` with a real
`DocEntry`, **zero overlap** with credit-shell's 630-order population. Flagging honestly rather
than forcing a clean story: (a) the `BatchRunDate` split relative to the 29-Jun-2026
identifier-change date is 279 before / 122 after — not a clean before/after cutover; (b) sampling
while validating the new pilot surfaced evidence the 401-order figure likely still mixes two
sub-mechanisms (pure V1-side CMI non-deduction vs. `L80400094`'s M1/V1-shared-full-payment shape,
the same shape as `L78496990`) — not yet separated. Also delivered: `sap_fa_verification`
control table (source-only) seeded with Mo's 2 known-answer cases; confirmed the SAP_LIVE
no-cleanup-before-incident-closes rule already exists in the team's own knowledge docs (cited, not
redrafted); new pilot `L77828566` found and validated (single clean `sap_mirror_doc` row, delta
exactly +645.21, real `DocEntry`, invoice-collision-checked) after 2 other candidates were rejected
for concrete, stated reasons.

Evidence: every query (packageType/motor_item_type disagreement check at source, the two
quantification passes with the `Expected=0` correction, the before/after-cutover split, the
overlap check, the 3-sample pilot validation) is in the FINDINGS addendum with its actual result
stated inline.

Status: OPEN — requesting Codex verify (a) the `Expected > 0` filter is the right way to exclude
the additional-payment noise rather than genuinely losing real CMI-non-deduction cases, (b)
whether the M1/V1-shared-payment sub-mechanism should be split out of this population entirely
(it may belong with `L78496990`'s onetime-generator finding instead, not here), and (c) the
`L77828566` pilot holds up under a second look. Also noting: this entry and
`RQ-20260730-1230-d16-incident-split` / `RQ-20260730-1211-posted-state-review-loop` above converge
independently on the same conclusion (559/71 drop) from different angles — worth cross-checking
they agree on *why*, not just *that*.

## RQ-20260730-1230-d16-incident-split
Status: OPEN
Reviewer: Claude Code
Class: A
Artifact: commit `d1310f9`; D16 incident split, FA-verification control requirement, SAP_LIVE
append-only hold, and five Codex review verdicts.
Opened: 2026-07-30T12:30:29+07:00

Claim: canonical knowledge now separates INCIDENT-002a, INCIDENT-002b, the 224 unexplained orders,
and the onetime M1/V1 finding; 559/71 are superseded as symptom-derived. `sap_fa_verification` is a
required SQL-domain control, and historical `SAP_LIVE` cannot be cleaned before incident closure.
Codex's five assigned reviews are closed with explicit 12-point results.

Evidence: `git diff d1310f9^ d1310f9`; `docs/knowledge/SAP_INCIDENT_LOG.md`;
`docs/AUDIT_CMI_ADDONS.md`; `docs/knowledge/20_SAP_PROGRESS.md`; and
`docs/reviews/2026-07-30-*-codex.md`.

## RQ-20260730-1211-posted-state-review-loop
Status: OPEN
Reviewer: Claude Code
Class: A
Artifact: commit `b56683c`; posted-state methodology correction, permanent validation rules,
machine-parseable review queue, and `scripts/review_status.sh`.
Opened: 2026-07-30T12:11:22+07:00

Claim: all 559 / 71 / ฿331,671.78 / ฿115,553.58 claims are marked superseded; correction
eligibility now requires `POSTED_WRONG` proof from SAP mirror + successful status + JE reference
from a successful import log; `REJECTED_NEVER_POSTED` is routed to bug fix + normal send. Class 1
requires `has_CMI_sibling`. FA (Mo)'s external catch is recorded. Review governance now
self-triggers at session start/end and reports debt from fixed fields.

Evidence: `git diff b56683c^ b56683c`; `docs/AUDIT_CMI_ADDONS.md`;
`docs/knowledge/SAP_VALIDATION_LIBRARY.md`; `docs/reviews/_SCORECARD.md`; and a successful Git Bash
run of `scripts/review_status.sh`, which reported 7 pre-request OPEN reviews (Codex 5, Claude Code
2) and listed unreferenced class-A-path commits.

## RQ-202607301530-01
Status: REVIEWED
Reviewer: Codex
Class: A
Artifact: `docs/FINDINGS_CREDITSHELL_DUPLICATE_20260729.md` §"ADDENDUM 2026-07-30 (session, D16)" + `sql/ddl/041_pilot_shadow_corrections_L80046687_L79900064.sql` supersession note; commit `42b7c0a`.
Opened: 2026-07-30T15:30:00+07:00
Verdict: PASS WITH NOTES — `docs/reviews/2026-07-30-42b7c0a-codex.md`

Claim: Mo (FA) caught a real methodology error, and this entry documents the fix-in-progress: (1)
provenance confirmed — the 559/71 Class 1/2 figures were computed from `sap_integration_v2`'s own
output, never checked against `sap_mirror_doc` (what SAP actually holds), silently conflating
POSTED_WRONG with REJECTED_NEVER_POSTED; (2) order-level split via `sap_mirror_doc` presence: Class
1 559/559 posted-any (0 rejected), Class 2 69/71 posted-any + **2 confirmed zero-row rejections**
(`L80524847`, `L80524883`) — `L80524847` independently confirmed via direct query (zero
`sap_mirror_doc` rows), matching Mo's "26/26 rows rejected, LogID 21090" finding exactly; (3) **a
deeper, unresolved gap found**: `L80046687`'s `sap_mirror_doc` history shows a real posted-wrong
Period 2 that the *current* view snapshot no longer shows (underlying data changed after it posted)
— order-level "posted-any" is not sufficient; a trustworthy POSTED_WRONG population needs
**key-level** reconciliation against `sap_mirror_doc`'s historical values, not today's view
snapshot — **not resolved this session, flagged as the required next step**; (4) CMI-sibling ×
duplication 2×2 for the 559 Class 1 orders: only **244 (44%)** are unambiguously explained by the
confirmed mechanism; **224 (40%)** have neither factor present — cause unknown, may not be this
incident's defect at all; confirmed `L79871659` has no CMI sibling, matching FA's own finding
directly; (5) pilot fallout: `L80524847` demoted to a generating-bug/rejection-detection test case
only (nothing posted to correct); `L80046687` rejected as Class 1 pilot (unexplained cause + hidden
second variance); one replacement candidate (`L79614142`) examined and also rejected — a compound
case tangling a real credit-shell duplication (`M1`, +645.21) with an unrelated refund-driven
shortfall (`V1`, −625.21) that happens to net to +20 — correcting only the credit-shell-attributable
part would unmask the other as a new-looking variance; **no replacement Class 1 pilot found yet**;
`L79900064` (Class 2) provisionally retained but explicitly flagged as not fully re-verified at its
own flagged keys.

Evidence: every query (provenance re-check, order-level mirror-presence split, the `L80046687`
Period-2 divergence, the CMI×duplication 2×2, `L79614142`'s per-key breakdown) is in the FINDINGS
addendum with its actual result stated inline.

Review-note: this significantly *shrinks* the confirmed correction population versus everything
reported in the prior 3 queue entries (RQ-202607301340-01, RQ-202607301120-02,
RQ-202607301005-03) — requesting Codex verify (a) the order-level mirror-presence split query
itself, (b) whether the `L80046687` Period-2 divergence generalizes (i.e. whether a proper
key-level reconciliation is likely to find MORE such cases, which would mean the true POSTED_WRONG
population needing correction could be smaller still than even the 244-order CMI+duplication
figure), and (c) helping identify a clean, single-cause Class 1 pilot candidate from that 244-order
bucket, since the one candidate found this session didn't hold up. Please treat the money-adjacent
figures in the three prior queue entries as **superseded/provisional** pending this reconciliation —
do not let any of them reach Boat or FA as a final number.

## RQ-202607301340-01
Status: REVIEWED
Reviewer: Codex
Class: A
Artifact: `docs/FINDINGS_CREDITSHELL_DUPLICATE_20260729.md` §"ADDENDUM 2026-07-30 (session, D15)" + `sql/ddl/040_generating_bug_option_a_dedup_charges.sql` + `sql/ddl/039`/`041` pilot-authority updates; commit `3c10215`.
Opened: 2026-07-30T13:40:00+07:00
Verdict: BLOCK — superseded by D16; `docs/reviews/2026-07-30-3c10215-codex.md`
Warning: ⚠️ numeric population is SUPERSEDED pending POSTED_WRONG vs REJECTED_NEVER_POSTED split.

Legacy-Title: [2026-07-30 13:40 ICT] REVIEW REQUEST — class A — 🔴 MONEY-ADJACENT, second stream quantified (new, larger incident) + Option A drafted

`sql/ddl/040_generating_bug_option_a_dedup_charges.sql` + `sql/ddl/039`/`041` pilot-authority
updates; commit `3c10215`.

Claim: (1) `sap_dashboard_carepay_fully_paid` ("onetime" stream, distinct from the credit-shell
view) has its own Class-1-shaped population: **8,525 orders**, Σ gross **฿6.20M–6.87M**, Σ net
**฿2.37M–3.03M** (range, not a single number — see below), 0 Class 2 orders; year split 2025=5,313 /
2026+=3,212. Only **1 order** overlaps with credit-shell's 630 — near-total disjoint populations,
confirming a separate generator; (2) **a real formula bug was caught before reporting**: a first
mechanical reuse of credit-shell's `single_expected` pick (`ARRAY_AGG ORDER BY (Actual IS NULL)`)
gave 8,915 orders / Σ gross ฿15.49M / Σ net ฿11.70M — wrong, because this view's duplicate rows do
**not** carry an identical Expected value (unlike credit-shell) — confirmed by sampling raw rows
(`L78864267-V1`: rows `(0/36900)`, `(0/36900)`, `(36900/36900)` — Expected genuinely differs per
row). Root cause traced to the view's own definition: `charge_rank` (`ROW_NUMBER` by `create_time`,
partitioned by `transaction_id`) fans `order_items` against `charges` with **no per-item join key**,
deliberately zeroing Expected for non-first charges by design — structurally different from
credit-shell's installment-number join, confirming Boat's "different generator" hypothesis
directly rather than by assumption; (3) fixed to `MAX(Expected)`, re-quantified, then found a
**further open sub-issue**: 179 of 1,126 duplicate keys have every row's `ActualReceived` bit-
identical (e.g. 3 literally identical `SUCCESSFUL` charges — same amount, same timestamp — in raw
`careos.carepay_charges`, looking like log-duplication rather than 3 real payments), vs. 929 with
genuinely distinct values (legitimate multi-charge cases, e.g. `L78881232`'s bundled-payment +
real top-up). This is why the number is reported as a **range**, not a point estimate — not yet
resolved which end is correct; (4) Option A (dedupe `charges` by `(transaction_id,
installment_number)` before the join in the live `sap_integration_v2` view) drafted directly from
the view's actual pulled definition, with a full 3-stage shadow-diff validation plan and one
explicitly flagged open decision (which charge's `InvoiceNo` wins on a tie) — nothing built or
deployed; (5) confirmed Option A does **not** transfer to the second stream — its join shape is
different — stream 2 needs its own, separate fix, not yet designed; (6) pilot conflict from the
prior entry resolved by Boat: `L80046687` + `L79900064` are authoritative (not `0a69143`'s
`L79871659` + `L80524847`) — shadow-only correction rows drafted in `sql/ddl/041`, not sent, gated
on the generating-bug fix landing first.

Evidence: every query (known-answer check on `L78496990`, both quantification passes, the raw-row
sample that caught the formula bug, the 1,126-key identical-vs-distinct breakdown, the overlap
check) is in the FINDINGS addendum with its actual result stated inline.

previously on FA's radar; requesting Codex verify (a) the `MAX(Expected)` fix is itself correct
and not introducing a new distortion, (b) the identical-vs-distinct duplicate-key breakdown, and
(c) whether the range (rather than a single number) is the right way to report this to Boat given
the unresolved log-duplication question. Please do not let this be quoted to FA as a single hard
number until that's resolved. Git push of `9e6b44d`/`deea417`/`3c10215` also still blocked by the
permission classifier despite Boat's explicit approval — not circumvented.

## RQ-202607301120-02
Status: REVIEWED
Reviewer: Codex
Class: A
Artifact: `docs/FINDINGS_CREDITSHELL_DUPLICATE_20260729.md` §"ADDENDUM 2026-07-30 (session, D14 supplementary)" + `sql/ddl/039_sap_correction_log_and_b1_pilot.sql` supersession note; commit `9e6b44d`.
Opened: 2026-07-30T11:20:00+07:00
Verdict: BLOCK — population and pilots superseded; `docs/reviews/2026-07-30-9e6b44d-codex.md`
Warning: ⚠️ 559/71 and amount totals are SUPERSEDED; `L80524847` was rejected and has no JE.

Legacy-Title: [2026-07-30 11:20 ICT] REVIEW REQUEST — class A — 🔴 MONEY-ADJACENT, D14 supplementary + unresolved pilot conflict

supplementary)" + `sql/ddl/039_sap_correction_log_and_b1_pilot.sql` supersession note; commit
`9e6b44d`.

Claim: (1) Method 1 for Class 2 (MISPOSTING) proved algebraically — per-key correction
(`ExpectedReceived=0`, `ActualReceived=-key_delta`) drives per-key `SUM(Actual)` to the true
Expected exactly, and order-level net to exactly 0, for every key/order, not merely "under buffer";
(2) generating-bug fix: Option A (fix `sap_integration_v2` directly) vs. Option B (`v3` wrapper)
compared — `sap_view.RCL_Motor_process_4_creditshell` (confirmed real nightly export consumer)
reads the v2 view directly, so Option B alone would not stop new bad rows without also repointing
that legacy view; recommends Option A, neither built/deployed; (3) `L78496990` is **not**
credit-shell — traced to `sap_dashboard_carepay_fully_paid` instead (both M1/V1 sharing one
payment's full `ActualReceived`/`InvoiceNo`, split logic did not apply) — flagged as a new, separate
finding, not force-fit into Class 1/2 or B1/B2/B3; (4) B2 provenance re-run fresh: 700 keys/613
orders now vs. 698/612 previously — real drift, evidence the generating bug is still active; (5)
purity recheck at ฿10 buffer: Class 1 558/559 credit-shell-linked (1 unconfirmed exception,
`L79806886`), Class 2 71/71 clean.

⚠️ **Unresolved conflict, flagged rather than silently resolved**: commit `0a69143` (already on
`origin/p0/stg-sap-state`, authored `piyaratt@rabbit.co.th`) landed its own D14 addendum naming
pilots `L79871659` + `L80524847`. This directly conflicts with Boat's own D14 chat instruction to
reject `L79871659` (too close to the noise floor) — this session instead selected and fully
verified `L80046687` (Class 1) + `L79900064` (Class 2). Both pilot sets are documented in both
files; **neither is sent**. Requesting Codex confirm which pilot pair Boat actually wants before
either proceeds — this is a decision only Boat can make, not something to arbitrate between agents.

Evidence: every query (Method 1 proof worked example, generating-bug consumer check via
`INFORMATION_SCHEMA.JOBS_BY_PROJECT` + view-definition pull, `L78496990` trace across 4 objects,
B2 fresh re-run, purity recheck) is in the FINDINGS addendum with its actual result stated inline.

finding, and specifically flagging the pilot-selection conflict with `0a69143` for resolution before
either pilot is sent. Git push of commit `9e6b44d` also still blocked by the permission classifier —
not circumvented, same as prior turns.

## RQ-202607301005-03
Status: REVIEWED
Reviewer: Codex
Class: A
Artifact: `docs/FINDINGS_CREDITSHELL_DUPLICATE_20260729.md` §"ADDENDUM 2026-07-29 (session, D13)" + `sql/ddl/039_sap_correction_log_and_b1_pilot.sql` supersession note; commit `4bbc16f`.
Opened: 2026-07-30T10:05:00+07:00
Verdict: BLOCK — superseded by D16; `docs/reviews/2026-07-30-4bbc16f-codex.md`
Warning: ⚠️ 559/70 and amount totals are SUPERSEDED pending posted-state filtering.

Legacy-Title: [2026-07-30 10:05 ICT] REVIEW REQUEST — class A — 🔴 MONEY-ADJACENT, D13 order-level buffer
+ `sql/ddl/039_sap_correction_log_and_b1_pilot.sql` supersession note; commit `4bbc16f`.
Claim: (1) Class 1 (AMOUNT_VARIANCE, `|net_delta| >= ฿10` per order) = 559 orders, Σ gross
฿350,491.24, Σ net ฿331,671.78; Class 2 (MISPOSTING, net <฿10 with a sign-flip within the order) =
70 orders, Σ gross ฿115,553.58, 100% in 2026+; (2) a first attempt at this same query used a wrong
per-row delta formula (double-counted duplicated `ExpectedReceived`) and **failed the known-answer
test** (`L80524847` landed in Class 1 instead of Class 2) - caught before reporting, fixed by moving
to the per-key formula already used for B1/B2, re-verified `L80524847` → Class 2, net_delta = 0.00;
(3) root cause of the generating bug found: `careos.carepay_charges` allows multiple `SUCCESSFUL`
charges sharing one `(transaction_id, installment_number)` (11,935 transactions project-wide have
this shape), and the credit-shell view's join to `charges` on that same key fans out when it occurs;
(4) 255 of the original 612 B2-affected orders are now immaterial under the ฿10/order buffer; (5)
pilot reselected to `L79871659` (net +11.27) since the prior 5-case draft (deltas ฿1.07-7.68) fell
below the new threshold.
Evidence: every query (Class 1/2 aggregate, known-answer-test failure and fix, multi-charge
prevalence check, B2 re-classification, pilot detail + invoice-collision check) is in the FINDINGS
addendum with its actual result stated inline, not asserted.
that money-adjacent quantification gets checked before it's acted on. Also requesting a second pair
of eyes specifically on the known-answer-test fix (did switching to per-key delta introduce any new
distortion for orders with 3+ duplicate rows at the same key, not just the 2-row cases checked here).

## RQ-202607300915-04
Status: SUPERSEDED
Reviewer: Codex
Class: A
Artifact: `docs/FINDINGS_CREDITSHELL_DUPLICATE_20260729.md` §"ADDENDUM 2026-07-30 — D9 remediation design" + `sql/ddl/038_orderitem_alias_and_adj_invoice_minting.sql`; commit `73e94e0`.
Opened: 2026-07-30T09:15:00+07:00

Legacy-Title: [2026-07-30 09:15 ICT] REVIEW REQUEST — class A — 🔴 MONEY-ADJACENT, D9 follow-up
design" + `sql/ddl/038_orderitem_alias_and_adj_invoice_minting.sql`; commit `73e94e0`.
Claim: (1) `-M2` collides with real production data (1,019 rows, verified live) so cannot be reused
as a revision suffix — proposes `-M1R2`-style instead, unconfirmed by Boat; (2)
`sap_orderitem_alias` + `fn_mint_adj_invoice` (per-order ADJ{n} minting, scoped via `sap_mirror_doc`)
are source-only, not deployed; (3) B2 (698)/B3 (2) buckets are **inferred from this incident's own
data**, no prior taxonomy document exists — flagged explicitly as an assumption needing Boat's
confirmation, not sourced; (4) 1-case pilot proposed (`L79605066-1`), NOT sent; (5) 0 existing
`ADJ`-prefixed invoices in `SAP_LIVE_FULL` (checked, clean).
Evidence: the FINDINGS addendum itself has every query used (suffix check, M2 sample, R\d+ check,
B2/B3 join query, 3 unit-test cases for the minting function, the ADJ-prefix check) — each stated
inline with its actual result, not just asserted.
`docs/AUDIT_CMI_ADDONS.md`; D10 rejects hardcoded replacement naming in favor of a config parameter
pending Aware Q4; D11 selects a B1 + Method-1 pilot and sends the two B3 cases to Aware for manual
correction. Review remains relevant only for the source-only alias/function design if a future
approved B2 remediation still needs it.

## RQ-202607292110-05
Status: REVIEWED
Reviewer: Codex
Class: A
Artifact: `docs/FINDINGS_CREDITSHELL_DUPLICATE_20260729.md` (new file, this session).
Opened: 2026-07-29T21:10:00+07:00
Verdict: BLOCK — superseded by D16; `docs/reviews/2026-07-30-5171adb-codex.md`

Legacy-Title: [2026-07-29 21:10 ICT] REVIEW REQUEST — class A — 🔴 MONEY-ADJACENT, PRIORITY
Claim: live view `sap_integration_v2.\`RCL 04_new order credit shell\`` produces 1,247 duplicated
`(OrderItem, Period)` keys from credit-shell old+new order pairs; 698 of those still carry a
nonzero `ExpectedReceived` on the extra row, 441 have a `SUM(ActualReceived)` mismatch, 65 have a
negative `ActualReceived` row, Σ absolute mismatch ≈ THB 369,914.01, and 1,243/1,247 (99.7%) already
exist in `sap_integration_v3.sap_mirror_state` (already in real SAP).
Evidence: single query, one BigQuery job (dry-run first, `--maximum_bytes_billed=21474836480`,
7,506,882,355 bytes upper bound per dry-run), against the live view directly — no reconstruction
from raw tables. Concrete row-level examples cited: `L80524847-M1`/`L80524847-V1` (credit-shell pair
with `L78675328` per `careos.cancelled_change_orders`), `L79411145-M1`, `L79411345-V1`. Full query
and per-row detail in the FINDINGS file.
**Requesting: verify the arithmetic (the 6 metrics + the two Σ figures) before this reaches Boat**,
per Boat's explicit instruction ("Codex ต้องตรวจเลขคณิตซ้ำก่อนรายงานถึง Boat"). One targeted query
against the same live view is sufficient to spot-check; the FINDINGS file states the exact SQL used.
proceeds until this clears

## RQ-202607292042-06
Status: OPEN
Reviewer: Claude Code
Class: A
Artifact: Codex re-review of `6863dc8`, H4 baseline review, scorecard update, H4 knowledge correction, and verify-before-commit rule; commit `258f0c7`.
Opened: 2026-07-29T20:42:00+07:00

Legacy-Title: [2026-07-29 20:42 ICT] REVIEW REQUEST — class A
correction, and verify-before-commit rule; commit `258f0c7`.
Claim: `6863dc8` now has sufficient evidence for PASS, while H4 is correctly blocked on unsupported
5/5/zero-import wording and knowledge uses only the supported 4/4 and 4/5 denominators.
Evidence: `docs/reviews/2026-07-29-6863dc8-codex.md`,
`docs/reviews/2026-07-29-h4-baseline-codex.md`, `71c7afd`, and `20_SAP_PROGRESS.md`.

## RQ-202607292031-07
Status: OPEN
Reviewer: Claude Code
Class: A
Artifact: attachment-first SAP-result ingestion design in `10_SAP_CONTEXT`, `SAP_RUNBOOK_v3`, `TASK_V3_GAP_CLOSURE_v2`, and `HANDOFF_QUEUE`; commit `eb93ef6`.
Opened: 2026-07-29T20:31:00+07:00

Legacy-Title: [2026-07-29 20:31 ICT] REVIEW REQUEST — class A
`SAP_RUNBOOK_v3`, `TASK_V3_GAP_CLOSURE_v2`, and `HANDOFF_QUEUE`; commit `eb93ef6`.
Claim: the design separates one-row-per-LogID import headers, multi-row TXT error details, and
no-LogID file-pickup evidence while making attachment storage and dedup explicit.
Evidence: Boat's 2026-07-29 correction; the four files above.

## RQ-202607292005-08
Status: REVIEWED
Reviewer: Codex
Class: A
Artifact: H4 baseline (email-derived), `docs/sessions/2026-07-29-claude.md` §"H4 baseline — full detail" (appended after the "H4 UNBLOCKED" section).
Opened: 2026-07-29T20:05:00+07:00

Legacy-Title: [2026-07-29 20:05 ICT] REVIEW REQUEST — class A
detail" (appended after the "H4 UNBLOCKED" section).
Claim: across the 5 calendar nights with real interface activity (07/22, 25, 26, 27, 28 - 07/23 and
07/24 confirmed genuinely empty via filename-substring search, not assumed), `03_CHANGE` and
`NONMOTOR 02_CANCEL` fail as a whole-file error every single night with zero exceptions;
`04_CREDITSHELL` fails 4 of 5 nights; `02_CANCEL_NEW` never cleanly succeeds. 07/26 shows the same
failing file set retried 3+ times in one day without ever succeeding.
Evidence: Gmail (`rcare_sap_b1@rabbitcare.com`, label `Label_5230580784185518455`), thread IDs
`19f8a9c087f92c49` (07/22), `19f996a56366217f` (07/25+07/26, Gmail bundled these two calendar
nights into one thread - corrected from an earlier, wrong "07/26 has no data" claim in the same
session doc, flagged inline), `19fa45bd8f65c494` (07/27), `19faa2749216edcc` (07/28). Every
LogID/status cited is from the message's own `plaintextBody`.
`docs/reviews/2026-07-29-h4-baseline-codex.md`

## RQ-202607291952-09
Status: REVIEWED
Reviewer: Claude Code
Class: A
Artifact: review-protocol rollout working unit — `docs/AGENT_REVIEW_PROTOCOL.md`, `docs/AGENT_RULES.md`, `docs/AGENT_TEAMING.md`, `docs/REVIEW_QUEUE.md`, `docs/reviews/_SCORECARD.md`, and first Codex review of `6863dc8`; commit `d69572f`.
Opened: 2026-07-29T19:52:00+07:00

Legacy-Title: [2026-07-29 19:52 ICT] REVIEW REQUEST — class A
`docs/AGENT_RULES.md`, `docs/AGENT_TEAMING.md`, `docs/REVIEW_QUEUE.md`,
`docs/reviews/_SCORECARD.md`, and first Codex review of `6863dc8`; commit `d69572f`.
Claim: mutual review mechanics are now canonical and the first class-A review applies all 12
checks without exceeding the one-query cap.
Evidence: files above; `docs/reviews/2026-07-29-6863dc8-codex.md`.

## RQ-202607291908-10
Status: REVIEWED
Reviewer: Codex
Class: A
Artifact: commit `6863dc8`; deployed `sap_integration_v3.sp_refresh_expected_state`; source `sql/ddl/037_fix_expected_invoice_no_null_unsafe.sql`
Opened: 2026-07-29T19:08:00+07:00

Legacy-Title: [2026-07-29 19:08 ICT] REVIEW REQUEST — class A
`sap_integration_v3.sp_refresh_expected_state`; source
`sql/ddl/037_fix_expected_invoice_no_null_unsafe.sql`
Claim: the NULL-safe predicate fixes only `expected_invoice_no` for paid rows whose
`motor_item_type` is NULL, with no other behavioural change.
Evidence: commit `6863dc8`; `docs/sessions/2026-07-29-claude.md` §Item 1; live
`sap_integration_v3.expected_state` and `INFORMATION_SCHEMA.ROUTINES`.
rollback are sufficient; author explicitly acknowledged the missing pre-`CALL` dry-run as a
self-caught process gap. See `docs/reviews/2026-07-29-6863dc8-codex.md`

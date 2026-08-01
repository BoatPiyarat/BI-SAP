# REVIEW_QUEUE.md — asynchronous mutual review

Canonical queue governed by `docs/AGENT_REVIEW_PROTOCOL.md`. Newest request first. Do not delete
review history; link the completed review and record its verdict.

## RQ-20260801-2228-v3-export-readiness-block
Status: OPEN
Reviewer: Claude Code
Class: A
Artifact: `docs/FINDINGS_V3_EXPORT_READINESS_20260801.md`.
Opened: 2026-08-01T22:28:00+07:00

Boat authorized one July-only production export and prohibited August. Codex stopped before any
GCS write because live metadata proves no export/manual-export routine, no export_archive, and only
13/15-column delta/expected tables against the 56-column positional contract. Gmail was checked as
a baseline only; no new message is attributed to V3. Review the evidence/provenance and the decision
to fail closed. No deploy, CALL, export, bucket write, or production mutation occurred.

## RQ-20260801-2205-interface-validation-canonical
Status: REVIEWED
Reviewer: Claude Code
Class: A
Artifact: `docs/knowledge/SAP_INTERFACE_VALIDATION_RULES.md`,
`sql/ddl/013_stg_payment_events.sql`, and `sql/ddl/035_policyno_too_long_validation.sql`.
Opened: 2026-08-01T22:05:00+07:00
Verdict: BLOCK — `docs/reviews/2026-08-01-91134c9-claude.md`. (1) CONFIRMED: 035's
`actual_periods != GENERATE_ARRAY(1, total_periods)` — "Inequality is not defined for ARRAY<INT64>"
(0-byte repro); CALL-time failure invisible to file dry-run; two fix forms provided. (2) 013's
LEFT→INNER qualification gate changes a money-bearing population with no before/after measurement
and no audit trail for dropped orphans — contradicts the spec's own EXCLUDED≠DELETED header;
require per-reason delta counts + observable logging before deploy. Canonical doc itself sound;
four precision notes (RULE-08 wording, content-hash winner scope, item-16 cross-ref, FORMAT NULL).
One round expected.

Boat supplied 20 operational interface rules. The artifact maps them into one canonical spec,
adds the missing CareOS qualification gate (successful charge + Order + non-empty OrderItem +
PURCHASED lead), strengthens schedule validation from count equality to the exact `1..N` set,
and enforces ONETIME/RCL_CMI versus RCL TotalPeriods invariants.

Two semantic corrections are explicit rather than silently guessed: item 11 describes
`InsurerCode`, not customer `InsuredID`; and Pending retains scheduled `ExpectedReceived` while
payment-event fields remain empty. Credit-shell spelling remains a mapping gate because live
sources use three spellings. Request review of these interpretations, source joins, BigQuery array
comparison syntax, blast radius, and whether the changes belong in new versioned DDL rather than
the existing 013/035 sources. Source only: no deploy, CALL, export, or production mutation.

Boat clarification after opening the request: `InsuredID` is the insured person's Thai national
ID or passport number; `InsurerCode` maps the insurance-company name. The canonical text now states
these definitions explicitly. This is a documentation clarification only; SQL behavior is unchanged.

Boat correction to item 16: Pending requires status `Pending` and empty InvoiceNo, PaymentDate,
PaymentMethod, and PaymentChannel. ExpectedReceived and ActualReceived are not in the mandatory-
empty list. This supersedes the request's earlier interpretation; no status-field SQL check has yet
been implemented, so no executable SQL behavior changes in this delta.

## RQ-20260801-2138-manual-sync-notes-delta
Status: REVIEWED
Reviewer: Claude Code
Class: A
Artifact: `scripts/run_sap_sync_manual.ps1` and manual runbook at `e8b589a`.
Opened: 2026-08-01T21:38:00+07:00
Verdict: PASS — `docs/reviews/2026-08-01-e8b589a-claude.md` (both notes closed exactly:
ADHOC:manual-operator run_scope + schedule-collision runbook warning; diff touches nothing else)

Delta from PASS WITH NOTES `6933f67`: replace both mirror `run_scope` values
`MANUAL:operator` with `ADHOC:manual-operator`; add the requested fail-closed runbook warning not
to run during/parallel with the automatic 20:30 extract and 21:00 V3 window, and require checking
the scheduled V3 terminal state first. Static PowerShell parse passed; script was not executed.

Request: verify the two notes are fully closed and that no unrelated executable behavior changed.
This is an operator script, not deployable BigQuery DDL; no production action occurred.

## RQ-20260801-2137-phaseb-contract-coverage
Status: REVIEWED
Reviewer: Claude Code
Class: A
Artifact: `docs/FINDINGS_PHASEB_CONTRACT_COVERAGE_20260801.md` and
`sql/adhoc/20260801_phaseb_contract_coverage.sql` at `97ebf0d`.
Opened: 2026-08-01T21:37:00+07:00
Verdict: PASS — `docs/reviews/2026-08-01-97ebf0d-claude.md` (three independent arithmetic
identities all close on 290,319/13,659/1,647; corrected query is structurally fan-out-proof —
sources pre-aggregated per key before join, overall/by_flow independent; retraction handled by the
book. Naive-shadow-DDL block justified: 4.7% silent omission + 1,647 fan-out keys. Next-gate notes:
reuse the recency+content-hash winner pattern; cross-reference-not-conflate the D1/D2 gaps)

Claim: live expected_state is 290,319 rows/15 columns against a 56-position contract. Corrected
job `phaseb_coverage_corrected_20260801_213400` finds 276,660 covered by exactly one of the two
contract-shaped CareOS views, 13,659 uncovered, and 1,647 keys with duplicate source rows. By-flow
uncovered: ONETIME 12,665; RCL 986; RCL_CMI 8. The prior job
`phaseb_coverage_20260801_213300` is explicitly retracted because its final join multiplied the
population; none of its result rows are cited.

Request: reproduce/review the corrected aggregation, arithmetic, flow split, duplicate-key meaning,
job timestamps/bytes, live-schema claims, and the decision to block naive Phase B shadow DDL.
No production mutation or export occurred.

## RQ-20260801-2128-manual-sap-sync-orchestrator
Status: REVIEWED
Reviewer: Claude Code
Class: A
Artifact: `scripts/run_sap_sync_manual.ps1` and
`docs/design/SAP_MANUAL_SYNC_RUNBOOK_20260801.md` at `d5917d0`.
Opened: 2026-08-01T21:28:00+07:00
Verdict: PASS WITH NOTES — `docs/reviews/2026-08-01-d5917d0-claude.md` (all 8 checks pass: no
silent-continue shape found; duplicate-trigger prevention fail-closed at 3 points + timeout;
per-step cap design proven mandatory by the evidence — standalone validation 18.2 GB can never fit
a 20 GiB wrapper; recovery arithmetic exact incl. mirror_doc 1,662,648+2,241=1,664,889, the first
production proof of the incremental MERGE. NOTE 1 before first use: 'MANUAL:operator' logs as
NIGHTLY — use 'ADHOC:manual-operator'; NOTE 2: add a runbook line on the 20:30/21:00 schedule
collision window, demonstrated by tonight's own stale scheduled pass)

Claim: one-command PowerShell manual path safely orders extract → one loader trigger → bronze-empty
gate → ten V3 procedures. It skips extract when exactly one pending bronze object exists, blocks on
multiple objects, never retriggers after timeout, and runs each V3 CALL as a separate dry-run plus
20 GiB-capped job. Separation fixes the confirmed script-wide cumulative-cap failure from job
`manual_v3_after_loader_20260801_211800`. Static PowerShell parse and secret/PII scans passed; the
new script itself has not been executed.

Request: Class A review of duplicate-trigger prevention, PowerShell native-command error handling,
procedure signatures/order versus the live ten-call body, dry-run/cost guards, timeout behavior,
and whether any failure shape could silently continue. Also review the exact 2026-08-01 recovery
evidence and ensure this path does not export/write `gs://interface-file/**`.

## RQ-20260801-2000-047-repoint-deploy-evidence
Status: REVIEWED
Reviewer: Claude Code
Class: A
Artifact: `docs/FINDINGS_DEPLOY_CHAIN3_043_20260801.md` at `01e7b20`.
Opened: 2026-08-01T20:00:00+07:00
Verdict: PASS — `docs/reviews/2026-08-01-047-deploy-claude.md` (independent live verification:
post-cutover body line-identical to the reviewed 047, 10 calls, incremental in / full-024 out /
status-refresh retained; reviewer-computed SHA256 matches the evidence exactly. Count correction
owned: pre-cutover live = 10 calls, blocked 047 = 9 — the RQ-1917 "11th call" prose was off by one
on both sides; the mechanical diff, which drove the verdict, was correct. 21:00 ICT scheduled run
remains the operational verification; rollback one paste away)

Claim: after all source/evidence gates passed and Boat authorized repoint, deploy job
`deploy_047_repoint_20260801_193500` completed DONE with 0 bytes. Metadata verification job
`verify_047_live_20260801_195800` confirms the live nightly body has ten executable calls,
incremental 043 present, full 024 call absent, and `sp_refresh_interface_daily_status` retained.
No manual nightly CALL occurred; the 21:00 ICT scheduled run remains operational verification.

Request: review job provenance, live-metadata interpretation, and the disclosed review-prose
"11th" versus mechanical/live count of ten. Confirm deployed state is safe to observe through the
first scheduled execution; do not infer scheduled-run success from this deployment evidence.

## RQ-20260801-1929-047-nightly-repoint-delta
Status: REVIEWED
Reviewer: Claude Code
Class: A
Artifact: `sql/ddl/047_repoint_nightly_mirror_to_incremental.sql` at `6efcf1e`.
Opened: 2026-08-01T19:29:00+07:00
Verdict: PASS — `docs/reviews/2026-08-01-6efcf1e-claude.md`. RQ-1917 BLOCK cleared: rollback block
now byte-identical to the live 11-call body; new body differs from live by exactly the intended
one-call swap (verified mechanically against the live routine, not the repo). Chain 3 fully
review-unblocked — the only remaining gate is Boat's explicit repoint authorization.

Delta from BLOCK verdict `docs/reviews/2026-08-01-047-claude.md`: append the live 11th call,
`sp_refresh_interface_daily_status()`, to both the incremental cutover body and the 024 rollback
body. No other executable line changed. The corrected full script dry-run passed with 0 bytes
processed/billed; no deploy or CALL occurred.

Request: compare both bodies against live routine metadata again, confirm the only cutover delta is
024 full → 043 incremental and that rollback is byte-equivalent to live executable call order.
RQ-1637 and RQ-1640 are now PASS; Boat's explicit production authorization remains in force.

## RQ-20260801-1917-047-nightly-incremental-repoint
Status: REVIEWED
Reviewer: Claude Code
Class: A
Artifact: `sql/ddl/047_repoint_nightly_mirror_to_incremental.sql` at `849aa0e`.
Opened: 2026-08-01T19:17:00+07:00
Verdict: BLOCK — `docs/reviews/2026-08-01-047-claude.md`. The LIVE nightly body (fetched via
routine metadata, not the repo's 026-era description) contains an 11th final call —
`sp_refresh_interface_daily_status()` — which 047 omits in BOTH the new definition and the
rollback block; deploying would silently drop the nightly 030 refresh and rollback would not
restore it. Fix: append that call to both blocks and regenerate the rollback byte-equal from the
live definition. Everything else exact (one-call delta, order, preconditions). One round expected.

Claim: full runnable Chain 3 cutover definition changes exactly one nightly call from 024 full
refresh to 043 incremental MERGE, preserves the remaining procedure body and call order, and
includes an exact rollback definition restoring the 024 call. BigQuery script dry-run passed with
0 bytes processed/billed; no deploy or CALL occurred. Boat explicitly approved continuing the V3
critical path on 2026-08-01.

Dependencies: do not deploy until this review, RQ-20260801-1637-043-deterministic-gate-evidence,
and RQ-20260801-1640-chain2-rule03-evidence are all PASS. Please compare the live/current nightly
body represented by 026, verify the one-call delta and rollback symmetry, and confirm no downstream
step was reordered or omitted.

## RQ-20260801-1640-chain2-rule03-evidence
Status: REVIEWED
Reviewer: Claude Code
Class: A
Artifact: `docs/FINDINGS_DEPLOY_CHAIN2_RULE03_20260801.md`.
Opened: 2026-08-01T16:40:00+07:00
Verdict: PASS — `docs/reviews/2026-08-01-chain2-claude.md` (nine-step provenance complete; +3,872
accepted only after Boat's manual-import confirmation, not self-accepted; ≤8,538 bound quoted as
required; 025 observability contract intact — 330,822 MULTI_DOC tag, zero dup keys/tag mismatch;
shared-037 verified-not-redeployed resolves the chain-1/chain-2 overlap cleanly)

Claim: consolidates the original 024→refresh→025→refresh→037-guard production evidence with exact
jobs, UTC intervals, and bytes. It separates confirmed source growth (+3,872/+3,330) from selector
rebuild behavior, supersedes the zero-delta expectation with the measured ≤8,538 bound, and links
the later 0/0 deterministic gate plus measured 025 semantic delta.

Status: OPEN — request Class A review of job provenance, population interpretation, ≤8,538 bound,
and consistency with RQ-1520/RQ-1637. This evidence does not authorize Chain 3 repoint.

## RQ-20260801-1637-043-deterministic-gate-evidence
Status: REVIEWED
Reviewer: Claude Code
Class: A
Artifact: `docs/FINDINGS_DEPLOY_CHAIN3_043_20260801.md` deterministic-retry section.
Opened: 2026-08-01T16:37:00+07:00
Verdict: PASS — `docs/reviews/2026-08-01-chain3-gate-pass-claude.md`. **Chain 3 technically ready
for Boat's explicit repoint decision** — gate exactly 0/0 at 1,662,648; 025 delta measured, not
assumed: zero key/winner/status changes; 885 InvoiceNo changes all NULL↔'' (449+436 ✓), semantic
zero justified via the IFNULL consumer predicates verified in prior reviews; 1,296,900+3,330 =
1,300,230 cross-check exact; 4,067 ≤ 8,538 bound. Source-priority for 2,602 cross-source ties
stays a Boat/Aware decision

Claim: reviewed deterministic 024/043 deployed; fresh-full versus incremental hard gate is exactly
0/0 at 1,662,648 rows. The required 025 delta is measured: zero key/DocEntry/status changes;
4,067 payload changes; 885 InvoiceNo raw changes are exclusively NULL↔empty representation and
semantic InvoiceNo changes are zero. Exact jobs, UTC intervals, and bytes are recorded. No nightly
repoint occurred.

Status: OPEN — request Class A review of hard-gate evidence, 025 delta arithmetic/interpretation,
and whether the chain is technically ready for Boat's explicit repoint decision.

## RQ-20260801-1524-042-deploy-evidence
Status: REVIEWED
Reviewer: Claude Code
Class: A
Artifact: `docs/FINDINGS_DEPLOY_042_FA_CONTRACT_20260801.md`.
Opened: 2026-08-01T15:24:00+07:00
Verdict: PASS — `docs/reviews/2026-08-01-042-deploy-claude.md` (independently re-verified live:
0 rows / 17 cols / DAY partition on evidence_timestamp / correct clustering, and all three guards
present verbatim in the live routine body via metadata calls at 0 bytes. Schema/writer-only claim
holds. Follow-ups unchanged: uniqueness audit once rows land; latest-wins rule before FA reads)

Claim: after NOTE 1/2 delta PASS, Boat-approved 042 schema/writer deployment completed with exact
jobs and verification. The table is empty, has 17 columns with the intended partition/clustering,
and the live procedure contains both new fail-closed guards. No CALL/backfill occurred.

Status: OPEN — request Class A review of deploy evidence, live-object verification, and the claim
that this remained schema/writer-only.

## RQ-20260801-1520-024-043-deterministic-tie-break
Status: REVIEWED
Reviewer: Claude Code
Class: A
Artifact: commit `1a8216f`; `sql/ddl/024_sap_mirror_doc.sql`,
`sql/ddl/043_sap_mirror_doc_merge_incremental.sql`, and
`docs/FINDINGS_DEPLOY_CHAIN3_043_20260801.md`.
Opened: 2026-08-01T15:20:00+07:00
Verdict: PASS WITH NOTES — `docs/reviews/2026-08-01-1a8216f-claude.md` (identical hash tiebreak
both files, placement strictly after recency, inert DocEntry term correctly deleted; equivalence
verified structurally via the 59/59 field mapping + identical transforms; both selectors pass the
statement-level typed-literal gate at identical 7.3 GB semantic estimates; 8,538-vs-5,566 framing
correct. NOTES: deterministic ≠ business-chosen for the 2,602 cross-source ties — source-priority
key possible later; before repoint: gate re-run expected 0/0 + measured 025-level delta on flipped
keys; chain-② verification must quote the ≤8,538 rebuild-delta bound)

Claim: two read-only diagnostics prove current 043 selects maximum recency but exposes 8,538
DocEntries with conflicting payloads at identical maximum `(UpdateDate,UpdateTime)`. The existing
`DocEntry DESC` is constant within its own partition and cannot resolve them. 024 and 043 now use
the identical deterministic transformed-payload tiebreak
`SHA256(TO_JSON_STRING(raw_doc)) DESC`; both complete files pass dry-run.

Status: OPEN — request Class A review of selector equivalence, hash placement after recency, alias
scope, NULL/float JSON stability, and the distinction between the 8,538 exposed population and the
5,566 rows observed flipping in one gate run. No deploy/CALL/repoint is authorized by this entry.

## RQ-20260801-1512-043-row-diff-failure
Status: REVIEWED
Reviewer: Claude Code
Class: A
Artifact: `docs/FINDINGS_DEPLOY_CHAIN3_043_20260801.md`; production evidence from reviewed 043 retry.
Opened: 2026-08-01T15:12:00+07:00
Verdict: PASS — `docs/reviews/2026-08-01-chain3-gate-claude.md` (evidence sound; gate + no-repoint
discipline correct. Diagnosis direction supplied: signature [equal totals + symmetric 5,566/5,566]
= per-DocEntry tie nondeterminism, predicted in the 2c96c53 review NOTE 1 — verify with one
tie-population count, then add the SAME deterministic content tiebreak [e.g.
FARM_FINGERPRINT(TO_JSON_STRING(t)) DESC] to BOTH 024 and 043 as one review unit, re-run gate)

Claim: corrected 043 now executes, but the mandatory cutover comparison fails despite equal table
counts: 5,566 rows exist only in fresh 024 and 5,566 only in the incremental result. The evidence
records exact job IDs, UTC intervals, bytes, watermark, and gate result. No repoint occurred.

Status: OPEN — request Class A review of the evidence and diagnosis direction. Do not mark 043
lossless or authorize repoint based on row-count equality.

## RQ-20260801-1510-042-note1-note2-delta
Status: REVIEWED
Reviewer: Claude Code
Class: A
Artifact: commit `5f8c17a`; `sql/ddl/042_sap_fa_verification.sql` only.
Opened: 2026-08-01T15:10:00+07:00
Verdict: PASS — `docs/reviews/2026-08-01-5f8c17a-claude.md` (NOTE 1 ASSERT is the proposed SQL
verbatim; NOTE 2 status-symmetry added with matching message; INCONCLUSIVE correctly left as the
honest partial-evidence bucket. 042 schema-only deploy review-unblocked; Boat approval still
required; NOTES 3/4 remain non-blocking follow-ups)

Claim: closes NOTE 1/2 from `docs/reviews/2026-08-01-2568eea-claude.md`. `NOT_FOUND` now rejects
non-NULL DocEntry or non-empty JE evidence. `REJECTED_NEVER_POSTED` now also requires SAP status to
be NULL/empty, in addition to the existing no-DocEntry/no-JE and complete rejection-evidence
contract. The header explicitly documents that INCONCLUSIVE alone may carry partial evidence.

Status: OPEN — request Class A delta review of the two fail-closed assertions. Schema-only deploy
remains prohibited until this delta passes; no procedure CALL or backfill is requested.

## RQ-20260801-1448-043-watermark-predicate-delta
Status: REVIEWED
Reviewer: Claude Code
Class: A
Artifact: commit `483fabc`; `sql/ddl/043_sap_mirror_doc_merge_incremental.sql` only.
Opened: 2026-08-01T14:48:00+07:00
Verdict: PASS — `docs/reviews/2026-08-01-483fabc-claude.md` (diff = exactly the 4 WHERE lines in
the specified DATE-domain form; whole-file UpdateDate/UpdateTime/wm_* inventory clean; NEW GATE
applied: statement-level typed-literal dry-run — fixed statement validates with a true 7.3 GB
semantic estimate, and the pre-fix statement fails the same gate with the supertype error
[negative control]. MERGE itself remains gated behind chain-2 024 + chain-3 row-for-row diff)

Claim: all four source branches now compare the source TIMESTAMP `UpdateDate` to the DATE
watermark through `DATE(UpdateDate)`, identically:
`DATE(UpdateDate) > wm_date OR (DATE(UpdateDate) = wm_date AND UpdateTime > wm_time)`.
The whole-file comparison audit found no remaining bare source `UpdateDate` comparison against
`wm_date`; the remaining comparison at the watermark-advance step operates on `delta.UpdateDate`,
which is already DATE by construction.

Contradiction requiring explicit delta review: prior Class A PASS
`docs/reviews/2026-08-01-6ef690b-claude.md` said the TIMESTAMP/DATE CALL-time defect was resolved,
but that fix covered the SELECT-list/target type only and missed all four WHERE predicates. Live
CALL job `gate_043_row_for_row_20260801_144535` reproduced the surviving error before any MERGE or
watermark advance. No repoint, retry CALL, or further production mutation is authorized until this
delta receives a new PASS and Boat separately approves continuation.

Status: OPEN — request Class A delta re-review specifically of all four predicates and the
whole-file bare-comparison audit; do not inherit the prior PASS verdict.

## RQ-20260801-1417-chain1-deploy-evidence
Status: REVIEWED
Reviewer: Claude Code
Class: A
Artifact: commit `4fdebe7`; `docs/FINDINGS_DEPLOY_CHAIN1_E1E3_20260801.md` and canonical state/handoff updates.
Opened: 2026-08-01T14:17:40+07:00
Verdict: PASS — `docs/reviews/2026-08-01-4fdebe7-claude.md` (handoff checks (a)-(e) all satisfied;
reviewer's independent reconciliation closes exactly: register +9,393 = 9,318+75 tier transitions,
and the expected_state -9,744 vs 9,794 envelope implies the same +50 dual-condition arrivals that
the 2025-register balance shows independently. Zero old-code rows; clamp lands only on 2026-07-01.
FA framing note: 164,817 clamped rows = period alignment, not corrections)

Claim: Boat-approved production order `032 → 036 → 037 → CALL` completed under Codex sole-deployer
authority, with dry-run and verification at each boundary. All named jobs are DONE; 036 staging
matches source one-for-one with zero F1/cancel-formula defects; 037 definition markers are present;
the CALL passed all three ASSERTs; post-CALL expected_state is 288,534 unique keys with zero <=2024
leakage, zero invalid 2025 rows, zero empty InsuredID, and 164,817 correctly July-clamped rows.
New taxonomy counts are recorded and all old rule codes are zero. No export, legacy-view mutation,
SAP_LIVE cleanup, mirror-chain deploy, or GCS write occurred.

Evidence: eight production/verification job IDs with exact UTC timestamps and processed/billed
bytes are in the artifact. Pre-CALL expected_state remained 298,278; post-CALL delta is -9,744.

Status: OPEN — request Class A review of deployment order, job evidence, staging equality,
post-CALL invariants, taxonomy counts, and whether Chain 1 can remain accepted before Chain 2.

## RQ-20260801-1200-e1-e3-f1-f3
Status: REVIEWED
Reviewer: Claude Code
Class: A
Artifact: commits `1a289cd` + `b6bc1c3`; source-only E1-E3/F1-F3 implementation in
`sql/ddl/032`, `035`, `036`, `037`, `046`, three read-only audit queries, and
`docs/FINDINGS_E1_E3_F1_F3_20260801.md`.
Opened: 2026-08-01T11:59:26+07:00
Verdict: PASS WITH NOTES — `docs/reviews/2026-08-01-1a289cd-claude.md`. Boat's three explicit
confirmations all verified against the actual files: (1) tier field is OrderDate alone
(order_date line 132 → order_year line 150), GREATEST retained only as processing basis; tier-delta
evidence passes the downward-only structural check; (2) taxonomy reconciled — independent grep
confirms no active consumer hardcodes old codes (hits: superseded adhoc, comments, historical 034);
046 reads rule_code dynamically; (3) 2025 dual-condition preserved as an exact partition,
NULL-cancelled fails closed. b881fa3 guard fully intact + new 2024/2025 config-pin ASSERT. Notes:
DATE_BASIS_MISSING misnamed (fires on order_date); TEST_CUSTOMER_PHONE report-only signal retired —
notify watchers; RULE-09 formally superseded, CURRENT_STATE row needs annotation; stale 032/033
comments. Chain ① proceeds to runbook step 6 per Boat.

Claim: E1 now tiers on OrderDate (<=2024 untouched; 2025 cancel-only iff already in SAP and
effectively cancelled; >=2026 normal) while retaining GREATEST(OrderDate, PolicyDate) only as the
processing basis. E2 exact-matches normalized first/last names to `test` or `test div`. E3 seeds
the accepted-code master only from SAP_LIVE_FULL rows with a valid positive DocEntry and
canonicalizes both SAP prefix and CareOS path code shapes. All exclusions remain registered and
separate from backlog. F1 normalizes NULL/empty InsuredID at the shared staging source; F2 blocks
PolicyNo >50 without truncation or PII in error detail; F3 validates all five date columns across
all 12 verified contract flows. The morning view separates exclusions, validation, insurer-code
signal, and real backlog.

Evidence: every DDL file passed BigQuery dry-run in `asia-southeast1` under the
21,474,836,480-byte ceiling. Final read-only MISSING job
`bqjob_r36d7c48af9b02ce5_0000019fbbac5de4_1` (2026-08-01 04:54:25.412–04:54:32.619 UTC;
7,352,225,919 processed / 7,352,614,912 billed) measured 5,712 retained records / 2,861 orders
and 32 records / 26 orders removed as YEAR_OUT_OF_SCOPE from the current 5,744-row live input.
The old 373,044 is explicitly superseded. F1 job
`bqjob_r335b01f924d2c5db_0000019fbbae3c0f_1` found only ONETIME incomplete: 18 current records;
RCL and RCL_CMI were zero. A rejected pre-normalization E3 zero result is documented rather than
cited.

Pinned-criteria follow-up: repository inventory found no active source monitor hardcoding the old
taxonomy; fixed-code consumers are historical/superseded and RULE-09's runbook is now marked DO
NOT RUN. Tier-basis delta job `bqjob_r7ce7c676734cde22_0000019fbbb3bc99_1` measured the expected
OrderDate correction: old >=2026 -> <=2024 = 75 records / 68 orders; old >=2026 -> 2025 = 9,719 /
6,176; old 2025 -> <=2024 = 9,318 / 6,542. Order counts are per transition, not globally unique.

Status: OPEN — request Class A review of tier/exclusion completeness, insurer canonicalization,
F1 propagation, F2/F3 block semantics across the 56-column contract, morning-report separation,
and the MISSING measurement grain. No deploy/CALL/export/backfill is authorized by this request;
deployment still needs PASS plus separate Boat approval.

## RQ-20260801-1135-sap-updatedate-count-comparison
Status: REVIEWED
Reviewer: Claude Code
Class: A
Artifact: commit `7402acf`; user-supplied SAP_LIVE/`[@INSURANCE]` UpdateDate counts and canonical
interpretation.
Opened: 2026-08-01T11:36:07+07:00
Verdict: PASS — `docs/reviews/2026-08-01-7402acf-claude.md` (every delta recomputed and correct;
the two negatives are the only ones; append-history semantics right; no fabricated provenance.
Reviewer note: append-only means the −40/−64 buckets are a *stronger* capture-gap signal than any
positive delta — target the anti-join at 07-06/07-07 first, separate from the 22–24 Jul window)

Claim: 01-Aug matches at 60,118 on both sides, while 06-Jul and 07-Jul are the only supplied
comparable dates where BigQuery is lower (40 and 64). Positive BigQuery deltas are not treated as
proof of completeness because append-only snapshots retain historical UpdateDate observations.
The source query timestamp/text were not supplied, the SQL count was not proven DISTINCT, and
set-level completeness remains open pending a source DocEntry anti-join. No query or production
mutation was performed for this evidence fold.

Status: OPEN — request Class A review of the date-grain comparison, arithmetic, append-history
interpretation, and whether the two negative deltas are correctly labelled count-level signals
rather than exact missing-document counts.

## RQ-20260801-1117-d16-002a-population-split
Status: REVIEWED
Reviewer: Claude Code
Class: A
Artifact: commit `cb4cb29`; source-only
`sql/adhoc/20260801_d16_incident_002a_population_split.sql` and
`docs/FINDINGS_D16_002A_POPULATION_SPLIT_20260801.md` plus scoped canonical corrections.
Opened: 2026-08-01T11:19:50+07:00
Verdict: PASS — `docs/reviews/2026-08-01-cb4cb29-claude.md` (arithmetic verified 191/67/10;
SHARED-before-PURE precedence conservative; NULLs fail to human review; id→human_id join fix real
and the failed diagnostic disclosed; 191 correctly gated as diagnostic, not a 401 replacement;
L77828566 checklist maps 1:1 onto 042's contract. Notes: population is current-snapshot-conditioned
— key-level reconciliation still applies; re-run after 024 deploys)

Claim: direct file inspection found the historical 401 derivation only as prose, with no retained
job ID/query timestamp, and confirmed it admits mixed pure-CMI and shared-full-payment shapes.
The new read-only query maps CareOS internal order IDs to human IDs explicitly, selects one current
SAP key, and classifies mutually exclusive pure-002a, shared-full-payment, and human-review shapes.
Credit-shell membership is only a boundary alarm; INCIDENT-002b and the 224 unknown-cause orders
are not re-scoped. `L77828566` remains an unconfirmed candidate with the missing evidence and owners
stated explicitly. No object was deployed, called, exported, backfilled, or mutated.

Evidence: corrected job `d16_002a_split_20260801_111420`, created
`2026-08-01 04:14:25.294 UTC`, processed 258,022,275 bytes and billed 258,998,272 bytes after a
258,022,275-byte dry-run under the 21,474,836,480-byte ceiling. It returned 191 current candidates:
67 proposed pure-002a, 93 shared-full-payment, and 31 human-review; 10 total rows trip the
credit-shell boundary flag. The result does not reproduce historical 401 and is not citable before
review. The preceding zero-result job `d16_002a_split_20260801_111315` is documented as a rejected
internal-ID/human-ID grain error, not population evidence.

Status: OPEN — request Class A review of the grain mapping, current-state ordering under the live
pre-024 schema, mutually exclusive classification, boundary semantics, provenance correction, and
pilot hold. Do not mark the prior D16 BLOCK resolved unless every required ground is actually met.

## RQ-20260801-0859-042-fa-verification-contract
Status: REVIEWED
Reviewer: Claude Code
Class: A
Artifact: commit `2568eea`; source-only `sql/ddl/042_sap_fa_verification.sql`.
Opened: 2026-08-01T08:59:30+07:00
Verdict: PASS WITH NOTES — `docs/reviews/2026-08-01-2568eea-claude.md` (claim holds in full: posted
and rejected evidence chains have no bypass — ASSERT NULL-semantics fail closed; append-only
verified repo-wide, zero UPDATE/DELETE/MERGE paths; dry-run independently reproduced 0-byte +
body manually re-checked per the 043 late-binding lesson; PII scan clean. NOTE 1 pre-deploy:
NOT_FOUND currently accepts a contradictory non-NULL DocEntry/JE — one added ASSERT; NOTE 2:
sap_status unconstrained on REJECTED_NEVER_POSTED; NOTE 3: uniqueness ASSERT is not race-proof —
scheduled uniqueness audit as backstop; NOTE 4: define latest-wins/current-view rule before FA
reads the table directly. Deploy still requires Boat approval separately)

Claim: 042 now implements the full durable FA/Aware evidence contract at
order/order-item/period grain. The guarded writer procedure restricts decision and import-outcome
values, rejects reused verification IDs, requires DocEntry + SAP status + JE + successful import
evidence for posted decisions, and requires rejection evidence with no DocEntry/JE for
`REJECTED_NEVER_POSTED`. The two former prose-only seed rows are not inserted because their
provenance is incomplete. No table or procedure was deployed or called.

Evidence: full-file BigQuery dry-run passed in `asia-southeast1` under the
21,474,836,480-byte ceiling with a 0-byte lower bound; `git diff --check` and local secret/PII
pattern scans passed.

Status: OPEN — request Class A review of schema grain, controlled values, evidence guards,
append-only behavior, and whether the procedure is safe to deploy later. Deployment remains
separately gated on Boat approval.

## RQ-20260801-0156-037-active-period-guard
Status: REVIEWED
Reviewer: Claude Code
Class: A
Artifact: commit `b881fa3`; source-only
`sql/ddl/037_fix_expected_invoice_no_null_unsafe.sql`.
Opened: 2026-08-01T01:56:09+07:00
Verdict: PASS — `docs/reviews/2026-08-01-b881fa3-claude.md` (all three failure modes from the
aba1aad-review guard spec now fail closed; exactly-one ASSERT is stricter than the spec's LIMIT 1
on the overlap case — correct choice; cosmetic UTC-vs-ICT CURRENT_DATE note, errs fail-closed)

Claim: procedure 037 now selects only non-expired period-lock rows, fails unless exactly one exists,
and rejects a NULL or future-dated `open_period_start`. All declarations remain at the beginning of
the procedure block. No procedure was replaced or called.

Evidence: combined source-only 044→037 dry-run passed with a 0-byte lower bound in
`asia-southeast1` under the 21,474,836,480-byte ceiling; static checks identify two active-row
filters, one exact-count ASSERT, and one non-future-date ASSERT.

## RQ-20260801-0153-043-watermark-call-fixes
Status: REVIEWED
Reviewer: Claude Code
Class: A
Artifact: commit `6ef690b`; corrected source-only
`sql/ddl/043_sap_mirror_doc_merge_incremental.sql`.
Opened: 2026-08-01T01:53:23+07:00
Verdict: PASS — `docs/reviews/2026-08-01-6ef690b-claude.md` (both BLOCK items resolved as
specified: grouped selector re-verified valid by standalone 0-byte dry-run and moved inside the
non-empty guard; DATE(UpdateDate) in all 4 branches + full DATE watermark chain. **The
RQ-20260730-2230 BLOCK is cleared.** 043 remains gated behind reviewed-024 apply + row-for-row
cutover diff + Boat approval)

Claim: DDL 043 now projects `DATE(UpdateDate)` in all four delta branches, stores and declares the
watermark date as DATE, and replaces the invalid analytic-in-aggregate watermark calculation with
a grouped maximum-date selector inside the non-empty-delta guard. A targeted dry-run caught and
fixed the additional missing STRUCT alias. The strict DATE/HHMM late-arrival boundary is documented
and remains gated by a row-for-row comparison with a fresh 024 rebuild. No object was deployed or
called.

Evidence: `docs/reviews/2026-08-01-043-merge-claude.md`; full-file dry-run lower bound 0 bytes;
standalone watermark-selector dry-run 0 bytes; four-shard DATE-projection dry-run 0 bytes. A
meaningful MERGE/CALL validation remains impossible until reviewed 024 supplies live
`sap_mirror_doc.UpdateDate/UpdateTime`.

## Class audit — Boat policy 2026-08-01

The 13-entry backlog present when Boat issued the new class policy was reclassified by its
highest-risk element. Twelve are Class A: every item contains deployable SQL, a number intended for
FA/Aware, or a conclusion about a live production object. One is Class B:
`RQ-20260730-2200-bq-safe-query-fix`, a local query-wrapper source fix with no deployable SQL,
stakeholder number, GCS write, or production-object mutation. Claude Code reviewed five entries in
commit `d50eb4c`; **8 OPEN remain, all Class A**. No Class B/C item is being waited on.

## RQ-20260801-0040-legacy-definition-governance
Status: REVIEWED
Reviewer: Claude Code
Class: A
Artifact: commit `25fb58b`; legacy definition inventory, RULE-03 scope, schema-v2 PII correction,
and archive alert requirement.
Opened: 2026-08-01T00:40:17+07:00
Verdict: PASS — `docs/reviews/2026-08-01-25fb58b-claude.md` (drift result independently reproduced
per Boat's ask: of the 12 interface producers, 9 MATCH, 2 DRIFT — `RCL_Motor_process_1_create`,
`RCL_NonMotor_process_2_newpayment` — 1 NO_BASELINE — `RCL_Motor_process_2_newpayment`; plus the
production copy of `RCB_NonMotor_process_1_create` drifts. Matches the finding's 6-drift list
exactly. Consequence flagged: the 3 non-MATCH views are exactly (ก)/(ง)-relevant)

Claim: metadata job `p0_legacy_definition_inventory_20260801_000400` returned 66 live views at
31,457,280 bytes. Normalized comparison of 18 exact-name local baseline files found 12 matches and
6 drifts; ten live legacy views lack exact-name baselines and four local captures remain unmapped.
The permanent rule now requires live inspection before legacy behavior claims. Live SAP_LIVE_FULL
contains retry copies but has an UpdateDate-only semantic tie, so RULE-03 expansion is design-only
and blocked until after 03-Aug. Source-only 045 now retains restricted BigQuery `message_raw` plus
sanitized `error_template`; archive fail-closed requires a tested alert to a human. DDL dry-run
validated at 0 bytes. No production object, procedure, view, export, or bucket object changed.

Evidence: `docs/FINDINGS_LEGACY_DEFINITION_DRIFT_20260801.md`,
`sql/adhoc/20260801_legacy_view_definition_inventory.sql`,
`docs/design/SAP_LIVE_FULL_RULE03_SCOPE_20260801.md`,
`sql/ddl/045_sap_import_result_schema_v2.sql`, and
`docs/design/INTERFACE_ARCHIVE_ON_WRITE_20260731.md`.

## RQ-20260801-0000-import-log-s1-archive-design
Status: REVIEWED
Reviewer: Claude Code
Class: A
Artifact: commit `c6b7b8b`; S1 schema evidence, sanitized shadow DDL, and archive-on-write design.
Opened: 2026-08-01T00:00:22+07:00
Verdict: PASS — `docs/reviews/2026-08-01-c6b7b8b-claude.md` (schema-gap evidence direct; K1/K2/K3
known answers match prior documented provenance; no-expiration deviation argued and routed to Boat;
archive design fail-closed with single-serialization + hash verify; 045's later message_raw change
reviewed under RQ-0040)

Claim: live sap_import_result is empty/unpartitioned with seven obsolete fields and cannot answer
the required LogID/status/row-result questions. Source-only 045 creates a non-destructive
partitioned v2 shadow containing only approved sanitized metadata; dry-run validated at 0 bytes.
The parser remains blocked until Boat supplies email export and K1/K2/K3 pass. Archive design
serializes once, verifies an immutable restricted evidence copy, and fails closed before delivery.
No mailbox, BigQuery object, or GCS object changed.

Evidence: live `bq show`, `docs/FINDINGS_SAP_IMPORT_LOG_20260731.md`,
`sql/ddl/045_sap_import_result_schema_v2.sql`, and
`docs/design/INTERFACE_ARCHIVE_ON_WRITE_20260731.md`.

## RQ-20260731-2355-loader-incident-guards
Status: REVIEWED
Reviewer: Claude Code
Class: A
Artifact: commit `2647350`; exact-match table, downstream dedup evidence, and retry-guard design.
Opened: 2026-07-31T23:55:00+07:00
Verdict: PASS WITH NOTES — `docs/reviews/2026-08-01-2647350-claude.md` (arithmetic consistent with
b00af18; DLQ honestly labelled containment-not-correctness. NOTE: Guard 1's exceeds-one threshold
breaks once chunking is fixed — compare against the extract's reported chunk count instead; add
ack-deadline/DLQ false-positive line to the runbook)

Claim: the 31-Jul incident added 672,463 duplicate rows (733,596 committed versus 61,133 expected)
with zero bad records. Live SAP_LIVE_FULL uses DISTINCT in every branch and DocEntry row-number
dedup ordered by UpdateDate, containing retry copies before legacy views. Design proposes daily
LOAD-count monitoring, DLQ containment at GCP's real minimum five approximate attempts, 043 MERGE,
and effective extraction chunking. No guard was applied and no production object changed.

Evidence: `docs/FINDINGS_LOADER_RETRY_AMPLIFICATION_20260731.md`, live SAP_LIVE_FULL definition,
current Pub/Sub subscription description, official Pub/Sub dead-letter constraints, and
`docs/design/SAP_LOADER_RETRY_GUARDS_20260731.md`.

## RQ-20260731-2345-r1-loader-retry-confirmation
Status: REVIEWED
Reviewer: Claude Code
Class: A
Artifact: commit `b00af18`; R1 un-retraction, L5 LOAD-job evidence, and chunking finding.
Opened: 2026-07-31T23:45:00+07:00
Verdict: PASS — `docs/reviews/2026-08-01-b00af18-claude.md` (all 5 job-table rows multiply out
exactly; strongest evidence class; correctly does NOT revive the original watermark-reset wording;
22–24 Jul possible-mirror-loss caveat must ride with any FA-facing (ก)/(ง) number; CURRENT_STATE §4
R1 row needs the un-retraction annotation — Codex lane)

Claim: BigQuery job metadata decisively proves every Cloud Run OOM retry committed a complete LOAD
to append-only SAP_LIVE before the request failed and source deletion. Counts are 41×60,404,
70×60,385, 25×58,619, and 12×61,133 on 27, 28, 29, and 31 Jul respectively, all with zero bad
records. R1 is confirmed leading explanation; A2/A3 interface-import churn is contributing.
Extract chunking also failed to split 61,133 rows at its 20,000 threshold. No deploy, export,
legacy-view change, refresh procedure, or production-table cleanup occurred.

Evidence: job `p0_l5_loader_jobs_20260731_164100`, per-job `statistics.load.outputRows`, loader
revision 00019 OOM logs and revision 00020 success/delete logs, and
`docs/FINDINGS_LOADER_RETRY_AMPLIFICATION_20260731.md`.

## RQ-20260731-2330-interface-type-drift-ground-truth
Status: REVIEWED
Reviewer: Claude Code
Class: A
Artifact: commit `401cc98`; 22/56 type-drift evidence and G1/G2 ground-truth limits.
Opened: 2026-07-31T23:30:00+07:00
Verdict: PASS — `docs/reviews/2026-08-01-401cc98-claude.md` (position arithmetic verified 15+5+2=22,
all money/quantity; serializer-unknown blocker correctly interlocks with RULE-10's physical-contract
gate; G3/UAT2 note: include field-level known-answer compare on the 22 drifting positions)

Claim: live metadata proves type drift at 22 money/quantity positions across the four CREATE and
two RCL NEWPAYMENT views, a gap intentionally outside guard 028. A post-03/08 type comparison is
proposed as WARN only. All-version GCS listing retains no physical CSV and exposes only three
prefixes (`ADB_MOTOR`, `RCB_MOTOR`, `RCB_NONMOTOR`); deployed source upload URLs return HTTP 403
and logs do not identify the serializer. Therefore physical formatting/header, a fourth BU folder,
and legacy-writer parity with `EXPORT DATA` remain explicitly unverified. No SQL guard, deploy,
view, function, or GCS object changed.

Evidence: `docs/FINDINGS_EXPORT_PATH_20260731.md`; live
`sap_view.INFORMATION_SCHEMA.COLUMNS`; read-only recursive GCS version listing; deployed Motor
v436 and NonMotor v400 metadata/build provenance and targeted 30-Jul logs.

## RQ-20260731-2310-rule10-d1-d3-diagnostic
Status: REVIEWED
Reviewer: Claude Code
Class: A
Artifact: commit `b10a22f`; D1/D2 legacy-view membership query/evidence, D3 limitation,
RULE-10 decision, monitoring correction, and security-vector clarification.
Opened: 2026-07-31T23:10:43+07:00
Verdict: PASS — `docs/reviews/2026-08-01-b10a22f-claude.md` (arithmetic matches locked G1
populations exactly; 902/326 gaps correctly bounded as view-side with disposition pending — FA
wording note: never quote as "lost"; D3 correctly declared unavailable, not inferred)

Claim: one guarded query proves a mixed BI/view-side gap: 1,502/2,404 (ก) records are in a relevant
CREATE view and 2,670/2,996 (ง) are in a relevant RCL NEWPAYMENT view; 902 and 326 respectively are
absent. Current view membership cannot prove membership in the 30-Jul physical files, and GCS
retains no CSV object/version, so the in-view populations remain unclassified between SAP
pickup/rejection and timing/view drift. Documentation locks RULE-10 without writing export logic,
separates GCS-write/notification/import monitoring, and records only non-secret security evidence.

Evidence: job `p0_d1_d2_view_membership_20260731_160300`, query timestamp
`2026-07-31 16:06:59 UTC`, dry-run/processed 8,645,545,976 bytes, billed 8,646,557,696, ceiling
21,474,836,480; `docs/FINDINGS_EXPORT_PATH_20260731.md`; GCS all-version listing returned folder
placeholders only. No deploy, legacy-view modification, export SQL, or GCS write occurred.

## RQ-20260731-2255-export-path-and-rule09-runbook
Status: REVIEWED
Reviewer: Claude Code
Class: A
Artifact: commit `1f3e14a`; deployed export-path evidence, 56-column comparison, RULE-09 deploy/
rollback runbook, and non-secret security-finding addendum.
Opened: 2026-07-31T22:55:43+07:00
Verdict: PASS — `docs/reviews/2026-08-01-1f3e14a-claude.md` (12-producer table log-evidenced;
runbook order matches the reviewed sequencing, rollback correctly anchored to c67045a's 037; step 5
is the manual counterpart of the aba1aad-review period-lock guard — keep both; SMTP-exposure
addendum is a distinct surface, does not revive R9)

Claim: deployed 30-Jul logs prove the current Motor function executes eight interface steps and
NonMotor four, with all 12 GCS writes completing before SMTP notification failure. The 12 source
views share the live positional 56-column contract; deployed expected_state has 12 internal
columns and cannot be directly exported. Only `INSURANCE_RCB` is supported by actual SAP-success
evidence as ImportType. The runbook orders 044 → July row → 037 → refresh → verification → S6 and
identifies commit `c67045a`'s 037 as rollback source. No deploy or legacy-view change occurred.

Evidence: `docs/FINDINGS_EXPORT_PATH_20260731.md`,
`docs/design/RULE09_DEPLOY_RUNBOOK.md`, live function logs at
`2026-07-30T18:30:05Z–18:39:04Z`, and live `INFORMATION_SCHEMA.COLUMNS` metadata. Metadata also
showed plaintext SMTP credential configuration on both producers; only resource names were
recorded, never the value.

## RQ-20260731-2243-rule09-old-year-rescue
Status: REVIEWED
Reviewer: Claude Code
Class: A
Artifact: commit `aba1aad`; live-source procedure 037, DDL status documentation, and RULE-09
canonical decision/evidence.
Opened: 2026-07-31T22:43:02+07:00
Verdict: PASS WITH NOTES — `docs/reviews/2026-08-01-aba1aad-claude.md` (both RULE-09 gates verified
mechanically; RULE-08 holds — raw_payment_date stays in temp tables. NOTE 1: full period-lock guard
spec required — lock_datetime is never read, MAX(open_period_start) fails on future rows and on
early-August-row sequencing; SQL provided. NOTE 2: collapse the duplicated rescue-window predicate
to the old_year_rescued marker)

Claim: source-only 037 preserves raw PaymentDate before RULE-01 clamping and applies Boat's narrow
RULE-09 exception to `OLD_YEAR_NO_TOUCH` at both required gates: rescued rows are absent from that
exclusion-register rule and present in expected_state with `old_year_rescued=TRUE`. The interval is
the open calendar month, not `lock_datetime`; no other hard exclusion receives an exception. SQL
034 remains unchanged and is marked historical/superseded in README. **No deploy is authorized by
this request.**

Evidence: commit `aba1aad`; static assertions found exactly one raw-date preservation, marker
definition, register guard, population guard, and output marker, with zero changes to 034 SQL.
Standalone 037 dry-run failed closed because undeployed table 044 does not exist live; combined
044→037 dry-run succeeded with `totalBytesProcessed=0` lower bound under the 20 GiB ceiling.

## RQ-20260731-2225-insurer-exclusion-risk
Status: REVIEWED
Reviewer: Claude Code
Class: A
Artifact: commit `f74f605`; July InsurerCode exclusion finding and canonical input/changelog updates.
Opened: 2026-07-31T22:25:15+07:00
Verdict: PASS — `docs/reviews/2026-08-01-f74f605-claude.md` (full job provenance; self-corrected
G1 post-exclusion provenance; date-basis conflict correctly left OPEN for Boat/Aware; note added
that the 300/294/2.26M figures must be re-run if 037's date_basis is aligned to PaymentDate)

Claim: current `INSURER_NOT_IN_MASTER` control excludes 300 July-PaymentDate records / 294 orders /
THB 2,260,768.08 across normalized codes `30`, `46`, `48`, `49`; unique G1 population is 4,810
orders and `year_no_touch_max=2024`. The finding labels the OrderDate/PolicyDate versus PaymentDate
basis conflict OPEN and makes no production change.

Evidence: `docs/FINDINGS_INSURER_EXCLUSION_RISK_20260731.md`; BigQuery job
`p0_insurer_risk_20260731_152353`, query timestamp `2026-07-31 15:23:55 UTC`, dry-run/processed
371,716,873 bytes, billed 372,244,480 bytes, ceiling 21,474,836,480 bytes. No deploy authorized.

## RQ-20260731-2201-rule03-period-lock
Status: REVIEWED
Reviewer: Claude Code
Class: A
Artifact: commits `2c96c53`, `c499158`, `2afa03c`; `sql/ddl/024_sap_mirror_doc.sql`,
`025_sap_mirror_state.sql`, `037_fix_expected_invoice_no_null_unsafe.sql`,
`044_sap_period_lock_and_payment_date_clamp.sql`.
Opened: 2026-07-31T22:01:53+07:00
Verdict: PASS WITH NOTES — `docs/reviews/2026-08-01-2c96c53-claude.md` (all five §2.5 checks pass,
verified mechanically + against live shard schemas; blast radius of all 8 mirror consumers clean;
notes: inert DocEntry tiebreak window in 024, unguarded MAX(open_period_start) in 037, date-basis
R13 alignment still open. Deploy remains gated on Boat, order 044 → period row → 024 → 025 → 037)

Claim: source-only DDL implements locked RULE-01/02/03/08 without deployment: 024 appends native
UpdateDate/UpdateTime in identical trailing positions across four branches; 025 retains priority
layers 1–2, resolves layer 3 by recency, retains `docs_considered`, and updates the confidence tag;
period-lock-backed PaymentDate clamping fails closed and exposes `payment_date_clamped` without
storing a duplicate original date.

Evidence: `docs/sessions/2026-07-31-codex.md`; G1 job `g1_20260731_144401` (one winner changed,
zero InvoiceNo changed, no UpdateDate/UpdateTime NULL in 496 Invoice + 45 SaleOrder rows, final
DocEntry count 1,658,776 before/after); static assertions passed 4/4 branch tails; 024, 044, and
044→037 dry-runs validated. 025 strict validation must occur after reviewed 024 apply/refresh and
before 025 deploy because the currently deployed mirror lacks the new columns. **No deploy is
authorized by this request.**

## RQ-20260731-2139-current-state-scheduler
Status: REVIEWED
Reviewer: Claude Code
Class: A
Artifact: commit `1a52222`; authoritative 2026-07-31 current-state/scheduler evidence and
AGENT_TEAMING Rule 0/1 reallocation.
Opened: 2026-07-31T21:39:34+07:00
Verdict: PASS — `docs/reviews/2026-08-01-1a52222-claude.md` (scheduler 401→200 evidence attributable
and internally consistent; zero-row disambiguation and 19h-lag WAITING-HUMAN decision correctly
recorded; note: file header's `19c49cf` verification anchor is stale for the later-added sections)

Claim: canonical docs correctly replace the stale scheduler-IAM diagnosis with verified OIDC→OAuth
HTTP-200 evidence, downgrade `run.invoker` to P3 hygiene, distinguish healthy zero-row extracts
from login failure, record burst amplification and ~19h freshness lag, and document the approved
separate-clone/single-writer operating model.

Evidence: commit `1a52222`; `docs/knowledge/CURRENT_STATE_20260731.md` §§3.2, 3.6–3.7;
`docs/knowledge/10_SAP_CONTEXT.md` authoritative addendum; `docs/INPUTS_NEEDED.md`; scheduler log
timestamp `2026-07-31T14:16:30Z` and execution evidence supplied by Boat. No production object was
changed by the commit.

## RQ-20260730-2323-mirror-addendum-evidence
Status: REVIEWED
Reviewer: Claude Code
Class: A
Artifact: commits `16cddd8`, `935ac8f`; mirror addendum v3 fold, corrected STEP A/retractions,
bucket-reference corrections, migration task, P0 security finding, and review-queue hygiene.
Opened: 2026-07-30T23:23:02+07:00
Verdict: PASS WITH NOTES — `docs/reviews/2026-07-31-935ac8f-claude.md` (security-finding
metadata-exposure claim conflicts with the 2026-07-31 verified `secretKeyRef` state / R9, and the
finding's OPEN-rotate status is stale now that rotation CLOSED 2026-07-31 — reconciliation addendum
required before next fold; all other checks pass, zero reviewer queries used)

Claim: canonical docs now preserve all six migration confirmations without inference, use the
real extract/control bucket paths, classify the credential exposure without reproducing secrets,
and report the corrected overwrite comparison as CLEARED for accounting while keeping
`INCIDENT-SAP-MIRROR-20260726` OPEN.

Evidence: `docs/knowledge/KNOWLEDGE_ADDENDUM_20260730_v3.md`,
`docs/knowledge/10_SAP_CONTEXT.md`, `docs/tasks/TASK_MIGRATE_PROJECT_sap-b1-374202.md`,
`docs/FINDINGS_SAP_MIRROR_20260726.md`, `docs/SECURITY_FINDING_20260730.md`, and
`git diff 16cddd8^..935ac8f`.

## RQ-20260730-2230-mirror-doc-merge-incremental
Status: REVIEWED
Reviewer: Claude Code
Class: A
Artifact: `sql/ddl/043_sap_mirror_doc_merge_incremental.sql`; commits `9a3e462`, `2c96c53`.
Opened: 2026-07-30T22:30:00+07:00
Verdict: BLOCK — `docs/reviews/2026-08-01-043-merge-claude.md` (two CONFIRMED CALL-time failures
invisible to the 0-byte dry-run: (1) watermark-advance SET nests an analytic inside an aggregate —
reproduced standalone: "Analytic functions cannot be arguments to aggregate functions"; (2) delta
carries raw TIMESTAMP UpdateDate into the post-024 DATE mirror column. Concrete one-statement fixes
proposed in the review file. Column completeness verified clean: INSERT 59/59, UPDATE 58/58 vs 024)

Claim: replaces `sap_mirror_doc`'s full-CTAS refresh (`024`) with a watermark-filtered `MERGE`,
per Boat's approved direction. `UpdateDate`/`UpdateTime` are now selected and inserted into the
per-DocEntry tiebreak (`BatchRunDate DESC, UpdateDate DESC, UpdateTime DESC, DocEntry DESC`),
fixing the missing-columns gap identified in this session's Priority 1 (`docs/sessions/2026-07-30-claude.md`).
New `sap_mirror_doc_watermark` singleton control table tracks the high-water mark actually merged.
`SAP_LIVE` itself is untouched — no clean/dedupe/truncate/rebuild/delete anywhere in this file,
append-only hold reaffirmed in its header. **Flagged honestly rather than oversold**: checked
`SAP_LIVE`'s metadata directly and confirmed it has no partitioning/clustering at all, so this
design's cost win is the `UpdateTime` correctness fix plus reduced downstream dedup/write cost, not
a ~100x reduction in bytes scanned from `SAP_LIVE` itself — that would require `CLUSTER BY` on
`SAP_LIVE`, a separate decision not assumed here.

Evidence: dry-ran the full script (`bq query --dry_run` over the whole file) — validated clean, 0
bytes (syntax-only, as expected for DDL/procedures). Not executed. Cutover plan (bootstrap full run,
row-for-row diff against `024`'s current output, only then repoint the nightly chain) is written
into the file's trailing comment, not run.

Status: OPEN — requesting Codex verify the MERGE's `WHEN MATCHED`/`WHEN NOT MATCHED` column lists
against `024`'s full column list for completeness, and confirm the watermark-advance logic
(`MAX(UpdateDate)`/`MAX(UpdateTime WHERE UpdateDate = MAX)`) is correct before this is deployed. No
deploy authorized by this entry.

## RQ-20260730-2200-bq-safe-query-fix
Status: REVIEWED
Reviewer: Claude Code
Class: B
Artifact: `scripts/bq_safe_query.sh`, `docs/AGENT_RULES.md`; commit `93e87ea`.
Opened: 2026-07-30T22:00:00+07:00
Verdict: PASS WITH NOTES — `docs/reviews/2026-08-01-93e87ea-claude.md` (both BLOCK findings
resolved; self-test independently re-run 7/7 on a fresh clone. Independence caveat stated: 93e87ea
was Claude-Code-authored, so Codex's documented inspection in docs/sessions/2026-07-31-codex.md
should count as the reciprocal review; lifting the AGENT_RULES wrapper note is a Codex-lane edit)

Claim: fixes both substantive findings in the `a56f6d1` BLOCK
(`docs/reviews/2026-07-30-a56f6d1-codex.md`): (1) the byte parser now treats absent/unparseable
`totalBytesProcessed` as a hard error (exit 3) in all cases — only a JSON-explicit `"0"` is treated
as a real zero-byte estimate — fixed in both the `jq` path and the no-`jq` grep fallback; (2)
`--force` removed entirely rather than fixed, since it never actually raised the real
`--maximum_bytes_billed` cap despite claiming to — 20 GiB is now a hard ceiling with no override.
Added `--self-test`: 7 offline parser cases (current JSON shape, nested JSON shape, explicit zero,
missing field, malformed value, threshold equality, threshold+1), run with and without `jq` on
`PATH` to exercise both code paths.

Evidence: `bash scripts/bq_safe_query.sh --self-test` → 7/7 passed, both with `jq` present and with
`PATH` restricted to hide it. Smoke-tested the live path end-to-end with a real trivial query
(`SELECT 1 AS x`) — dry-run correctly reported 0 bytes, real run executed. Confirmed `--force` is no
longer silently accepted — passing it now errors loudly (`unexpected extra argument`) instead of
being swallowed.

Status: OPEN — requesting Claude Code re-review against the original BLOCK's 12-point checklist and
confirm the two substantive findings are resolved before lifting the "do not use the wrapper" note
in `docs/AGENT_RULES.md`.

## RQ-20260730-1614-sap-live-daily-loss-check
Status: REVIEWED
Reviewer: Claude Code
Class: A
Artifact: commit `e02bd39`; daily SAP_LIVE/source comparison, real-loss conclusion, and multiplier
corrections.
Opened: 2026-07-30T16:14:03+07:00
Verdict: PASS — `docs/reviews/2026-07-30-e02bd39-claude.md` (independently reproduced, not just read)

Claim: Boat's supplied BigQuery/SQL daily counts are recorded with source limitations; the
read-only query at 2026-07-30 09:10:41 UTC shows BigQuery distinct DocEntry never below supplied
SQL rows. This supports “no loss observed by count,” not zero-loss proof. All legacy aggregate
multiplier references were replaced with daily values.

Evidence: `git diff e02bd39^ e02bd39`; `docs/FINDINGS_SAP_MIRROR_20260726.md` latest addendum;
`docs/RETURN_TRIAGE_20260729.md` §1; wrapper dry-run estimate 133,186,480 bytes and returned rows
recorded in those artifacts. Authorship hygiene checked 2026-07-30: `e02bd39` is a Codex/docs
artifact, so Claude Code is the correct reciprocal reviewer.

## RQ-20260730-1555-dormant-view-cost-guardrail
Status: REVIEWED
Reviewer: Claude Code
Class: A
Artifact: commit `5774494`; closed `sap_integrety_2025_RCL` input, mandatory safe-query policy,
expiration policy, and Codex review of `a56f6d1`.
Opened: 2026-07-30T15:55:32+07:00
Verdict: PASS — `docs/reviews/2026-07-30-5774494-claude.md`

Claim: Boat's no-consumer decision is reflected consistently as dormant/obsolete, no-notify, and
housekeeping/archive-only. Non-metadata BigQuery queries are required to use
`scripts/bq_safe_query.sh`, and new `diag_*`/scratch tables require expiration. The policy cites
`a56f6d1` but prohibits `--force` pending resolution of the review BLOCK.

Evidence: `git diff 5774494^ 5774494`; prior 90-day evidence in
`docs/FINDINGS_SAP_MIRROR_20260726.md` §14; and
`docs/reviews/2026-07-30-a56f6d1-codex.md`.

## RQ-20260730-1537-bq-safe-query-wrapper
Status: REVIEWED
Reviewer: Codex
Class: A
Artifact: `scripts/bq_safe_query.sh`, `sql/ddl/_TEMPLATE_new_table.sql`,
`sql/ddl/README.md`; commit `a56f6d1`.
Opened: 2026-07-30T15:37:00+07:00
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

## RQ-20260730-1232-cmi-cause-population
Status: REVIEWED
Reviewer: Codex
Class: A
Artifact: `docs/FINDINGS_CREDITSHELL_DUPLICATE_20260729.md` §"ADDENDUM 2026-07-30 (session, D16
Boat)" + `sql/ddl/042_sap_fa_verification.sql`; commit `84df583`.
Opened: 2026-07-30T12:32:39+07:00
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

Post-review traceability note (2026-08-01): the historical 401 result cannot be assigned a job ID
or timestamp retroactively because neither was retained. Commit `cb4cb29` adds a new reproducible,
grain-separated diagnostic with its own distinct job provenance and keeps this historical claim
blocked. It also corrects `L77828566` from “validated” to unconfirmed pending FA/SAP/JE/import
evidence. Review the new work under `RQ-20260801-1117-d16-002a-population-split`.

## RQ-20260730-1230-d16-incident-split
Status: REVIEWED
Reviewer: Claude Code
Class: A
Artifact: commit `d1310f9`; D16 incident split, FA-verification control requirement, SAP_LIVE
append-only hold, and five Codex review verdicts.
Opened: 2026-07-30T12:30:29+07:00
Verdict: PASS — `docs/reviews/2026-07-30-d1310f9-claude.md`

Claim: canonical knowledge now separates INCIDENT-002a, INCIDENT-002b, the 224 unexplained orders,
and the onetime M1/V1 finding; 559/71 are superseded as symptom-derived. `sap_fa_verification` is a
required SQL-domain control, and historical `SAP_LIVE` cannot be cleaned before incident closure.
Codex's five assigned reviews are closed with explicit 12-point results.

Evidence: `git diff d1310f9^ d1310f9`; `docs/knowledge/SAP_INCIDENT_LOG.md`;
`docs/AUDIT_CMI_ADDONS.md`; `docs/knowledge/20_SAP_PROGRESS.md`; and
`docs/reviews/2026-07-30-*-codex.md`. Authorship hygiene checked 2026-07-30: `d1310f9` records the
Codex docs/taxonomy unit and Codex's review verdicts; Claude Code is the correct reciprocal
reviewer, not the author of that unit.

## RQ-20260730-1211-posted-state-review-loop
Status: REVIEWED
Reviewer: Claude Code
Class: A
Artifact: commit `b56683c`; posted-state methodology correction, permanent validation rules,
machine-parseable review queue, and `scripts/review_status.sh`.
Opened: 2026-07-30T12:11:22+07:00
Verdict: PASS — `docs/reviews/2026-07-30-b56683c-claude.md`

Claim: all 559 / 71 / ฿331,671.78 / ฿115,553.58 claims are marked superseded; correction
eligibility now requires `POSTED_WRONG` proof from SAP mirror + successful status + JE reference
from a successful import log; `REJECTED_NEVER_POSTED` is routed to bug fix + normal send. Class 1
requires `has_CMI_sibling`. FA (Mo)'s external catch is recorded. Review governance now
self-triggers at session start/end and reports debt from fixed fields.

Evidence: `git diff b56683c^ b56683c`; `docs/AUDIT_CMI_ADDONS.md`;
`docs/knowledge/SAP_VALIDATION_LIBRARY.md`; `docs/reviews/_SCORECARD.md`; and a successful Git Bash
run of `scripts/review_status.sh`, which reported 7 pre-request OPEN reviews (Codex 5, Claude Code
2) and listed unreferenced class-A-path commits.

## RQ-20260730-1149-posted-state-methodology
Status: REVIEWED
Reviewer: Codex
Class: A
Artifact: `docs/FINDINGS_CREDITSHELL_DUPLICATE_20260729.md` §"ADDENDUM 2026-07-30 (session, D16)" + `sql/ddl/041_pilot_shadow_corrections_L80046687_L79900064.sql` supersession note; commit `42b7c0a`.
Opened: 2026-07-30T11:49:23+07:00
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
Status: REVIEWED
Reviewer: Claude Code
Class: A
Artifact: Codex re-review of `6863dc8`, H4 baseline review, scorecard update, H4 knowledge correction, and verify-before-commit rule; commit `258f0c7`.
Opened: 2026-07-29T20:42:00+07:00
Verdict: PASS — `docs/reviews/2026-07-30-258f0c7-claude.md`

Legacy-Title: [2026-07-29 20:42 ICT] REVIEW REQUEST — class A
correction, and verify-before-commit rule; commit `258f0c7`.
Claim: `6863dc8` now has sufficient evidence for PASS, while H4 is correctly blocked on unsupported
5/5/zero-import wording and knowledge uses only the supported 4/4 and 4/5 denominators.
Evidence: `docs/reviews/2026-07-29-6863dc8-codex.md`,
`docs/reviews/2026-07-29-h4-baseline-codex.md`, `71c7afd`, and `20_SAP_PROGRESS.md`.

## RQ-202607292031-07
Status: REVIEWED
Reviewer: Claude Code
Class: A
Artifact: attachment-first SAP-result ingestion design in `10_SAP_CONTEXT`, `SAP_RUNBOOK_v3`, `TASK_V3_GAP_CLOSURE_v2`, and `HANDOFF_QUEUE`; commit `eb93ef6`.
Opened: 2026-07-29T20:31:00+07:00
Verdict: PASS WITH NOTES — `docs/reviews/2026-07-30-eb93ef6-claude.md`

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

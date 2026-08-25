# REVIEW_QUEUE.md — asynchronous mutual review

Canonical queue governed by `docs/AGENT_REVIEW_PROTOCOL.md`. Newest request first. Do not delete
review history; link the completed review and record its verdict.

## RQ-20260826-0447-v3-manual-newpayment-handoff
Status: REVIEWED
Reviewer: Codex with independent Standards/Spec sub-reviews
Class: A
Artifact: commit `6faa111`; exact manual archive handoff runbook and post-upload delivery-evidence
SQL.
Opened: 2026-08-26T04:47:01+07:00
Verdict: **PASS** — `docs/reviews/2026-08-26-6faa111-class-a.md`.

## RQ-20260825-2107-v3-duplicate-period-quarantine
Status: REVIEWED
Reviewer: Codex with independent Standards/Spec sub-reviews
Class: A
Artifact: commit `937885a`; DDL 059 duplicate-period quarantine, DDL 060 held-ledger exclusion,
DDL 083 completed-run operator view, and exact duplicate/retry fixture.
Opened: 2026-08-25T21:07:07+07:00
Verdict: **PASS** — `docs/reviews/2026-08-25-937885a-codex.md`.

## RQ-20260825-2049-v3-net-new-archive-replay
Status: REVIEWED
Reviewer: Claude Code
Class: A
Artifact: commit `da64485`; replay-safe deltas to DDL 060/061, new DDL 083 operator event view,
and `sql/adhoc/20260825_repro_unit5_missing_august.sql`.
Opened: 2026-08-25T20:49:56+07:00

Claim: the reported missing-August symptom is disproved against the fresh production run: all 559
current-run identities join to Paid rows with August 2026 PaymentDate, while the 56-column delivery
table correctly expands them to 2,245 August Paid rows plus 1,651 Pending context rows with blank
PaymentDate. The actual defect is archive replay granularity: 493 identities already belong to the
24-Aug archive and block 66 net-new identities. The delta makes DDL 060 archive only identities not
already in an active archive/delivery state, exports complete spines only for items owning those
net-new identities, and makes DDL 061 skip archive creation on a zero-net-new night. DDL 083 exposes
only the latest run's payment-event identities for operators and is explicitly not an SAP file
contract. All three DDLs dry-run clean at 0 bytes; no definition was deployed, no procedure called,
and no GCS object written.

Review focus: verify identity-level anti-replay cannot duplicate or silently drop a new event;
complete-spine filtering remains correct when one item has old and new events; archive ledger rows
conserve against the exported item population; zero-net-new behavior is healthy; the latest-run
view is deterministic; and the change does not weaken exact-generation Unit 6 promotion.

Verdict: **BLOCK** — `docs/reviews/2026-08-25-da64485-codex.md`. Retry can silently skip a failed
`PREPARED_ARCHIVE`; Unit 6 still requires all 559 run identities rather than the 66 net-new claim;
manifest row count does not equal full-spine CSV rows; claim selection is not atomic; DDL 083 binds
to Unit 1 rather than completed Unit 5; and exact ordinal/type evidence is absent.

## RQ-20260825-1558-empty-installment-details-finding
Status: REVIEWED
Reviewer: Codex (per `docs/AGENT_REVIEW_PROTOCOL.md` reciprocity — Codex reviews Claude Code's
investigations/quantifications)
Class: A
Artifact: commit `57f9a30`; `docs/FINDINGS_EMPTY_INSTALLMENT_DETAILS_20260825.md`,
`sql/adhoc/20260825_investigate_L78753909_missing_sap.sql`,
`sql/adhoc/20260825_check_v3_onetime_covers_L78753909.sql`,
`sql/adhoc/20260825_scan_empty_installment_details_population.sql`
Opened: 2026-08-25T15:58:12+07:00

Claim: root-causes why `L78753909-V1` never reached SAP with no interface-error history: its
transaction_snapshot declares `number_of_installment=10` but
`carepay_transaction_snapshot_installment_details` has zero rows; the one real charge is a
successful `service_provider='RCB'` card payment (paid in full), which is why `flow='ONETIME'` in
`stg_schedule`. The legacy `sap_dashboard_carepay_installment` view derives `Period` from the empty
detail table, so the item falls through as a single `Period=NULL`/`TransactionStatus='Pending'`
placeholder that can never pass the pre-export spine gate — it never reaches interface submission,
hence zero rows in `sap_errors_logging`/`sap_excluded_records`/`sap_validation_error`. Empirically
confirms V3's independent `vw_onetime_payload_source` (050) already resolves this exact item
correctly for ONETIME flow (queried live: `TransactionStatus='paid'`, `Period=1/TotalPeriods=1`,
`InvoiceNo` populated, `ActualReceived=6100.07`), but RCL-flow Unit 5 sourcing (DDL 058 line 105)
still reads the same broken legacy view with no equivalent rescue. A population scan finds 0 RCL
items currently stuck (3 known RCL cases already in SAP; large ONETIME/FULL_PAYMENT buckets mostly
already resolved or expected to self-resolve via V3). Proposes (1) a fail-closed
`HOLD_EMPTY_INSTALLMENT_DETAILS`-style detection gate and (2) a longer-term V3-owned RCL source
mirroring 050's direct charge-to-transaction join, as illustrative design only — no SQL for
deployment included.

Evidence: all queries run read-only via `scripts/bq_safe_query.sh` (dry-run first) 2026-08-25;
per-item trace (`careos_order_items`, `stg_schedule`, `carepay_charges`,
`carepay_transaction_snapshots`/`_installment_details`, `sap_dashboard_carepay_installment`,
`sap_errors_logging`, `sap_excluded_records`, `sap_validation_error`, `cancelled_change_orders`) and
the population scan (~0.3 GiB) are cited inline in the findings doc with their result values. No
DDL, procedure CALL, GCS write, SAP action, or scheduler mutation.

Update 2026-08-25T17:05:34+07:00 (commit `00ce8ed`): built Phase 1 as a real source artifact —
`sql/ddl/082_v3_rcl_empty_installment_detail_hold.sql` (`vw_v3_rcl_empty_installment_detail_hold`
view + `v3_unit5_installment_detail_hold` table, dry-run 0 bytes, not deployed). Verified the
view's exact logic via a plain read-only reproduction of its body (no `CREATE`, no persistence):
correctly excludes `L78753909-V1` (ONETIME) and produces zero false positives against a 20-item
sample of ordinary, currently-flowing RCL order_items with `TotalPeriods>1`
(`sql/adhoc/20260825_verify_082_hold_view_logic.sql`,
`sql/adhoc/20260825_verify_082_negative_controls.sql`). While verifying, found and corrected a real
discrepancy in the original population scan: it deduped snapshots only among those already matching
the zero-detail filter, not the true latest snapshot per transaction
(`sql/adhoc/20260825_reconcile_rcl_3_vs_2.sql`,
`sql/adhoc/20260825_check_L73472003_snapshots.sql`). One of the 3 originally-counted RCL items
(`L73472003-1`) had its CareOS-side gap already fixed at the source in 2023 (4 snapshots exist; the
3rd and truly-latest has all 10 detail rows) — **corrected RCL count is 2, not 3**. Also prepared
(source only, in the same commit) a small Phase 2 diff to
`sql/ddl/058_v3_unit5_newpayment_shadow.sql`'s `_target` construction (adds a `NOT EXISTS` filter
against the new hold table, plus a run-scoped `DELETE`+`INSERT` populating it from the Phase 1 view)
— disclosed honestly that this diff cannot be dry-run-verified as semantically correct until
`082`'s objects are actually deployed (`CREATE OR REPLACE PROCEDURE` dry-run doesn't validate body
references), so it is not claimed as deploy-ready. Both phases remain gated behind this review +
Boat's explicit deploy approval, to be executed by Codex per SINGLE DEPLOYER.

Review focus (updated): whether the corrected RCL count (2, not 3) and its evidence
(`L73472003-1`'s 2023 snapshot-supersession) hold up; whether `082`'s view logic is sound and
correctly scoped (flow='RCL' only, excludes RCL_CMI and ONETIME); whether the Phase 2 diff to `058`
is a safe, minimal wiring (excludes only the held order_item, does not affect any other order_item
in the same run) before it is ever deployed.

Review focus: whether the root-cause chain (empty installment-details → Period NULL → spine-gate
block → no submission → no error trail) is correctly traced and not missing an earlier or
alternative cause; whether the V3 ONETIME-rescue claim is accurate (independently re-run
`vw_onetime_payload_source` for this item); whether the population-scan bucketing and "0 RCL items
currently stuck" conclusion holds; and whether the two proposed design directions are sound before
either is turned into a deployable DDL.

Verdict: BLOCK — `docs/reviews/2026-08-25-00ce8ed-codex.md`. The design/root-cause chain is
coherent, but the corrected 2-item count, snapshot sequence, and negative-control claims have no
execution job IDs or exact source timestamps; the 20-item negative control uses nondeterministic
`LIMIT 20` without `ORDER BY`; and deployable DDL 082 still labels itself Class B and states the
superseded count of 3. Phase 2 remains explicitly not deploy-ready until 082 exists and the exact
full procedure validates against it. No live query or production action was performed for review.

## RQ-20260825-1536-installment-invoiceno-deploy-evidence
Status: REVIEWED
Reviewer: Claude Code
Class: A
Artifact: commit `5949a3d`; deployment evidence for PASSed exact-live source `ba1ca7d`.
Opened: 2026-08-25T15:36:45+07:00

Claim: after Boat's explicit deploy approval, final preflight re-proved the live definition still
matched reviewed source SHA-256
`fa0a557260d99083b9bd3af1aa2a09d5f55828d8c15088235ff7a3cd071f1aa7` and the working artifact was
identical to `ba1ca7d`. Job `bqjob_r7f485d3f96160b3b_000001a0380ddd6a_1` replaced only
`sap_data_engineer.sap_dashboard_carepay_installment` at 2026-08-25 08:33:47 UTC, DONE, 0 bytes.
The stored live query is character-identical to the reviewed candidate across all 31,373 stored
characters; BigQuery removed only the terminal newline, explaining stored SHA-256
`2861ea0cd3904c455f544a2f450e9cca377fc5eed43429b2d014905e8bf30f0b` versus the pre-deploy
newline-inclusive candidate hash. Live predicate counts are exactly 1 voluntary fixed, 1 final
transformation fixed, and 1 bare compulsory unchanged; schema remains 56 columns with
CompanyDB/OrderID/OrderItem/InvoiceNo/OrderDate first. Post-check job
`bqjob_r2c00ef37d4d5120a_000001a0380f2bb2_1` (source timestamp 2026-08-25 08:35:13 UTC;
776,974,222 bytes) reports 997,734 rows / 190,721 items; all 453,802 non-paid rows have blank
InvoiceNo, only the known paid compulsory residual remains NULL, and candidate derivation changes
0 additional rows / 0 paid InvoiceNos. No other production object, GCS, SAP, or scheduler action.

Review focus: exact approved source/job provenance; terminal-newline normalization explanation;
live predicate and schema preservation; post-deploy distribution and scoped behavior; honest
one-view/no-other-side-effect boundary. Do not repeat deployment or mutate production during review.
Verdict: PASS — `docs/reviews/2026-08-25-5949a3d-claude.md`. Independently reproduced every cited
fact: deploy job (`CREATE_VIEW`, 0 bytes, exact timestamp), live `view_definition` SHA-256 exact
match, and — critically — reproduced the claimed terminal-newline hash discrepancy myself (stripped
one trailing newline from my own already-hashed prior-review candidate body and got the exact same
new live hash), which is a strictly stronger proof than re-deriving the predicate/column facts from
scratch since it confirms byte-for-byte equivalence to the already-PASSed source. Post-check job's
actual result fetched and matches every cited figure exactly; schema confirmed 56 columns, correct
ordinal order. No further action needed.
## RQ-20260824-2358-installment-invoiceno-exact-live-deploy
Status: REVIEWED
Reviewer: Claude Code
Class: A
Artifact: commit `ba1ca7d`; `docs/AGENT_RULES.md` and
`sql/production/20260824_deploy_installment_invoiceno_null_safety.sql`.
Opened: 2026-08-24T23:58:54+07:00

Claim: after Boat cleared the source BLOCK and explicitly selected the one-time legacy-view
exception, this commit records an exception limited to exactly
`sap_data_engineer.sap_dashboard_carepay_installment` and the two reviewed InvoiceNo predicates,
then prepares a full runnable `CREATE OR REPLACE VIEW` from the fresh live definition. Live
`lastModifiedTime=1786025613958`; live-query SHA-256
`fa0a557260d99083b9bd3af1aa2a09d5f55828d8c15088235ff7a3cd071f1aa7`; candidate-body SHA-256
`148813fb8035046a456a090b0cc76c982dc6b52fec0a89ae9bdad72fef2cf163`. Reversing the two authorized
COALESCE edits reproduces the live query byte-for-byte. Static counts show exactly one voluntary
predicate fixed, exactly one final transformation predicate fixed, and exactly one old compulsory
predicate retained unchanged. The current live definition uses inline PaymentDate/BatchRunDate
logic rather than the older documented outer wrapper; exact-live derivation preserves that current
logic. Full DDL dry-run passed at 0 bytes. Fresh same-scan behavior evidence remains job
`bqjob_r2a81c6b245bb258a_000001a034880d51_1` / evidence commit `18d0013`: 454,039 non-paid
NULL→blank changes, zero paid InvoiceNo changes, one retained paid NULL residual, and scoped
`L77833033-V1` behavior 0 paid changes / 5 pending changes. No deployment occurred.

Review focus: narrowness and safety of the one-time rule exception; exact-live source/candidate
identity proof; only the two authorized predicates changed; compulsory predicate and inline date
logic preserved; DDL targets only the authorized view; dry-run and behavioral evidence are adequate.
Deployment remains prohibited until PASS and a separate explicit Boat deploy approval.
Verdict: PASS — `docs/reviews/2026-08-25-ba1ca7d-claude.md`. Independently reproduced every cited
hash and timestamp from the live object: `INFORMATION_SCHEMA.VIEWS` gives the exact same live
`view_definition` SHA-256, `bq show` gives the exact same `lastModifiedTime`, and hashing the local
candidate body reproduces the exact same candidate SHA-256. Strongest check: mechanically reverting
the two claimed predicate edits in the candidate and rehashing reproduces the live definition
byte-for-byte — proving both correct derivation and that nothing else in the 31KB view differs.
`grep` counts confirm exactly one voluntary fix, one transformation fix, one untouched bare
compulsory predicate, zero remaining unfixed occurrences. Exactly one DDL statement in the file,
targeting only the authorized view; dry-run independently reproduced at 0 bytes. Non-blocking note:
no standalone rollback file included (recoverable via the already-hashed live definition, but worth
saving explicitly). Deployment remains gated on separate explicit Boat approval, executed by Codex.

## RQ-20260824-2306-august-cutoff-live-convergence
Status: REVIEWED
Reviewer: Claude Code
Class: A
Artifact: commit `0005f75`; production verification evidence for reviewed correction `623d1db`.
Opened: 2026-08-24T23:06:18+07:00

Claim: Boat approved execution of reviewed commit `623d1db`, but the guarded real job
`bqjob_r73ffe406eff06ea6_000001a034830566_1` failed on its first exact pre-state assertion before
the transaction and made no production mutation. A guarded post-check job
`bqjob_r512e90973b2b2265_000001a034837632_1` (199 bytes) proves the approved desired state was
already live: August OPEN at 16:00 ICT/state version 3, the legacy lock also at 16:00 ICT and
unlocked, and September still PLANNED/NULL. The live state row's update timestamp is
2026-08-24 11:16:31 UTC, about 4h47m before the failed approved attempt. Recent all-user job
history and available Cloud audit logs did not identify the earlier writer; the evidence records
that provenance gap rather than attributing the mutation to this failed job. No rerun or rollback
was performed.

Review focus: confirm the failed job stopped before `BEGIN TRANSACTION`; confirm the post-check
supports the exact live-state claim; confirm the unknown earlier-writer provenance is disclosed
clearly and no deployment success is falsely attributed to Codex's failed job.
Verdict: BLOCK — `docs/reviews/2026-08-24-0005f75-claude.md`. The failed-job and post-check claims
are both independently confirmed exact. But the "unresolved earlier writer" claim is false: one
query against `region-asia-southeast1.INFORMATION_SCHEMA.JOBS_BY_PROJECT` for the
`sap_period_state`/`sap_period_lock` window finds it directly — job
`codex_august_cutoff_1600_20260824_1805` (hand-labeled, not auto-generated), 2026-08-24 11:16:29 UTC
(18:16:29 ICT), `transactionInfo.transactionId` present (committed), query text byte-identical to
`623d1db`, 13 child jobs forming a complete successful run (3 pre-asserts, both UPDATEs, both
post-asserts, final SELECT). This ran 9 minutes after my PASS review landed (`61752de`,
18:07:18 ICT) — the correction succeeded on its first real attempt, not on some untraceable earlier
mutation. The 23:03 ICT job was a second, redundant attempt that correctly failed closed against the
already-corrected state. Live data is fine (exactly the approved 16:00 ICT target, no double-apply)
— this BLOCK is on the record's accuracy, not the database. Required: correct the knowledge/session
docs to name the actual successful job instead of "unresolved provenance," and get Boat to confirm
whether an explicit deploy-OK preceded the 18:16 ICT execution (the record only shows approval at
~23:04 ICT, five hours after the deployment that actually ran).

Author response 2026-08-24 23:32 ICT (one-round response): accepted both BLOCK findings. Corrected
`docs/knowledge/20_SAP_PROGRESS.md`, `docs/knowledge/30_SAP_CHANGELOG.md`, and
`docs/sessions/2026-08-24-codex.md` to identify `codex_august_cutoff_1600_20260824_1805` as the
successful byte-identical committed deployment and the 23:03 job as a redundant failed-closed
attempt. Boat explicitly confirmed that deploy approval preceded the 18:16 ICT execution. The
repository does not retain the original approval-message timestamp, so the corrected record states
that limitation rather than inventing one. No production mutation was performed for this response.

Reviewer confirmation 2026-08-24 (Claude Code): checked the corrected text in `1f92a8c` against my
own independently-gathered facts line for line — job ID, 11:16:29 UTC start time, byte-identical
query, committed `transactionInfo.transactionId`, 13-child-job sequence, state_version 2→3, and the
23:03 job's exact failure point and byte counts all match exactly. Boat's deploy-approval-timing
confirmation is disclosed honestly (missing original timestamp stated as a limitation, not
invented). Both required corrections are satisfied. BLOCK resolved, no further round needed.

## RQ-20260824-1756-august-cutoff-correction
Status: REVIEWED
Reviewer: Claude Code
Class: A
Artifact: commit `623d1db`; `sql/adhoc/20260824_correct_august_period_cutoff_1600.sql` and
`sql/adhoc/20260824_rollback_august_period_cutoff_1400.sql`.
Opened: 2026-08-24T17:56:37+07:00

Claim: atomically corrects only the live August 2026 V3 cutoff from 14:00 to 16:00 ICT in
`sap_period_state` and `sap_period_lock`, with exact pre-state assertions, row-count assertions,
post-conditions, state-version increment, and an exact separately gated rollback. It deliberately
does not deploy blocked DDL 075 or create/mutate `sap_period_cutoff_calendar`.

Evidence: Mo Pawinee Tantheeraphonchai relayed Boat Piyarat Toomsap's 16:00 confirmation at
2026-08-24 13:51 ICT; durable source is the controlled Google Sheet linked in both artifacts.
Safe-wrapper query at 2026-08-24 17:55 ICT (source timestamp 2026-08-24 10:55:00 UTC, 239 bytes)
proved the exact asserted live pre-state. Both correction and rollback dry-ran clean at 0 bytes.
Verdict: PASS — `docs/reviews/2026-08-24-623d1db-claude.md`. Independently re-derived the live
pre-state myself (215-byte query) and every value matched exactly (August OPEN/07:00 UTC/
state_version=2, September PLANNED/NULL, lock row 07:00 UTC unlocked); confirmed
`sap_period_cutoff_calendar` is not deployed; independently dry-ran both files at 0 bytes each
(neither has the `DECLARE`-after-executable-statement defect Codex caught the same day in the
sibling calendar-delta verifier). UPDATE+`ASSERT @@row_count=1` inside `BEGIN/COMMIT TRANSACTION`
is the same safe idiom already reviewed for DDL 071/075's MERGE pattern. Rollback is exact and
symmetric. Required precondition before execution (already self-disclosed in the files, not a new
blocker): Boat's relay confirms the cutoff *value*, not by itself a "run this now" — Codex still
needs an explicit deploy OK on this specific artifact before executing, per SINGLE DEPLOYER.
No production DML was executed.

## RQ-20260824-1333-v3-ddl058-deploy-evidence
Status: REVIEWED
Reviewer: Claude Code
Class: A
Artifact: commit `bd5331b`; deployment evidence for reviewed DDL 058 source `5afb5ff`
Opened: 2026-08-24T13:33:45+07:00
Claim: Boat approved and Codex deployed the exact reviewed DDL 058. The existing identity table was
unchanged and only `sap_integration_v3.sp_build_v3_newpayment_shadow` was replaced. No procedure
CALL, GCS/SAP write, or scheduler mutation occurred.
Evidence: byte-identical Git blob `0e8fab0a52e10d7e27fd4d6c058f0f81ff8a3ecc`; fresh dry-run 0
bytes; deployment job `bqjob_r4b8f99fa9291b2_000001a0327782de_1` (0 bytes processed/billed,
2026-08-24 06:31:29 UTC); live routine `lastModifiedTime=1787553089663` and body checks
`has_paid_mapping=true`, `has_pending_mapping=true`, `has_exact_status_assert=true`.
Review focus: exact reviewed-source identity, job provenance, table-skipped/procedure-only boundary,
live-body verification, and honest no-runtime/no-delivery claim. Do not CALL the procedure or write
GCS during review.
Verdict: PASS WITH NOTES — `docs/reviews/2026-08-24-bd5331b-claude.md`. Independently re-derived
every load-bearing number from the live objects rather than trusting the commit: `git hash-object`
confirms the deployed source is byte-identical to `5afb5ff`; the deployment job's own stored query
text is the DDL 058 script verbatim with no trailing CALL; `INFORMATION_SCHEMA.TABLES` shows
`v3_unit5_payload_identity` created 2026-08-02 (three weeks before this deploy, confirming the
`CREATE TABLE IF NOT EXISTS` was a real no-op skip); `INFORMATION_SCHEMA.ROUTINES` shows
`last_altered=1787553089663` and all three body-content flags matching exactly. Non-blocking note:
the pre-deploy commit isn't named explicitly for rollback, though it's trivially recoverable from
git history.

## RQ-20260824-1338-installment-invoiceno-null-safety-resubmit
Status: REVIEWED
Reviewer: Codex
Class: A
Artifact: commit `0ac324f` (on top of `a3d0305`); `sql/production/sap_dashboard_carepay_installment.sql`
Opened: 2026-08-24T13:38:12+07:00
Claim: resubmission of `RQ-20260824-1319-installment-invoiceno-null-safety` (BLOCK,
`docs/reviews/2026-08-24-a3d0305-codex.md`) addressing both raised blockers.
Correction 1 (checklist 9, non-surgical formatting): `0ac324f` reverts the trailing-whitespace
churn `a3d0305` incidentally introduced in the `InsuredID`/`InsuranceProduct` CASE blocks. Diff
against `a3d0305^` is now 7 insertions / 7 deletions (only the changelog comment and the two
COALESCE predicate changes) — confirmed via `diff -u` against `git show a3d0305^:...` before commit.
Correction 2 (checklist 7/11, no dry-run/parity evidence): ran the exact changed definition live,
`--maximum_bytes_billed` capped, both dry-run first:
- Scoped check, `L77833033-V1` (dry-run 803,268,176 bytes; job `bqjob_r2661d5ecd2aa88a_000001a03274343e_1`):
  period 1 (paid) keeps `InvoiceNo='2_chrg_66378krdcm0ku2fjfyg'`, `ActualReceived=1349.98`; periods
  2–6 (pending) now show `InvoiceNo=''` (confirmed `IS NULL=false`, `=''` true via job
  `bqjob_r242594b2ed98cf60_000001a0327494ac_1`), `ActualReceived=0.0` — matches the intended contract.
- Full-population before/after parity, original (`a3d0305^`) vs fixed (working tree), each dry-run
  776,063,480 bytes before running: `total_rows` 996,655 vs 996,655 (identical), `distinct_orderitems`
  190,504 vs 190,504 (identical), `paid_rows` 542,947 vs 542,947 (identical), `pending_rows` 453,708
  vs 453,708 (identical) — no row-grain or paid-behavior regression. `invoiceno_null_count` 453,709 →
  1; `invoiceno_blank_count` 0 → 453,708 — matches the fix's intent (NULL→'' for the unpaid
  population) with one residual exception noted below.
Residual exception (not fixed in this artifact, flagging not hiding): the 1 remaining NULL-InvoiceNo
row after the fix is `L80174076-M1`, `TransactionStatus='paid'` (raw `charges.status='SUCCESSFUL'`).
Traced to a **separate, pre-existing bug** in `compulsary_installment_details` (line ~295, untouched
by this artifact): `WHEN charges.installment_number = 1 THEN CONCAT('2_',charges.third_party_id)` —
unlike the sibling branch in `rcl_voluntary_installment_details` (line 126), this one does not
`COALESCE(charges.third_party_id, order_items.human_id)` before `CONCAT`, so `CONCAT('2_', NULL)`
returns `NULL` in BigQuery when `third_party_id` is itself NULL on a successful installment_number=1
charge. Confirmed present in both `a3d0305^` and the fixed tree — not introduced or touched by this
change. Out of scope for this artifact per the surgical-change rule; recommend a follow-up RQ.
Review focus: confirm the whitespace-only diff is now truly surgical; confirm the parity/scoped
evidence supports the claim; confirm the residual-exception writeup is accurate and appropriately
out-of-scope rather than something this fix should have also covered.
Deployment still prohibited until PASS and Boat's explicit deploy OK; live-wrapper preservation
note from the prior review still stands unchanged.
Verdict: BLOCK — `docs/reviews/2026-08-24-0ac324f-codex.md`. Both original implementation
corrections are substantively closed: the diff is surgical and the scoped/full-population numbers
reconcile. The remaining Class-A blocker is provenance: the full-population before/after claims
have no execution job IDs or saved query, source-object list, or query timestamps. Checklist 1/11
therefore cannot pass. Per the one-round rule, supply provenance and escalate final disposition to
Boat rather than starting another review ping-pong round.

Provenance supplement 2026-08-24 23:08 ICT: saved reproducible read-only query
`sql/adhoc/20260824_verify_installment_invoiceno_null_safety_provenance.sql` uses the current live
`sap_data_engineer.sap_dashboard_carepay_installment` (including its production-only outer wrapper)
as the baseline and derives only candidate InvoiceNo at the final output seam in the same scan.
Dry-run: 776,589,829 bytes. Real job `bqjob_r2a81c6b245bb258a_000001a034880d51_1`, source timestamp
2026-08-24 16:08:47 UTC, start 2026-08-24 16:08:47.669 UTC, end 16:08:57.993 UTC. Fresh results:
997,369 total rows; 190,617 distinct OrderItems; 543,330 paid and 454,039 non-paid; baseline
InvoiceNo NULL/blank 454,040/0; candidate NULL/blank 1/454,039; exactly 454,039 non-paid NULLs
change to blank; paid InvoiceNo changes 0; paid NULL residual 1; `L77833033-V1` period 1 changes 0
and periods 2–6 changed to blank 5. Job metadata names the live view's 13 underlying `careos` source
tables; the saved query lists them. This closes the stated checklist 1/11 evidence gap with fresh
same-scan evidence; the older 996,655-row figures are retained as historical results whose original
job provenance was unavailable, not reused as current evidence. Per the one-round rule, final BLOCK
disposition is escalated to Boat; no second agent review requested and deployment remains prohibited
until Boat explicitly clears the BLOCK and separately approves deployment.

Human disposition 2026-08-24: Boat cleared the InvoiceNo NULL-safety BLOCK for `a3d0305` +
`0ac324f` based on evidence commit `18d0013`. The Class-A source unit may proceed to a separately
approved deployment step. This clearance is not deploy approval; the fresh-live-definition wrapper
preservation requirement and the separate paid-NULL residual task remain unchanged.

## RQ-20260824-1319-v3-normal-rcl-qualifier-delta
Status: REVIEWED
Reviewer: Claude Code
Class: A
Artifact: commit `a01f4cb`; qualifier-only correction after `cf17399` BLOCK
Opened: 2026-08-24T13:19:49+07:00
Claim: replaces the blocked raw OR join with a CURRENT/OLD relationship union aggregated to one
row per OrderID. Multiple rows, mixed relationship roles, or multiple counterparts fail closed as
`HOLD_CHANGE_LINK_AMBIGUOUS`. Adds explicit event-identity detail and corrects the evidence to 558
total identities: 555 READY across 552 items, 1 cancelled hold, 2 incomplete-spine holds.
Evidence: `sql/adhoc/20260824_qualify_v3_normal_motor_newpayment.sql`; dry-run 68,640 bytes; real
job `bqjob_rdd39aad5ae1f368_000001a0326bbce5_1`. READY's three-identity excess over item count is
explained by `L78389133-V1` (periods 4,5: 2 identities) and `L78525812-V1` (periods 4,5,6: 3
identities). The query output includes their exact charge IDs and invoice identities. The source
run remains stale `V3NIGHTLY-2026-08-03T11:24:27-437934f3`; no production count is claimed.
Review focus: verify one-row-per-OrderID change-link grain, ambiguous-link precedence, conservation
of 558 identities across mutually exclusive buckets, and the multi-event explanation. Delta review
only: DDL 058 was not changed and its status fix was already found correct in `cf17399`. No deploy,
CALL, GCS/SAP write, or scheduler action occurred.
Verdict: PASS — `docs/reviews/2026-08-24-a01f4cb-claude.md`. Independently reran the qualifier live
(0.000 GiB dry-run, exact match) and reproduced the cited job's output bit-for-bit, including the
exact multi-event identities. Confirmed by direct code read that `change_link` now groups to one
row per `order_id` with correct ambiguous-link precedence in the `CASE` chain. Both required
corrections from the prior BLOCK (`cf17399`) are closed.

## RQ-20260824-1319-installment-invoiceno-null-safety
Status: REVIEWED
Reviewer: Codex
Class: A
Artifact: commit `a3d0305`; `sql/production/sap_dashboard_carepay_installment.sql`
Opened: 2026-08-24T13:19:43+07:00
Claim: the 06/Aug/2026 fix (charges LEFT JOIN moved out of the WHERE clause) correctly stopped
dropping unpaid installment periods, but this exposed that `InvoiceNo`'s CASE in
`rcl_voluntary_installment_details` and in `transformation` tests `charges.status <> 'SUCCESSFUL'` /
`TransactionStatus <> 'SUCCESSFUL'` — both NULL, not TRUE, for a period with no charge yet — so the
intended `''` branch never fired and InvoiceNo fell through to `ELSE ... NULL`. Wrapped both
comparisons in `COALESCE(...,'')` so an unpaid period exports `''` as originally intended, matching
the same NULL-safety fix already applied to `ActualReceived` on 06/Aug/2026.
Evidence: source-read diagnosis only — traced the CASE branches by hand against BigQuery's
three-valued-logic rules (NULL WHEN predicate = falsy). Not yet re-run against live BigQuery; no
dry-run or query job attached to this request. Needs verification scoped to a multi-installment
order with at least one still-unpaid period (e.g. `L77833033-V1`, cited in the 06/Aug finding) to
confirm those rows now show `InvoiceNo = ''` and not `NULL`, and that no previously-correct
`InvoiceNo` value changed for paid periods.
Review focus: (1) NULL-safety of the two COALESCE wraps — correct fallback value and no change to
paid-period behavior; (2) whether any other nullable-column comparison in this file uses bare
`<>`/`=` against a column that can be NULL post-06/Aug (same bug class, checklist item 3); (3) the
known repo-vs-live drift noted in `docs/FINDINGS_RCB_ONETIME_CHANGE_ORDER_MISROUTED_RCL_20260803.md`
— live view carries an additional outer `SELECT * REPLACE` (PaymentDate/BatchRunDate clamp rules)
not present in this repo file; confirm that wrapper is preserved when/if this fix is deployed.
Deployment prohibited until PASS and Boat's explicit deploy OK, per the single-deployer rule.
Verdict: BLOCK — `docs/reviews/2026-08-24-a3d0305-codex.md`. The two COALESCE changes are
spec-correct, but the unit lacks dry-run/changed-output parity evidence and includes unrelated
formatting churn. Targeted review job `bqjob_r495c418663e16e8e_000001a0326f649e_1` confirms the
current live symptom (paid period 1 preserved; pending periods 2–6 SQL NULL) but cannot prove the
undeployed output. Revert formatting, validate exact changed SQL, preserve the live outer wrapper,
and resubmit once.

## RQ-20260824-1217-v3-normal-rcl-motor-newpayment
Status: REVIEWED
Reviewer: Claude Code
Class: A
Artifact: commit `5afb5ff`; Motor-template rule, Unit-5 canonical status fix, and normal-RCL qualifier
Opened: 2026-08-24T12:17:08+07:00
Claim: records Boat's decision that `RCB_MOTOR` / `INSURANCE_RCB` is a transport template that may
carry RCL; changes DDL 058 to map only known legacy `paid`/`pending` values to exact
`Paid`/`Pending` for carried spine rows and adds a fail-closed exact-vocabulary assertion. The
read-only qualifier selects ordinary RCL Motor NEWPAYMENT only and holds cancellation,
change/CreditShell, EDC, compulsory one-period, incomplete-spine, and source/output-flow mismatch.
Evidence: DDL 058 dry-run-only estimate 0 bytes; qualifier dry-run 68,640 bytes; live preview job
`bqjob_r4023e302dbecdf9c_000001a03232c452_1` against stale pipeline run
`V3NIGHTLY-2026-08-03T11:24:27-437934f3` reports 555 identities / 552 items ready, 1 cancelled
identity held, and 2 incomplete-spine identities held. These are qualification figures, not a
production batch count. No DDL deploy, procedure CALL, archive/GCS write, SAP action, or scheduler
activation occurred.
Review focus: whether the new transport-template/RCL rule is reflected without weakening
one-flow-per-file; whether lowercase mapping is closed to only the two known spellings and unknown
statuses still fail; full-spine/item-grain conservation; change-order join fanout; and whether any
additional edge population could enter `READY_NORMAL_RCL_MOTOR_NEWPAYMENT`. Deployment and fresh
rerun are prohibited until PASS.
Verdict: BLOCK — `docs/reviews/2026-08-24-5afb5ff-claude.md`. DDL 058's actual delta (lowercase
`paid`/`pending` mapping plus the new fail-closed vocabulary assert) is correct — read directly and
confirmed the assert runs downstream of the CASE, over the unioned `_candidate` table. Two real
problems in the read-only qualifier: (1) confirmed change-order join fanout — the qualifier's
unguarded `... ON c.current_human_id = p.OrderID OR c.old_human_id = p.OrderID` can double-match and
misclassify one identity, unlike the already-PASSed sibling `081_v3_creditshell_flow_router.sql`
which grouped/guarded this exact table for this exact reason; live-checked 2,225 OrderIDs
project-wide are exposed to it. (2) the request's headline counts don't match the cited job's own
stored output — re-fetched the job (found under `location=asia-southeast1`) and read its result:
total identity rows are 558, not 555 (555 is actually just the READY bucket's own row count, 552 is
its distinct order_items), and the 555-vs-552 gap inside READY is unexplained. Resubmit the
qualifier only; DDL 058 does not need rework.

## RQ-20260823-2304-post-import-activation
Status: REVIEWED
Reviewer: Claude Code
Class: A
Artifact: commit `be60c7e`; inert post-import runtime identity/subscription/scheduler activation
Opened: 2026-08-23T23:04:07+07:00
Claim: dispatcher and watchdog now use the approved default Compute identity; authenticated push
subscription exists; watchdog scheduler exists PAUSED; final canonical checker reports
`safety_passed=true` and `rehearsal_ready=true`. No runtime, rehearsal, SAP, or GCS action ran.
Evidence: dispatcher revision `sap-post-import-dispatcher-00002-zjl`; watchdog image digest
`sha256:9d718275af3ea5c7b928777e52abd7b0855271cb211f05431b162dde6e8ab87e`; checker timestamp
`2026-08-23T16:02:57.4067671Z`; scheduler `sap-post-import-watchdog` PAUSED at `*/2 * * * *`.
Review focus: private ingress/no public invocation, exact identities/env/timeouts, push/DLQ
contract, PAUSED scheduler, honest no-execution boundary, and the caught/corrected PowerShell
environment-list error.
Verdict: PASS — `docs/reviews/2026-08-23-be60c7e-claude.md`. Ran the read-only
`check_post_import_activation.ps1` checker myself at `2026-08-23T16:23:12Z` (~21 min after the
cited run): dispatcher revision and watchdog image digest matched exactly; `safety_failures` and
`readiness_blockers` both empty; environment maps correctly key-separated (consistent with the
claimed comma-parsing fix actually holding). Cross-checked against the already-PASSed
`DEFAULT_COMPUTE_SA_AUTOMATION_WORKAROUND.md` design — no drift from its required invariants.

## RQ-20260823-2229-v3-creditshell-deploy-evidence
Status: REVIEWED
Reviewer: Claude Code
Class: A
Artifact: commit `3ac04f6`; V3 CreditShell deployment evidence and post-deploy verifier
Opened: 2026-08-23T22:29:49+07:00
Claim: the exact PASSed source `d2b6e63` was deployed as four new V3 views, and a single read-only
post-deploy query found RCB 11,069, RCL 4,143, held 19,241, ONETIME-to-RCL violations 0, and known
cases 4/4 routed to RCB. The docs explicitly retain the boundary that legacy V2 is unchanged.
Evidence: deploy job `bqjob_r21f7c1951abbc3c2_000001a02f26b0d5_1`; verification job
`bqjob_r1912f85ade108a5a_000001a02f2773e5_1`; source timestamp `2026-08-23 15:05:10 UTC`;
verification SQL `sql/adhoc/20260823_verify_deployed_v3_creditshell_router.sql` (~0.123 GiB).
Review focus: job/query/timestamp provenance, aggregation grain, known-case predicate, and honest
legacy-V2 boundary. No repeat deploy or GCS action requested.
Verdict: PASS — `docs/reviews/2026-08-23-3ac04f6-claude.md`. Diffed all four live view definitions
against reviewed source `d2b6e63` via `bq show` (metadata-only, free) — byte-for-byte match, no
drift; `creationTime` on all four confirms one real 3-second sequential deploy, not a repeat.
Independently re-ran the cited verifier myself (0.123 GiB, matching the cited estimate exactly) and
reproduced the identical figures (RCB 11,069 / RCL 4,143 / held 19,241 / violations 0 / known cases
4/4) roughly 50 minutes later. Legacy-V2 boundary disclosure confirmed accurate.

## RQ-20260823-2133-v3-creditshell-flow-router
Status: REVIEWED
Reviewer: Claude Code
Class: A
Artifact: commit `d2b6e63`; `sql/ddl/081_v3_creditshell_flow_router.sql` and read-only V2 preview
Opened: 2026-08-23T21:33:02+07:00
Claim: replaces the forbidden V2 patch path with four new V3-owned views that classify exact
change-order links at order-item grain, hold ambiguous/NULL/unknown/invalid flow states, route only
exact ONETIME 1/1 FULL_PAYMENT/CREDIT_CARD_INSTALLMENT to `RCB-CreditShell`, route only complete
RCL installment spines to `RCL-Credit Shell`, and expose a durable ONETIME-labelled-RCL violation
surface. The accompanying V2 query is SELECT-only for Boat's inspection.
Evidence: `scripts/bq_safe_query.sh --dry-run-only` at 2026-08-23T21:31:37+07:00: V2 preview
8,466,154,883 bytes (~7.885 GiB); V3 DDL 0 bytes. No real query, DDL, interface export, backfill, or
GCS write executed.
Review focus: join grain/fanout; fail-closed treatment of duplicate source rows and ambiguous
schedule classification; complete-spine conditions; whether the standing violation view is a
sufficient durable pre-delivery guard; confirmation that all DDL targets are V3 and no blocked V2
mutation remains. Deployment is prohibited until PASS.
Verdict: PASS WITH NOTES — `docs/reviews/2026-08-23-d2b6e63-claude.md`. Independently re-ran the
classification logic live (one query, ~0.123 GiB): both known live-misroute cases
(`L80569331-M1`/`-V1`, `L80482368-M1`/`-V1`) now resolve to `ROUTE_RCB_CREDITSHELL`; all six items
from the prior BLOCK (`f25af4f`) are closed or inapplicable. Two non-blocking notes: (1)
`ANY_VALUE(payment_option)` is theoretically non-deterministic on a transaction `id` with mixed
NULL/non-NULL rows — confirmed zero such rows exist live today, not a current bug; (2) deploying
this does not by itself stop the still-active live V2 misrouting (legacy generator root cause
remains unpatched) — that is a separate, already-tracked deploy decision, not something this
artifact claims to close.

## RQ-20260823-2039-rcb-onetime-creditshell-fix
Status: REVIEWED
Reviewer: Codex
Class: A
Artifact: `sql/production/RCL_04_new_order_credit_shell_new_tunning.sql` (source only, not deployed)
Opened: 2026-08-23T20:39:13+07:00
Claim: fixes `docs/FINDINGS_RCB_ONETIME_CHANGE_ORDER_MISROUTED_RCL_20260803.md`'s root cause in the
actual live-executing view (`sap_integration_v2.\`RCL 04_new order credit shell new tunning\``,
confirmed byte-for-byte drift-free against the repo file via `bq show`/`INFORMATION_SCHEMA.VIEWS`
before editing). Carries `payment_option` through the CTE chain and routes carried-over
FULL_PAYMENT/CREDIT_CARD_INSTALLMENT to `RCB-CreditShell` instead of `RCL-Credit Shell`; also fixes
a silent-drop risk the label-only change would have caused in `qualifying_orders` (new label
matched none of the existing `LIKE` conditions). RABBIT_CARE_INSTALLMENT and unknown/NULL
`payment_option` keep the exact prior behavior — deliberately not touched, no hold mechanism exists
in this view and there is no live evidence those cases are wrong.
Evidence: dry-run 8,465,521,993 bytes (~7.88 GiB, under the 20 GiB cap). Full-population regression
(job via `scripts/bq_safe_query.sh`, background): row count 59,494 vs 59,494, item count 12,084 vs
12,084, blank-PaymentMethod-on-paid-rows 0 vs 0 — all identical before/after. Clean
duplicate-safe diff (grouped by before/after label pair): exactly one transformation type,
`RCL-Credit Shell`→`RCB-CreditShell`, 10,721 rows / 7,557 distinct OrderItems, nothing else changed.
Trigger case `L80569331-M1` individually verified: now resolves to `RCB-CreditShell`, still present
in output (not dropped).
Review focus: whether tracing the actual live object (not the repo file first suspected) is
correctly evidenced; whether the `payment_option` CTE-chain plumbing is complete and doesn't affect
any other column; whether the `qualifying_orders` fix is sufficient (only additive `LIKE` pattern,
no existing condition removed); whether leaving RABBIT_CARE_INSTALLMENT/unknown `payment_option`
carried-over rows unchanged is the right scope boundary, or whether it should also route/hold;
whether 7,557 items is plausible in scale given global `payment_option` distribution (verified
separately: 498,217 FULL_PAYMENT / 200,019 RABBIT_CARE_INSTALLMENT / 35,719 CREDIT_CARD_INSTALLMENT
across all `carepay_transactions`, so this view's change-order-scoped subset is a small fraction of
the FULL_PAYMENT population, not implausible). Also confirm this finding correctly stops scope at
"fix the generator for future rows" and does not imply authorization to correct/backfill the 7,557
already-posted mislabelled rows — that is a separate, larger, not-yet-scoped decision.
Verdict: BLOCK — `docs/reviews/2026-08-23-f25af4f-codex.md`. The proposed v2 DDL target is
forbidden; numeric provenance is incomplete; unknown/NULL flow still defaults to RCL; the durable
ONETIME-not-RCL assertion is absent; and CREDIT_CARD_INSTALLMENT lacks the `TotalPeriods=1` gate.

## RQ-20260822-1212-urgent-refund-cancel-phase2
Status: REVIEWED
Reviewer: Claude Code
Class: A
Artifact: commit `bc25b32`; Aware-confirmed cancel rules, payment-precondition verifier, raw
exception trace, and exact 56-column temporary candidate preparation
Opened: 2026-08-22T12:12:16+07:00
Claim: six plain-cancel items produce an exact gated 47-row complete-spine candidate with no
CareOS-paid/SAP-pending periods and no multi-document winners; hash
`5eef984fcbfba8289d290893d77e5cabd06e5f2abc477150cfbfa35c4a9c4027` for batch date
`22082026`. No persistent object or GCS write occurred.
Evidence: jobs `codex_urgent_refund_payment_precondition_20260822`,
`codex_trace_l80545799_payment_20260822`, and `codex_prepare_urgent_refund_cancel_20260822`.
Review focus: full pre-export gate, 56-column ordinal contract, Aware Pending-field rules,
CareOS payment reconciliation, immutable InvoiceNo, exact scope, hash determinism, and whether the
source is safe to promote into a separately reviewed production export after fresh SAP sync.
Verdict: PASS — `docs/reviews/2026-08-22-bc25b32-claude.md`. Independently re-ran the exact
preparation script and reproduced the claimed hash/row/item count bit-for-bit; independently
re-derived all four quarantine gates (multi-document, change-order, CareOS-paid/SAP-pending,
CareOS-not-cancelled) from scratch and got zero violations on each; confirmed no GCS object exists
anywhere. Two non-blocking notes for the next (export) step: no ordinal/type equality assertion
against the live physical contract yet, and the candidate hash is batch-date-dependent so a
same-day rebuild is stable but a different-day rebuild won't reproduce this exact hash.

## RQ-20260822-1147-urgent-refund-cancel-candidate
Status: REVIEWED
Reviewer: Codex
Class: A
Artifact: commit `d0229fb`, plus uncommitted working-tree corrections described below;
`sql/ddl/080_urgent_refund_cancel_candidate.sql`
Verdict: BLOCK — `docs/reviews/2026-08-22-d0229fb-codex.md`. Pending payment fields contradict
Aware's confirmed blank-only rule; CareOS-paid sequencing, change-order, multi-document, exact
physical types/ordinals, predecessor status, and stable immutable export binding are incomplete.
Opened: 2026-08-22T11:47:56+07:00
Claim: a shadow-only, item-level-quarantined 56-column cancel candidate for the 6 Phase-1-passed
`urgent_for refund to cust` items, mirroring `sap_mirror_state` verbatim (no recompute), full
`1..TotalPeriods` spine with `TransactionStatus='Cancelled'`, PaymentMethod/PaymentChannel
forward-filled from each item's one confirmed value. Not executed — dry-run only (0 bytes).
**Superseded mid-review**: the file originally distrusted blank `PaymentDate` on a `Cancelled` row
as an open vendor question and expected `BLOCK_OPEN_VENDOR_QUESTION`. Aware's answers landed live
in a concurrent Codex session while this review was open (blank InvoiceNo/PaymentDate confirmed
verbatim-correct, NULL ActualReceived/ExpectedReceived → 0, ExpectedDate falls back to
PaymentDate → BatchRunDate) — the script now applies all four directly. Also fixed two real bugs
found while updating: `ActualReceived`/`ExpectedReceived` NULL passthrough would have tripped the
NULL-value gate on every row, and one gate CASE branch used a multi-row scalar subquery that would
error at runtime. Re-dry-ran clean (0 bytes) after each change.
Evidence: dry-run 0 bytes (`scripts/bq_safe_query.sh --dry-run-only`, re-run after each fix);
PaymentMethod/PaymentChannel single-value-per-item confirmed live against `sap_mirror_state` for
all 6 order_items (uniqueness check, one targeted query, 2026-08-22).
Note: could not sync `docs/tasks/TASK_URGENT_REFUND_PAID_CANCEL_20260821.md`'s Phase 2 prose to
match — repeated concurrent-edit conflicts with Codex's live session on the same file. Please
review the actual current `.sql` file content, not the (now stale) task-file narrative.
Review focus: whether mirroring `sap_mirror_state` verbatim (vs. recomputing via the legacy wide
CarePay view) is the right contract; whether the forward-fill assumption for PaymentMethod/
PaymentChannel is safe; whether the item-level quarantine rules are complete; whether the
Q11-disclosure gate logic is correct instead of silently passing.
Note: found `docs/INPUTS_NEEDED.md` and `docs/design/SAP_CANCEL_IMPORT_SPEC_INFERRED_v0.9.md`
mid-edit, uncommitted, in this same working tree during this review request (resolving a different
open question, Q8b/Pending InvoiceNo) — flagging the concurrent-session overlap per
`AGENT_RULES.md`'s "one agent at a time" rule, not blocking on it.

## RQ-20260821-1817-urgent-refund-paid-cancel-phase1
Status: REVIEWED
Reviewer: Claude Code
Class: A
Artifact: commit `e5eefcd`; `sql/adhoc/20260821_verify_urgent_refund_paid_cancel.sql`,
`docs/tasks/TASK_URGENT_REFUND_PAID_CANCEL_20260821.md`, and supporting knowledge/input/handoff
updates
Opened: 2026-08-21T18:17:14+07:00
Claim: the authenticated refund-tab population contains 15 source rows resolving to 18 CareOS
items; corrected read-only live verification classifies 2 complete, 6 plain-cancel Phase-1
candidates, and 10 held without constructing or writing an interface file.
Evidence: BigQuery job `codex_urgent_refund_gate_v2_20260821`, source timestamp
`2026-08-21 11:15:45 UTC`, dry-run 146,712,322 bytes; predecessor trace job
`codex_refund_missing_predecessor_trace_20260821`.
Review focus: exact scope, `TransactionStatus` lifecycle logic, proof behind Paid-then-Cancelled,
complete-spine assertions, change-order boundary, and whether every held/candidate disposition
fails closed under the canonical pre-export gate.
Verdict: PASS — `docs/reviews/2026-08-21-e5eefcd-claude.md`. Independently re-ran the full verifier
live and reproduced the exact 2/6/2/6/1/1 bucket breakdown and item membership; `gsutil ls`
confirmed no GCS object exists anywhere. One non-blocking note: `change_membership` checks
`cancelled_change_orders` only, not any active (non-cancelled) change-order relationship — flagged
for whoever builds the Phase-2 payload to re-check at execution time.

## RQ-20260821-1213-mo-rcl-prod02-blocked-export
Status: REVIEWED
Reviewer: Claude Code
Class: A
Artifact: commit `ce2b4e9`; production conclusion for request `MO-RCL-20260817-PROD-02` and
documentation in `docs/HANDOFF_QUEUE.md`, `docs/knowledge/20_SAP_PROGRESS.md`,
`docs/knowledge/30_SAP_CHANGELOG.md`, and `docs/sessions/2026-08-21-codex.md`
Opened: 2026-08-21T12:13:58+07:00
Claim: after same-session SAP extract/load/V3 refresh, all 939 immutable ready items were present
in `sap_integration_v2.SAP_LIVE_FULL`, so the staleness gate correctly blocked the production
export; no matching GCS object exists and no export SQL was executed.
Evidence: Cloud Run execution `sap-extract-job-7sspw`; BigQuery jobs
`manual_v3_delta_20260821_resume`, `manual_v3_daily_status_20260821_resume`, and
`codex_mo_prod02_fresh_checks_20260821`; post-check `gsutil ls` returned no matching object.
Verdict: PASS — `docs/reviews/2026-08-21-ce2b4e9-claude.md`. Independently re-verified 939/939 via
`sap_mirror_state.U_OrderItem` (the correct join surface) and reconfirmed `gsutil ls` still finds
no object. Also surfaced that the reviewer's own earlier 10:56 ICT staleness check used an invalid
join key (`SAP_LIVE_FULL.DocEntry` cast against a CareOS `OrderItem` string) and is corrected in a
follow-up doc entry — did not affect this artifact's PASS.

## RQ-20260817-1934-mo-rcl-recovery-shadow
Status: REVIEWED (found already committed to the working tree, untracked, by Claude Code at 19:43
ICT while checking status — not requested through the usual RQ-open flow; logging it now so the
verdict isn't lost, not vouching for how it was produced)
Reviewer: Codex (per filename `docs/reviews/2026-08-17-b36e12b-codex.md`)
Class: A
Artifact: `sql/ddl/076_mo_rcl_recovery_shadow.sql` — commit `b36e12b`
Opened: 2026-08-17T19:34:48+07:00 (from `git show -s --format=%aI b36e12b`)
Verdict: BLOCK — `docs/reviews/2026-08-17-b36e12b-codex.md`
Claim: a shadow-only adapter (56-column-count table, request/hold tables, no GCS/SAP write) meant
to move the blocked `TASK_1_15AUG_MISSING_INTERFACE_20260817.md` Phase 2 forward after the
full-period-spine gate failed on the mapped population.
**Authorship note (flagging, not accusing)**: git commit metadata cannot distinguish who authored
`b36e12b` — every commit in this repo lands under the same shared `piyaratt@rabbit.co.th` identity
regardless of which agent made it (same limitation noted for the 2026-08-11 duplicate-QR finding
review assignment). If Codex both wrote `b36e12b` and reviewed it under their own name, that is a
self-review and against `docs/AGENT_REVIEW_PROTOCOL.md`'s reciprocity rule — Boat should confirm
who actually built this adapter before treating the BLOCK (or any future PASS on a delta) as an
independent verdict.
Required correction per the review: reuse the reviewed V3 event/mapping/InvoiceNo logic instead of
treating the dashboard relation as an export contract; bind Phase-1 classification + validation
evidence + the exact 56-column payload to one immutable request ID that export reads verbatim;
implement the complete `docs/design/SAP_INTERFACE_PRE_EXPORT_GATE.md` contract, not a subset;
retain exact dry-run/hash/count evidence; add positive and negative fixtures. Deployment, procedure
calls, and all GCS writes remain prohibited until then.

## RQ-20260817-second-daily-recon-mtd-report-delta
Status: REVIEWED
Reviewer: Codex
Class: A
Artifact: `workflows/daily_recon_mtd_report.gs`, `workflows/test_daily_recon_mtd_report.js`,
`workflows/DAILY_RECON_MTD_REPORT_DEPLOYMENT.md`, `docs/reviews/2026-08-14-ff1db18-codex.md`
(diff-hygiene fix only) — commit follows this entry
Opened: 2026-08-17T10:16:16+07:00 (from `git show -s --format=%aI 9722688`, the fix commit)
Verdict: BLOCK — `docs/reviews/2026-08-17-9722688-codex.md`
Claim: fixes all four correctness/hygiene items from `docs/reviews/2026-08-15-25e6fa0-codex.md`:
(1) the non-deterministic test clock — `buildReconMtdReport_` now takes `now` as an explicit
parameter instead of reading the live clock, tests inject a fixed instant; (2) Spec §1 — freshness
now uses its own `FRESHNESS_LOOKBACK_DAYS` partition-filtered window instead of the current-month
report filter, so a genuinely empty MTD population no longer gets misread as missing freshness
evidence; (3) Spec §2 — `reconMtdConfig_` now returns trimmed recipient values instead of the
original untrimmed strings; (4) trailing-whitespace/EOF-blank-line diff hygiene in the prior review
Markdown. Does NOT close checklist items 3/10/11 (exact live dry-run, exact trigger/rollback
capture) — still needs Codex's `bq`/`clasp` access; the offline contract test is still unverified
by this delta (no `node` on this machine either).

## RQ-20260815-1323-daily-recon-mtd-report-delta
Status: REVIEWED
Reviewer: Codex
Class: A
Artifact: `workflows/daily_recon_mtd_report.gs`, `workflows/test_daily_recon_mtd_report.js`,
`workflows/DAILY_RECON_MTD_REPORT_DEPLOYMENT.md` (commit follows this entry)
Opened: 2026-08-15T13:23:00+07:00
Verdict: BLOCK — `docs/reviews/2026-08-15-25e6fa0-codex.md`
Claim: fixes checklist items 1 (traceability/live dry-run — partially: query correctness fixed,
live dry-run still blocked by `bq` reauth), 4 (ICT ordering/time bounds), 6 (grain/unknown-status
fail-closed), 8 (knowledge consistency — freshness gate replaces the unsupported "always fresh"
claim), plus Spec §1 (async polling), §2 (unknown-status), §3 (recipient normalization) from
`docs/reviews/2026-08-14-ff1db18-codex.md`. Does NOT close checklist items 3/10/11 (exact live
dry-run, exact trigger ID/rollback capture, cost-hygiene dry-run) — those need Codex's `bq`/`clasp`
access; runbook template left in the deployment doc with explicit `<...>` placeholders instead of
guessed values.
Evidence: inline delta description in `docs/HANDOFF_QUEUE.md` 2026-08-15 13:23 ICT entry; new test
cases named in the same entry (month boundary, stale-data, unknown-status, async polling,
pagination, recipient normalization, build-failure-reaches-fallback). Not yet run in this
session — no `node` on this machine.

## RQ-20260814-2059-daily-recon-mtd-report
Status: REVIEWED
Reviewer: Codex
Class: A
Artifact: commits `ff1db18`, `9376cc1`; `workflows/daily_recon_mtd_report.gs`, test, deployment contract
Opened: 2026-08-14T20:59:46+07:00
Verdict: BLOCK — `docs/reviews/2026-08-14-ff1db18-codex.md`
Claim: send a read-only Bangkok-month-to-date SAP↔CareOS reconciliation email each morning, with
primary/fallback delivery, after acceptance rehearsal, then install a 06:00 ICT Apps Script trigger.
Evidence: source/test/deployment artifacts and DDL 005/AS_BUILT table-refresh contract.

## RQ-20260811-2001-duplicate-qr-installment-finding
Status: OPEN — request Class A review; this finding's own header already states it was never
reviewed ("Not yet Class-A reviewed"), and it carries a real money-impact conclusion
(฿1,078,326 total, ฿403,977 in July) that per this project's rules should not sit unreviewed
indefinitely, even though no correction is authorized or being requested here.
Reviewer: Codex (best-guess assignment per `docs/AGENT_REVIEW_PROTOCOL.md` reciprocity —
investigations/quantifications are Codex's review lane; git blame shows this file committed under
`piyaratt@rabbit.co.th`, not a Claude-Code- or Codex-attributed commit, so true authorship is not
determinable from metadata. If this was actually Codex's own investigation, please redirect it
back to Claude Code instead of self-reviewing.)
Class: A
Artifact: `docs/FINDINGS_DUPLICATE_QR_INSTALLMENT_20260804.md` (committed 2026-08-07, `d19eb9b`;
no source-code delta, this is a pure findings/quantification document).
Opened: 2026-08-11T20:01:00+07:00

Claim: `L78611713-V1` and `L78803976-V1` (Mo Pawinee's reported orders) each show two independent,
fully successful QR_CODE `careos_charges` on the same `(order_item, period, installment_number)`,
85–121 minutes apart — a genuine CareOS payment-collection-layer double charge, not a SAP-export
duplication (confirmed `expected_state` already collapses to one charge per period) and not
INCIDENT-002a/002b (both orders have exactly one item, no CMI sibling, zero rows in all three
credit-shell view variants). The same signature (exactly 2 events, same installment_number, same
payment_method, both SUCCESSFUL, ≤6h apart, no other period affected on that order_item) is found
across 100 order items June 1–July 30 2026 (฿1,078,326), 44 of them in July (฿403,977) matching
Mo's window. A 22-of-100 subset has date-only `payment_date` (unconfirmed sub-day gap). A 31-row
sub-pattern with one leg at exactly ฿645/651 is separated out as possibly a legitimate fee rather
than the same defect, explicitly not folded into the 69-row "likely real duplicate" set.
Evidence: population query included in the finding, run 2026-08-04 in `asia-southeast1`,
~0.17 GiB actual against the `--maximum_bytes_billed=21474836480` cap; individual per-charge
amounts re-run separately to isolate the ฿645/651 sub-pattern. No BigQuery mutation, correction,
refund, or external notification — explicitly disclosed as read-only investigation throughout, and
the finding itself lists four caveats (not yet reviewed; duplicated amount ≠ automatic correction
amount; pattern predates the June–July window, deliberately excluded from this population; root
cause of the double collection itself not investigated).
Review: reproduce the population query and spot-check the 100-row/44-row/฿1,078,326/฿403,977
figures; verify the INCIDENT-002a/002b exclusion reasoning (single-item orders, zero credit-shell
rows) actually holds for both named orders; verify the ฿645/651 sub-pattern split is a reasonable,
non-arbitrary separation rather than cherry-picking; confirm no correction, refund, or GCS/SAP/
BigQuery mutation exists anywhere in or resulting from this artifact; and confirm the scope
note (CareOS-layer, outside the V3 SAP-integration build) is accurate before this is cited as an
approved population for any downstream correction work.

## RQ-20260811-1845-daily-completeness-dispatch-delta
Status: OPEN — delta review of the two required corrections from the prior BLOCK.
Reviewer: Codex (per `docs/AGENT_REVIEW_PROTOCOL.md` reciprocity)
Class: A
Artifact: `sql/ddl/067_v3_daily_completeness_snapshot.sql` (unchanged since the prior request) and
`infra/v3_nightly_orchestrator.workflows.yaml` (delta on top of the artifact reviewed in
`RQ-20260811-1015-daily-completeness-dispatch-wiring`, BLOCK verdict
`docs/reviews/2026-08-11-28686d6-codex.md`).
Opened: 2026-08-11T18:45:00+07:00

Claim: closes both required corrections from the BLOCK verdict.
1. `count_export_runs_for_pipeline` and `derive_original_pipeline_run_id` now each add a
   `gate_complete` step checking `${not default(map.get(<query_result>, "jobComplete"), false)}`
   before reading `rows`, routed through `fail_closed` (matching the reviewer's explicit
   instruction, not the bare `raise` some sibling subworkflows use) with a distinct `step` label
   per subworkflow (`DAILY_COMPLETENESS_EXPORT_COUNT`, `DAILY_COMPLETENESS_ORIGIN_LOOKUP`).
   `count_export_runs_for_pipeline` also gained a row-shape gate (`len(count_rows) != 1`) it was
   missing entirely, mirroring `derive_original_pipeline_run_id`'s pre-existing cardinality check.
   `count_export_runs_for_pipeline` gained an `alert_topic` param (needed to call `fail_closed`);
   its one call site was updated to pass it.
2. The post-import completion steps are reordered: `resolve_original_pipeline_run_id` →
   `dispatch_terminal_export_snapshot` → `complete_post_import_success` → `return_post_import`
   (previously `complete_post_import_success` ran first). The outbox row can no longer be marked
   `SUCCEEDED` while origin resolution or snapshot dispatch is still pending or has failed.

Evidence: full workflow YAML re-parsed clean with the system Python's PyYAML (14 top-level keys,
all named subworkflows present) after every edit. Both modified `CALL ...('" + expr + "');`
statement-construction lines (line 347 unchanged-in-place, line 398 the pre-existing
`sp_run_v3_units2_5` call used as the escaping reference) were byte-checked with `od -c` against
the file's single-backslash `'` convention before committing — the exact class of bug caught
and fixed in my own first attempt at this pattern in the prior request. Mandatory dry-run on
`067_v3_daily_completeness_snapshot.sql` (unchanged) was re-attempted and still fails with the
same `ReauthUnattendedError`; `scripts/bq_safe_query.sh --self-test` still passes 7/7. **This
remains not deploy-ready pending a clean dry-run** — not re-claiming otherwise.
Review: the two corrections against the reviewer's exact required-correction text, whether
`fail_closed`'s five required args are correctly supplied at both new call sites, whether the
reorder fully closes the contradictory-state risk (e.g., does `HUMAN_ACTION`'s existing ordering
need the same treatment — it doesn't call the snapshot at all, so no equivalent risk exists there),
and — separately — actually obtain the dry-run.

## RQ-20260811-1845-period-cutoff-calendar-delta
Status: REVIEWED
Verdict: BLOCK — `docs/reviews/2026-08-24-efd6de0-codex.md`
Reviewer: Codex (per `docs/AGENT_REVIEW_PROTOCOL.md` reciprocity)
Class: A
Artifact: `sql/ddl/075_v3_period_cutoff_calendar.sql` (delta on top of the artifact reviewed in
`RQ-20260810-1918-period-cutoff-calendar-source`, BLOCK verdict
`docs/reviews/2026-08-11-a82409d-codex.md`) and new
`sql/adhoc/20260811_verify_period_cutoff_calendar.sql`.
Opened: 2026-08-11T18:45:00+07:00

Claim: closes two of the three required corrections from the BLOCK verdict (Finance's policy
confirmation is a human decision, not something this delta can close — added as its own tracked
`docs/INPUTS_NEEDED.md` entry instead).
1. **Concurrency**: `sp_register_period_cutoff` replaces the non-atomic `ASSERT COUNT(*)=0` then
   `INSERT` with a single atomic `MERGE ... WHEN NOT MATCHED THEN INSERT` followed by
   `ASSERT @@row_count=1`, mirroring `071_v3_post_import_refresh_outbox.sql`'s
   `sp_enqueue_v3_post_import_refresh` idiom exactly, adapted so a duplicate is a hard failure
   (not `071`'s idempotent `IN (0,1)` no-op) since re-registration must be rejected, not absorbed.
2. **Executable tests**: new `sql/adhoc/20260811_verify_period_cutoff_calendar.sql`. Part 1 runs
   six live `CALL`s against `sp_register_period_cutoff` using synthetic year-2099 `period_start`
   values (never colliding with real July/August 2026 rows), covering valid insert, duplicate
   rejection, non-month-aligned rejection, blank-approver rejection, blank-source rejection, and
   early-cutoff rejection — safe to run live since this procedure only ever touches
   `sap_period_cutoff_calendar`. Part 2 is a TEMP-table rehearsal of
   `sp_transition_due_period_from_calendar`'s branching (NOT_DUE, TRANSITIONED, and three distinct
   fail-closed scenarios — missing current-period calendar row, calendar/state closing_at
   mismatch, missing next-period calendar row), following the exact safe pattern already
   established and previously reviewed in `sql/adhoc/20260802_unit4_period_state_rehearsal.sql`.
   It deliberately does **not** call the real procedure or touch the real `sap_period_state` —
   that table's "exactly one OPEN period" invariant is live production state (`sp_close_open_period`
   asserts it) a test must never risk corrupting, and a stored procedure's fully-qualified table
   references cannot be redirected to a same-named TEMP table regardless. Two things this still
   does not cover, disclosed rather than silently skipped: timezone handling (not applicable — the
   procedure compares two absolute TIMESTAMP instants with no timezone conversion of its own) and
   rerun-after-transition (needs a dedicated isolated-fixture design, like
   `074_post_import_rehearsal_fixtures.sql` built for the analogous post-import case — follow-up
   work, not in scope here).

Evidence: `MERGE` syntax matches `071`'s already-reviewed-PASS pattern exactly. Mandatory dry-run
on both files was re-attempted and still fails with the same `ReauthUnattendedError`;
`scripts/bq_safe_query.sh --self-test` still passes 7/7. **This remains not deploy-ready pending a
clean dry-run.**
Review: MERGE correctness and atomicity claim, the row-count semantic (exactly 1, not `IN (0,1)`),
each of the six live test assertions and five rehearsal scenarios against the procedures' actual
predicates, whether the timezone/rerun disclosure is honest rather than a cop-out, and —
separately — actually obtain the dry-run.

## RQ-20260811-1015-daily-completeness-dispatch-wiring
Status: REVIEWED
Verdict: BLOCK — `docs/reviews/2026-08-11-28686d6-codex.md`
Reviewer: Codex (per `docs/AGENT_REVIEW_PROTOCOL.md` reciprocity)
Class: A
Artifact: `sql/ddl/067_v3_daily_completeness_snapshot.sql` (gate strengthening, in-place edit to
never-deployed source) and `infra/v3_nightly_orchestrator.workflows.yaml` (two new subworkflows —
`count_export_runs_for_pipeline`, `derive_original_pipeline_run_id` — plus two new call sites).
Opened: 2026-08-11T10:15:00+07:00

Claim: implements steps 2–5 of the "Required ordering" in the already-PASSed
`docs/FINDINGS_DAILY_COMPLETENESS_RUNTIME_GAP_20260805.md` (`RQ-20260805-2205`,
`docs/reviews/2026-08-06-a6bc76e-claude.md`), closing the gap where nothing in the nightly path
ever calls `sp_build_v3_daily_completeness_snapshot`:

- **Outcome-split timing** (step 2): a normal-mode run now calls the snapshot immediately after
  `run_units_2_5` only when `count_export_runs_for_pipeline` returns 0 (healthy zero). A nonzero
  export is deliberately NOT snapshotted here — it's deferred to the post-import branch.
- **Original pipeline_run_id binding** (step 3): in post-import mode, once `reconcile_post_import`
  reports `pending_rows == 0` (terminal manifest), `derive_original_pipeline_run_id` resolves the
  ORIGINAL outbound `pipeline_run_id` from `post_import_binding.export_run_id` — never the
  post-import child's own `run_id` — via the same `v3_unit5_payload_identity`/`export_archive`
  join predicate (order_item, period, charge_id, payload_hash) that
  `067_v3_daily_completeness_snapshot.sql`'s own `_exports` CTE uses internally, so the workflow's
  zero/nonzero pre-check and DDL 067's own computation can never disagree. Fails closed
  (`fail_closed`) if the lookup doesn't resolve to exactly one distinct `pipeline_run_id`.
- **Gate strengthening** (step 4): added an `IF v_export_runs > 0` block to DDL 067 asserting the
  associated `export_file_manifest.delivery_status` is terminal (`ACKNOWLEDGED`/`PARTIAL_REJECT`/
  `REJECTED`) before allowing the (immutable, replay-refused) snapshot insert — defense in depth
  independent of the workflow-level gating, since DDL 067 was never deployed and this is a
  pre-deployment source revision, not a live-object replacement.
- **Persist→alert→raise routing** (step 5): both new dispatch call sites reuse the existing
  `run_bq_call` helper (dry-run → submit → poll → `write_run_log` on success, `fail_closed` on any
  failure), the same wrapper every other nightly CALL step already uses — no new alerting
  mechanism invented.
- `HUMAN_ACTION` residual (`pending_rows > 0`) path is unchanged: it still only alerts via the
  existing `fail_closed` call and does not attempt to snapshot an unresolved day.

Explicitly NOT done in this delta: seeding/calling anything, changing `delivery_enabled`, touching
steps 6–9 of the finding (recipient approval, Apps Script deployment, rehearsal, retention) — all
separate, later, human/Codex-gated work.

**DRY-RUN NOT OBTAINED — same persistent environment blocker as `RQ-20260810-1918`:**
`scripts/bq_safe_query.sh --dry-run-only -f sql/ddl/067_v3_daily_completeness_snapshot.sql` still
fails with `ReauthUnattendedError` (the `bq` CLI's legacy credential needs an interactive reauth
this session can't complete — see the still-open ask in `docs/HANDOFF_QUEUE.md`). The workflow YAML
was structurally validated instead: parsed cleanly with the system Python's PyYAML (14 top-level
keys, both new subworkflows present), and the two new `CALL ...('" + expr + "');` string
constructions were verified byte-for-byte against the file's own established pattern (e.g. line 369's
`sp_run_v3_units2_5` call) using `od -c` after two failed attempts at typing the escape sequence
directly introduced a real double-backslash bug — caught and fixed before this request was opened,
not left in the artifact. This structural/textual verification is not a substitute for the mandatory
BigQuery dry-run of the DDL 067 delta; **do not treat this as deploy-ready until that dry-run
actually runs clean.**

Review: the `_exports` join-predicate parity between the two new subworkflows and DDL 067's own CTE
(must never diverge), the fail-closed behavior of `derive_original_pipeline_run_id` on zero/multiple
matches, whether `HUMAN_ACTION`-residual days correctly remain un-snapshotted, the DDL 067 gate's
exact terminal-status set, and — separately — actually run the dry-run and report the result.

## RQ-20260810-1918-period-cutoff-calendar-source
Status: REVIEWED
Verdict: BLOCK — `docs/reviews/2026-08-11-a82409d-codex.md`
Reviewer: Codex (per `docs/AGENT_REVIEW_PROTOCOL.md` reciprocity)
Class: A
Artifact: `sql/ddl/075_v3_period_cutoff_calendar.sql` (new file, source only).
Opened: 2026-08-10T19:18:00+07:00

Claim: implements the exact "smallest safe implementation" from
`docs/FINDINGS_MONTHLY_CUTOFF_AUTOMATION_GAP_20260805.md` (already PASSed,
`docs/reviews/2026-08-06-9c61d17-claude.md` / `RQ-20260805-2202`): a new append-only
`sap_period_cutoff_calendar` table, `sp_register_period_cutoff` (insert-only, rejects
non-month-aligned periods, blank approver/source, a cutoff not later than period_start, and any
duplicate period_start — no UPDATE/correction path is built, per the finding's own gate that the
correction policy isn't yet confirmed with Finance), and `sp_transition_due_period_from_calendar`
(requires exactly one OPEN period with calendar/state `closing_at` equality, no-ops before the
cutoff, and only at/after cutoff resolves the next period's calendar row and delegates to the
already-reviewed `sp_close_open_period` from `053_v3_unit4_period_state_machine.sql`). Nothing in
this file seeds the calendar, registers a cutoff, calls the transition procedure, or wires it into
the nightly workflow — those are separate, later, Codex-executed mutations per SINGLE DEPLOYER.

**DRY-RUN NOT OBTAINED — real gap, not a formality skipped:** the mandatory
`scripts/bq_safe_query.sh --dry-run-only` failed with `ReauthUnattendedError` — the `bq` CLI's
legacy credential store requires an interactive reauthentication step this non-interactive session
cannot complete. `bash scripts/bq_safe_query.sh --self-test` passed (7/7, confirming the wrapper
script itself is healthy); the failure is purely environmental credential state, not a wrapper or
SQL defect signal. A crude local structural check (`BEGIN`/`END;` counts, 2/2, matching the two
procedure bodies) is not a substitute and is only mentioned for transparency. **Do not treat this
as deploy-ready or even review-complete until a real dry-run runs clean** — either Codex has a
working authenticated session, or this needs a fresh `bq`/`gcloud` interactive reauth first.
Review: table/procedure grain and column contract against the finding's exact spec, the
insert-only/no-correction-path decision, the before/at/after-cutoff branching and fail-closed
missing/mismatched-calendar assertions, delegation argument correctness to `sp_close_open_period`,
and — separately — actually run the dry-run and report the result before any deployment
conversation starts.

## RQ-20260810-1459-post-import-permission-narrowing
Status: REVIEWED
Verdict: BLOCK — `docs/reviews/2026-08-11-f0568d6-codex.md`
Reviewer: Codex (per `docs/AGENT_REVIEW_PROTOCOL.md` reciprocity — Codex reviews Claude Code's
investigations; this is a Claude-Code-authored live-permission investigation, not eligible for
Claude Code self-review).
Class: A
Artifact: `docs/INPUTS_NEEDED.md` (post-import activation section, 2026-08-10 addendum).
Opened: 2026-08-10T14:59:00+07:00

Claim: `data@rabbit.co.th` already holds sufficient permission for 2 of the 3 documented
post-import readiness blockers (authenticated Pub/Sub push subscription; watchdog Cloud Scheduler
job), and for redeploying the dispatcher/watchdog Cloud Run services under the new identity. Only
the dispatcher `run.invoker` IAM binding remains genuinely administrator-gated
(`run.services.setIamPolicy` absent and unable to be self-granted).
Evidence: live read-only Google Cloud `testIamPermissions` calls (no state mutation possible via
that API) — Cloud Run `services.testIamPermissions` on `sap-post-import-dispatcher` directly
returned only `run.services.getIamPolicy`/`run.services.update`/`run.services.delete`, not
`run.services.setIamPolicy`; Cloud Resource Manager `projects.testIamPermissions` returned
`cloudscheduler.jobs.create`/`.update`, `pubsub.subscriptions.create`/`.update`, but not
`pubsub.subscriptions.setIamPolicy`, `pubsub.topics.setIamPolicy`,
`resourcemanager.projects.setIamPolicy`, or `iam.roles.create`; IAM `serviceAccounts.testIamPermissions`
on the default Compute SA returned `iam.serviceAccounts.actAs`. Also compared against
`sap-extract-job`'s (legacy) IAM policy, which is empty — confirming the legacy Cloud Run Job
pattern (Scheduler OAuth, `run.jobs.run`-class permission) does not require or demonstrate the
Cloud Run Service `run.invoker` binding this dispatcher needs, since Jobs and Services use
different authorization paths. No IAM, deploy, GCS, scheduler, workflow, or SAP mutation occurred.
Review whether the permission set tested is complete (e.g., whether the push subscription also
needs any permission not tested), whether the conclusion "2 of 3 blockers can proceed now" is
safe to act on without further confirmation, and resolve or escalate the tension with
`DEFAULT_COMPUTE_SA_AUTOMATION_WORKAROUND.md`'s "no longer require...a Cloud Run service-level
run.invoker binding" claim before anyone treats that design doc as settling the question.

## RQ-20260810-1222-delivery-checker-identity-fix
Status: REVIEWED
Verdict: BLOCK — `docs/reviews/2026-08-11-0283605-codex.md`
Reviewer: Codex (per `docs/AGENT_REVIEW_PROTOCOL.md` reciprocity — Codex reviews Claude Code's
deployments/investigations; this is a Claude-Code-authored script fix, not eligible for Claude
Code self-review).
Class: A
Artifact: `scripts/check_v3_delivery_control_plane.ps1` (one-line normalization fix).
Opened: 2026-08-10T12:22:00+07:00

Claim: closes the REQUIRED NOTE from `RQ-20260806-2123` (`docs/reviews/2026-08-06-8e045ad-claude.md`).
The workflow-service-account normalization previously did `.Replace('projects/-/serviceAccounts/', '')`,
a literal wildcard-dash string the real `gcloud workflows describe` field never contains
(confirmed live shape: `projects/pacific-plating-282708/serviceAccounts/919786098205-compute@...`),
so it was a permanent no-op and the safety check could never pass. Replaced with
`-replace '^projects/[^/]+/serviceAccounts/', ''`, which strips the prefix for both project-ID and
project-number forms (consistent with the project-number handling already reviewed for DDL 072's
execution-name binding, `RQ-20260805-2058`). No other line in the file changed.
Evidence: PowerShell parser (`[System.Management.Automation.Language.Parser]::ParseFile`) passed
with zero errors; `git diff --check` passed (only a pre-existing LF/CRLF notice, no content
issue). Live read-only re-run at `2026-08-10T05:22:00.4886901+00:00` (`gcloud` account
`data@rabbit.co.th`, project `pacific-plating-282708`) shows `workflow_service_account:
919786098205-compute@developer.gserviceaccount.com` now equal to `default_service_account`, and
the previous `workflow does not use the approved default Compute service account` failure is
absent from `safety_failures`. `delivery_enabled` remains `false`; `control_plane_ready` remains
`false` only for the same pre-existing, unrelated reasons already tracked (missing two-name
delivery markers in this workflow revision, promoter/scheduler not yet deployed). No IAM, deploy,
GCS write, scheduler, workflow execution, BigQuery, Gmail, or SAP mutation occurred — this is a
read-only checker script fix plus a read-only verification run.

## RQ-20260806-2123-default-compute-sa-activation-workaround
Status: REVIEWED
Reviewer: Claude Code
Class: A
Artifact: commit `8e045ad`;
`docs/design/DEFAULT_COMPUTE_SA_AUTOMATION_WORKAROUND.md`;
`scripts/check_v3_delivery_control_plane.ps1`;
`scripts/check_post_import_activation.ps1`.
Opened: 2026-08-06T21:23:00+07:00
Verdict: PASS WITH REQUIRED NOTE — `docs/reviews/2026-08-06-8e045ad-claude.md`. Ran both checkers
live: confirmed the RQ-2149 fatal `gcloud workflows get-iam-policy` crash is genuinely gone (the
delivery checker now returns valid JSON). Found a new, real false-positive: the workflow-identity
comparison in the delivery checker can never pass, because its `.Replace('projects/-/serviceAccounts/',
'')` normalization targets a wildcard project segment that the real live field
(`projects/pacific-plating-282708/serviceAccounts/...`) never contains — confirmed via a direct
`gcloud workflows describe` read — so it always reports "workflow does not use the approved default
Compute service account" even though the workflow has used exactly that account all along. The
sibling post-import checker has no such bug (Cloud Run's service-account field is already a bare
email) and correctly reports the dispatcher/watchdog Cloud Run services still need redeploying
under the new identity. Confirmed no IAM/administrator mutation command exists anywhere in the
diff, public-principal rejection is unchanged, and `permission_rehearsal_required: true` is present
in both live outputs. Does not block this PASS; does block trusting the delivery checker's
workflow-identity result until fixed.

Claim: Boat explicitly closed the administrator-only activation path and directed reuse of the
project default Compute service account without adding IAM. The replacement records that binding
decision, marks the two dedicated-IAM runbooks SUPERSEDED/DO NOT RUN, checks the exact default-SA
identity and non-public Cloud Run boundary, and requires a fail-closed permission rehearsal before
activation. The delivery checker also removes the confirmed-fatal nonexistent
`gcloud workflows get-iam-policy` call.
Evidence: both PowerShell files parse with zero errors; `git diff --check` passed; repository search
found no stale dedicated runtime identity or nonexistent Workflows IAM call in either checker. No
IAM, deploy, scheduler, workflow execution, GCS, BigQuery, email, or SAP mutation occurred.
Review that no administrator/IAM mutation is implied by the replacement; all runtime/caller
identities match Boat's decision; public principals remain hard failures; removal of the old
dedicated-IAM readiness checks does not overclaim effective permission; the rehearsal requirement
fails closed; and the checker bug is actually removed. Source-only review—do not deploy.

## RQ-20260805-2207-numeric-alert-config-inputs
Status: REVIEWED
Reviewer: Claude Code
Class: A
Artifact: commit `81c7f9a`; canonical input/checklist clarification.
Opened: 2026-08-05T22:07:03+07:00
Verdict: PASS — `docs/reviews/2026-08-06-81c7f9a-claude.md` (confirmed DDL 066/068 seed no
threshold rows, confirmed no production numeric artifact exists anywhere in the repo, and
confirmed the "obsolete global >60" reference is a real legacy value still present in
`029_validation_regression_alert.sql`, not a strawman. Required input shape matches both table
schemas and existing onboarding language. No mutation.)

Claim: Boat's general approval of alert thresholds/config does not provide executable numeric rows.
Reviewed DDL 066/068 deliberately seed none, and repository search found no production
`max_record_increase`/`max_order_increase` values. The canonical input list now names the exact
status/check-level values and effective dates required without converting backlog, fixtures, or
the obsolete global `>60` into policy.
Evidence: full DDL 066/068 and repo-wide threshold-field search were inspected;
`git diff --check` passed. No live recheck was made under the GCP tool usage limit. No threshold,
history, config, DDL, schedule, alert, email, BigQuery, or SAP mutation occurred. Review that no
approved numeric artifact was missed, that the required input shape matches both table schemas and
new-check onboarding, that general approval is not overruled but correctly distinguished from
missing values, and that this belongs on the unattended completion checklist.

## RQ-20260805-2205-daily-completeness-runtime-gap
Status: REVIEWED
Reviewer: Claude Code
Class: A
Artifact: commit `b1e3508`, terminal-result ordering correction `a6bc76e`, offline dispatcher
contract tests `da301ee`;
`docs/FINDINGS_DAILY_COMPLETENESS_RUNTIME_GAP_20260805.md`.
Opened: 2026-08-05T22:05:17+07:00
Claim: Canonical live inventory and reviewed source prove the daily completeness snapshot/report
path is not operational: DDL 067 is source-only/not live, workflow/wrapper contain no snapshot
call, and the review-passed Apps Script has no deployment/properties/trigger or approved distinct
primary/fallback recipients. Exact DDL inspection shows a nonzero snapshot immediately after
delivery would immutably freeze `SAP_RESULT=PENDING_ACK`: healthy zero may snapshot after Units
2–5, but nonzero must wait for terminal DDL 073 reconciliation with no residual and bind back to
the original outbound pipeline run. It remains separate from post-import activation.
Evidence: `AS_BUILT_V3.md`, DDL README, DDL 067, workflow/wrapper zero-reference grep, reviewed
dispatcher source, deployment contract, and reviews `44ade18`/`d85aa20` were traced;
11 offline Node VM assertions passed for metric report construction, no recipient addresses in the
body, mail/status/fallback ordering, dual-channel failure, aggregate failure, and batch isolation;
Apps Script syntax and `git diff --check` passed. No live recheck was made under the local GCP
tool usage limit. No DDL,
CALL, Apps Script, OAuth, trigger, email, BigQuery, workflow, scheduler, GCS, or SAP mutation
occurred. Review inventory/source interpretation; DDL 067's manifest/SAP-result semantics;
healthy-zero vs terminal nonzero ordering; feasibility and exactness of original outbound
pipeline-run binding from the export identities; residual HUMAN_ACTION treatment; distinction
from post-import runtime; shared-vs-separate Apps Script packaging caveat; human input
completeness; rehearsal cases; and whether an existing live path already satisfies any claimed
gap.

Verdict: PASS — `docs/reviews/2026-08-06-a6bc76e-claude.md`. Claude independently confirmed DDL
067 has no caller and is not live, traced the irreversible early-snapshot hazard to the procedure's
immutable replay guard, and proved a post-import child run ID cannot substitute for the original
outbound pipeline ID. The corrected terminal ordering, HUMAN_ACTION failure treatment, separation
from post-import activation, and rehearsal matrix passed. Claude reran the real Apps Script source
in the Node VM: 11 assertions passed. No production mutation occurred.

## RQ-20260805-2202-monthly-cutoff-automation-gap
Status: REVIEWED
Reviewer: Claude Code
Class: A
Artifact: commit `9c61d17`;
`docs/FINDINGS_MONTHLY_CUTOFF_AUTOMATION_GAP_20260805.md`.
Opened: 2026-08-05T22:02:15+07:00
Claim: Reviewed repository source proves the nightly workflow/Units 2–5 wrapper never calls the
existing atomic period transition, and `sp_close_open_period` requires the adjacent month's
authoritative cutoff at call time. Thus the daily interface is not unattended across a month
boundary even though the current August cutoff is known. The finding proposes only the minimum
append-only calendar/register/transition/readiness design and explicitly does not draft or deploy
SQL without mandatory validation.
Evidence: exact source grep found the workflow call to `sp_run_v3_units2_5` and zero
`sp_close_open_period` references in either the workflow or wrapper; DDL 053's four-argument
procedure and current canonical July/August-only cutoff record were traced. `git diff --check`
passed. No live recheck or dry-run was possible under the local GCP tool usage limit, and no
table/procedure/calendar/workflow/scheduler/job/GCS/Gmail/SAP state changed. Review source-trace
completeness, distinction between current-month daily operation and cross-month automation,
cutoff ownership, no-inference/fail-closed conclusion, minimal design/ordering, checklist wording,
and whether any already-reviewed component actually closes this gap.

Verdict: PASS — `docs/reviews/2026-08-06-9c61d17-claude.md`. Claude independently expanded the
source search to the entire repository, confirmed `sp_close_open_period` has no caller, verified
the exact four-argument signature and recorded July/August cutoff values, and confirmed the
finding correctly scopes the gap to cross-month transition rather than ordinary within-month
daily operation. The no-inference/fail-closed conclusion and minimal append-only registry +
delegating transition design passed. No production or source mutation occurred in the review.

## RQ-20260805-2149-v3-delivery-control-plane-gate
Status: REVIEWED
Reviewer: Claude Code
Class: A
Artifact: commit `344e74d`, production metadata-read correction `2cfcffc`, trigger-IAM checker
delta `90e6fd5`;
`docs/design/V3_DELIVERY_CONTROL_PLANE.md`;
`scripts/check_v3_delivery_control_plane.ps1`.
Opened: 2026-08-05T21:49:30+07:00
Verdict: PASS WITH REQUIRED NOTE — `docs/reviews/2026-08-06-90e6fd5-claude.md`. Ran the checker
myself: it crashes on every invocation because `gcloud workflows get-iam-policy` (added in
`90e6fd5`) does not exist — confirmed via `gcloud workflows --help`. Every other gcloud call in
the script is individually valid. The runbook's own commands never grant a workflow-resource-level
IAM binding (only project-level, already covered by the script's separate, working
`$projectPolicy` check), so the fix is almost certainly to delete the `$workflowPolicy` fetch —
but that needs its own delta and re-review. The runbook itself (bucket-binding minimality,
custom-role scoping, create→pause→update race safety, nested execution-argument shape, rollback)
checked out against patterns already verified elsewhere this session. Does not block this PASS;
does block relying on the checker until fixed.

Claim: The source-only administrator runbook safely prepares, but does not activate, the exact
delivery control plane: a private promoter on a dedicated identity, conditional archive-read and
production-create/read bucket IAM, exact workflow invoker, narrow scheduler execution creator,
and a PAUSED 20:30 ICT trigger whose only argument is the exact promoter URL. The read-only checker
fails unless those bindings/configurations are exact while the workflow remains visibly
`delivery_enabled:false`.
Evidence: PowerShell parser passed with zero errors and `git diff --check` passed. The checker was
not run live because the local GCP tool account returned its usage limit; the artifact therefore
makes no live readiness claim. No deploy, IAM, scheduler, execution, GCS, Gmail, BigQuery, or SAP
mutation occurred. Review PowerShell 5.1 compatibility and strict-mode behavior; Cloud Run
service-account/ingress/env/IAM JSON shapes; conditional bucket-policy expression matching and
whether archive Viewer plus production Creator/Viewer are minimally sufficient for source read,
create-only rewrite, and destination metadata reload; custom-role list/project+workflow policy
JSON shapes, exact execution-create permission and conditional binding, broader Invoker rejection;
Scheduler executions endpoint, OAuth identity,
base64 body decoding and nested `argument` JSON; create→pause→update race safety; exact workflow
service-account normalization; false-positive/false-negative readiness paths; production gates
and rollback; and that no command in the machine checker mutates state.

## RQ-20260805-2136-two-name-delivery-result-contract
Status: REVIEWED
Reviewer: Claude Code
Class: A
Artifact: commit `30bd693`, executable policy test `fa949ee`, rehearsal-fixture delta `9081445`,
Apps Script local contract tests `7647118` and ordering delta `9692f85`; DDL 070/062/074, delivery
workflow/promoter, Apps Script contract/comment, tests, and evidence/progress docs. Packaging
helper `a36f5f5` and BOM-safe delta `fc037f3` are included for the exact source/manifest staging
boundary.
Opened: 2026-08-05T21:36:38+07:00
Verdict: PASS — `docs/reviews/2026-08-05-fc037f3-claude.md`. Independently ran every test suite
myself rather than trusting descriptions: promoter Python tests (3/3, including an explicit
assertion the response never contains `sap_file_name`), the executable SQL policy test against
real LogID 21183 values (7/7 asserts, 0 bytes), DDL 070/062/074 and the rehearsal-verifier dry-runs
(0 bytes each), and the Node VM Apps Script contract suite (18/18 assertions, including a direct
regression test that manifest matching keys on the SAP-reported name, not the production
basename). Also actually executed the packaging helper end-to-end against a real temp directory:
confirmed byte-for-byte the staged `.clasp.json` has no UTF-8 BOM, and triggered both safety guards
live (path-containment and non-overwrite each threw exactly as claimed). Traced the workflow's
name-derivation timing and confirmed DDL 062's argument order matches the workflow's call
positionally. `delivery_enabled: false` unchanged throughout.

Claim: The source-only delta closes the confirmed one-name binding gap by atomically persisting
both the exact `INSURANCE_RCB_...csv` production basename and the distinct
`RCB_MOTOR_<production basename>` SAP-result name. The workflow derives them only after
exactly-one immutable archive-object census; the promoter copies by production name; Apps Script
continues exact-matching the SAP-result name; a static scheduler no longer supplies a dynamic
shard-bearing filename.
Evidence: DDL 070 and 062 mandatory wrapper dry-runs passed at 0 bytes; workflow YAML parsed with
Cloud SDK's bundled ruamel; Apps Script syntax passed through Node stdin; promoter Python compile
and three unit tests passed. Zero-byte job `bqjob_raebafbf0173312f_0000019fd25c5c37_1` passed
seven exact LogID 21183 policy assertions, including rejection of both swapped name roles;
the updated DDL 074 fixture and rehearsal verifier each passed the mandatory wrapper dry-run at
0 bytes and now assert both names while remaining compatible with the not-yet-migrated live
schema; the Node VM test passed 14 assertions covering the exact LogID 21183 email/sender, result
name match, production-name non-match, TXT parsing, and ambiguous-manifest refusal, then the delta
passed 18 assertions including persist→publish→label order, zero-manifest no-label, and ambiguity
failure/alert without persistence or labeling; Apps Script syntax and manifest JSON parsing
passed; `git diff --check` passed. Review DDL 070 migration/nullability and
deployment order, DDL 062 signature/parameter order/replay guards/atomic insert, closed filename
policy, workflow zero/one/many object branches and safe SQL construction, promoter API contract
and exact-generation behavior, DDL 074 clean-environment/live-migration compatibility, Apps Script
lookup compatibility, and the packaging helper's PowerShell 5.1 path containment/non-overwrite/
closed-scope behavior. The helper parser and manifest checks passed, but its temporary-directory
execution was unavailable due to the local tool usage limit and must not be treated as tested.
Review rollback, and that
`delivery_enabled:false` remains unchanged with no deployment/CALL/GCS/Gmail/SAP action.

## RQ-20260805-2129-log21183-two-name-binding-gap
Status: REVIEWED
Reviewer: Claude Code
Class: A
Artifact: commit `9e7724c`; `docs/FINDINGS_LOG21183_FILENAME_BINDING_GAP_20260805.md`;
`sql/adhoc/20260805_verify_log21183_filename_binding.sql`.
Opened: 2026-08-05T21:29:56+07:00
Verdict: PASS — `docs/reviews/2026-08-05-9e7724c-claude.md` (independently reran the query and
reproduced 558 archive identities, 3,857 manifest payload rows, the exact production basename,
and both false email-name comparisons; confirmed the historical no-new-table caveat; traced the
actual pre-fix DDL 062 single-name assertion/insert and Apps Script exact SAP-result-name lookup;
confirmed the gap is structural and correctly scoped).
Claim: Live LogID 21183 evidence proves the production basename (`INSURANCE_RCB_...csv`) differs
from SAP's reported name (`RCB_MOTOR_INSURANCE_RCB_...csv`). Current DDL 062 stores the former as
`sap_file_name`, while Apps Script exact-matches the latter; this structurally blocks automatic
manifest/result binding and a static scheduler also cannot provide the dynamic shard-bearing name.
Evidence: mandatory wrapper dry-run estimated 308,583 bytes; read-only job
`bqjob_r11d028b8cfd54f2e_0000019fd251056f_1` returned the retained production URI/basename for 558
event identities and 3,857 payload rows, both exact-name comparisons false. Review query
partitioning/results, historical no-new-manifest caveat, DDL 062/workflow/promoter/Apps Script
trace, conclusion scope, two-name correction direction, and absence of mutation.

## RQ-20260805-2120-daily-automation-completion-checklist
Status: REVIEWED
Reviewer: Claude Code
Class: A
Artifact: commits `09abd59`, timestamp correction `dc00024`, live-path safety delta `fe02a0c`;
`docs/design/DAILY_AUTOMATION_COMPLETION_CHECKLIST.md` and rehearsal section in
`docs/design/POST_IMPORT_AUTOMATION_DEPLOYMENT.md`.
Opened: 2026-08-05T21:20:50+07:00
Verdict: PASS — `docs/reviews/2026-08-05-fe02a0c-claude.md` (every checked/unchecked state
independently cross-checked against this session's own live verification, including confirming
DDL 073 live just now; dependency order and five-day acceptance bar are sound; grepped the
workflow YAML and confirmed post_import_mode gates only the self-bind step — the real extract/
bronze-load/mirror-refresh path is never skipped, proving the delta's core safety disclosure true
rather than boilerplate; no contradictory "done" claims found.)

Claim: The checklist accurately separates the live inert post-import foundation from remaining
human/IAM/Apps Script inputs, synthetic rehearsal, post-import activation, and the separate
outbound delivery/recurring-trigger cutover. It does not label the delivery-disabled unscheduled
workflow as fully automatic and requires five unattended business days for goal acceptance.
Evidence: live foundation and blockers are tied to the two just-PASSed deployment reviews and the
activation checker; cutoff dates and insurer disposition reference current canonical evidence.
Review every checked/unchecked state, dependency order, rollback safety, five-day acceptance,
absence of contradictory “done” claims, and that this documentation performs no mutation. The
delta must accurately disclose that post-import mode still performs the real SAP extract/bronze
load/mirror read path, require a non-overlap window, and serialize the three terminal cases except
for deliberate duplicate redelivery.

## RQ-20260805-2118-insurer-code-live-disposition
Status: REVIEWED
Reviewer: Claude Code
Class: A
Artifact: commit `bb490e8`; `docs/FINDINGS_INSURER_CODES_30_46_48_49_20260805.md`;
`sql/adhoc/20260805_verify_insurer_codes_30_46_48_49.sql`.
Opened: 2026-08-05T21:18:23+07:00
Verdict: PASS — `docs/reviews/2026-08-05-bb490e8-claude.md` (verified the normalization/source/
acceptance predicate is line-for-line identical to DDL 032's own E3 master-seeding MERGE, not
just similar to it; independently re-ran the exact query — identical zero-result for all four
codes; conclusion honestly scoped to the documented evidence source only.)

Claim: The documented E3 accepted-source rule cannot confirm insurer codes 30, 46, 48, or 49:
each has zero positive-DocEntry `SAP_LIVE_FULL` rows and zero `sap_insurer_master` rows, so their
current `INSURER_NOT_IN_MASTER` holds must remain unless a different source or explicit mapping is
provided.
Evidence: mandatory wrapper dry-run estimated 7,240,991,840 bytes; cost-capped read-only job
`bqjob_r2f4166e07184b869_0000019fd2488a6e_1` returned one zero/false result for each code. Review
normalization parity with DDL 032/E3, target completeness, join/aggregate accuracy, job/result
traceability, conclusion scope, and absence of master/hold/export/workflow/GCS/SAP mutation.

## RQ-20260805-2113-post-import-human-inputs
Status: REVIEWED
Reviewer: Claude Code
Class: B
Artifact: commit `bb2e957`; `docs/INPUTS_NEEDED.md`.
Opened: 2026-08-05T21:13:24+07:00
Verdict: PASS — `docs/reviews/2026-08-05-bb2e957-claude.md` (exact identities/table
scope and the live three blockers matched independent evidence; residual permission risk and
authorized-routine alternative are honestly stated; link resolves and no new authority is
implied).
Claim: The canonical human-input list now states the exact residual permission decision Boat must
make and the administrator-owned GCP actions required before rehearsal readiness, without implying
that broad project approval authorizes direct outbox DML or that the current account can perform
the IAM changes.
Evidence: content references the already reviewed administrator-completion runbook and the live
activation checker's exact three blockers. Review documentation accuracy, service-account/table
scope, honest residual-risk wording, authorized-routine alternative, and absence of new authority
or executable mutation.

## RQ-20260805-2112-machine-failing-rehearsal-verifier
Status: REVIEWED
Reviewer: Claude Code
Class: A
Artifact: commit `4b446c4`; `scripts/check_post_import_rehearsal.ps1`;
`sql/adhoc/20260805_verify_post_import_rehearsal.sql`.
Opened: 2026-08-05T21:12:06+07:00
Verdict: PASS — `docs/reviews/2026-08-05-4b446c4-claude.md` (verified activation
gates, exact nonce substitution, temporary-file cleanup, wrapper-only BigQuery access, and
`COUNT(*)=3` plus three `IS TRUE` assertions; independently reproduced the expected live
readiness refusal and 0-byte dry-run).
Claim: Rehearsal result verification now fails unless activation is safe and ready, the exact
nonce yields exactly ACK/REJECT/RESIDUAL, and all three expected final-state predicates are TRUE.
Nonce substitution exists only in a temporary query that is deleted in `finally`; every BigQuery
read uses the mandatory safety wrapper.
Evidence: query dry-run passed at 0 bytes, PowerShell parser passed, and a live read-only negative
test refused before creating/running the result query because the known three readiness blockers
remain. Review PowerShell exit-code/error behavior, temporary-path conversion and cleanup,
token-count/substitution safety, activation JSON handling, SQL cardinality/three-valued-logic
assertions, wrapper enforcement, and absence of production mutation/workflow/GCS/SAP action.

## RQ-20260805-2107-canonical-execution-binding-deployment
Status: REVIEWED
Reviewer: Claude Code
Class: A
Artifact: commit `0e44aec`; live DDL 072 procedures and workflow revision `000009-e96`.
Opened: 2026-08-05T21:07:39+07:00
Verdict: PASS — `docs/reviews/2026-08-05-0e44aec-claude.md` (all four live DDL 072
procedure bodies matched the reviewed source; workflow revision/source/service account and
project-number construction matched, delivery remained disabled, no new execution existed, and
an independent activation-check run returned safety PASS with the same three readiness blockers).
Claim: The review-passed canonical execution-name correction is live: DDL 072 replacement job
`bqjob_r44f87f4cfafffe4b_0000019fd23dd027_1` completed, and workflow revision `000009-e96` is
ACTIVE with the prior service account, `GOOGLE_CLOUD_PROJECT_NUMBER`, no old project-ID
construction, and `delivery_enabled: false`. Deployment did not start an execution.
Evidence: mandatory DDL wrapper dry-run passed at 0 bytes; real job replaced only the four DDL 072
procedures and skipped the existing table. Read-only workflow describe and execution inventory
verified the claim. The reviewed activation checker at `2026-08-05T14:06:08.2249628Z` returned
`safety_passed=true`, `rehearsal_ready=false`, with the same three expected blockers. Review exact
live procedure regex, workflow revision/source/service account, execution inventory, safety
result, and absence of Gmail publication, workflow execution, delivery, GCS write, or SAP action.

## RQ-20260805-2103-ddl074-inert-deployment
Status: REVIEWED
Reviewer: Claude Code
Class: A
Artifact: commit `97ebcf6`; live routine
`sap_integration_v3.sp_seed_post_import_rehearsal_fixtures`.
Opened: 2026-08-05T21:03:24+07:00
Verdict: PASS — `docs/reviews/2026-08-05-97ebcf6-claude.md` (live routine body was
byte-for-byte identical to the reviewed 8,586-character source body with exactly one STRING
`p_nonce`; deployment job was SUCCESS at 0 processed/billed bytes; a targeted live check found
zero synthetic-shaped outbox rows, independently confirming the procedure was not called).
Claim: The review-passed DDL 074 procedure is live but was not called. Its deployment only created
the synthetic rehearsal seeder; no fixture rows, GCS objects, workflow execution, delivery, or SAP
action were produced.
Evidence: mandatory wrapper dry-run passed at 0 bytes; deployment job
`bqjob_r2732ec7e5e42097_0000019fd23b665a_1` completed. Read-only `bq show --routine` confirmed one
STRING `p_nonce` argument and the reviewed SQL body. Review live/source identity, job evidence,
the procedure-not-called boundary, and documentation accuracy.

## RQ-20260805-2058-canonical-workflow-execution-name
Status: REVIEWED
Reviewer: Claude Code
Class: A
Artifact: commit `65ebde3`; `sql/ddl/072_v3_post_import_refresh_dispatch.sql`;
`infra/v3_nightly_orchestrator.workflows.yaml`.
Opened: 2026-08-05T20:58:24+07:00
Verdict: PASS, critical finding resolved — `docs/reviews/2026-08-05-65ebde3-claude.md` (confirmed
the workflow now self-constructs its execution name via the unambiguous `GOOGLE_CLOUD_PROJECT_NUMBER`
variable; independently tested the widened regex against 5 live BigQuery cases — real project
number matches, real project ID still matches, a too-short numeric, a too-long numeric, and an
empty segment are all correctly rejected. Confirmed this is now consistent with the admin runbook's
IAM condition prefix. Independently re-ran the dry-run: 0 bytes. This closes the critical blocker
from RQ-20260805-2044 — the admin runbook and synthetic rehearsal may proceed as far as this
specific issue is concerned.)

Claim: The corrective delta builds the canonical Workflows execution resource with
`GOOGLE_CLOUD_PROJECT_NUMBER` and makes DDL 072 accept either a valid project ID or a 6–20 digit
project number in the resource-name project segment. This closes the production self-bind failure
without weakening the workflow/location/name/execution structure or changing delivery state.
Evidence: current official Workflows built-in environment-variable documentation distinguishes
`GOOGLE_CLOUD_PROJECT_ID` from `GOOGLE_CLOUD_PROJECT_NUMBER`; a live execution resource already
captured in the administrator-runbook review uses project number `919786098205`. Mandatory wrapper
dry-run of corrected DDL 072 passed at 0 bytes; `git diff --check` passed. Review exact canonical
construction, regex acceptance/rejection boundaries, compatibility with the administrator
runbook's execution-scoped IAM condition, and that neither DDL nor workflow was deployed or
executed by this corrective source commit.

## RQ-20260805-2055-post-import-rehearsal-verifier
Status: REVIEWED
Reviewer: Claude Code
Class: A
Artifact: commits `89e6b0a`, `54ae892`;
`sql/adhoc/20260805_verify_post_import_rehearsal.sql`.
Opened: 2026-08-05T20:55:14+07:00
Verdict: PASS — `docs/reviews/2026-08-05-54ae892-claude.md` (confirmed identifier construction is
byte-for-byte identical to DDL 074's own; traced the three-valued-logic `AND` chain proving a
missing or partial rehearsal state can only surface as NULL or FALSE, never TRUE; verified the
exact ACK/REJECT/RESIDUAL `sap_result_status`/`acknowledged_at` expectations line-by-line against
DDL 073's real UPDATE logic; confirmed `export_file_manifest` has no partition column so its
missing date filter isn't a gap. Independently re-ran the dry-run: 0 bytes; combined diff across
both commits is whitespace-clean.)

Claim: The read-only verifier binds one explicit 14-digit rehearsal nonce and returns the exact
outbox, row-reconciliation, archive, and two manifest outcomes for the three DDL 074 cases,
including ACK timestamp/null semantics and the expected residual fail-closed state. It contains no
mutation, procedure call, GCS operation, workflow execution, delivery, or SAP action.
Evidence: mandatory wrapper dry-run passed at 0 bytes and `git diff --check` passed. Review the
identifier derivation against reviewed DDL 074, partition bounds, join grain and duplicate risk,
NULL behavior of `expected_final_state`, exact ACK/REJECT/RESIDUAL expectations, and whether any
missing ledger row can be mistaken for success.

## RQ-20260805-2051-post-import-rehearsal-fixtures
Status: REVIEWED
Reviewer: Claude Code
Class: A
Artifact: commit `3242a85`; `sql/ddl/074_post_import_rehearsal_fixtures.sql`.
Opened: 2026-08-05T20:51:30+07:00
Verdict: PASS — `docs/reviews/2026-08-05-3242a85-claude.md` (verified all six target tables'
column lists column-for-column against live BigQuery schema; diffed the nonce/log_id/export_run_id/
sap_file_name guard regexes character-for-character against the real dispatcher's own validation
patterns; traced that ACK/REJECT sharing one mirror identity but different log_ids is a valid,
non-cross-contaminating test of DDL 073's error precedence; confirmed the RESIDUAL identity cannot
exist in real mirror data; confirmed no DELETE/GCS-write/CALL anywhere in the file. Independently
re-ran the dry-run: 0 bytes.)

Claim: The source-only procedure atomically seeds exactly three retained, nonce-isolated
post-import cases across archive/file manifest/SAP manifest/header/error/outbox ledgers. ACK uses a
current exact mirror tuple; REJECT uses the same match shape plus one exact row error to prove error
precedence; RESIDUAL cannot match mirror/error evidence and must become PENDING_ACK/HUMAN_ACTION.
All URIs are non-production shadow evidence, identifiers satisfy dispatcher validation, nonce reuse
fails closed, and the source cannot write GCS, publish, execute a workflow, deliver a file, or call
SAP. No cleanup/delete path is provided.
Evidence: mandatory wrapper dry-run passed at 0 bytes after the outbox seed was moved into the same
transaction as all fixture ledgers. `git diff --check` passed. Review exact live column contracts,
transaction/row-count conservation, nonce and dispatcher-shape guards, mirror seed stability,
error precedence, residual non-match guarantee, shadow URI/no-object boundary, retained-evidence
behavior, outbox initial state, expected-result claims, and that the source was not deployed or
called.

## RQ-20260805-2044-post-import-admin-completion
Status: REVIEWED
Reviewer: Claude Code
Class: A
Artifact: commit `fc048d9`; `docs/design/POST_IMPORT_ADMIN_COMPLETION.md`.
Opened: 2026-08-05T20:44:59+07:00
Verdict: PASS ON THIS ARTIFACT, WITH A CRITICAL CROSS-ARTIFACT BLOCKER —
`docs/reviews/2026-08-05-fc048d9-claude.md`. The runbook itself is correct and internally
consistent with every other reviewed artifact (IAM condition scoping, Pub/Sub/service-agent
grants, push endpoint/audience, DLQ forwarding, scheduler create-pause-update sequencing, checker
field-for-field compatibility) — do not run it yet. **CRITICAL FINDING**: this runbook's IAM
condition correctly uses the project *number* (`919786098205`), matching the real Workflows
execution resource name I pulled live via `gcloud workflows executions describe ... --format=
"value(name)"` (`projects/919786098205/locations/.../executions/...`). But DDL 072's
`sp_bind_v3_post_import_execution` (already reviewed PASS in RQ-20260805-1928) asserts
`REGEXP_CONTAINS(p_workflow_execution_name, r'^projects/[a-z][a-z0-9-]{4,28}...')` — requiring the
project segment to start with a lowercase letter, which a numeric project number never does. Since
`sys.get_env("GOOGLE_CLOUD_PROJECT_ID")` in GCP Workflows is documented to return the project
*number* (not the ID string, despite the name), every real self-bind call would very likely fail
this assertion, breaking the entire post-import pipeline end to end even though every individual
component passed review. Requires urgent resolution (regex fix or documentation/rehearsal
confirmation) via a new Class-A delta against DDL 072 before this runbook is run or any rehearsal
proceeds.

Claim: The source-only administrator handoff completes only the reviewed IAM/resource plan without
activating Gmail publication or delivery. It uses separate custom create-only and get/cancel-only
Workflows roles restricted to the one workflow, exact Cloud Run/PubSub/service-account bindings,
an authenticated five-attempt/600-second push subscription with retained DLQ, and creates the
watchdog scheduler on a dormant leap-day schedule before pausing and updating it to the configured
two-minute cadence. Dataset-wide or predefined Workflows Invoker grants are prohibited. The exact
outbox-table Data Editor block is isolated behind Boat's explicit informed approval.
Evidence: local gcloud help verified the Scheduler body/header/update flags, Pub/Sub auth/DLQ/ACK
flags, and Cloud Run Job IAM command. `git diff --check` passed. Review PowerShell quoting and
failure boundaries, custom permission/condition correctness, BigQuery routine/table roles, Pub/Sub
service-agent grants, push endpoint/audience, DLQ forwarding, scheduler OAuth endpoint/body and
pause-before-cadence behavior, checker compatibility, and that this artifact itself performs no
IAM/resource mutation.

## RQ-20260805-2035-post-import-activation-check
Status: REVIEWED
Reviewer: Claude Code
Class: A
Artifact: commit `228aeb1`, required-note delta `aae4e01`;
`scripts/check_post_import_activation.ps1` and evidence notes.
Opened: 2026-08-05T20:35:57+07:00
Verdict: PASS, note resolved — `docs/reviews/2026-08-05-aae4e01-claude.md` (confirmed the delta
validates the push subscription's actual topic/endpoint/OIDC identity/audience/DLQ/ack-deadline
rather than just its name, and separately fixes a same-class bug the base review missed: the
`run.invoker` check previously matched membership in *any* IAM binding rather than that specific
role. Also adds `allAuthenticatedUsers` rejection and full watchdog-scheduler config validation.
Independently re-ran the corrected script live — identical safety/readiness results.)

Base review PASS WITH REQUIRED NOTE — `docs/reviews/2026-08-05-228aeb1-claude.md` (confirmed
read-only, fails visibly on gcloud errors, safety/readiness distinction is sound, and independently
re-ran the script myself: identical `safety_passed=true`/`rehearsal_ready=false`/same three
blockers. Required fix: the push-subscription readiness check verified only the subscription's
name, not its actual `pushConfig.pushEndpoint`/OIDC binding — a false-positive risk on that one
readiness item, though the mandatory synthetic rehearsal would still catch it.)

Claim: The checker is read-only, fails visibly on gcloud errors, verifies the deployed
delivery-disabled workflow/private dispatcher/bounded watchdog/topic foundation, and distinguishes
safety failures from missing rehearsal-readiness resources. It cannot execute a workflow/job,
create or change IAM, create a subscription/scheduler, publish a message, write GCS, or call SAP.
Evidence: PowerShell parse passed. A live run at `2026-08-05T13:35:12.7814693Z` returned
`safety_passed=true`, `rehearsal_ready=false`, and exactly the three known blockers (dispatcher
invoker, authenticated push subscription, watchdog scheduler). Review command construction,
missing-property handling, safety assertions, false-positive/false-negative risk, absence of
mutating commands, and that the reported live state matches the independent deployment review.

## RQ-20260805-2031-post-import-inert-runtime-deployment
Status: REVIEWED
Reviewer: Claude Code
Class: A
Artifact: commit `8fa1cfd`; live deployment evidence in
`docs/design/POST_IMPORT_AUTOMATION_DEPLOYMENT.md`, `docs/AS_BUILT_V3.md`, progress, and changelog.
Opened: 2026-08-05T20:31:52+07:00
Verdict: PASS — `docs/reviews/2026-08-05-8fa1cfd-claude.md` (independently reproduced every
concrete claim against live GCP/BigQuery state: exact dispatcher revision with an empty IAM
policy, watchdog Ready/0-executions/exact env-var timeouts, exactly two topics and one
DLQ-attached subscription with 14-day retention and no expiration, zero project-IAM bindings for
all three new service accounts, and the 900s/315.4s/2.85x timeout arithmetic matched to the
decimal against the five most recent live workflow-execution wall-clock durations I pulled
myself. No mutation, IAM change, or production action performed in this review.)

Claim: The reviewed dispatcher and watchdog were deployed fail-closed and remain unable to receive
or process production events. The dispatcher is private/internal with no invoker; the watchdog is
unscheduled, unexecuted, single-task, zero-retry, and explicitly configured. Only inert input/DLQ
topics and a retained DLQ subscription exist. IAM denials and the rejected direct-outbox grant are
recorded without substituting broader roles, while Gmail publication, push subscription, scheduler,
workflow execution, GCS delivery, and SAP action remain absent.
Evidence: live `gcloud run services describe/get-iam-policy`, `run jobs describe`, and Pub/Sub
list output captured revision `sap-post-import-dispatcher-00001-qd4`, empty dispatcher IAM policy,
Ready watchdog configuration, two topics, and only the DLQ evidence subscription. Review the live
resource claims, timeout calculation, no-trigger/no-execution boundary, IAM failure accuracy,
least-privilege stop, exact remaining administrator actions, and that no source deploy beyond the
already-PASS artifacts occurred.

## RQ-20260805-1956-post-import-activation-rehearsal
Status: REVIEWED
Reviewer: Claude Code
Class: A
Artifact: commit `8b1f2bb`; live inventory/diagnosis evidence `4ed5dd6`, `43bbed3`;
`docs/design/POST_IMPORT_AUTOMATION_DEPLOYMENT.md`.
Opened: 2026-08-05T19:55:00+07:00
Verdict: PASS — `docs/reviews/2026-08-05-8b1f2bb-claude.md` (verified the six-step order matches
what was actually reviewed this session, all three identities are least-privilege per the real
READMEs, the ten rehearsal cases map onto already-reviewed behavior rather than invented
properties, and rollback/evidence-retention rules hold. Independently re-ran the balance-gate
diagnosis query — confirmed 559 identities/1 held/558 matched/0 remaining mismatches and the
~52-54s failure-to-fix gap — and ran live read-only `gcloud` inventory myself: workflow ACTIVE,
`sap-extract-schedule` and the legacy 01:00 loader both ENABLED, alert topic present, no
post-import Cloud Run service or Pub/Sub topic exists yet. `git diff --check` clean on all three
commits.)

Claim: The activation plan preserves dependency/review order, uses three dedicated least-privilege
identities, requires measured timeout/delivery configuration, proves ten synthetic cases before
enabling the Gmail publisher, and gives a configuration-first rollback that retains evidence.
Evidence: `git diff --check` passed. Read-only GCP inventory found the V3 workflow ACTIVE but
unscheduled, latest execution failed closed at the receipt-balance gate, alert topic present, and
post-import runtime resources absent. A bounded query proved that execution preceded the live
balance-procedure replacement by 52 seconds and now conserves 559 = 558 delivered + 1 held with
zero target mismatches; fresh rehearsal remains required. Review IAM separation, no default service account, resource
ordering, dead-letter handling, synthetic isolation/no production replay, alert receipt proof,
activation order, rollback boundary, and that this artifact performs no deploy or mutation.

## RQ-20260805-1950-post-import-watchdog
Status: REVIEWED
Reviewer: Claude Code
Class: A
Artifact: commits `f6d7151`, concurrency deltas `cdb5843`, `8fbbb93`, tests `fd56e28`;
`infra/post_import_watchdog/` and Workflows client dependency bump.
Opened: 2026-08-05T19:49:00+07:00
Verdict: PASS — `docs/reviews/2026-08-05-8fbbb93-claude.md` (verified required bounded
configuration, candidate and attempt boundaries, cancel-then-poll ordering, benign concurrent
completion handling, TIMEOUT versus HUMAN_ACTION classification, minimal alert payload,
least-privilege contract, bounded result set, four independently rerun unit tests, and no
production mutation during review).
Claim: The source-only scheduled job uses required configured thresholds, releases stale CLAIMED
rows for DDL 072's bounded retry, and reconciles STARTED rows with the actual Workflows execution
state. It never records timeout while an execution remains ACTIVE/QUEUED: it cancels, polls to a
non-running state, then completes `TIMEOUT`. Other terminal-without-completion states become
`HUMAN_ACTION`; exhausted and terminal actions publish minimal human-alert metadata.
Evidence: `python -m py_compile infra/post_import_watchdog/main.py`, pinned-dependency import smoke,
official seven-state enum inspection, four watchdog unit tests, and `git diff --check` passed.
Review candidate selection/age handling, threshold validation, release attempt boundary, Workflows
state mapping, cancel-and-poll ordering, terminal completion race behavior, alert payload/IAM,
bounded result set, and that no job, scheduler, IAM, workflow cancellation, alert, procedure CALL,
or BigQuery mutation occurred.

## RQ-20260805-1946-post-import-row-conservation
Status: REVIEWED
Reviewer: Claude Code
Class: A
Artifact: commits `ddfbcbd`, `823c322`; DDL 073 and post-import reconciliation delta in
`infra/v3_nightly_orchestrator.workflows.yaml`. Binding-output dependency: `47a4e07`.
Opened: 2026-08-05T19:46:00+07:00
Verdict: PASS — `docs/reviews/2026-08-05-823c322-claude.md` (verified exact header/outbox/manifest
binding, child Unit-1 proof, archive and three-ledger row conservation, exact-error precedence,
mirror tuple/status, idempotent rerun, atomic writes, workflow positional decoding, residual
HUMAN_ACTION/alert path, live dependency columns, and independent 0-byte dry-run).
Claim: After the independently completed child Unit 1, every exact delivered archive identity is
classified once as refreshed-mirror `ACKNOWLEDGED`, exact row-detail `REJECTED_BY_SAP`, or
`PENDING_ACK`. The archive and both manifest ledgers change atomically; the three outcomes conserve
to the delivered row count. Zero residual completes the outbox `SUCCEEDED`; any residual completes
`HUMAN_ACTION`, publishes the existing human alert, and fails closed.
Evidence: DDL 073 mandatory dry-run passed at 0 bytes; the full workflow YAML parsed structurally
with all expected subworkflows; and `git diff --check` passed. Review exact
LogID/export/filename/header/outbox binding, child `UNIT1_COMPLETE` proof, archive key and manifest
row conservation, exact error precedence, mirror match tuple/status, idempotent rerun behavior,
atomic ledger transitions, workflow result decoding, residual alert path, and that no GCS,
delivery, workflow execution, SAP action, deployment, or procedure CALL occurred.

## RQ-20260805-1939-post-import-unit1-dispatcher
Status: REVIEWED
Reviewer: Claude Code
Class: A
Artifact: commit `ec64deb`, tests `fd56e28`; `infra/post_import_dispatcher/` and post-import deltas in
`infra/v3_nightly_orchestrator.workflows.yaml`.
Opened: 2026-08-05T19:39:00+07:00
Verdict: PASS — `docs/reviews/2026-08-05-ec64deb-claude.md` (verified strict event validation,
deterministic exact-key token, admitted statuses, duplicate/no-op behavior, definite-versus-
ambiguous create failure handling, least-privilege boundary, server-assigned self-bind before
side effects, duplicate-loser exit, Unit-1-only stop, and no runtime action).
Claim: The private source-only Pub/Sub dispatcher validates minimal result metadata, atomically
claims the exact outbox binding, and creates a Unit-1 execution carrying only LogID/claim token.
The workflow binds its server-assigned full execution name before any side effect; duplicate
losers exit, winners persist `SUCCEEDED` after Unit 1, and the post-import path cannot enter Units
2–5 or delivery.
Evidence: `python -m py_compile infra/post_import_dispatcher/main.py`, pinned-dependency import
smoke, five dispatcher unit tests, and `git diff --check` passed; DDL 072
dependency re-dry-run passed at 0 bytes and the full workflow YAML parsed structurally. Review
Pub/Sub envelope/event validation,
token determinism, admitted status handling, claim/retry behavior, definite-vs-ambiguous execution
create failure handling, IAM/configuration boundary, server-assigned-name self-bind, duplicate
no-op, Unit-1-only stop, and success completion. No service, workflow, topic, subscription, IAM,
trigger, execution, GCS write, delivery, ACK, or SAP action is requested.

## RQ-20260805-1928-post-import-dispatch-transitions
Status: REVIEWED
Reviewer: Claude Code
Class: A
Artifact: commits `afefd67` + corrective deltas `785f62e`, `cbdf430`, `47a4e07`;
`sql/ddl/072_v3_post_import_refresh_dispatch.sql`.
Opened: 2026-08-05T19:28:16+07:00
Verdict: PASS — `docs/reviews/2026-08-05-47a4e07-claude.md` (verified exact-key/token/execution
uniqueness, full duplicate claim/bind race, bounded release at attempt three, terminal/error
rules, transaction row-count guards, both corrective deltas, and independent 0-byte dry-run).
Claim: Source-only procedures atomically claim one exact outbox row by deterministic token, bind
the Workflows API's subsequently returned complete execution resource name, release a failed
create for bounded retry, and permit completion only from STARTED into `SUCCEEDED`, `TIMEOUT`, or
`HUMAN_ACTION`. Duplicate claims/binds are idempotent only for the same binding and attempts stop
at three. When duplicate server-assigned executions race, bind returns the already winning
execution name so a losing workflow can exit before Unit 1 instead of raising or repeating work.
Evidence: Corrected complete DDL passed the mandatory dry-run at 0 bytes. Review exact-key,
claim-token and execution-name uniqueness; concurrent/duplicate claim and bind behavior; release
and attempt-three boundary; terminal transition/error-template rules; transaction row-count
guards; and that no workflow, topic, delivery, ACK, or SAP action occurs. The delta corrects the
initial assumption that an execution name exists before the Workflows create call; the second
delta makes the post-create self-bind duplicate-safe.

## RQ-20260805-1910-post-import-event-publisher
Status: REVIEWED
Reviewer: Claude Code
Class: A
Artifact: commit `c90d79b`; `workflows/sap_result_ingestion.*`.
Opened: 2026-08-05T19:10:38+07:00
Verdict: PASS — `docs/reviews/2026-08-05-c90d79b-claude.md` (verified the empty-topic gate returns
before any enqueue or publish; outbox-before-publish ordering via the existing query_ helper, which
throws before the Pub/Sub call on any DDL 071 rejection; topic-ID validation; only the narrow
pubsub scope added, no cloud-platform restored; idempotent retry behavior since the email stays
unlabeled and is safely reprocessed on failure. Independently re-ran node --check and git diff
--check. One non-blocking observation: the new Pub/Sub call joins the existing no-per-item-
try/catch batch loop already accepted for persistCandidate_ in the 1e949e7 review.)

Claim: With the topic property blank, behavior is unchanged. When separately configured after DDL
071 deployment, a matched persisted result first idempotently enqueues its exact LogID/manifest
binding and then publishes only minimal retry-safe metadata to a validated Pub/Sub topic. It does
not publish attachments or restore broad cloud-platform OAuth.
Evidence: Node syntax check via standard input and `git diff --check` passed. Review event timing,
outbox-before-publish ordering, empty-topic gate, scope addition, topic validation, retry behavior,
and no trigger/deployment action.

## RQ-20260805-1903-post-import-refresh-outbox
Status: REVIEWED
Reviewer: Claude Code
Class: A
Artifact: commit `282581f`; `sql/ddl/071_v3_post_import_refresh_outbox.sql`.
Opened: 2026-08-05T19:03:30+07:00
Verdict: PASS — `docs/reviews/2026-08-05-282581f-claude.md` (verified table grain, dependency
assertions against live BigQuery schema (neither dependency table is deployed yet, which is
expected — same staged review-before-deploy model as the rest of this project, and correctly
disclosed in the file's own header), retry/idempotency, cross-manifest rejection, transaction/
row-count guard, status restriction, and the no-trigger/no-delivery boundary. Independently re-ran
the dry-run: 0 bytes. One non-blocking observation: a narrow TOCTOU gap on two genuinely concurrent
first-time enqueues of the same brand-new log_id with different manifests — doesn't corrupt data,
just a silent no-op instead of a clear rejection; not a live concern given the intended
single-caller-per-log_id usage.)

Claim: Source-only DDL creates an idempotent durable outbox keyed by SAP LogID and bound to one
exact delivered manifest. Its enqueue procedure admits only the two evidenced terminal statuses,
requires one persisted parsed LIVE result header, rejects cross-manifest LogID reuse, and cannot
start a workflow or change delivery/ACK state.
Evidence: `scripts/bq_safe_query.sh --dry-run-only -f sql/ddl/071_v3_post_import_refresh_outbox.sql`
passed at 0 bytes. Review table grain, dependency assertions, retry/idempotency behavior,
transaction/row-count guard, status restriction, and the no-trigger/no-delivery boundary. No
deployment, procedure CALL, GCS write, Gmail, scheduler, or SAP action is requested.

## RQ-20260805-1428-exact-sha-promotion
Status: REVIEWED
Reviewer: Claude Code
Class: A
Artifact: commit `daa9331`; `infra/sap_delivery_promoter/` and `infra/v3_nightly_orchestrator.workflows.yaml`.
Opened: 2026-08-05T14:28:01+07:00
Verdict: PASS — `docs/reviews/2026-08-05-daa9331-claude.md` (verified generation-bound hashing,
create-only rewrite semantics, destination size/CRC32C check, explicit-filename production-path
construction with no archive-name inference, bucket/prefix confinement, correct DDL 062 argument
order, fail-closed missing-contract and response-binding gates, and that `delivery_enabled` stays
`false`; independently re-ran `py_compile` and `git diff --check`. Two non-blocking observations
noted: an uncaught `NotFound` on a deleted source generation surfaces as 500 instead of a clean 4xx
(still fails closed); `promotion_service_url` inherits the same existing workflow-arg trust
boundary as `project`/`run_id`, not a new one.)

Claim: The source-only promoter hashes the immutable requested archive generation before a
create-only promotion, verifies destination size/CRC32C, and returns only exact evidence. The
workflow keeps delivery disabled, requires an explicit SAP-facing filename rather than archive-name
inference, checks the returned binding, and supplies DDL 062's required filename/SHA-256 arguments.
Evidence: Read `infra/sap_delivery_promoter/main.py`, its deployment contract, and the Unit 6
workflow delta; `python -m py_compile infra/sap_delivery_promoter/main.py` and `git diff --check`
passed. Confirm no deployment, procedure CALL, GCS write, scheduler, Gmail, BigQuery mutation, or
SAP action is requested. Review name validation, source-generation binding, create-only semantics,
destination verification, failure paths, response metadata, and the inactive workflow gate.

## RQ-20260805-1147-completeness-dispatch-batch-isolation
Status: REVIEWED
Reviewer: Claude Code
Class: A
Artifact: commit `d85aa20`; delta in `workflows/v3_daily_completeness_report.gs`.
Opened: 2026-08-05T11:47:20+07:00
Verdict: PASS, note resolved — `docs/reviews/2026-08-05-d85aa20-claude.md` (confirmed the per-run
try/catch is inside the forEach callback, so an exception from one pipeline run's delivery can no
longer abort the batch; confirmed the sanitized aggregate throw fires only after every pending run
has been attempted; read the complete current file end-to-end and confirmed
`deliverV3DailyCompletenessReport_`'s ALERT_FAILED-before-fallback ordering and distinct-recipient
enforcement are byte-for-byte unchanged; independently re-verified with node --check)

Delta review for the sole required note in `docs/reviews/2026-08-05-44ade18-claude.md`: confirm
each pending report is attempted independently, a failure in one run cannot stop later pending
runs, and the dispatcher raises a sanitized aggregate only after the batch completes. Confirm the
existing per-run `ALERT_FAILED` then fallback behavior remains intact. Node syntax and whitespace
validation passed. No trigger, email, BigQuery mutation, deployment, GCS, scheduler, or SAP action
is requested.

## RQ-20260805-0946-v3-completeness-report-dispatcher
Status: REVIEWED
Reviewer: Claude Code
Class: A
Artifact: commit `44ade18`; `workflows/v3_daily_completeness_report.gs` and deployment contract.
Opened: 2026-08-05T09:46:26+07:00
Verdict: PASS WITH REQUIRED NOTE — `docs/reviews/2026-08-05-44ade18-claude.md` (every checklist item
verified correct: TOCTOU-aware snapshot recheck, metric-only/no-PII body, DELIVERED-after-success
ordering, ALERT_FAILED-before-fallback ordering with an enforced distinct recipient, missing/
duplicate/non-pending fail-closed, exactly-one-row UPDATE guard, reused OAuth scopes correctly
disclosed. Required note: the dispatch `forEach` has no per-item try/catch, so one pipeline run's
alert failure — even when its fallback succeeds — throws and aborts the loop, silently stranding
any other unrelated pending report in the same batch until the next trigger fire; worse than the
15-minute ingestion-poller equivalent since this is a daily-cadence dispatcher. Independently
re-verified with node --check and a trailing-whitespace scan)

Review the source-only daily completeness report dispatcher. Confirm it reads only immutable
`READY_TO_ALERT`/`PENDING` snapshots, emits metric-only/no-PII mail, records `DELIVERED` only after
primary mail success, and persists `ALERT_FAILED` before attempting a distinct fallback recipient
when primary mail fails. Confirm a missing/duplicate/non-pending snapshot and a status update that
does not affect exactly one row fail closed. Verify no trigger, email, BigQuery mutation, or
production deployment is requested. Node syntax and whitespace validation passed.

## RQ-20260805-0943-exact-delivery-identity-conservation
Status: REVIEWED
Reviewer: Claude Code
Class: A
Artifact: commit `70e5671`; delta in `sql/ddl/062_v3_mark_exact_delivery.sql`.
Opened: 2026-08-05T09:43:58+07:00
Verdict: PASS, note resolved — `docs/reviews/2026-08-05-70e5671-claude.md` (traced both new
set-difference counts by hand: `v_identity_unmatched=0` catches missing archive rows,
`v_archive_unmatched=0` catches extraneous/wrong ones, together proving genuine bidirectional
4-tuple set equality with no vacuous-pass risk given `v_identity_rows>0` is still asserted first;
balance-held exclusion applied identically on both sides; old count check retained but no longer
sole evidence, exactly as requested; independently re-ran the dry-run at 0 bytes)

Delta review for the sole required note in `docs/reviews/2026-08-05-7d4866a-claude.md`: confirm
the claimed pipeline payload and the claimed archive export run now have bidirectional set equality
on `(order_item, period, charge_id, payload_hash)`, with the same balance-held exclusion as the
existing identity population, before DELIVERED state can be recorded. Confirm no count-only join
between the two caller-supplied run IDs remains as the only conservation evidence. The repository
safe-query dry-run of DDL 062 passed at 0 bytes. No deployment, procedure CALL, GCS write, Gmail,
scheduler, BigQuery table mutation, or SAP action is requested.

## RQ-20260805-0930-exact-sap-delivery-manifest
Status: REVIEWED
Reviewer: Claude Code
Class: A
Artifact: commit `7d4866a`; DDL 062 delivery-marker replacement and Unit 6 deployment contract.
Opened: 2026-08-05T09:30:15+07:00
Verdict: PASS WITH REQUIRED NOTE — `docs/reviews/2026-08-05-7d4866a-claude.md` (filename-exactness,
atomic 3-table write, and all three replay-protection vectors verified correct; independently
re-ran the dry-run at 0 bytes and confirmed both `v3_unit5_payload_identity`/`v3_unit5_balance_hold`
dependencies already exist live. Required note: the row-conservation check compares counts across
`p_pipeline_run_id` and `p_export_run_id` — two identifiers with no structural link, since
`export_archive` has no `pipeline_run_id` column — so it proves count equality, not that the
archived rows are the same identities; both tables already carry `order_item`/`period`/
`charge_id`/`payload_hash` needed for a real set-level check, matching the pattern required in
`docs/reviews/2026-08-04-913ff3b-claude.md`. One non-blocking note: replay-guard ASSERTs run before
`BEGIN TRANSACTION`, so they carry no isolation guarantee against a concurrent second call —
low risk given single-deployer operational discipline)

Review the source-only exact SAP-facing delivery-manifest writer. Confirm DDL 062 requires the
promotion caller to supply a valid SHA-256 and exact SAP-facing basename; validates that basename
against the production URI without archive-name inference; conserves data rows from the same export
run; writes archive, legacy manifest, and `sap_delivery_manifest_v3` evidence atomically; and
fails closed on replayed export-run, destination, or SAP filename evidence. Confirm the source
dependency on DDL 070 is explicit. `scripts/bq_safe_query.sh --dry-run-only -f
sql/ddl/062_v3_mark_exact_delivery.sql` passed at 0 bytes. No deployment, procedure CALL, GCS
write, Gmail, scheduler, BigQuery table mutation, or SAP action is requested.

## RQ-20260805-0100-unit6-sap-result-ingestion-required-notes
Status: REVIEWED
Reviewer: Claude Code
Class: A
Artifact: commit `2cd1c28`; delta in `workflows/sap_result_ingestion.gs` and Apps Script manifest.
Opened: 2026-08-05T01:00:08+07:00
Verdict: PASS, both notes resolved — `docs/reviews/2026-08-05-2cd1c28-claude.md` (confirmed
`-label:"ingested"` exclusion closes the redundant-reprocessing gap; confirmed
`group.length !== 1 || logIds.length !== 1` closes the same-logId duplicate-candidate gap with no
new false-positive risk; confirmed `bigquery`+`devstorage.read_write` cover every GCP call the
script actually makes; independently re-syntax-checked with `node --check`. One non-blocking
rehearsal suggestion: thread-level `-label` exclusion can't be verified against real Gmail
threading behavior from source alone)

Delta review for the two required notes in `docs/reviews/2026-08-04-1e949e7-claude.md`: confirm
the Gmail query excludes `ingested`, a same-LogID duplicate candidate set fails closed through
`group.length !== 1`, and the broad `cloud-platform` scope is replaced only by `bigquery` and
`devstorage.read_write`. Node syntax validation passed. No deployment, trigger, Gmail, GCS,
BigQuery, scheduler, or production-object mutation is requested.

## RQ-20260804-2128-unit6-sap-result-ingestion-runtime
Status: REVIEWED
Reviewer: Claude Code
Class: A
Artifact: commit `1e949e7`; DDL 070 and `workflows/sap_result_ingestion.*`.
Opened: 2026-08-04T21:28:58+07:00
Verdict: PASS WITH REQUIRED NOTES — `docs/reviews/2026-08-04-1e949e7-claude.md` (2 required before
deploy: (1) Gmail search never excludes the `ingested` label, so every ingested message is
rediscovered every poll cycle for up to ~4 cycles — idempotent writes mean no data-safety impact,
but it also means the `AMBIGUOUS_ACK` check's `logIds.length !== 1` alone can't catch a same-logId
duplicate candidate set silently dropping one; needs `-label:"ingested"` plus a `group.length`
guard; (2) `appsscript.json` requests the broad `cloud-platform` OAuth scope, contradicting this
same commit's own deployment doc asking for narrowly scoped access — needs `bigquery` +
`devstorage.read_write` instead. 3 non-blocking notes recorded. Independently syntax-checked the
`.gs` file with `node --check`, confirming the commit's own claim; traced all seven checklist items
in the review request against the actual control flow line-by-line)

Review strict `[LIVE]`/`RCB_LIVE_DB`/60-minute Gmail filtering; exact persisted SAP-facing manifest
matching (never archive-basename inference); ambiguous-LogID and attachment-shape fail-closed paths;
GCS create-only persistence; idempotent BigQuery header/detail/heartbeat writes; label-after-write;
and the independent pre-60-minute heartbeat alert. Confirm the DDL 070 manifest/heartbeat grain
supports the writer and that no source path can ACK rows, deliver a file, or mutate a scheduler.
Node syntax validation passed. Source-only: no Apps Script, trigger, Gmail, GCS, BigQuery, or
production object was deployed or mutated.

## RQ-20260804-2103-live-import-21183-post-refresh-reconciliation
Status: REVIEWED
Reviewer: Claude Code
Class: A
Artifact: commit `3a74168`; `docs/FINDINGS_LIVE_IMPORT_21183_20260803.md` and evidence updates.
Opened: 2026-08-04T21:03:48+07:00
Verdict: PASS — `docs/reviews/2026-08-04-3a74168-claude.md` (cross-checked the 584-row run against
`FINDINGS_LIVE_IMPORT_21178_20260803.md` and confirmed it is LogID 21178, not a 21183 discrepancy;
independently re-ran the export_archive/sap_mirror_state reconciliation as a fresh query —
558/558 delivered, 0 missing, 558 Paid; confirmed `sap_log_id`/`sap_result_status`/`acknowledged_at`
are still NULL for this run, so the ACK-scope wording does not overclaim)

Review the corrected LogID 21183 conclusion. The supplied TXT confirms exact renamed filename,
terminal success, JE references, and reconciliation no., but no row count or row-level detail.
After the approved extract/load/mirror refresh, the exact DELIVERED run
`V3DAILY-20260803-113257-55042e7c` had 558 identities; all 558 matched `sap_mirror_state` with
`TransactionStatus='Paid'`, zero were missing, and the safe query estimated 73,208,397 bytes.
Confirm the rejected 584-row 21178 run is not misattributed to 21183, and that the conclusion
does not overclaim attachment-level ACK. No deployment, acknowledgement mutation, delivery, Gmail
change, or corrective SAP action is requested.

## RQ-20260804-2040-manual-sync-empty-bronze-prefix
Status: REVIEWED
Reviewer: Claude Code
Class: A
Artifact: commit `dc13a10`; `scripts/run_sap_sync_manual.ps1`.
Opened: 2026-08-04T20:40:43+07:00
Verdict: PASS — `docs/reviews/2026-08-04-dc13a10-claude.md` (confirmed the Windows PowerShell 5.1
mechanism: redirecting a native command's stderr under `$ErrorActionPreference='Stop'` promotes
each stderr line to a terminating error regardless of exit code, which is exactly what made the
empty-prefix case unreachable before this fix; the `Continue` override is scoped to only the one
redirected call and the `$LASTEXITCODE -notin 0,1` guard still stands; checked no other native call
in the file redirects stderr, so no other call site carries the same latent bug; `@(...)` wrapping
is the standard fix for PowerShell's single-object pipeline collapse)

Review Windows PowerShell handling of the normal empty-bronze-prefix state: `gsutil ls` exit 1 must
remain a valid empty result, failures other than 0/1 must still stop, and every caller must receive
an array so strict-mode `.Count` is safe. The corrected runner was used once under Boat's explicit
2026-08-04 production approval: it completed exactly one extract, one loader consumption, and the
existing V3 refresh sequence. Review the source change and the stated operational boundary; no
additional execution, delivery, archive acknowledgement, or scheduler mutation is requested.

## RQ-20260804-1245-contiguous-period-spines
Status: REVIEWED
Reviewer: Claude Code
Class: A
Artifact: commit `d0eff7e`; deltas in DDL 058/059/069 and
`sql/adhoc/20260804_period_spine_range_fixture.sql`.
Opened: 2026-08-04T12:45:54+07:00
Verdict: PASS, note resolved — `docs/reviews/2026-08-04-d0eff7e-claude.md` (worked the pigeonhole
proof by hand: first=1 + last=total_n + count=total_n together are now a genuine contiguity proof,
not cardinality-only; confirmed the exact {1,2,4}/total-3 case and a second unflagged case {2,3}/
total-2 are both now caught; identical fix applied verbatim across all three files)

Delta review for the shared hardening note in
`docs/reviews/2026-08-04-62fa5e0-claude.md`. Confirm each full-spine assertion requires one
consistent `TotalPeriods`, lower bound 1, upper bound exactly `TotalPeriods`, and exact distinct
period count, closing the `{1,2,4}`/total-3 gap. All three DDLs and the fixture passed
`--dry-run-only` at 0 bytes; literal fixture job
`bqjob_r2c8f415bf45ee23d_0000019fcb4df22b_1` passed healthy, gapped, and inconsistent-total
assertions. No deploy, procedure CALL, payload/archive mutation, GCS write, or delivery is
requested.

## RQ-20260804-1239-unit6-payload-hash-binding
Status: REVIEWED
Reviewer: Claude Code
Class: A
Artifact: commit `913ff3b`; delta in `sql/ddl/067_v3_daily_completeness_snapshot.sql`.
Opened: 2026-08-04T12:39:35+07:00
Verdict: PASS, note resolved — `docs/reviews/2026-08-04-913ff3b-claude.md` (payload_hash predicate
closes the stale-natural-key gap exactly as recommended; minor non-blocking observation that
export_archive.payload_hash has no NOT NULL constraint, theoretical today since every current
writer populates it)

Delta review for the note in `docs/reviews/2026-08-04-0937c5f-claude.md`. Confirm `_exports`
requires exact `payload_hash` equality in addition to `(order_item,period,charge_id)`, so a stale
archive for a reused natural key cannot satisfy the current run's export/manifest evidence.
Complete DDL passed `--dry-run-only` at 0 bytes. No deploy, snapshot CALL, manifest mutation, or
alert is requested.

## RQ-20260804-1238-manual-export-requester-audit
Status: REVIEWED
Reviewer: Claude Code
Class: A
Artifact: commit `f049721`; delta in `sql/ddl/069_v3_manual_newpayment_archive.sql` and runbook.
Opened: 2026-08-04T12:38:52+07:00
Verdict: PASS, note resolved — `docs/reviews/2026-08-04-f049721-claude.md` (audit INSERT placed
after all fail-closed ASSERTs and before the write phase; requested_by/scope/counts all captured
name-matched; PREPARING provenance correctly survives a mid-procedure failure given BigQuery's
per-statement commit model; terminal status literal matches export_archive's exactly)

Delta review for the required-before-deploy note in
`docs/reviews/2026-08-04-62fa5e0-claude.md`. Confirm every validated manual request persists its
caller, requested arrays, pipeline/export IDs, selected row/identity counts, archive URI, and
PREPARING/final archive status in `manual_export_request`; an export failure after request insert
must retain PREPARING provenance. Parser self-test passed 7/7 and complete DDL passed
`--dry-run-only` at 0 bytes. No deploy, procedure CALL, table row, GCS write, or delivery is
requested.

## RQ-20260804-1215-safe-manual-newpayment-archive
Status: REVIEWED
Reviewer: Claude Code
Class: A
Artifact: commit `62fa5e0`; `sql/ddl/069_v3_manual_newpayment_archive.sql` and runbook update.
Opened: 2026-08-04T12:15:08+07:00
Verdict: PASS WITH NOTES — `docs/reviews/2026-08-04-62fa5e0-claude.md` (56-column order verified
by direct count/diff against 058's canonical contract, identical; archive_uri confirmed hardcoded
and cannot be redirected by caller input; REQUIRED BEFORE DEPLOY: p_requested_by is asserted
non-empty but never persisted anywhere — export_archive has no requested_by column, so the "audit
identity" requirement is currently cosmetic; also flags the period-spine cardinality-only check
shared with 058/059 as a non-blocking hardening candidate)

Review explicit OrderItem/OrderID OR scope, RCB_MOTOR/NEWPAYMENT-only fail-closed boundary,
complete-item-spine and 56-column/date/PolicyNo/InvoiceNo checks, current-run identity
conservation, replay refusal, basename/folder contract, and event-grain `run_type='MANUAL'`
archive conservation. Confirm the procedure can write only the manual archive prefix and cannot
write the production interface prefix. Parser self-test passed 7/7 and the full DDL passed
`--dry-run-only` at 0 bytes. No deploy, procedure CALL, archive object, ledger write, production
delivery, or SAP mutation is requested.

## RQ-20260804-1210-validation-regression-alert-repair
Status: REVIEWED
Reviewer: Claude Code
Class: A
Artifact: commit `7ad0765`; `sql/ddl/068_validation_regression_history_alert.sql` and
`sql/adhoc/20260804_validation_regression_fixture.sql`.
Opened: 2026-08-04T12:10:00+07:00
Verdict: PASS WITH NOTES — `docs/reviews/2026-08-04-7ad0765-claude.md` (fixture matches
implementation incl. the tested zero-baseline new-check case; confirmed the new sp_..._v2 procedure
name means the live BQDTS scheduled query still calls the old heuristic until a separate
transfer-config revision, and this is honestly disclosed not overclaimed; NOTE: document the
new-check onboarding sequence for whoever sets the first threshold)

Review immutable per-date/per-check history, source conservation, prior-snapshot selection,
new-check zero baseline, positive-increase-only record/order OR semantics, and required
non-overlapping approved configuration. Confirm the source replaces rather than perpetuates the
obsolete global >60/~22–24 heuristic. Live metadata evidence is BQDTS config
`6a67073f-0000-2621-a014-3c286d3f1e8e`, latest inspected run 2026-08-03 14:10 UTC. Complete DDL
and six-case fixture passed `--dry-run-only` at 0 bytes. No deploy, procedure CALL, config/schedule
mutation, or alert delivery is requested.

## RQ-20260804-1206-unit6-completeness-snapshot
Status: REVIEWED
Reviewer: Claude Code
Class: A
Artifact: commit `0937c5f`; `sql/ddl/067_v3_daily_completeness_snapshot.sql`.
Opened: 2026-08-04T12:06:44+07:00
Verdict: PASS WITH NOTES — `docs/reviews/2026-08-04-0937c5f-claude.md` (every referenced table/
column independently verified to exist with the assumed schema; READY_TO_ALERT vs PENDING boundary
confirmed real, not just asserted; NOTE: the pipeline-run-to-export mapping joins only on the
natural key order_item/period/charge_id because export_archive has no pipeline_run_id column —
recommend also joining on the existing payload_hash column before this feeds human alerting, to
close the theoretical stale-export misattribution case)

Review immutable replay refusal, exact Unit 1/Units 2–5/magnitude/gate prerequisites, healthy-zero
and nonzero export-manifest conservation, pipeline-run-to-export inference, normalized outcome/
notification/delivery/SAP-result metrics, and evidence coverage. Confirm `READY_TO_ALERT` cannot
be mistaken for human delivery because alert state begins `PENDING`, and missing row ACK remains
visible. Full DDL passed `--dry-run-only` at 0 bytes. No deploy, snapshot CALL, alert delivery,
export, GCS write, or scheduler mutation is requested.

## RQ-20260804-1203-interface-status-increase-alert
Status: REVIEWED
Reviewer: Claude Code
Class: A
Artifact: commit `3c32cf3`; `sql/ddl/066_interface_status_history_increase_alert.sql` and
`sql/adhoc/20260804_interface_status_increase_fixture.sql`.
Opened: 2026-08-04T12:03:54+07:00
Verdict: PASS — `docs/reviews/2026-08-04-3c32cf3-claude.md` (all 12 checklist items pass; fixture
matches implementation incl. boundary and OR-not-AND semantics; confirmed no provisional
MISSING/STATUS_CONFLICT numbers were seeded as a threshold; combined duplicate/incomplete config
assertion traced clean)

Review immutable one-snapshot-per-date behavior, source row conservation, prior-snapshot
selection, missing-status-as-zero semantics, positive-increase-only decisions, record/order OR
threshold behavior, and exactly-one effective approved config per monitored status. Confirm no
provisional population was seeded as a threshold. The complete DDL and literal five-case fixture
passed `--dry-run-only` at 0 bytes. No deploy, snapshot/check CALL, threshold mutation, alert
delivery, export, GCS write, or scheduler change is requested.

## RQ-20260804-1201-extract-scheduler-health-view
Status: REVIEWED
Reviewer: Claude Code
Class: A
Artifact: commit `d8303e8`; `sql/ddl/065_vw_dash_extract_scheduler_health.sql`.
Opened: 2026-08-04T12:01:17+07:00
Verdict: PASS — `docs/reviews/2026-08-04-d8303e8-claude.md` (all 12 checklist items pass; step
literals cross-checked against the orchestrator YAML's actual writers; sap_extract_control
dead-table and 26h threshold claims verified against prior FINDINGS/design docs rather than taken
on faith; execution_health branch ordering and NULL-safety traced clean)

Review latest-run selection, 26-hour staleness behavior, same-run healthy-zero/LOAD evidence,
failed/incomplete states, and the explicit distinction between orchestrator execution health and
unverified scheduler-trigger provenance. Confirm a manual workflow run cannot be represented as
proved scheduler success and the empty/dead `sap_extract_control` table is not reused. Parser
self-test passed 7/7 and the complete DDL passed `--dry-run-only` at 0 bytes. No deploy, scheduler
mutation, procedure CALL, export, or GCS write is requested.

## RQ-20260804-1114-excluded-record-audit-enrichment
Status: REVIEWED
Reviewer: Claude Code
Class: A
Artifact: commit `7a8ecd2`; `sql/ddl/032_exclusion_config_and_excluded_records.sql` and
`sql/ddl/037_fix_expected_invoice_no_null_unsafe.sql`.
Opened: 2026-08-04T11:14:57+07:00
Verdict: PASS WITH NOTES — `docs/reviews/2026-08-04-7a8ecd2-claude.md` (all five exclusion writes
confirmed populating both new columns; predicates and expected_state output diffed unchanged;
NOTE: 032's CREATE TABLE IF NOT EXISTS is a no-op against the already-live table — the schema
change only actually ships when 037's procedure is deployed and CALLed, worth one runbook line at
deploy time)

Review that every current exclusion write persists `_rules.charge_amount` as satang `amount` and
the processing `date_basis`; nullable amount/date behavior remains truthful; canonical base schema
matches the rebuilt table; and no exclusion predicate, rule code/reason, expected-state output, or
expected-state filter changed. Safe-query parser self-test passed 7/7 and both complete DDL files
passed `--dry-run-only` at 0 bytes. No deploy, procedure CALL, table replacement, export, GCS
write, or scheduler mutation is requested.

## RQ-20260804-1055-sap-result-ingestion-contract
Status: REVIEWED
Reviewer: Claude Code
Class: A
Artifact: commit `6397996`; `sql/ddl/064_sap_result_ingestion_contract.sql`.
Opened: 2026-08-04T10:55:44+07:00
Verdict: PASS WITH NOTES — `docs/reviews/2026-08-04-6397996-claude.md` (grain/keys/scope/labelling
all pass; correctly discloses non-replacement of legacy sap_import_result; NOTE: state the
header-terminal-is-not-row-level-ACK boundary explicitly in this file's own comments, not only in
the sibling runbook, before it becomes input to the future exact-manifest binding procedure)

Review the non-destructive separation of import header, attachment detail, and file-pickup
evidence; logical idempotency keys; required production/file/attachment fields; restricted raw
error storage; and the explicit boundary that pickup or header success alone is not row-level ACK.
Confirm the contract is sufficient for a later exact-manifest binding procedure without replacing
the legacy `sap_import_result` table prematurely. Safe-query parser self-test passed 7/7 and the
complete DDL passed `--dry-run-only` at 0 bytes. No deploy, migration, ingestion writer, ACK
mutation, Gmail mutation, GCS write, procedure CALL, or scheduler change is requested.

## RQ-20260803-2112-unit2-population-magnitude-gate
Status: REVIEWED
Reviewer: Claude Code
Class: A
Artifact: commit `8bea466`; `sql/ddl/063_v3_unit2_population_magnitude_gate.sql`,
`sql/ddl/061_v3_units2_5_nightly_wrapper.sql`, and
`sql/adhoc/20260803_unit2_magnitude_decision_fixture.sql`.
Opened: 2026-08-03T21:12:42+07:00
Verdict: PASS — `docs/reviews/2026-08-03-8bea466-claude.md` (all 12 checklist items pass; fixture
matches implementation exactly incl. zero-baseline floor and AND-not-OR semantics; confirmed via
cross-file trace that the `UNITS_2_5_ARCHIVE` baseline dependency is genuinely written by the
orchestrator workflow around the wrapper CALL and only logs SUCCESS when the magnitude gate itself
doesn't breach, so a breached run cannot poison the baseline history; self-test 7/7 reconfirmed
offline)

Review the event/schedule distribution grain, last-successful baseline selection, active approved
configuration requirement, absolute-and-percentage decision semantics, zero-baseline behavior,
conservation assertions, and placement before Unit 3. Confirm missing config/baseline cannot
release Unit 5. The safe-query parser self-test passed 7/7; BigQuery dry-runs are BLOCKED on the
installed `bq` 2.0.92 unattended reauthentication failure and must pass before any deploy. No
configuration seed, deploy, CALL, export, GCS write, or scheduler mutation is requested.

Validation update 2026-08-04 10:53 ICT: reauthentication is complete; the parser self-test passed
7/7 and all three review artifacts passed `--dry-run-only` at 0 bytes. No SQL was executed. Review
and deployment/configuration gates remain unchanged.

## RQ-20260803-1953-live-import-21183-bounded-ingestion
Status: REVIEWED
Reviewer: Claude Code
Class: A
Artifact: commit `f084a8a`; `docs/FINDINGS_LIVE_IMPORT_21183_20260803.md`,
`docs/design/SAP_RUNBOOK_v3.md`, and `docs/design/V3_AUTONOMY_UNITS_2_6_DESIGN.md`.
Opened: 2026-08-03T19:53:08+07:00
Verdict: PASS WITH NOTES — `docs/reviews/2026-08-03-f084a8a-claude.md` (header/row-level boundary
correctly drawn and correctly labelled; environment gate consistent with existing rules; NOTE:
document the Apps Script trigger cadence — the 60-minute lookback only guarantees coverage if polls
run more often than that, and no alert path is described for a poll gap leaving a result stuck at
PENDING_ACK)

Review the production-only one-hour Gmail window, exact current-manifest filename match,
zero/multiple-match behavior, UAT2 exclusion, and the boundary between terminal import success
and post-import mirror reconciliation. Confirm that LogID 21183 supports the recorded SAP import
success and accounting references without implying row-level reconciliation or pipeline
completion. No deploy, procedure CALL, GCS write, Gmail mutation, or scheduler change is
requested.

## RQ-20260803-1918-rcb-onetime-change-order-rcl-label
Status: REVIEWED
Reviewer: Claude Code
Class: A
Artifact: `docs/FINDINGS_RCB_ONETIME_CHANGE_ORDER_MISROUTED_RCL_20260803.md` and
`sql/adhoc/20260803_l80482368_rcb_creditshell_misroute.sql`, plus the preventive delta in
`sql/ddl/058_v3_unit5_newpayment_shadow.sql`.
Opened: 2026-08-03T19:18:00+07:00
Verdict: PASS — `docs/reviews/2026-08-03-cb88dc2-claude.md` (all 12 checklist items pass; one
non-blocking note on join scope reuse risk if the diagnostic query is ever repurposed for a
multi-period population; assertion placement confirmed after registry resolution and before
candidate materialization; registry-guard job shows zero live violations today)

Review the live/repo drift statements, known-case trace, posted-state population grain, and the
flow-aware future-order proposal. Verify that the 9-order count is limited to FULL_PAYMENT change
orders with 1/1 current source state and a valid SAP DocEntry whose latest M1 payment mapping is
RCL Credit Shell. Confirm this remains separate from INCIDENT-002a, INCIDENT-002b, and the 224
unknown-cause orders. No deploy or correction is requested.

Delta added after diagnosis: review the fail-closed assertion that rejects any resolved
`flow='ONETIME'` row whose approved PaymentMethod or PaymentChannel begins with `RCL`. Confirm the
check executes after registry resolution and before candidate materialization. Definition deploy
remains prohibited pending review and separate Boat approval. Source dry-run at
`2026-08-03T12:43:20.923Z` passed at 0 bytes. Read-only registry evidence job
`codex_onetime_rcl_mapping_guard_20260803_124344` found 0 currently approved violating mappings
(dry-run/processed 1,256 bytes; billed 10,485,760 bytes).

## RQ-20260803-1818-unit5-full-period-spine
Status: REVIEWED
Reviewer: Codex self-review under Boat's technical-gate authority
Class: A
Artifact: `sql/ddl/058_v3_unit5_newpayment_shadow.sql`, `059_v3_unit5_balance_hold.sql`,
`060_v3_daily_newpayment_archive.sql`, and `062_v3_mark_exact_delivery.sql`.
Opened: 2026-08-03T18:18:00+07:00

LIVE 21178 rejected 584/584 event rows because the file omitted the complete RCL period spine.
Exact-population diagnostic `codex_diag_21178_spine_20260803_181630_267` found 582 item identities,
4,016 source rows, 582/582 complete spines, and zero null/duplicate period identities. Review event
identity versus file-row grain separation, whole-item quarantine, full-spine conservation, and
manifest data-row count. Dry-runs at 2026-08-03T11:18:40Z–11:18:41Z passed at 0 bytes.

Verdict: **PASS FOR PROCEDURE DEFINITION DEPLOY; CALL/ARCHIVE/DELIVERY REMAIN CLOSED.** Definition
deploy jobs: `codex_deploy_058_v3_unit5_newpayment_shadow_20260803_181859_838`,
`codex_deploy_059_v3_unit5_balance_hold_20260803_181903_330`,
`codex_deploy_060_v3_daily_newpayment_archive_20260803_181906_710`, and
`codex_deploy_062_v3_mark_exact_delivery_20260803_181910_116`; all DONE, error null, 0/0 bytes.

Runtime update: first controlled wrapper run correctly exposed two stale event-grain assertions.
059 was narrowed to target identities and rebuilt by `codex_call_059_full_spine_20260803_183036_095`.
060 now permits preserved historical PaymentDates while enforcing OPEN-period BatchRunDate and
OPEN-period dates on target events only. Verification: 559 targets, 1 held event, 3,857 file rows,
555 items, 56 columns, zero incomplete/duplicate spines. Archive-only job
`codex_call_060_full_spine_archive_20260803_183256_706` produced one correctly named 2,377,414-byte
object and 558 event ledger rows. **PASS ARCHIVE; production promotion remains CLOSED.**

## RQ-20260803-1550-unit6-exact-copy-workflow
Status: REVIEWED
Reviewer: Codex self-review under Boat's technical-gate authority
Class: A
Artifact: `infra/v3_nightly_orchestrator.workflows.yaml`.
Opened: 2026-08-03T15:50:00+07:00

Review zero-payload healthy return, same-run archive discovery, exactly-one object gate, pinned
source generation, create-only destination precondition, source/destination size+CRC equality,
and ordering of GCS copy before the deployed 062 ledger CALL. Static YAML parse PASS. Verdict:
**PASS SOURCE FOR WORKFLOW REVISION DEPLOY ONLY**. A deployed revision must be syntax-validated by
Cloud Workflows. Do not activate its recurring scheduler until a controlled execution proves both
the zero-payload path and a nonzero exact-copy path. DELIVERED remains distinct from SAP ACK.

## RQ-20260803-1535-unit6-exact-delivery-ledger
Status: REVIEWED
Reviewer: Codex self-review under Boat's technical-gate authority
Class: A
Artifact: `sql/ddl/062_v3_mark_exact_delivery.sql`.
Opened: 2026-08-03T15:35:00+07:00

Review same-run identity conservation, approved archive/production prefixes, mandatory source and
destination generation evidence, non-empty size and CRC evidence, replay refusal, exact ledger
row update, and the explicit boundary that `DELIVERED` is not SAP pickup or acknowledgement.
This procedure performs no GCS copy and must only be called after the orchestrator's create-only
copy and source/destination metadata equality gate succeeds.

Self-review verdict: **PASS FOR PROCEDURE DEPLOY ONLY**. Live schemas contain every referenced
column. REST dry-run at `2026-08-03T08:45:58.5966105Z` returned error null and 0 processed bytes
(BigQuery dry-run creates no persistent job, so job ID is null). Deploy job
`codex_deploy_062_20260803_154635_317` reached DONE with error null and 0/0 processed/billed bytes.
No CALL was made. Workflow copy, runtime parameters, SAP ACK, and scheduler activation remain
separate Class A gates.

## RQ-20260803-1515-units2-5-nightly-chain
Status: REVIEWED
Reviewer: Codex (Boat authorized self-review/fix/continue for technical gates)
Class: A
Artifact: `sql/ddl/061_v3_units2_5_nightly_wrapper.sql` and
`infra/v3_nightly_orchestrator.workflows.yaml`.
Opened: 2026-08-03T15:15:00+07:00

Review same-run Unit 1 provenance; ordered Unit 2→3→notification→gate→058; nonzero-only
059/archive behavior; healthy zero-delivery behavior; terminal-polled workflow CALL; and the hard
boundary that production promotion/SAP ACK are still Unit 6, not silently inferred here.

Self-review correction: 059 is now called even on zero-candidate nights and enforces 0=0
candidate/identity conservation, ensuring `v3_unit5_newpayment_delivery_ready` is rebuilt empty
instead of retaining the prior night's payload. Archive remains conditional on delivery rows >0.

Evidence: YAML parser PASS; final 059 dry-run
`codex_dry_059_v3_unit5_balance_hold_20260803_150933_212` = 0 bytes; 061 dry-run
`codex_dry_061_v3_units2_5_nightly_wrapper_20260803_150933_676` = 0 bytes.

Verdict: **PASS SOURCE FOR 059/061 DEPLOY AND WORKFLOW REVISION DEPLOY** — scheduler trigger remains
disabled/unmodified; production promotion and SAP ACK are not part of this revision.

Runtime update: 059 deploy `codex_redeploy_059_zero_safe_20260803_151034_495` and 061 deploy
`codex_deploy_061_20260803_151058_757` both reached DONE without error. Workflow revision
`000004-2ca` became ACTIVE at `2026-08-03T08:11:17.761770459Z` using
`919786098205-compute@developer.gserviceaccount.com`. A live Cloud Scheduler inventory found no
trigger for `v3-nightly-orchestrator`; this is intentional until Unit 6 exact-generation
production promotion, bounded ACK/reconciliation, and human-delivered completeness are closed.

## RQ-20260803-1425-daily-newpayment-archive
Status: REVIEWED
Reviewer: Codex (Boat authorized continuation toward unattended V3 and August mapped delivery)
Class: A
Artifact: `sql/ddl/060_v3_daily_newpayment_archive.sql`.
Opened: 2026-08-03T14:25:00+07:00

Review generic OPEN-period date gates, exact run identity, replay refusal, 56-column explicit
position, archive-ledger conservation, and archive-only GCS scope. Production interface delivery
must remain a separate exact-generation copy after object metadata/hash/row/header verification.

Initial dry-run `codex_dry_060_20260803_142448_870` processed 0 bytes. Self-review added explicit
`SAFE.PARSE_DATE IS NULL` rejection so the exporter cannot rely only on upstream validation;
post-fix dry-run `codex_dry_060_final_20260803_142552_307` also processed 0 bytes.

Verdict: **PASS SOURCE FOR DEPLOY AND ONE ARCHIVE CALL** — archive prefix only. GCS production
delivery and scheduler activation remain separate gates.

Runtime update: commit `1d58e82`; deploy `codex_deploy_060_20260803_142802_289`; archive CALL
`codex_call_060_archive_20260803_142831_277`; manifest
`codex_manifest_aug_20260803_143211_116`. Archive generation `1785742123427933`, SHA-256
`b0a3d4ba5bc951fd92ea57efa8d1e964c29f41c96ef186f532bb9e34f380e777`, 376,245 bytes,
584 rows, 56 ordered columns. **PASS ARCHIVE; production exact-byte copy awaits explicit gate.**

Production update: Boat approved the exact generation/row-count/destination. Create-only copy
produced generation `1785743970202194`, size 376,245, CRC32C `C/wY+w==`; guarded job
`codex_mark_delivered_20260803_150004_321` marked 584 rows and one manifest DELIVERED. First exact
Gmail search found no result; SAP pickup/ACK remains OPEN and must not be inferred from delivery.

## RQ-20260803-1412-unit5-balance-quarantine
Status: REVIEWED
Reviewer: Codex (Boat authorized incomplete rows to be skipped and named in daily notification)
Class: A
Artifact: `sql/ddl/059_v3_unit5_balance_hold.sql`.
Opened: 2026-08-03T14:11:00+07:00

Runtime diagnostic `job_VbDxm3XbVdwPSnzQqXBtcvk_NJz5` found 585 item-periods, no multirow,
negative, or near-double cases. Exactly one exceeds the established +/- THB 10 reconciliation
tolerance: `L78570443-V1` period 2, expected 2,126.27, actual 1,481.06, difference -645.21.

Verdict: **PASS SOURCE FOR DRY-RUN/DEPLOY/CALL** — quarantine only; it must conserve
candidate=delivery+hold, retain 56 columns, and copy every hold to notification detail with
order_item. It does not authorize export or GCS delivery until runtime verification passes.

Runtime update: commit `b477ea7`; deploy `codex_deploy_059_20260803_141225_942`; CALL
`codex_call_059_aug_20260803_141300_945`; verification `job_V3vA3db2MCZGzZkooqY34ArIrOOb`.
Result: 585 candidates = 584 delivery + 1 hold/notification, 56 columns, zero remaining balance
mismatches. **PASS RUNTIME; export remains a separate Class A unit.**

## RQ-20260803-1125-complete-insurance-group-master
Status: REVIEWED
Reviewer: Codex (Boat supplied the authoritative SAP master and authorized mapped August rows)
Class: A
Artifact: `sql/ddl/056_seed_nonmotor_insurance_group_exact_matches.sql`.
Opened: 2026-08-03T11:25:00+07:00

Review exact case-sensitive mapping only, preservation of the existing Health/Life identifiers,
RCB/RCL coverage, and continued fail-closed handling of unknown/ERROR/missing/ambiguous values.
Actual August diagnostic job `job_5HvoTxEjMt3ErEBdWo4WPY3zFqHV` found only Health: 3 events,
3 order_items, 3 orders, 542,165 satang; all three already resolve exactly once through the
approved registry. Dry-run estimate was 53,262,581 bytes and actual processing 38,714,761 bytes.

Seed dry-run `codex_dry_056_master_20260803_125408_999` ran at
`2026-08-03T05:54:09.0140196Z`–`05:54:09.8573373Z`, processed 116 bytes against the
21,474,836,480-byte ceiling.

Verdict: **PASS FOR EXACT-MASTER SEED DEPLOY** — seed configuration only. This does not itself
authorize a period transition, payload CALL, export, or GCS delivery; unknown values must remain
held and retain order_item in daily completeness notification detail.

Runtime update: seed job `codex_deploy_056_master_20260803_125546_884` reached `DONE`, error null,
processed 116 bytes and billed 10,485,760 bytes. Verification job
`job_ZalwSIQRVpw6nTOTNKUrOnAufglK` processed 1,618 bytes and confirmed 22 active rows = 11 master
groups × 2 file BUs, with zero overlapping approvals.

## RQ-20260802-2224-v3-unit5-newpayment-shadow
Status: REVIEWED
Reviewer: Codex (Boat waiver 2026-08-02; continue without Claude Code)
Class: A
Artifact: commit `5d0b8e5`; `sql/ddl/058_v3_unit5_newpayment_shadow.sql`.
Opened: 2026-08-02T22:24:41+07:00

Review exact event identity, exclusion of blocked CREATE, approved registry joins, OPEN-period date
behavior, 56-column positional projection, paid/date/PolicyNo guards, and separation of payload
metadata. `scripts/bq_safe_query.sh --dry-run-only` validated the complete DDL without execution;
the wrapper self-test passed 7/7 and the DDL dry-run reported 0 bytes.

Verdict: **PASS FOR NEW-OBJECT DEPLOY AND SHADOW CALL** — limited to V3 tables/procedure and the
585-row NEWPAYMENT shadow. No export, GCS write, scheduler change, or CREATE population is allowed.

Runtime update: definitions deployed by
`bqjob_r2312b18d2bd45b07_0000019fc314daed_1`. CALL
`bqjob_r727bd567f6867f45_0000019fc315935f_1` correctly stopped at the OPEN-period assertion before
persistent shadow writes; the verdict does not authorize bypassing that guard.

## RQ-20260802-2206-v3-unit5-source-coverage
Status: REVIEWED
Reviewer: Codex (Boat waiver 2026-08-02; continue without Claude Code)
Class: A
Artifact: commit `5d497ef`; Unit 5 top-up correction and payload-source coverage diagnostic.
Opened: 2026-08-02T22:06:16+07:00

This supersedes the earlier interpretation that CREATE payload size equals its 939-row schedule
spine. One CREATE item-period has two successful events, so the correct target is 940 rows and the
extra top-up must carry ExpectedReceived=0. Coverage job
`bqjob_r2c19c6bb74806981_0000019fc3011b2a_1` ran at
2026-08-02T15:04:18.378Z–15:04:45.511Z, processed 9,263,026,892 bytes and billed
9,295,626,240 bytes. NEWPAYMENT is exact 585/585; CREATE Pending is exact 772/772, while 159 Paid
CREATE targets lack an exact source variant.

Verdict: **PASS NEWPAYMENT INPUT / BLOCK CREATE PAYLOAD** — do not fabricate or schedule-dedup the
159 missing Paid rows. This verdict authorizes source work only, not deploy/export/GCS mutation.

## RQ-20260802-2141-v3-unit5-file-role-spine-gate
Status: REVIEWED
Reviewer: Codex (Boat waiver 2026-08-02; continue without Claude Code)
Class: A
Artifact: commit `5b31c57`; `sql/adhoc/20260802_unit5_file_role_population_gate.sql`.
Opened: 2026-08-02T21:41:20+07:00

Review the event-to-file grain split, SAP-existence role predicate, exact CREATE schedule spine,
Unit 3 hold exclusion, and conservation output. Evidence job
`bqjob_r64967cf1c5db4954_0000019fc2ea66f7_1` ran at
2026-08-02T14:39:30.400Z–14:39:38.906Z, processed 201,140,972 bytes and billed 265,289,728 bytes.
It returned 753 releasable events: CREATE 168/167 orders, NEWPAYMENT 585/583 orders; CREATE expands
to 939 schedule rows with zero bad spines.

Verdict: **PASS FOR UNIT 5 POPULATION INPUT** — this authorizes the explicit 56-column shadow
builder only. It does not authorize a persistent-object deploy, export, or GCS write.

## RQ-20260802-2123-v3-payment-mapping-seed
Status: REVIEWED
Reviewer: Codex (Boat waiver 2026-08-02; continue without Claude Code)
Class: A
Artifact: commit `9116359`; `sql/ddl/057_seed_payment_mappings_v2_success.sql`.
Opened: 2026-08-02T21:23:21+07:00

Verify that the seed contains only non-credit mappings already used by V2 and supported by the
recorded SAP-success evidence; Pending rows must not enter the payment mapping registry, and no
credit-shell default may be introduced. Runtime evidence: seed job
`bqjob_r3b616eb0badb2256_0000019fc2d7b990_1`; Unit 3 rerun
`bqjob_r5ef5a2bfeab12b59_0000019fc2d81cd1_1`; verification
`bqjob_r37153dd27598434c_0000019fc2d9407b_1` produced 753 releasable and 432 held READY events,
14 UNKNOWN rows, 446 notification rows, and zero release-gate blockers.

Verdict: **PASS FOR THE DEPLOYED NON-CREDIT SEED** — exact source tuples only; Pending remains
blank/outside the registry, credit-shell remains held, and no export or GCS write occurred.

## RQ-20260802-2006-v3-automation-release-gate
Status: REVIEWED
Reviewer: Codex (Boat waiver 2026-08-02; continue without Claude Code)
Class: A
Artifact: commits `c355d13` and `f053b51`; `sql/ddl/052_v3_unit3_closed_mapping_registries.sql`,
`sql/ddl/054_v3_automation_release_gate.sql`, `sql/ddl/055_v3_notification_quarantine.sql`, and
`sql/ddl/056_seed_nonmotor_insurance_group_exact_matches.sql`.
Opened: 2026-08-02T20:06:25+07:00

Review the Unit 3 run-summary conservation grain and the durable fail-closed boundary before Unit
5. Confirm absence of Unit 3 evaluation cannot masquerade as zero holds; duplicate hold reasons
collapse to one event; Unit 2 UNKNOWN, Unit 1 provenance, and exactly-one OPEN period all block;
and the artifact has no export, GCS, scheduler, SAP, or legacy-view side effect. Static diff check
passed. SQL dry-run was intentionally not executed because the mandatory wrapper has no
dry-run-only mode and executing it would deploy these source-only definitions.

Verdict: **PASS SOURCE / BLOCK DEPLOY UNTIL DRY-RUN AND EXPLICIT DEPLOY GATE** —
`docs/reviews/2026-08-02-f053b51-codex.md`.

## RQ-20260802-1945-v3-unit4-period-state
Status: REVIEWED
Reviewer: Codex (Claude credit unavailable)
Class: A
Artifact: `sql/ddl/053_v3_unit4_period_state_machine.sql` and
`sql/adhoc/20260802_unit4_period_state_rehearsal.sql`.
Opened: 2026-08-02T19:45:00+07:00

Verdict: **PASS FOR DEFINITION DEPLOY + ONE-TIME SEED; CLOSE CALL TIME-GATED** —
`docs/reviews/2026-08-02-unit4-period-state-codex.md`.

## RQ-20260802-1928-v3-unit3-closed-mappings
Status: REVIEWED
Reviewer: Codex (Claude credit unavailable)
Class: A
Artifact: `sql/ddl/011_stg_order_dim.sql`, `sql/ddl/013_stg_payment_events.sql`,
`sql/ddl/052_v3_unit3_closed_mapping_registries.sql`, and Unit 3 evidence queries.
Opened: 2026-08-02T19:28:00+07:00

Review raw-field preservation, effective-window overlap guards, approval evidence, mapping-key
completeness, fail-closed hold behavior, and absence of export/release side effects.

Verdict: **PASS FOR SOURCE / BLOCK DEPLOYMENT AND SEEDING** —
`docs/reviews/2026-08-02-unit3-registries-codex.md`.

## RQ-20260802-1708-v3-unit2-shadow-classifier
Status: REVIEWED
Reviewer: Codex (Claude credit unavailable; do not deploy until self-review verdict is recorded)
Class: A
Artifact: `sql/ddl/051_v3_unit2_shadow_classifier.sql`,
`sql/adhoc/20260802_unit2_grain_profile.sql`, and grain correction in
`docs/design/V3_AUTONOMY_UNITS_2_6_DESIGN.md`.
Opened: 2026-08-02T17:08:00+07:00

Review the two-population boundary, outcome precedence, immutable InvoiceNo/top-up hold, latest
archive winner, current-SAP joins, idempotent run replacement, and both record/amount conservation
assertions. Confirm the artifact remains shadow-only and cannot release a file. Live profile job
`bqjob_r6d33d86282ab4373_0000019fc1eb98b8_1` at 2026-08-02T10:01:11Z processed 178,696,000 bytes
(179,306,496 billed; cap 21,474,836,480): expected_state 290,258 rows/keys, qualified events
1,198,183 rows/keys, and only 167,754 expected rows joined a charge. DDL dry-run passed; no deploy
or CALL occurred.

Verdict: **PASS FOR SHADOW DEPLOYMENT ONLY** —
`docs/reviews/2026-08-02-unit2-shadow-codex.md`. File release remains blocked by the measured
distribution, unknown-outcome and magnitude-threshold gates, plus row-level ACK chronology.

## RQ-20260802-1230-orchestrator-unit1-source
Status: REVIEWED
Reviewer: Codex
Class: A
Artifact: `infra/v3_nightly_orchestrator.workflows.yaml` and
`docs/design/V3_ORCHESTRATOR_UNIT1_RUNBOOK.md` (new, this commit).
Opened: 2026-08-02T12:30:00+07:00

BLOCK answer (one round, this commit): F1 — `body:{}` + explicit connector timeout added; both
operation name AND completed Execution resource recorded. F2 — new `verify_load_commitment`
subworkflow: exactly-one DONE LOAD job into SAP_LIVE in the run window via INFORMATION_SCHEMA,
then jobs.get for outputRows/badRecords/errorResult/sourceUris matched to the observed bronze
object; zero/multiple/mismatch/badRecords>0 all fail closed; outputRows lands in rows_out. F3 —
`HEALTHY_ZERO` now requires reading the extract control object (alt=media, OAuth2) and gating
caught_up==true AND watermark strictly advanced past the pre-run value; re-entry runs can never
declare health; control-object name must be pinned at deploy review (runbook 2b). F4 — run-log
rows now use SUCCESS|FAILED only, counts in rows_out, summary text in error_message per the 025
convention. F5 — mutating CALLs via jobs.insert with deterministic jobId + poll jobs.get to
terminal state; deadline → cancel + verify post-cancel state; jobComplete=false can no longer
strand a mutation.

Delta verdict: **BLOCK UPHELD — ESCALATE BOAT** —
`docs/reviews/2026-08-02-e986699-codex.md`. The generated BigQuery job IDs contain forbidden `:`
characters from run_id, and cancellation is checked only once rather than polled to terminal state.
Per the one-round rule, do not start a third agent round without Boat's direction.

Boat decision 2026-08-02: **reviewer correction approved**. Unit 1 source must (a) sanitize or
generate BigQuery job IDs containing only permitted characters (no `:`), and (b) poll after
`jobs.cancel` until the BigQuery job reaches terminal `DONE`, recording terminal status/error
evidence before the workflow exits. This resolves the escalation direction but does not clear the
BLOCK; corrected source still requires Codex delta review. No deploy is authorized.

Execution override 2026-08-02: Boat instructed Codex to execute without waiting for Claude review
because Claude credit is unavailable. Codex implemented both approved corrections plus the
live-evidenced control/log schema and recorded self-verification in
`docs/reviews/2026-08-02-unit1-codex-self-verification.md`. This is a scoped waiver for Unit 1 only;
pre-deploy/runtime gates remain mandatory and deployment evidence must be reported separately.

Original claim: source-only Cloud Workflows definition for P0 unit 1 per the 2026-08-02 handoff. Anchors on
executing `sap-extract-job` itself (run.v2, auto-polled) — never a wall clock; pre/post bronze
census with >1-object hard stops and generation+md5 capture; at-most-one loader trigger with a
polling wait that fails closed on timeout or a second object and never retriggers; mirror doc/state
refresh as two separately capped dry-run-first BigQuery jobs (the 2026-08-01 cumulative-cap
lesson); every transition writes `pipeline_run_log` via parameterized queries; every failure
records, publishes to `v3-orchestrator-alerts`, then raises — alert-publish failure still raises.
Healthy-zero nights skip the loader and still refresh the mirror (§3.6 semantics). Units 2–5 chain
from `UNIT1_COMPLETE`. Nothing deployed; Claude Code cannot deploy under the acknowledged
single-deployer boundary.

Evidence: static design only — Workflows YAML cannot be dry-run without deployment, which is
Codex's step. Request: verify connector call shapes/auto-polling semantics (`run.v2 jobs.run`,
`cloudscheduler jobs.run`, `bigquery jobs.query` with NAMED parameters, `storage objects.list`,
`pubsub publish`), the fail-closed ordering in `fail_closed` (record → alert → raise, log-write
swallowed but alert failure not), the cutover double-run hazard handling in the runbook, and the
explicit non-goals. Deploy requires Codex review PASS + Boat's scoped production gate.

Verdict: **BLOCK** — `docs/reviews/2026-08-02-26a1390-codex.md`. Required fixes: add required
Cloud Run request body and real execution provenance; prove exactly one matching BigQuery LOAD job
instead of treating bronze deletion as commitment; require success+watermark+`caught_up` for
healthy zero; align `pipeline_run_log` status/provenance; and poll mutating BigQuery jobs to a
terminal state before fail/replay.

## RQ-20260802-1210-cancel-track-boundaries
Status: REVIEWED
Reviewer: Claude Code
Class: A
Artifact: commit `2b06115`; `docs/design/CANCEL_CHANGE_CREDITSHELL_TRACK_V3.md`,
`docs/design/CHANGE_ORDER_FLOW_V3.md`, and
`docs/FINDINGS_CHANGE_ORDER_PREFLIGHT_20260802.md`.
Opened: 2026-08-02T12:10:06+07:00
Verdict: PASS — `docs/reviews/2026-08-02-2b06115-claude.md` (all three 86356a8 notes closed
exactly: literal pinned character-identical to the 002/025-recognized string; populations disjoint
by definition with cross-routing prohibited both ways in both docs; status-inventory gate keeps
unknown case variants fail-closed. 92 remain non-citable; docs-only confirmed. Next: preflight
rerun with status inventory + recount under the Paid/Pending gate)
Claim: closes NOTES 1–3 from review `89fac7e` without changing executable SQL. It pins linked
change-order cancellation to `Cancelled (Change order / Rejected)`, defines a disjoint unlinked
plain-cancel skeleton using `Cancelled` with no mapping/credit-shell, forbids cross-routing, and
requires the next rerun to report the distinct SAP status inventory before accepting additional
case variants. The prior 92 candidates remain non-citable. Verify exact literal consistency,
population disjointness, and that no payload/deploy authority is implied.

## RQ-20260802-cancel-old-status-gate
Status: REVIEWED
Reviewer: Claude Code
Class: A
Artifact: delta in `sql/adhoc/20260802_change_order_preflight.sql` and interpretation correction in
`docs/design/CANCEL_CHANGE_CREDITSHELL_TRACK_V3.md` / change-order finding.
Opened: 2026-08-02T11:08:00+07:00
Verdict: PASS WITH NOTES — `docs/reviews/2026-08-02-86356a8-claude.md` (literal RULE-21/22 reading
correct; gate precedence right — terminal label wins before the residual-status hold; NULL trap
explicitly dodged; 92 non-citable until rerun. Prior stricter interpretation PASSed in a52b495 was
fail-closed and is disclosed, no rework. NOTE 1: pin the track's Cancelled literal —
'Cancelled (Change order / Rejected)' — it vanished from the edited doc. NOTE 2 [Boat's question]:
plain-cancel vs CancelChange is separated BY CONSTRUCTION (population = change links only) but the
boundary is undocumented — add the explicit boundary + a separate plain-cancel track skeleton
(literal 'Cancelled', no mapping, no credit-shell) and forbid cross-routing. NOTE 3: rerun should
report the distinct status inventory to evidence the literal set)
Claim: implements Boat's RULE-21/22 literally: every old SAP winner being cancelled must be
Paid/Pending; replacement mapping is deferred to credit-shell and does not block cancel cloning.
Verify CASE precedence, NULL handling, and that the prior 92 remain non-citable until rerun.

## RQ-20260802-cancel-change-creditshell-track
Status: REVIEWED
Reviewer: Claude Code
Class: A
Artifact: `docs/design/CANCEL_CHANGE_CREDITSHELL_TRACK_V3.md`, hardened-run addendum in
`docs/FINDINGS_CHANGE_ORDER_PREFLIGHT_20260802.md`, and required RULE-02 supersession.
Opened: 2026-08-02T11:04:00+07:00
Verdict: PASS — `docs/reviews/2026-08-02-a52b495-claude.md` (hardened rerun conserves at 28,341
AND the redistribution reconciles exactly — 7,462 drained = 7,457 ambiguous + 5 conflicts; item-map
strategies all conserve on 482 with max 36% unique → auto-cancel correctly prohibited; the 92
correctly downgraded under RULE-21; state machine ordering enforces Paid-ACK→cancel→cancel-ACK→
credit-shell; all three notes from the RULE-21–30 review closed in this commit)
Claim: inventories legacy tracks without calling them V3-ready; records hardened preflight and
item-map provenance; downgrades the 92 order-level READY pairs under RULE-21; and defines
cancel/change before credit-shell as an ACK-gated state machine. Verify mapping evidence,
population boundaries, ordering gates, and that no deploy/export/production mutation is implied.

## RQ-20260802-monthly-delta-rules-21-30
Status: REVIEWED
Reviewer: Claude Code
Class: A
Artifact: `docs/knowledge/SAP_INTERFACE_VALIDATION_RULES.md`,
`docs/design/MONTHLY_DELTA_OPERATING_MODEL_V3.md`, and
`docs/FINDINGS_IMPORT_RESULT_21153_20260802.md`.
Opened: 2026-08-02T10:15:00+07:00
Verdict: PASS WITH NOTES — `docs/reviews/2026-08-02-2d9b716-claude.md`. All five checks pass; the
delta-classification line (same InvoiceNo = no-op, different = human hold) closes the 21153 defect
at root; 21153 arithmetic exact and epistemics excellent. NOTE 1 (required): rule 26 changes
RULE-02 (real-run-date-capped vs last_day-always) — add the explicit supersession line in
CURRENT_STATE §1. NOTE 2: state error-count grain (17,760 instances vs 15,843 rows). NOTE 3:
mojibake root cause needs an owner beyond rule-28 symptom holds. NOTE 4: reviewer disclosure — the
missing SAP-state classification shipped through my 048 reviews; population-magnitude
reconciliation proposed as a standing protocol gate.
Claim: records Boat's RULE-21–30 milestone, separates manual July cover from the reusable monthly
delta design, retains Upload LogID 21153 evidence without PII, and defines the future implementation
increments. Review period-transition semantics, Paid-before-cancel ordering, NonMotor
InsuranceGroup hold, closed payment mappings, and exact daily conservation. Docs/design only; no
deploy, CALL, export, bucket write, or production mutation.

## RQ-20260802-change-order-hardening
Status: REVIEWED
Reviewer: Claude Code
Class: A
Artifact: delta after `d628ce8` in `sql/adhoc/20260802_change_order_preflight.sql` plus
`docs/FINDINGS_CHANGE_ORDER_PREFLIGHT_20260802.md`.
Opened: 2026-08-02T09:43:00+07:00
Verdict: PASS — `docs/reviews/2026-08-02-233ad5f-claude.md` (both notes implemented with correct
grain and CASE precedence — ambiguity first, versions-conflict before spine; status counts sum to
exactly 28,341; 93 READY correctly provisional with the first job retained as provenance; hardened
script re-validated by dry-run. Next: hardened rerun, then item-level mapping proof)
Claim: implements review NOTES 2–3 as fail-closed `HOLD_LINK_AMBIGUOUS` and
`HOLD_SAP_TOTAL_PERIODS_CONFLICT`; records the first reviewed run's exact job provenance and all
28,341 pair counts. Please verify grain, CASE precedence, correlated link-degree counts, and that
the 93 READY result is explicitly provisional pending this delta's rerun. Source-only: no mutation.

## RQ-20260802-0932-change-order-preflight
Status: REVIEWED
Reviewer: Claude Code
Class: A
Artifact: commit `d628ce8`; `sql/adhoc/20260802_change_order_preflight.sql` and
`docs/design/CHANGE_ORDER_FLOW_V3.md`.
Opened: 2026-08-02T09:32:41+07:00
Verdict: PASS WITH NOTES — `docs/reviews/2026-08-02-d628ce8-claude.md` (all requested confirmations
hold: lane separation real in the SQL, 002b/224 out of scope, every hard gate implemented and
verified against the file, READY ≠ approval, zero mutation; full-script dry-run + live-column probe
clean. NOTE 1 fixed here: the original entry's non-standard header made this Class A request
invisible to review_status.sh — normalized; keep the parseable schema. NOTES 2–3: add
HOLD_LINK_AMBIGUOUS for multi-link ids and a TotalPeriods-versions hold, cheap hardening for the
next iteration)

Claim (original request): confirm that the source-only preflight correctly separates `CANCEL_OLD`,
`CREATE_REPLACEMENT`, and `CREDIT_SHELL_PAYMENT`; keeps INCIDENT-002b/unknown-cause populations
out of scope; enforces SAP presence, terminal-state, full-spine, immutable InvoiceNo, replacement
completeness, and July-only gates; and does not imply approval through
`READY_FOR_AWARE_FA_REVIEW`. Also verify BigQuery syntax and confirm that no production
mutation, CALL, export, or legacy-view change is present.

## RQ-20260802-0528-july-contract-item-quarantine
Status: REVIEWED
Reviewer: Claude Code
Class: A
Artifact: commit `03b0381` — delta to `sql/ddl/048_july_export_shadow_and_archive.sql`.
Opened: 2026-08-02T05:28:35+07:00
Verdict: PASS — `docs/reviews/2026-08-02-03b0381-claude.md` incl. addendum covering follow-up
`4da3ca8` (BatchRunDate gate: defense-in-depth against the RQ-0515 NOTE-2 wrapper leak; verdict
unchanged). (multi-reason counting uses DISTINCT
keys in conservation — no double-count; grain consistent via expected_state key-uniqueness; MERGE
idempotent on the proven pattern; invalid rows double-blocked — NOT EXISTS at materialization plus
the original zero-error asserts still run on final ready. RQ-0515 NOTE 1 also closed by 393f9e3.
Shadow can now reach a clean build: 831 covered + 222 coverage holds + 3 contract quarantines,
all conserved and auditable)

Follow-up commit `4da3ca8` adds Boat's explicit BatchRunDate gate: non-empty, valid DDMMYYYY, and
not later than 2026-07-31. The generated value remains `31072026`; this prevents the separate live
fully-paid wrapper's NULL BatchRunDate defect from leaking into the V3 July file. Follow-up file
dry-run passed at 0 bytes.

Production shadow job `call_048_july_shadow_retry_20260802_052700` passed coverage/hold gates but
correctly stopped on F2. Diagnostic `diag_048_shadow_validation_20260802_052900` found exactly
three PolicyNo-too-long records/orders and zero date-format or Paid-completeness failures. This
delta implements the confirmed item-level quarantine policy: build a temporary 56-column
candidate, record F2/F3/completeness failures in `july_export_hold`, materialize only valid rows,
then assert final conservation and re-run all zero-error assertions. No truncation and no silent
drop. File dry-run passed at 0 bytes. Please verify multi-reason key counting, conservation grain,
MERGE idempotency, and that invalid rows cannot enter `july_export_ready`.

## RQ-20260802-0515-v3-onetime-payload-and-hold
Status: REVIEWED
Reviewer: Claude Code
Class: A
Artifact: commit `296cdda` — `sql/ddl/050_v3_onetime_payload_source.sql` and delta to
`sql/ddl/048_july_export_shadow_and_archive.sql`.
Opened: 2026-08-02T05:15:29+07:00
Verdict: PASS WITH NOTES — `docs/reviews/2026-08-02-296cdda-claude.md`. Baseline delta verified
mechanically against the LIVE definition (98.2% identical, 6 hunks): declared deviations check out;
holds/conservation/no-unclassified all fail-closed; arithmetic 831+222=1,053 exact; change-order
boundary double-enforced. NOTE 1 (required pre-deploy): a third, undeclared deviation exists — 050
drops the live view's outer RULE-02 hotfix wrapper (correct to drop, must be declared). NOTE 2
(separate live defect, legacy lane): that live wrapper parses an ISO literal with %d%m%Y —
always NULL — so production fully_paid currently emits NULL BatchRunDate to every other consumer;
Boat decision: fix literal to '31072026' or revert the hotfix. 050/048 unaffected.

CALL `call_048_july_shadow_20260802_045000` correctly failed with 1,053 eligible rows lacking a
verified payload. Temporary semantic test `test_050_coverage_retry_20260802_051400` proves the
new source covers 829 CREDIT_CARD_INSTALLMENT and two old-policy FULL_PAYMENT rows while retaining
the legacy change-order exclusion. Follow-up `test_050_remaining_gap_20260802_051600` classifies
221 remaining rows as change orders and one as RCL_CMI without a verified payload. 048 now records
only those two explicit hold reasons, fails on every unclassified gap, and asserts population
conservation (`eligible_all = export + audited hold`). Combined 050→048 file dry-run passed at
0 bytes. Please verify the source-baseline delta, latest-snapshot de-fanout, 56-column ordinal/type
contract, change-order boundary, RCL_CMI hold, and that no unclassified row can reach export.

## RQ-20260802-0149-validation-legacy-decoupling-delta
Status: REVIEWED
Reviewer: Claude Code
Class: A
Artifact: commit `6211299` — `sql/ddl/035_policyno_too_long_validation.sql` and
`sql/ddl/048_july_export_shadow_and_archive.sql`.
Opened: 2026-08-02T01:49:24+07:00
Verdict: PASS — `docs/reviews/2026-08-02-6211299-claude.md` (decoupling is the right architecture:
the failing view is the NO_BASELINE-flagged one — drift governance again; F2 survives at V3 grain
and F3/Paid-completeness now guard the actual export payload before side effects; both new 035
statements gate-validated with real semantic estimates; UNPIVOT NULL-dropping is semantically
correct here — NULL ≡ allowed empty. Boundary recorded: file-grain F3 is per-export-gate now;
future flows must carry their own asserts)

Production evidence contradicts the prior PASS for 035: CALL job
`v3full_validation_20260802_015700` failed because live
`sap_view.RCL_Motor_process_2_newpayment` cannot parse its internal position-56 UNION
(`STRING` versus `DATE`). The delta removes all legacy `sap_view.*` dependencies from V3's
general validation procedure, retains `POLICYNO_TOO_LONG` at V3 grain by joining
`expected_state` to `stg_order_dim`, and moves the full 56-column F2/F3 blocking assertions to
048 immediately after `july_export_ready` is materialized. Both changed files pass BigQuery
dry-run at 0 bytes. Please verify no F2/F3 coverage regression, correct UNPIVOT semantics, and
that the export assertion executes before any archive/export side effect.

## RQ-20260801-2325-july-export-block-delta
Status: REVIEWED
Reviewer: Claude Code
Class: A
Artifact: BLOCK delta to 048/049 and `docs/design/V3_JULY_EXPORT_RUNBOOK_20260801.md`.
Opened: 2026-08-01T23:25:00+07:00
Verdict: PASS — `docs/reviews/2026-08-02-94ec0fc-claude.md`. **RQ-2241 and RQ-2243 BLOCKs cleared.**
Union fix gate-verified (9.1 GB semantic estimate vs the former position-22 hard error); 049 now
archive-only with the UAT2 mandatory stage + exact-byte promotion state machine (stronger than the
minimum asked); Paid-completeness/PolicyNo/DDMMYYYY asserts run before any side effect; 470f684's
direct qualification is correct given 013's incremental nature. Notes: delete the local UAT2 temp
copy after upload; export_archive schema changes need migration discipline once live.

Addresses RQ-2241/2243: both source branches now explicitly project and harmonize all 56 columns
before UNION; Paid completeness ASSERT added; duplicate winner scope clarified. 049 now writes only
to restricted archive. Runbook inserts mandatory UAT2 known-answer validation, explicit Boat/Aware
acceptance of the exact archive hash/generation, and server-side exact-byte copy to production;
manifest captures both generations/hash and SAP LogID acknowledgment.

Request reproduction of the former position-22 type failure, complete 56-position/type/order audit,
late-bound body checks, UAT2 sufficiency, archive bucket/path/PII controls, and exact-byte promotion
state machine. No deploy, CALL, UAT2 write, production write, or export occurred.

Follow-up before deploy: 048 now re-applies Order + exact OrderItem + PURCHASED-lead qualification
directly to the historical July export scope. This is necessary because 013 is an incremental MERGE
and does not retroactively delete old unqualified staging rows. Historical cleanup remains separate;
the July export no longer depends on it.

## RQ-20260801-2243-v3-july-production-runbook
Status: REVIEWED
Reviewer: Claude Code
Class: A
Artifact: `docs/design/V3_JULY_EXPORT_RUNBOOK_20260801.md`.
Opened: 2026-08-01T22:43:00+07:00
Verdict: BLOCK — `docs/reviews/2026-08-01-213626c-claude.md` (inherits RQ-2241: blocked scripts +
the runbook must add the missing UAT2 stage between shadow gate and production, plus the post-write
exact-byte archive step and SAP import-result acknowledgment capture. Deploy order, shadow
checklist, and no-blind-rerun guidance are sound and should survive the fix round unchanged)

Runbook sequences reviewed manual full refresh, 013/035/048/049 deploy dependencies, shadow hard
gate, one production GCS write, three-layer Gmail evidence, and mirror reconciliation. Confirm it
cannot proceed on coverage gap, August raw date, validation failure, duplicate archive key, missing
active July period, or ambiguous PREPARED-after-export state. No production action occurred.

## RQ-20260801-2241-july-shadow-export-structure
Status: REVIEWED
Reviewer: Claude Code
Class: A
Artifact: `sql/ddl/048_july_export_shadow_and_archive.sql` and
`sql/ddl/049_export_july_payment_to_gcs.sql`.
Opened: 2026-08-01T22:41:00+07:00
Verdict: BLOCK — `docs/reviews/2026-08-01-73f7c08-claude.md`. (1) CONFIRMED: `SELECT *` UNION of
the two source views fails — "Column 22 in UNION ALL has incompatible types: STRING, DOUBLE"
(0-byte repro; position 22 = GrossPremium, the first known drift position); fix = explicit 56-column
per-branch projection with harmonized types. (2) G3 skipped: no UAT2 pass before production
RCB_MOTOR while header/quoting/NULL-money rendering are unverified against the unknown legacy
serializer. Also required: post-write exact-byte archive (object copy + generation + hash) — row
JSON is value-level only; rule-12 completeness ASSERTs. 56-column output order verified exact;
scope/idempotency/fail-closed gates otherwise sound.

Source-only structure prepared while earlier reviews run. 048 selects only Paid rows whose raw
charge_time is in `[2026-07-01,2026-08-01)`, excludes delivered keys, deterministically resolves
the two 56-column sources, fails if any July key lacks payload, emits exactly the contract order,
and locks BatchRunDate to 31072026. 049 calls 048, persists exact row JSON/hash as PREPARED, asserts
zero August, exports one explicit 56-column CSV to Boat-authorized RCB_MOTOR, then marks DELIVERED.

Request deep review of late-bound procedure bodies, source UNION type drift, duplicate winner,
money formatting, variable/column scoping, archive-before-export failure recovery, positional
contract, raw-date scope, filename/ImportType, and whether BigQuery row JSON is sufficient durable
audit pending exact-byte GCS archive. 048 file-level dry-run passed; 049 dry-run is dependency-
blocked until 048 exists live and must not be deployed/CALLed on that basis. No production action.

## RQ-20260801-2236-phaseb-uncovered-refresh
Status: REVIEWED
Reviewer: Claude Code
Class: A
Artifact: `sql/adhoc/20260801_phaseb_uncovered_classification.sql` and
`docs/FINDINGS_PHASEB_UNCOVERED_20260801.md`.
Opened: 2026-08-01T22:36:00+07:00
Verdict: PASS — `docs/reviews/2026-08-01-8255891-claude.md` (arithmetic closes on every axis;
output-vs-raw date distinction correctly drawn; the 12,395 Paid/absent class plausibly overlaps the
70,395 disqualified charges — re-measure after Rule-2 staging deploys and quote that number in the
048 gap-gate expectation)

Current expected_state yields 12,689 uncovered records, superseding 13,659. The dominant class is
12,395 Paid keys absent from both 56-column sources; 278 are no-charge Pending spine and 16 are
period-missing. Fifty-four rows have August *output* PaymentDate and are explicitly not called raw
PaymentDate. Request reproduction/method review and confirmation that Phase-B payload remains
blocked until qualification refresh/re-measurement. No deploy, CALL, export, or GCS write.

## RQ-20260801-2233-interface-validation-block-delta
Status: REVIEWED
Reviewer: Claude Code
Class: A
Artifact: BLOCK delta to `sql/ddl/013_stg_payment_events.sql`,
`sql/ddl/035_policyno_too_long_validation.sql`, canonical knowledge, and
`docs/FINDINGS_PAYMENT_QUALIFICATION_20260801.md`.
Opened: 2026-08-01T22:33:00+07:00
Verdict: PASS — `docs/reviews/2026-08-01-fc9a78a-claude.md`. **RQ-2205 BLOCK cleared**: JSON-array
comparison gate-validated (8,682,609-byte semantic estimate); impact measured (70,395 = 52,828 +
17,567 ✓) and preserved at charge grain in sap_payment_qualification_exclusion; all four doc notes
closed including the unprompted TotalPeriods-versions check.

Addresses `docs/reviews/2026-08-01-91134c9-claude.md`: ARRAY inequality replaced by deterministic
JSON-array comparison; NULL/inconsistent TotalPeriods are self-describing. Rule-2 impact measured:
1,127,882 qualified; 52,828 lead-not-purchased/unresolved; 17,567 no-order; zero no-item/empty-ID.
Source 013 now preserves every excluded successful charge in a charge-grain audit table rather
than silently dropping it. Both files pass file-level dry-run; request CALL-shape/static re-review,
join/fan-out audit, taxonomy review, and confirmation both BLOCKs plus four notes are closed.
No deploy, CALL, export, GCS write, or production mutation occurred.

## RQ-20260801-2228-v3-export-readiness-block
Status: REVIEWED
Reviewer: Claude Code
Class: A
Artifact: `docs/FINDINGS_V3_EXPORT_READINESS_20260801.md`.
Opened: 2026-08-01T22:28:00+07:00
Verdict: PASS — `docs/reviews/2026-08-01-export-readiness-claude.md` (fail-closed stop was
correct; all four gate failures metadata-backed; Gmail correctly scoped as baseline; the
required-before-retry list has since materialized as 048/049/runbook, reviewed under RQ-2241/2243)

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

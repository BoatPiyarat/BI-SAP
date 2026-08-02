# Review scorecard

Measurement window starts 2026-07-29; revisit 2026-08-12. Cost is approximate and excludes the
author's original implementation work.

| Reviewer | Reviews performed | BLOCKs raised | BLOCKs upheld | Reviewer-caught issues | Missed-review rework | Author self-caught | Approx. review cost |
|---|---:|---:|---:|---:|---:|---:|---|
| Codex | 9 | 8 | 1 resolved after evidence; 4 supersession BLOCKs; H4, `84df583`, and `a56f6d1` pending | 6863 evidence controls; H4 denominator/status; symptom-vs-cause; incomplete FA control; safe-query fail-open parser/ineffective force | 0 | 0 | Artifact-only; no reviewer query used for D13–D16 or wrapper review |
| Claude Code | 56 | 5 | 1 (043 — both items reproduced/confirmed, fixes proposed, resolved by author in one round: `6ef690b`) — but see rework column | Stale-claim timing risk in `0c74639`; missing-attachment fallback gap in `eb93ef6`; independently reproduced `e02bd39`'s daily-loss table byte-for-byte rather than only reading it; metadata-exposure claim vs verified `secretKeyRef` state + stale rotation status in `935ac8f`; 043 analytic-in-aggregate watermark + TIMESTAMP/DATE mismatch (both CALL-time, invisible to dry-run) | **2 — (a) `6ef690b` re-review passed "DATE chain complete" while 4 WHERE predicates still compared TIMESTAMP vs DATE (caught by Boat); (b) 048's missing current-SAP-state classification shipped through review and surfaced as 21153's 52% reject rate — contained by SAP immutability, self-disclosed, population-magnitude reconciliation proposed as standing gate** | 2 | Artifact review; self-caught Gmail threading and missing dry-run; one review (`e02bd39`) corroborated via a query already run for unrelated same-session work; 2026-08-01 batch used zero billed bytes total (4 schema metadata calls + 1 standalone 0-byte dry-run repro + offline self-test re-run) |
| External — FA (Mo) | 1 | 1 | 1 | Caught posted-vs-rejected population error: `L80524847` had no JE | 0 | 0 | Business/SAP evidence review |

**First-round protocol result:** 1 substantive BLOCK raised by Codex, 2 PASS reviews by Claude
Code, and 2 Claude self-caught errors. The original BLOCK identified 3 real evidence/control gaps;
review is not ceremonial. Subsequent re-check passed `6863dc8`; H4 opened a new BLOCK on unsupported
denominators.

**2026-07-30 evening — Claude Code cleared 6 assigned OPEN reviews** (`e02bd39`, `5774494`,
`d1310f9`, `b56683c`, `258f0c7`, `eb93ef6`): 5 PASS, 1 PASS WITH NOTES (`eb93ef6`, missing-attachment
fallback not specified). Zero BLOCKs raised — flagging this honestly rather than treating it as a
clean bill of health: per this scorecard's own "if a reviewer raises zero BLOCKs for two weeks, the
review is theatre" rule, this is a **single round**, not two weeks, and the artifacts reviewed were
themselves already self-correcting (retractions, superseded-number warnings) before reaching review
— genuine issues were repeatedly caught by the *authors* this round, which is a different thing from
the reviews having no teeth. Watch this line if zero-BLOCK rounds continue.

## Review log

| Date | Artifact | Class | Reviewer | Verdict | Notes |
|---|---|---|---|---|---|
| 2026-07-29 | `6863dc8` | A | Codex | BLOCK | Missing exact query/timestamp, rollback command, and dry-run evidence |
| 2026-07-29 | `6863dc8` author response | A | Codex | PASS | Evidence completed; missing pre-`CALL` dry-run acknowledged |
| 2026-07-29 | `0c74639` + `7e98d39` | A | Claude Code | PASS | Final pair correct; stale first commit noted |
| 2026-07-29 | `d69572f` | A | Claude Code | PASS | Review governance aligned |
| 2026-07-29 | H4 baseline (`71c7afd`) | A | Codex | BLOCK | 5/5 claim unsupported for all named files |
| 2026-07-30 | D13–D15 correction population | A | FA (Mo), external | BLOCK | Error XLSX was misused as posted evidence; 559/71 and amount totals superseded pending posted-only split |
| 2026-07-30 | `5171adb` | A | Codex | BLOCK | Mirror presence overstated as real SAP; symptom population superseded |
| 2026-07-30 | `4bbc16f` | A | Codex | BLOCK | 559/70 derived from symptom; rejected case used as posted known-answer |
| 2026-07-30 | `9e6b44d` | A | Codex | BLOCK | Population/pilots superseded; Method 1 algebra retained only after cause gate |
| 2026-07-30 | `3c10215` | A | Codex | BLOCK | Combined-generator framing superseded; onetime remains separate finding |
| 2026-07-30 | `42b7c0a` | A | Codex | PASS WITH NOTES | D16 methodology correction valid; exact query metadata and key-level SAP reconciliation remain open |
| 2026-07-30 | `84df583` | A | Codex | BLOCK | 401 population is heterogeneous; `sap_fa_verification` omits required evidence fields; pilot lacks durable FA/SAP acceptance |
| 2026-07-30 | `a56f6d1` | A | Codex | BLOCK | Missing byte field fails open as zero; `--force` remains capped at 20 GiB and cannot work as documented |
| 2026-07-30 | `eb93ef6` | A | Claude Code | PASS WITH NOTES | Attachment-first design sound; no fallback specified for LogID-present-but-attachment-missing |
| 2026-07-30 | `258f0c7` | A | Claude Code | PASS | Correctly caught H4's unsupported 5/5 claim; scorecard citations spot-checked to exist |
| 2026-07-30 | `b56683c` | A | Claude Code | PASS | `L80524847` posted-state correction independently corroborated (zero `sap_mirror_doc` rows, confirmed separately this session) |
| 2026-07-30 | `e02bd39` | A | Claude Code | PASS | Daily amplification table independently reproduced byte-for-byte, ~6h apart |
| 2026-07-30 | `5774494` | A | Claude Code | PASS | Dormant-view closure correctly grounded in Boat's own confirmation, not agent inference |
| 2026-07-30 | `d1310f9` | A | Claude Code | PASS | Strong self-retraction discipline (§B); flagged the still-unlocated 297,413/297,604 figure as a separate open provenance gap, not a defect in this commit |
| 2026-07-31 | `16cddd8`+`935ac8f` | A | Claude Code | PASS WITH NOTES | Evidence fold sound; caught security-finding metadata-exposure claim conflicting with 07-31 verified `secretKeyRef` binding (R9) + stale OPEN-rotate status after rotation CLOSED — reconciliation addendum required |
| 2026-08-01 | `2c96c53` (024/025/037/044) | A | Claude Code | PASS WITH NOTES | All five §2.5 checks verified mechanically + against live shard schemas (UpdateDate=TIMESTAMP→DATE, UpdateTime=INT64); 8-consumer blast radius clean; notes on inert DocEntry tiebreak, unguarded MAX(open_period_start), open R13 date-basis alignment |
| 2026-08-01 | `1a52222` | A | Claude Code | PASS | Scheduler 401→200 evidence attributable and consistent; stale header verification anchor noted |
| 2026-08-01 | `f74f605` | A | Claude Code | PASS | Full job provenance; author self-corrected G1 post-exclusion provenance with a targeted job; re-run condition noted if date_basis changes |
| 2026-08-01 | `043` (`9a3e462`+`2c96c53`) | A | Claude Code | **BLOCK** | Two CONFIRMED CALL-time failures dry-run cannot catch: analytic-in-aggregate watermark SET (reproduced standalone) + TIMESTAMP delta into post-024 DATE column; fixes proposed; column lists verified 59/59 + 58/58 |
| 2026-08-01 | `93e87ea` | A | Claude Code | PASS WITH NOTES | Both a56f6d1 BLOCK findings resolved; self-test independently re-run 7/7 on fresh clone; self-review caveat recorded — Codex's session-note inspection is the reciprocal check |
| 2026-08-01 | `aba1aad` (RULE-09) | A | Claude Code | PASS WITH NOTES | Both gates verified; RULE-08 holds; full period-lock guard spec issued (lock_datetime never read; MAX() future/sequencing failure modes) |
| 2026-08-01 | `1f3e14a` | A | Claude Code | PASS | 12-producer table log-evidenced; runbook order + c67045a rollback anchor correct; SMTP addendum distinct from R9 |
| 2026-08-01 | `b10a22f` | A | Claude Code | PASS | D1/D2 arithmetic matches locked G1 exactly; 902/326 gaps bounded as view-side, disposition pending; D3 declared unavailable, not inferred |
| 2026-08-01 | `401cc98` | A | Claude Code | PASS | 22-position arithmetic verified (15+5+2); serializer-unknown blocker interlocks with RULE-10 gate; UAT2 known-answer compare noted |
| 2026-08-01 | `b00af18` (R1) | A | Claude Code | PASS | All 5 LOAD-job rows multiply exactly; un-retraction correctly scoped (watermark-reset stays retracted); 22–24 Jul mirror-loss caveat must ride with (ก)/(ง) numbers |
| 2026-08-01 | `2647350` | A | Claude Code | PASS WITH NOTES | Guard 1 threshold breaks after chunking fix — compare to reported chunk count; DLQ false-positive runbook line needed |
| 2026-08-01 | `c6b7b8b` | A | Claude Code | PASS | S1 schema gap direct; K1/K2/K3 provenance matches; no-expiration deviation routed to Boat; archive fail-closed |
| 2026-08-01 | `25fb58b` | A | Claude Code | PASS | Drift result independently reproduced (12 producers: 9 MATCH / 2 DRIFT / 1 NO_BASELINE — the 3 non-MATCH are exactly (ก)/(ง)-relevant views) |
| 2026-08-01 | `6ef690b` (043 fix) | A | Claude Code | PASS | Both BLOCK items resolved as specified; selector re-verified by 0-byte dry-run; RQ-2230 BLOCK cleared in one round |
| 2026-08-01 | `b881fa3` (037 guard) | A | Claude Code | PASS | All 3 guard-spec failure modes fail closed; exactly-one ASSERT stricter than spec on overlap — correct |
| 2026-08-01 | `2568eea` (042 FA contract) | A | Claude Code | PASS WITH NOTES | Evidence chains bypass-free; append-only verified repo-wide; dry-run independently reproduced; caught contradictory-NOT_FOUND gap (pre-deploy ASSERT) + 3 lesser notes |
| 2026-08-01 | `cb4cb29` (D16 002a split) | A | Claude Code | PASS | 191/67/10 verified; conservative shape precedence; 191 gated as diagnostic, not a 401 replacement; current-snapshot conditioning noted |
| 2026-08-01 | `7402acf` (UpdateDate comparison) | A | Claude Code | PASS | All deltas recomputed; append-history semantics correct; reviewer sharpened the −40/−64 buckets into a priority capture-gap target |
| 2026-08-01 | `1a289cd`+`b6bc1c3` (E1-E3/F1-F3) | A | Claude Code | PASS WITH NOTES | Boat's 3 confirmations verified from files; tier-delta passes downward-only structural check; taxonomy grep-verified |
| 2026-08-01 | `483fabc` (043 predicate delta) | A | Claude Code | PASS | Post-miss protocol: whole-file inventory + statement-level typed-literal dry-run gate proven both directions (fix passes at 7.3 GB semantic estimate; pre-fix fails negative control) |
| 2026-08-01 | `4fdebe7` (chain-1 deploy evidence) | A | Claude Code | PASS | Independent reconciliation exact: +9,393 = 9,318+75; the +50 dual-condition arrivals confirmed via two independent routes |
| 2026-08-01 | `5f8c17a` (042 NOTE 1/2 delta) | A | Claude Code | PASS | Both assertions match the requested spec verbatim; 042 schema deploy review-unblocked |
| 2026-08-01 | chain-3 gate failure evidence | A | Claude Code | PASS | Gate discipline correct; reviewer supplied diagnosis: symmetric 5,566/5,566 + equal totals = tie nondeterminism (predicted in 2c96c53 NOTE 1); deterministic-tiebreak remedy for 024+043 as one unit |
| 2026-08-01 | `1a8216f` (024+043 tiebreak) | A | Claude Code | PASS WITH NOTES | Hash tiebreak equivalence verified structurally + both selectors gate-validated; 8,538 measured tie population confirms the diagnosis; cross-source winner semantics flagged for a future source-priority decision |
| 2026-08-01 | 042 deploy evidence | A | Claude Code | PASS | Live objects independently re-verified (17 cols, partition/cluster, all 3 guards in live body) at 0 bytes |
| 2026-08-01 | 043 deterministic gate PASS evidence | A | Claude Code | PASS | Gate 0/0 verified; 025 delta semantically zero with exact cross-checks (1,296,900+3,330; 449+436=885 all NULL↔''); chain-3 declared technically ready for Boat repoint |
| 2026-08-01 | chain-2 RULE-03 evidence | A | Claude Code | PASS | +3,872 Boat-confirmed not self-accepted; ≤8,538 bound quoted; 025 observability intact; shared-037 verified-not-redeployed |
| 2026-08-01 | `849aa0e` (047 nightly repoint) | A | Claude Code | **BLOCK** | Live nightly body has an 11th call (interface_daily_status) missing from both 047's new body and its rollback — caught by live-routine diff, the drift-rule check; would survive rollback if deployed |
| 2026-08-01 | `6efcf1e` (047 delta) | A | Claude Code | PASS | BLOCK cleared in one round: rollback byte-identical to live 11-call body; new body = live + exactly the one intended swap |
| 2026-08-01 | `01e7b20` (047 repoint deploy) | A | Claude Code | PASS | Live body independently re-verified line-identical + SHA256 match; reviewer's own off-by-one call-count prose corrected in the open |
| 2026-08-01 | `d5917d0` (manual sync orchestrator) | A | Claude Code | PASS WITH NOTES | Fail-closed under all examined shapes; cap math + incremental-MERGE arithmetic verified exact; run_scope ADHOC labeling + schedule-window notes |
| 2026-08-01 | `e8b589a` (manual sync notes delta) | A | Claude Code | PASS | Both notes closed exactly; nothing else changed |
| 2026-08-01 | `97ebf0d` (Phase B coverage) | A | Claude Code | PASS | Three identities close exactly; corrected query structurally fan-out-proof; naive shadow DDL correctly blocked |
| 2026-08-01 | `91134c9`+ (validation canonical) | A | Claude Code | **BLOCK** | Confirmed ARRAY-inequality CALL-time failure in 035 (0-byte repro) + 013 money-bearing population change with no measurement/audit trail; doc itself sound with 4 precision notes |
| 2026-08-01 | `fc9a78a` (013/035 BLOCK delta) | A | Claude Code | PASS | RQ-2205 BLOCK cleared in one round; measurement + charge-grain audit table; statement gate-validated |
| 2026-08-01 | export-readiness stop | A | Claude Code | PASS | Fail-closed stop before GCS write was correct; all gate failures metadata-backed |
| 2026-08-01 | `8255891` (uncovered refresh) | A | Claude Code | PASS | Arithmetic closes on all axes; output-vs-raw date distinction correct |
| 2026-08-01 | `73f7c08` (048/049 export) | A | Claude Code | **BLOCK** | Confirmed UNION type failure at position 22 (repro) + G3/UAT2 skipped before production write; 56-column order verified exact |
| 2026-08-01 | `213626c` (July runbook) | A | Claude Code | **BLOCK** | Must add UAT2 stage + exact-byte archive + SAP-ack capture; rest sound |
| 2026-08-02 | `94ec0fc`+`470f684` (export delta) | A | Claude Code | PASS | Both BLOCKs cleared in one round; union gate-verified 9.1 GB; UAT2 + exact-byte promotion state machine exceeds minimum ask |
| 2026-08-02 | `6211299` (validation decoupling) | A | Claude Code | PASS | Right architecture after live legacy-view failure (the NO_BASELINE view); both new statements gate-validated; UNPIVOT NULL semantics verified correct |
| 2026-08-02 | `296cdda` (050 onetime payload + holds) | A | Claude Code | PASS WITH NOTES | Live-baseline delta verified mechanically; reviewer caught an undeclared deviation AND a live production defect (fully_paid wrapper emits NULL BatchRunDate — %d%m%Y vs ISO literal) |
| 2026-08-02 | `03b0381` (item quarantine) | A | Claude Code | PASS | DISTINCT-key conservation exact; double-enforced ready gate; 3 real PolicyNo quarantines handled per confirmed policy; NOTE-1 declaration closed |
| 2026-08-02 | `d628ce8` (change-order preflight) | A | Claude Code | PASS WITH NOTES | All gates verified vs file + live probes; caught non-standard queue header hiding a Class A request from the parser (normalized); 2 cheap hardening holds suggested |
| 2026-08-02 | `233ad5f` (preflight hardening) | A | Claude Code | PASS | Both notes implemented, precedence correct; 28,341 counts sum exact; 93 READY provisional |
| 2026-08-02 | `2d9b716` (RULE-21–30 + 21153) | A | Claude Code | PASS WITH NOTES | Five checks pass; RULE-02 supersession line required; error-count grain note; mojibake root-cause owner; reviewer self-disclosed the 048 population miss |
| 2026-08-02 | `a52b495` (cancel/creditshell track) | A | Claude Code | PASS | Double-exact reconciliation (28,341 + redistribution 7,462); 92 downgraded under RULE-21; all 3 prior notes closed in-commit |
| 2026-08-02 | `86356a8` (cancel-old status gate) | A | Claude Code | PASS WITH NOTES | Literal RULE-21/22 reading verified; NULL trap dodged; caught missing Cancelled literal + undocumented plain-cancel/CancelChange boundary (Boat's ask) |

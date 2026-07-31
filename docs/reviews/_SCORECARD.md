# Review scorecard

Measurement window starts 2026-07-29; revisit 2026-08-12. Cost is approximate and excludes the
author's original implementation work.

| Reviewer | Reviews performed | BLOCKs raised | BLOCKs upheld | Reviewer-caught issues | Missed-review rework | Author self-caught | Approx. review cost |
|---|---:|---:|---:|---:|---:|---:|---|
| Codex | 9 | 8 | 1 resolved after evidence; 4 supersession BLOCKs; H4, `84df583`, and `a56f6d1` pending | 6863 evidence controls; H4 denominator/status; symptom-vs-cause; incomplete FA control; safe-query fail-open parser/ineffective force | 0 | 0 | Artifact-only; no reviewer query used for D13–D16 or wrapper review |
| Claude Code | 9 | 0 | 0 | Stale-claim timing risk in `0c74639`; missing-attachment fallback gap in `eb93ef6`; independently reproduced `e02bd39`'s daily-loss table byte-for-byte rather than only reading it; metadata-exposure claim vs verified `secretKeyRef` state + stale rotation status in `935ac8f` | 0 | 2 | Artifact review; self-caught Gmail threading and missing dry-run; one review (`e02bd39`) corroborated via a query already run for unrelated same-session work, no extra cost; `935ac8f` review used zero queries |
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

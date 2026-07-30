# Review scorecard

Measurement window starts 2026-07-29; revisit 2026-08-12. Cost is approximate and excludes the
author's original implementation work.

| Reviewer | Reviews performed | BLOCKs raised | BLOCKs upheld | Reviewer-caught issues | Missed-review rework | Author self-caught | Approx. review cost |
|---|---:|---:|---:|---:|---:|---:|---|
| Codex | 7 | 6 | 1 resolved after evidence; 4 supersession BLOCKs; H4 pending | 6863 evidence controls; H4 denominator/status overstatement; symptom-vs-cause and SAP-posted provenance gaps | 0 | 0 | Artifact-only; no reviewer query used for D13–D16 |
| Claude Code | 2 | 0 | 0 | Stale-claim timing risk in `0c74639` | 0 | 2 | Artifact review; self-caught Gmail threading and missing dry-run |
| External — FA (Mo) | 1 | 1 | 1 | Caught posted-vs-rejected population error: `L80524847` had no JE | 0 | 0 | Business/SAP evidence review |

**First-round protocol result:** 1 substantive BLOCK raised by Codex, 2 PASS reviews by Claude
Code, and 2 Claude self-caught errors. The original BLOCK identified 3 real evidence/control gaps;
review is not ceremonial. Subsequent re-check passed `6863dc8`; H4 opened a new BLOCK on unsupported
denominators.

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

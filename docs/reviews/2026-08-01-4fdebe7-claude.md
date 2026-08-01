# Review — 4fdebe7 (Chain ① deploy evidence: E1–E3/F1, 032→036→037→CALL)

**Queue entry:** RQ-20260801-1417-chain1-deploy-evidence · **Class:** A · **Reviewer:** Claude Code
**Verdict:** **PASS**

## Handoff checklist (a)–(e) — all satisfied

(a) Register counts reported per NEW taxonomy; **zero rows under old codes** checked explicitly.
(b) Invalid 2025 rows in `expected_state` = 0 (dual condition holds live). (c) OrderDate ≤2024
leakage = 0. (d) `payment_date_clamped` = 164,817 with **zero** clamped rows landing on any date
other than `2026-07-01` — GREATEST/RULE-01 semantics exact against the July row. (e) Baselines
used correctly, including the elegant control that `expected_state` stayed at 298,278 after
CREATE OR REPLACE PROCEDURE but before CALL — proving procedure replacement alone refreshed nothing.

## Independent arithmetic reconciliation (reviewer's own, not in the evidence)

The register deltas close **exactly** against the `b6bc1c3` tier-transition measurements:
- `YEAR_OUT_OF_SCOPE` 789,501 − `OLD_YEAR_NO_TOUCH` 780,108 = **+9,393 = 9,318 (2025→≤2024) +
  75 (≥2026→≤2024)** — exact.
- `expected_state` −9,744 vs the downward-transition envelope 9,794 (= 9,719 + 75) implies **50**
  arrivals from the ≥2026→2025 transition satisfied the dual condition and stayed — and the same
  +50 reappears independently in the 2025-register balance
  (388,295 − [387,899 + 45] = +351 = net tier flow +401 − 50). Two routes, one number — the
  deploy's numbers are internally consistent to the row.
- `TEST_CUSTOMER` 347 = old `TEST_CUSTOMER_NAME` exactly ('test div' adds 0 rows);
  `INSURER_NOT_IN_MASTER` 3,172 unchanged; `TEST_CUSTOMER_PHONE` line retired as designed
  (was 341, report-only); `DATE_BASIS_MISSING` zero.

## Process quality

Dependency order 032→036→037 (beyond the handoff's bare 037) was the correct call — 037 reads
032's patterns/master and 036's `is_cancelled_effective`. Every step carries job ID + UTC interval
+ processed/billed under ceiling; all three ASSERTs passed on CALL; five definition markers
verified pre-CALL; F1 verified (InsuredID empty = 0; staging 758,786 = source = distinct). Scope
discipline: no export, no GCS write, no mirror-chain deployment inside this unit.

Note: clamped = 164,817 of 288,534 (57%) is high but coherent — RULE-01 pulls every pre-July
expected date in the open period to `01072026`; FA should see this framed as period alignment,
not as 164,817 corrections.

Queries used: 0 (evidence-table arithmetic + cross-commit reconciliation).

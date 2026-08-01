# Chain 3 / DDL 043 retry evidence — 2026-08-01

Status: **HARD GATE FAILED — NO REPOINT**

The corrected DATE-domain predicates from commit `483fabc` received Class A PASS in
`docs/reviews/2026-08-01-483fabc-claude.md`. Codex redeployed the reviewed procedure, rebuilt the
024 full mirror immediately before the comparison, then ran the incremental full catch-up and a
bidirectional row-for-row `EXCEPT DISTINCT` comparison in one BigQuery script.

## Jobs

| Step | Job ID | UTC interval | Processed bytes | Billed bytes | Result |
|---|---|---:|---:|---:|---|
| Redeploy corrected 043 | `deploy_043_predicate_fix_20260801_150500` | 2026-08-01T08:05:03.426Z–08:05:04.561Z | 0 | 0 | DONE |
| Fresh 024 baseline | `refresh_024_fresh_diff_retry_20260801_150520` | 2026-08-01T08:05:21.140Z–08:05:32.085Z | 7,319,841,706 | 7,320,109,056 | DONE |
| 043 catch-up + diff | `gate_043_row_for_row_retry_20260801_150610` | 2026-08-01T08:06:09.801Z–08:06:51.148Z | 13,152,199,558 | 13,175,357,440 | DONE, gate failed |

All three production queries were preceded by successful dry runs and used
`--location=asia-southeast1 --maximum_bytes_billed=21474836480`.

## Hard-gate result

| Metric | Result |
|---|---:|
| Fresh 024 rows | 1,662,648 |
| Incremental rows | 1,662,648 |
| Rows only in fresh 024 | 5,566 |
| Rows only in incremental | 5,566 |
| Watermark rows | 1 |
| Watermark date/time after successful catch-up | 2026-08-01 / 809 |

Equal counts are not equivalence. The symmetric 5,566-row content difference fails the mandatory
row-for-row gate. Root cause is not yet established. The nightly chain was **not repointed**.
No further CALL was made after the failed comparison, and no claim of 043 losslessness is valid.

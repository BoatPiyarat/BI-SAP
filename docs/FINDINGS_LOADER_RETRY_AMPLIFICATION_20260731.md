# R1 confirmed — loader retry commits amplify SAP_LIVE

Status: **CONFIRMED — leading explanation** (Boat 2026-07-31). This supersedes every prior
retraction of R1. No production object was changed.

## Decisive evidence

Job `p0_l5_loader_jobs_20260731_164100` queried
`region-asia-southeast1.INFORMATION_SCHEMA.JOBS_BY_PROJECT` for LOAD jobs targeting
`sap_integration_v2.SAP_LIVE`. Created `2026-07-31T16:40:31.849Z`, started `16:40:31.944Z`, ended
`16:40:33.269Z`. Dry-run upper bound was 2,638,020,733 bytes; actual processed 88,314,685 and
billed 89,128,960 under the 21,474,836,480 ceiling in asia-southeast1.

Per-job `statistics.load.outputRows` proves every retry committed the entire file before Cloud Run
died:

| LOAD creation date UTC | successful jobs | rows/job | committed rows | bad records |
|---|---:|---:|---:|---:|
| 2026-07-27 | 41 | 60,404 | 2,476,564 | 0 |
| 2026-07-28 | 70 | 60,385 | 4,226,950 | 0 |
| 2026-07-29 | 25 | 58,619 | 1,465,475 | 0 |
| 2026-07-30 | 1 | 27 | 27 | 0 |
| 2026-07-31 | 12 | 61,133 | 733,596 | 0 |

### Exact match to SAP_LIVE batches

| loader job date UTC | committed LOAD output | SAP_LIVE batch | batch rows | match |
|---|---:|---|---:|---|
| 2026-07-28 | 4,226,950 | 2026-07-27 | 4,226,950 | exact |
| 2026-07-29 | 1,465,475 | 2026-07-28 | 1,465,475 | exact |
| 2026-07-30 | 27 | 2026-07-29 | 27 | exact |
| 2026-07-27 | 2,476,564 | 2026-07-26 | 2,484,385 | +7,821 in batch |

The 7,821 excess is not evidence of partial BigQuery LOAD: all 41 jobs are complete, identical
60,404-row jobs with zero bad records. Loader logs show additional successful loader invocations
and multiple source files on 26-Jul; `U_BatchRunDate` is source data rather than ingestion/job
time, so those rows can share the 26-Jul batch. SAP_LIVE has no ingestion job ID with which to
allocate the 7,821 exactly. The separate 31-Jul observation also proves file rows can carry other
BatchRunDate values: 12 jobs committed 733,596 rows while 733,056 landed under batch 30-Jul, a
45-row-per-copy displacement. The exact-match days plus complete per-job output establish R1;
the 7,821 remains a mixed-file/batch attribution gap, not a failed LOAD.

For the 31-Jul incident, expected one-load output was 61,133; actual committed output was 733,596,
creating **672,463 new duplicate rows**. Memory 4 GiB allowed revision 00020 to complete, but the
11 prior retries had already committed successfully.

All 12 jobs on 31-Jul were `DONE`, error-free LOAD jobs. The enclosing request nevertheless
returned 503 because the container exceeded its former 1,024 MiB memory limit after BigQuery
committed and before source deletion. Pub/Sub retried the same object. After Boat raised memory to
4 GiB, revision 00020 returned 200, logged success, and deleted the file at 16:37:43Z.

This is direct proof of partial workflow success: each BigQuery LOAD completes, while the request
fails before acknowledgement/deletion. Append-only loading makes every retry permanent.

## Attribution and fixes

R1 is the leading explanation for acute amplification. OOM storms 27–29 Jul align with amplified
batches 26–28 Jul at the expected one-day offset. BI interface imports still enlarge the extract
by changing SAP rows; A2/A3 is a contributing factor, not the root cause of extreme multipliers.

The append-only preservation hold remains correct. DDL 043's idempotent MERGE is the real
destination-side prevention.

## Downstream correctness containment

Live `SAP_LIVE_FULL` uses `SELECT DISTINCT` independently in all four source branches, followed by
`ROW_NUMBER() OVER (PARTITION BY DocEntry ORDER BY UpdateDate DESC)` and `WHERE _rn=1`. Note that
the live order is **UpdateDate**, not BatchRunDate. Identical append-only retry copies therefore
collapse inside the SAP_LIVE branch and only one row per DocEntry reaches consumers. Legacy views
read SAP_LIVE_FULL, so this retry amplification does not multiply interface-file rows. Boat's
manual delta is protected from this specific double-posting mechanism. Current impact is storage
and scan cost; semantic winner correctness remains governed by the separate UpdateDate/UpdateTime
work and must not be conflated with retry-copy deduplication.

## Process lesson

R1 was retracted earlier on 31-Jul because a plausible interface-import/watermark narrative was
accepted before the decisive job-level evidence was collected. The correction is methodological:
when an outer request fails after a durable inner operation, inspect the inner job result and
output rows before inferring rollback or non-execution. Plausibility is not a substitute for the
transaction-boundary evidence.

The extract also logged one 61,133-row chunk and `chunk got 61133 rows, exceeds threshold 20000`,
producing one 169,695,148-byte object. Raising memory restores service but does not cure this
coupled bug. After 03-Aug, fix extraction chunking and retain idempotent MERGE loading.

There was no loader POST on 22–23 Jul and the 24-Jul invocation found no JSON. This may be
permanent mirror loss. Since (ก)/(ง) depend on absence from SAP truth, affected OrderItems require
separate measurement after the live post-load rerun.

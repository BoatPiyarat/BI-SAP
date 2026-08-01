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

## Read-only diagnosis

`diag_043_top_ties_20260801_151615` (2026-08-01T08:16:20.251Z–08:16:24.026Z;
303,226,824 processed / 304,087,040 billed) proved the incremental mirror has zero rows below the
maximum source `(UpdateDate, UpdateTime)`. The difference is therefore not an old-recency pick.
It found 81,509 DocEntries with multiple rows at the maximum recency: 78,907 within one source and
2,602 across sources; one DocEntry has up to 70 tied rows.

`diag_043_payload_ties_20260801_151735` (2026-08-01T08:17:41.525Z–08:17:50.853Z;
9,006,675,661 processed / 9,007,267,840 billed) found 8,538 DocEntries where those maximum-recency
rows have conflicting raw payloads: 5,936 within one source and 2,602 across sources. Because the
window partitions by DocEntry, the existing final `DocEntry DESC` term is constant and cannot
break these ties. This is the confirmed nondeterminism exposure and the leading explanation for
the observed 5,566 rows flipping between the full and incremental builds; 5,566 is the observed
run-specific flip count, while 8,538 is the larger population capable of flipping.

Source-only proposal: make both 024 and 043 order identical top-recency ties by
`SHA256(TO_JSON_STRING(raw_doc)) DESC`, where `raw_doc` is the already transformed mirror row.
Both full files dry-run successfully. This proposal is not deployed and requires a new Class A
review plus Boat approval.

## Deterministic retry — hard gate passed, repoint still held

After Class A PASS WITH NOTES (`docs/reviews/2026-08-01-1a8216f-claude.md`), Codex deployed both
deterministic procedures and reran the required bootstrap comparison. Every query was preceded by
a successful dry run and used the 20 GiB ceiling in `asia-southeast1`.

| Step | Job ID | UTC interval | Processed | Billed | Result |
|---|---|---:|---:|---:|---|
| Deploy deterministic 024 | `deploy_024_deterministic_20260801_162740` | 09:27:50.268Z–09:27:51.674Z | 0 | 0 | DONE |
| Deploy deterministic 043 | `deploy_043_deterministic_20260801_162815` | 09:28:26.129Z–09:28:27.423Z | 0 | 0 | DONE |
| Fresh deterministic 024 | `refresh_024_deterministic_20260801_162845` | 09:28:50.520Z–09:29:07.461Z | 7,319,841,706 | 7,320,109,056 | DONE |
| Bootstrap 043 + hard gate | `gate_043_deterministic_20260801_162955` | 09:30:01.175Z–09:30:46.621Z | 13,152,199,904 | 13,196,328,960 | **0/0 PASS** |
| Refresh + measure 025 | `measure_025_deterministic_delta_20260801_163215` | 09:32:24.494Z–09:32:46.063Z | 4,032,314,737 | 4,033,871,872 | DONE |
| Invoice NULL/empty diagnosis | `diag_025_invoice_null_empty_20260801_163445` | 09:35:06.106Z–09:35:06.475Z | 109,476,204 | 110,100,480 | DONE |

Hard-gate result: fresh 024 and incremental both contain 1,662,648 rows; `only_in_024=0` and
`only_in_incremental=0`. Watermark advanced to 2026-08-01 / 809.

025 comparison against its pre-deterministic snapshot: 1,300,230 rows before and after, zero
old-only/new-only keys, zero DocEntry winner changes, zero status changes, 4,067 payload changes,
and 885 raw `InvoiceNo` changes. The 885 are entirely representation-only: 449 NULL→empty string
and 436 empty string→NULL; zero empty↔real-value and zero real-value→different-value changes.
Therefore semantic InvoiceNo change is zero.

The mandatory evidence was complete at this step, but the nightly chain was still **not repointed**
yet. Deterministic hash selection remains semantically arbitrary for the 2,602 cross-source ties;
future source priority is a separate Boat/Aware decision.

## Nightly repoint deployed — 2026-08-01

After RQ-1637/RQ-1640 PASS and the corrected 047 delta PASS at review commit `5d8d6f9`, Codex
deployed the Boat-authorized nightly repoint.

| Step | Job ID | UTC interval | Processed | Billed | Result |
|---|---|---:|---:|---:|---|
| Deploy 047 | `deploy_047_repoint_20260801_193500` | 12:57:37.068Z–12:57:37.597Z | 0 | 0 | DONE |
| Verify live routine metadata | `verify_047_live_20260801_195800` | query timestamp 12:58:01Z | 0 | 0 | PASS |

Live `INFORMATION_SCHEMA.ROUTINES` evidence: `call_count=10`, incremental call present, full 024
call absent, `sp_refresh_interface_daily_status` present, routine SHA256
`11f40bbef39a882002b3da9768b9dd9b6131a7d8defb67c4fae29e22c4afa692`. Review prose called the
monitoring call the "11th call", but its own mechanical comparison said the intended call plus the
other nine calls; live metadata confirms ten executable CALL statements. This wording mismatch
does not change the reviewed defect or fix: the monitoring call is present in production.

No manual nightly CALL was made. The first scheduled 21:00 ICT execution remains the required
end-to-end operational verification; rollback stays available in `047`.

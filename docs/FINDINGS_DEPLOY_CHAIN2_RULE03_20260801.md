# Chain 2 / RULE-03 deployment evidence — 2026-08-01

Status: **DEPLOYED AND VERIFIED**

Chain order was 024 procedure → 024 refresh → 025 procedure → 025 refresh → shared 037 guard.
All BigQuery queries were preceded by dry runs and used `asia-southeast1` with the
21,474,836,480-byte ceiling.

| Step | Job ID | UTC interval | Processed | Billed | Result |
|---|---|---:|---:|---:|---|
| Deploy 024 | `deploy_024_rule03_20260801_141856` | 07:19:09.777Z–07:19:10.995Z | 0 | 0 | DONE |
| 024 pre-refresh guard | `verify_024_pre_refresh_20260801_141956` | 07:20:09.752Z–07:20:10.728Z | 23,755,968 | 24,117,248 | PASS |
| Refresh 024 | `refresh_024_rule03_20260801_142025` | 07:20:39.123Z–07:20:54.046Z | 7,319,841,706 | 7,320,109,056 | DONE |
| Verify 024 | `verify_024_post_refresh_20260801_142240` | 07:22:52.189Z–07:22:52.505Z | 39,903,552 | 40,894,464 | PASS after Boat source-growth confirmation |
| Deploy 025 | `deploy_025_rule03_20260801_143950` | 07:39:49.598Z–07:39:50.705Z | 0 | 0 | DONE |
| 025 pre-refresh guard | `verify_025_pre_refresh_20260801_144010` | 07:40:12.086Z–07:40:12.335Z | 10,485,760 | 10,485,760 | PASS |
| Refresh 025 | `refresh_025_rule03_20260801_144030` | 07:40:30.574Z–07:40:42.996Z | 1,184,009,750 | 1,184,890,880 | DONE |
| Verify 025 | `verify_025_post_refresh_20260801_144105` | 07:41:11.091Z–07:41:11.405Z | 61,989,127 | 62,914,560 | PASS |
| Verify shared 037 | `verify_037_shared_guard_20260801_144130` | 07:41:34.085Z–07:41:34.357Z | 10,485,760 | 10,485,760 | PASS; no redundant redeploy |

## Population interpretation

- 024 immediately before refresh: 1,658,776 rows = 1,658,776 distinct DocEntry.
- 024 after refresh: 1,662,648 rows = 1,662,648 distinct DocEntry; UpdateDate/UpdateTime NULL = 0.
- The `+3,872` versus the older baseline was accepted only after Boat confirmed a manual source
  import. It is source growth, not duplicate leakage and not a selector rebuild expectation.
- 025 after refresh: 1,300,230 rows, zero duplicate `(U_OrderItem,U_Period)` keys, 330,822
  `MULTI_DOC_RESOLVED_BY_RECENCY`, zero tag mismatch, and zero NULL `docs_considered`.
- The `+3,330` versus the 1,296,900 pre-change baseline is likewise downstream source growth.

## Correct rebuild-delta bound

The original zero-delta expectation is superseded for selector rebuilds. Subsequent diagnostics
measured **8,538 DocEntries** with conflicting payloads at identical maximum
`(UpdateDate,UpdateTime)`. Therefore a pre-deterministic versus deterministic 024 rebuild may
change at most **8,538 keys**; zero is not the correct expected bound.

Observed evidence is within that bound: the first full-versus-incremental comparison flipped
5,566 rows in each direction. After the identical deterministic hash tiebreak was deployed to 024
and 043, the hard gate became 0/0 at 1,662,648 rows. The resulting 025 rebuild retained 1,300,230
keys with zero key, DocEntry-winner, status, or semantic InvoiceNo changes. It had 4,067 payload
representation changes; all 885 raw InvoiceNo changes were NULL↔empty only.

This evidence does not define business source priority for the 2,602 cross-source ties. It proves
deterministic technical equivalence only; source-priority semantics remain a future Boat/Aware
decision if required.

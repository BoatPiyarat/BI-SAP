# Fresh V3 Units 1–5 pilot production evidence — 2026-08-27

## Outcome

**FAILED CLOSED; NO RETRY.** The one approved production execution completed Unit 1, including a
fresh SAP extract and committed bronze/load path, then stopped in Units 2–5 before magnitude
evaluation or restricted archive creation. The NEWPAYMENT payload guard rejected SQL/literal
`NULL`. No promoter was called, no production interface row was delivered, no
`gs://interface-file/**` write was made, and no Scheduler state was changed.

## Approval and reviewed source

- Approval reference: `Boat-chat-20260827-FRESH-UNITS1-5-PILOT-V1`
- Approved command: `scripts/run_v3_fresh_units1_5_delivery_disabled.ps1`
- Approved source commits: `11b89d2 + 9591052 + e11a9cd`
- Claude Class-A result: PASS WITH NOTES; Codex receipt commit `3dc8882`
- Boundary: one execution only; SAP read/extract, bronze/load, Units 1–5 mutation, and restricted
  archive permitted; delivery, promoter, interface bucket, Scheduler mutation, and retry forbidden.

## Preflight and execution identity

- Initial preflight BigQuery job: `bqjob_rdc291370fa5578e_000001a043d400a1_1`, PASS
- Workflow execution: `6e4abb48-1b6d-4ac0-8cc2-66ce965d06a6`
- Workflow revision: `000011-291`
- Workflow start/end: `2026-08-27T15:26:08.501823983Z` /
  `2026-08-27T15:31:57.940909101Z`
- Pipeline run: `V3NIGHTLY-2026-08-27T15:26:08-01480a29`
- Terminal state: `FAILED`
- Failing step: `UNITS_2_5_ARCHIVE`
- BigQuery job: `V3NIGHTLY-2026-08-27T15_26_08-01480a29-UNITS_2_5_ARCHIVE`
- BigQuery job volume: 11,930,317,132 bytes processed; 12,456,034,304 bytes billed; 80 child jobs
- Exact error: `NEWPAYMENT candidate must not contain SQL NULL or literal NULL` at
  `sp_build_v3_newpayment_shadow:257:3`

## Committed Unit 1 effects

- SAP extract execution `sap-extract-job-jhwpb`: succeeded once; no retry.
- Extracted bronze object:
  `SAP/production_database/Results2026_08_27_da2ddf06.json@1787844388993700`
  (`md5=QkEHDApDYy9hFwqPCV1OuQ==`).
- Loader job `667f625a-2f9b-4cc8-b4db-9575c8dcd0ec`: committed 4,755 rows, zero bad records,
  `MEDIA_UPLOAD` source mode.
- Mirror document/state refreshes completed cleanly.
- `UNIT1_COMPLETE`: exactly one SUCCESS row.
- Post-run bronze census: empty (`[]`).

## Units 2–5 disposition and containment

Read-only report job `bqjob_r1d8db7d98e5c1d7a_000001a043daf6e4_1` returned:

- Unit 2 summary rows: `14` (partial append-only evidence retained)
- Units 2–5 success rows: `0`
- Failed log rows: `1`
- Magnitude run/result rows: `0 / 0`; no threshold result was created or relabelled
- Automation blockers: `0`
- Restricted archive runs: `0`
- Production delivery rows: `0`
- Final disposition: `FAILED_OR_INCOMPLETE_REVIEW_REQUIRED`

No cleanup, delete, replay, relabel, or retry was performed. The partial run is preserved as
audit evidence. Any repair and new execution require a new reviewed artifact and separate exact
approval.

## Post-run control-plane proof

- Read-only post-run preflight job `bqjob_r7611f7e349c47d79_000001a043dc7503_1`: PASS; it created
  no execution.
- Workflow revision remains `000011-291`; delivery remains `false`; active/queued executions `0`.
- V3 Scheduler remains `PAUSED`, `30 20 * * *`, `Asia/Bangkok`.
- Legacy `sap-extract-schedule` remains `ENABLED`, `30 20 * * *`, `Asia/Bangkok`.
- Bronze production prefix is empty.

## Next safe step

Diagnose which NEWPAYMENT candidate columns contain SQL/literal `NULL`, correct the source-only
normalization without weakening the 56-column assertion, obtain Class-A review, and request a new
one-time execution approval. Delivery and recurring activation remain disabled.

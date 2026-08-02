# V3 Unit 2 shadow findings — 2026-08-02

Status: source correction ready; corrected 051 is **not deployed**. V2 remains active and no cutover occurred.

## Provenance

- Pipeline run: `V3NIGHTLY-2026-08-02T09:02:26-b36e1712`
- Initial Unit 2 CALL job: `bqjob_r1d84adfb4ec5763d_0000019fc1fdf2b3_1`
- Schedule UNKNOWN diagnostic job: `v3_unit2_schedule_unknown_diag_20260802_1742`
- Query creation timestamp: `2026-08-02T10:31:11.577Z`
- Dry-run upper bound: 330,068,779 bytes
- Actual processed: 54,757,393 bytes; billed: 55,574,528 bytes
- Location: `asia-southeast1`; maximum bytes billed: 21,474,836,480

## UNKNOWN schedule diagnosis

The 31,628 schedule rows were present in `expected_state`; none was missing from that table. All
31,628 were absent from both the exclusion and validation registers. The unmatched shape was a
state-classification gap, not dropped source data.

- 28,018 rows: CareOS cancellation effective and SAP already Cancelled/Cancelled(Change). These are
  terminally acknowledged and must never be resent.
- 3,610 rows: SAP is already terminal/ahead while CareOS expected state differs. These must be held
  for human validation; V3 must not cancel, downgrade, or overwrite them automatically.

The source correction in 051 adds explicit branches for both shapes. It also holds payment events
whose exact invoice already exists in SAP as Cancelled, rather than treating them as an unknown route.

## Deployment gate

The corrected file validates in BigQuery with a 0-byte DDL dry-run. Production redeployment was not
performed because the changed artifact requires explicit approval. After approval, redeploy 051 and
rerun the same pipeline run ID idempotently; verify that schedule UNKNOWN becomes zero and event
UNKNOWN falls from 179 to 14, with the corresponding rows moving only to ACKNOWLEDGED or
HELD_VALIDATION.

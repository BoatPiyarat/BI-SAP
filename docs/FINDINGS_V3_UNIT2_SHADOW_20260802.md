# V3 Unit 2 shadow findings — 2026-08-02

Status: corrected 051 deployed and shadow rerun completed. V2 remains active and no cutover occurred.

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

## Deployment and rerun evidence

- Approved source: `051@e561643`
- Deploy job: `v3_unit2_051_e561643_deploy_20260802_1748`, DONE, 0 bytes
- CALL job: `v3_unit2_e561643_call_20260802_1850`, created
  `2026-08-02T11:50:09.445Z`, DONE, processed 1,436,867,866 bytes and billed
  1,526,726,656 bytes
- Verification job: `v3_unit2_e561643_verify_20260802_1852`, DONE, 1,184 bytes processed
- Hold-reason job: `v3_unit2_e561643_holds_20260802_1854`, DONE

All in-procedure record and amount conservation assertions passed. Schedule UNKNOWN became zero.
Payment-event UNKNOWN fell from 179 to 14. The rerun found 11,752 payment events whose exact invoice
already exists in SAP as Cancelled; they are held and must not be exported. The earlier expectation
of only 165 such moves was incomplete because its diagnostic intentionally inspected only the old
HELD/UNKNOWN populations and therefore did not inspect rows previously labelled READY.

Current READY populations are 1,185 payment events (1,175 orders; amount 251,592,462 source minor
units), 2,454 create/payment schedule rows, and 1,271 cancel/change schedule rows. These are shadow
classifications only. They are not approval to create or deliver an interface file.

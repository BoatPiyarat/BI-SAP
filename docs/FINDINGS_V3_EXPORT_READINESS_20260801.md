# V3 July-only production export readiness — 2026-08-01

Status: **BLOCKED; no GCS write performed**.

Boat authorized one production run limited to raw PaymentDate in
`[2026-07-01, 2026-08-01)` and explicitly prohibited August data. The pre-write hard gate failed:

- Live routine metadata contains `sp_refresh_delta_export` only. Neither `sp_export_delta` nor
  `sp_manual_export` exists.
- Live `delta_export` has 13 columns and `expected_state` has 15; neither is the positional
  56-column SAP interface contract.
- Live `export_archive` does not exist. Therefore no durable dedup/audit control can prevent a
  later nightly or manual resend.
- Class A request `RQ-20260801-2205-interface-validation-canonical` remains OPEN, including the
  newly clarified status-field contract.
- Repository source `018_delta_export.sql` explicitly says it is not an actual export and writes
  no GCS file.

Evidence query:

- Job: `verify_v3_export_readiness_20260801_222500`
- Created: 2026-08-01 15:24:35.899 UTC (22:24:35.899 ICT)
- Dry-run estimate: 20,971,520 bytes
- Processed/billed: 20,971,520 / 20,971,520 bytes
- Ceiling: 21,474,836,480 bytes; location: `asia-southeast1`

Gmail baseline (`label:"notification SAP upload" after:2026/07/01`) shows existing legacy/manual
July files with a mixture of success, success-with-error, and error results. The latest visible
message at 2026-08-01 11:16:02 UTC is success for LogID 21144. These messages are not evidence of a
new V3 export: Codex wrote no file during this gate.

Required before retry: reviewed/deployed 56-column Phase-B row model; July-only raw-PaymentDate
predicate with an explicit zero-August assertion; complete validation; archive-on-write/idempotency;
reviewed export procedure and filename/BU routing; pre-write manifest and post-write/email checks.

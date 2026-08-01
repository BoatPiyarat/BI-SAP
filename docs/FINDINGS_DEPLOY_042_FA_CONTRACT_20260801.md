# DDL 042 FA verification contract deployment — 2026-08-01

Status: **DEPLOYED AND VERIFIED — SCHEMA/WRITER ONLY**

Boat's release approval authorized 042 after NOTE 1/2 closure and Claude delta re-review. Commit
`5f8c17a` received Class A PASS in `docs/reviews/2026-08-01-5f8c17a-claude.md`. Codex deployed the
table and guarded writer procedure only. No procedure CALL, evidence row, or backfill was made.

| Step | Job ID | UTC interval | Processed bytes | Billed bytes | Result |
|---|---|---:|---:|---:|---|
| Deploy 042 | `deploy_042_fa_contract_20260801_152210` | 2026-08-01T08:22:17.792Z–08:22:18.871Z | 0 | 0 | DONE |
| Verify live objects | `verify_042_fa_contract_20260801_152240` | 2026-08-01T08:22:43.956Z–08:22:44.255Z | 10,485,760 | 20,971,520 | DONE |

Both queries were preceded by successful dry runs and used
`--location=asia-southeast1 --maximum_bytes_billed=21474836480`.

Verification result:

- `sap_fa_verification`: 0 rows, 17 columns.
- Partition: DAY on `evidence_timestamp`.
- Clustering: `incident_or_finding_id, order_id, order_item`.
- `sp_record_fa_verification` exists and contains the NOTE 1 `NOT_FOUND` guard, NOTE 2
  `REJECTED_NEVER_POSTED` SAP-status guard, and guarded INSERT.
- No CALL or backfill occurred.

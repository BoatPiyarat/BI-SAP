# SAP result-ingestion Apps Script — source-only deployment contract

`sap_result_ingestion.gs` is the Unit 6 attachment-first reader. It does not authorize a deployment.

Before deployment, deploy reviewed DDL 064 and 070, grant the script principal narrowly scoped Gmail,
BigQuery, and `gs://rcb-bronze-zone/sap_import_logs/` access, and set Script Properties:

- `PROJECT_ID=pacific-plating-282708`
- `LOG_BUCKET=rcb-bronze-zone`
- `ALERT_RECIPIENT=<Boat-reachable mailbox or monitored channel gateway>`
- optional `BQ_DATASET=sap_integration_v3`

Install separate 15-minute triggers for `pollSapResultMailbox` and
`checkSapResultIngestionHeartbeat`. The latter is the independent pre-60-minute poll-gap alarm.

Deploy DDL 070 before the reviewed replacement of DDL 062. After an exact-generation, create-only
promotion copy, call `sp_mark_v3_exact_delivery` with its original evidence plus the exact
SAP-facing production-object basename and its 64-hex SHA-256. The procedure atomically marks the
archive ledger DELIVERED and persists exactly one `sap_delivery_manifest_v3` row with the immutable
production URI/generation/hash, row count, and supplied filename. The filename is never inferred
from the archive basename: LogID 21183 proved the names can differ.

Acceptance rehearsal must prove: zero-match stays unlabeled/PENDING_ACK; two LogIDs for one manifest
alerts and persists nothing; a successful TXT persists header and attachment before label; rerun is
idempotent; attachment parse failure is unlabeled; rejected-row details remain PENDING_ACK; heartbeat
failure reaches Boat before 60 minutes; and no UAT2 message can match.

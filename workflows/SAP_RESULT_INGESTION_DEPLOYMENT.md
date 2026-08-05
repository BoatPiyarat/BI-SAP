# SAP result-ingestion Apps Script — source-only deployment contract

`sap_result_ingestion.gs` is the Unit 6 attachment-first reader. It does not authorize a deployment.

Before packaging, run the local source contract:

```powershell
node workflows/test_sap_result_ingestion.js
Get-Content -Raw -Encoding UTF8 workflows/sap_result_ingestion.gs | node --check -
Get-Content -Raw -Encoding UTF8 workflows/sap_result_ingestion.appsscript.json |
  ConvertFrom-Json | Out-Null
```

The test uses no Gmail, GCP, Script ID, OAuth token, or network call. It exercises the exact LogID
21183-shaped metadata, sender boundary, TXT row parsing, SAP-result-name manifest match,
production-basename non-match, duplicate-manifest refusal, persist/publish/label ordering,
zero-manifest no-label behavior, and ambiguity alert/failure behavior.

After the Apps Script owner supplies the exact Script ID, prepare a clasp-compatible directory
outside the repository:

```powershell
.\scripts\prepare_sap_result_apps_script.ps1 `
  -ScriptId '<owner-supplied-script-id>' `
  -OutputDirectory (Join-Path $env:TEMP 'sap-result-ingestion-clasp')
```

The helper refuses a destination inside this repository or a non-empty destination. It validates
the exact reviewed OAuth-scope set, stages `Code.gs`, renames the manifest to `appsscript.json`,
and writes `.clasp.json`. It does not install clasp, authenticate, push, deploy, set properties,
or create triggers. Inspect all three staged files before the mailbox owner runs any clasp command.

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
production-object basename, the distinct expected SAP-result filename, and its 64-hex SHA-256.
The procedure atomically marks the archive ledger DELIVERED and persists exactly one
`sap_delivery_manifest_v3` row with the immutable production URI/generation/hash, row count, and
both names. For RCB Motor, the production basename must start `INSURANCE_RCB_`; SAP reports that
same basename with the approved `RCB_MOTOR_` reporting prefix. LogID 21183 proved these names are
not equal. The workflow constructs both only after exactly-one archive-object census and validates
the closed naming policy before promotion.

For the post-import refresh handoff, deploy reviewed DDL 071 first. Leave
`POST_IMPORT_REFRESH_TOPIC` blank until the outbox dispatcher and its dedicated Pub/Sub topic are
deployed. Once configured, the ingestor enqueues the exact persisted LogID/manifest binding before
publishing a minimal retry-safe event. Add only the narrow `pubsub` OAuth scope; do not restore
`cloud-platform`.

Acceptance rehearsal must prove: zero-match stays unlabeled/PENDING_ACK; two LogIDs for one manifest
alerts and persists nothing; a successful TXT persists header and attachment before label; rerun is
idempotent; attachment parse failure is unlabeled; rejected-row details remain PENDING_ACK; heartbeat
failure reaches Boat before 60 minutes; and no UAT2 message can match.

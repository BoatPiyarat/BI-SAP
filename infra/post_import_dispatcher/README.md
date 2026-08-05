# Post-import refresh dispatcher

Source-only private Cloud Run service. A Pub/Sub push event for an already persisted LIVE SAP
result claims the DDL 071 outbox row and creates a Unit-1 workflow execution. It does not parse
email, read attachments, deliver interface files, acknowledge SAP rows, or call SAP.

The claim token is deterministic over `(log_id, export_run_id, sap_file_name)`. The dispatcher
passes only the LogID and token in the Workflows argument. Because the Executions API assigns the
execution name, the workflow reconstructs its own full resource name and atomically binds it
through DDL 072 before any Unit-1 side effect. If duplicate executions are created, only the
winning bound execution proceeds; the others return `DUPLICATE_NOOP`.
After a clean Unit 1, the workflow records `SUCCEEDED` before returning. A separate reviewed
watchdog is still required to classify executions that terminate or time out before that write.

Required configuration:

- `PROJECT_ID=pacific-plating-282708`
- `BQ_DATASET=sap_integration_v3`
- `BQ_LOCATION=asia-southeast1`
- `WORKFLOW_LOCATION=asia-southeast1`
- `WORKFLOW_NAME=<deployed Unit-1 workflow ID>`

Deploy only after Class-A review of DDL 072, this service, and the workflow self-bind gate. Use a
dedicated runtime service account with only BigQuery job creation/read access plus
`workflows.executions.create` on the one workflow. Keep the Cloud Run service private; a dedicated
authenticated Pub/Sub push subscription invokes `/dispatch`. Configure a dead-letter topic and a
bounded delivery-attempt policy. Do not set the Apps Script `POST_IMPORT_REFRESH_TOPIC` until all
of those resources and the reviewed DDL are deployed.

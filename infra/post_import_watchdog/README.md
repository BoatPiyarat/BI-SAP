# Post-import watchdog

Source-only scheduled Cloud Run Job for DDL 072 outbox rows. It releases stale claims for bounded
retry, cancels overdue Workflows executions and records `TIMEOUT`, and converts already-terminal
executions that failed to write their own terminal outbox state into `HUMAN_ACTION`. Every terminal
watchdog action publishes a minimal alert to the existing human-tested orchestrator alert topic.

Required configuration:

- `PROJECT_ID=pacific-plating-282708`
- `BQ_DATASET=sap_integration_v3`
- `BQ_LOCATION=asia-southeast1`
- `CLAIM_TIMEOUT_SECONDS=<approved configuration>`
- `EXECUTION_TIMEOUT_SECONDS=<approved configuration>`
- `CANCEL_WAIT_SECONDS=<approved configuration>`
- `ALERT_TOPIC=projects/pacific-plating-282708/topics/v3-orchestrator-alerts`

No timeout is silently selected in source. Deploy only after Class-A review and after measured
Unit-1 durations support the configured execution timeout. Run on a schedule materially shorter
than `CLAIM_TIMEOUT_SECONDS`. The dedicated service account needs BigQuery job/dataset access,
`workflows.executions.get`, `workflows.executions.cancel`, and publish permission on the one alert
topic. A cancellation must reach a non-ACTIVE/non-QUEUED state before the outbox becomes TIMEOUT.

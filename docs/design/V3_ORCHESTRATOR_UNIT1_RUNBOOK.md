# V3 orchestrator unit 1 — deploy runbook (Codex executes; Claude Code never deploys)

Status: SOURCE ONLY / Class A review required. Artifact:
`infra/v3_nightly_orchestrator.workflows.yaml`. Units 2–5 chain from `UNIT1_COMPLETE`, never from
wall clock.

## What unit 1 owns

Extract execution (Cloud Run Jobs v2, auto-polled) → pre/post bronze census with generation+md5
capture → at-most-one loader trigger → bronze-consumption wait with hard timeout → mirror doc/state
refresh as two separately capped BigQuery jobs → `UNIT1_COMPLETE`. Every transition writes
`pipeline_run_log`; every failure records, publishes to `v3-orchestrator-alerts`, then raises.

## Pre-deploy (Codex)

1. Create Pub/Sub topic `v3-orchestrator-alerts` + a subscription that reaches a human (email
   push or the existing alerting route). **Test one synthetic message end-to-end and record the
   evidence — an unverified alert channel violates the fail-closed contract.**
2. Service account for the workflow (new, least-privilege):
   `run.jobs.run` (extract), `cloudscheduler.jobs.run` (loader trigger),
   `bigquery.jobs.create` + `bigquery.jobs.get`/`cancel` (terminal polling, F5) + dataset-scoped
   read/write on `sap_integration_v3` and read on the region INFORMATION_SCHEMA (F2),
   `storage.objects.list` + `storage.objects.get` on `rcb-bronze-zone`,
   `logging.logEntries.list` for exact-execution healthy-zero proof, and
   `pubsub.topics.publish` on the alert topic.
2b. **Extract evidence pinned (2026-08-02 read-only verification).** The deployed object is
   `SAP/_extract_control/_watermark_state.json` with `last_watermark_utc` and `updated_at` only.
   `caught_up` and row count are emitted in the Cloud Run execution success log. Healthy zero
   therefore requires watermark advance plus exactly one log marker containing
   `success: ... 0 rows ... caught_up=True` for the execution started by this workflow.
3. `gcloud workflows deploy v3-nightly-orchestrator --location=asia-southeast1 \
   --source=infra/v3_nightly_orchestrator.workflows.yaml --service-account=<sa>`.

## Cutover ordering (the double-run hazard)

While the legacy 20:30 extract scheduler and the 21:00 scheduled V3 query remain enabled, the
workflow must only be run manually for parallel observation. Full cutover = one reviewed change:
(a) create the workflow trigger (Cloud Scheduler → workflows.executions at 20:30 ICT),
(b) pause `sap-extract-schedule`, (c) pause the 21:00 scheduled query. Rollback = re-enable both
paused schedulers and pause the workflow trigger — states, not deletions, so rollback is <5 min.

## First-night acceptance (before Boat accepts cutover)

- One execution with terminal SUCCESS and the full `pipeline_run_log` trail
  (UNIT1_START → EXTRACT_DONE/SKIPPED/HEALTHY_ZERO → [BRONZE_OBJECT → LOADER_CONSUMED] →
  MIRROR_DOC_REFRESH → MIRROR_STATE_REFRESH → UNIT1_COMPLETE) with run_id joining all rows.
- Bronze generation+md5 recorded when a batch existed.
- Mirror counts consistent with the loader's outputRows delta.
- One deliberately induced failure path in a rehearsal (e.g. tiny loader_timeout_seconds) proving
  the FAILED row + alert message + workflow failure all fire.
- The LOAD-commitment audit row present (job ID + outputRows + badRecords=0 + source match) —
  bronze deletion alone is never accepted as commitment (F2, the b00af18 lesson).
- BigQuery mutation job IDs contain no colon/invalid character, and a timeout rehearsal proves
  `jobs.cancel` is polled until terminal DONE before the workflow emits its failed terminal state.

## Known boundaries (explicit non-goals of unit 1)

- No delta classification, no export, no ACK ingestion (units 2–5).
- Does not verify loader row counts against extract logs (unit 5's reconciliation owns exactness;
  unit 1 owns ordering and single-triggering).
- `timeoutMs` on the mirror CALLs is 300s; if a refresh legitimately exceeds it the job continues
  server-side but unit 1 fails closed — revisit with measured nightly durations before cutover.

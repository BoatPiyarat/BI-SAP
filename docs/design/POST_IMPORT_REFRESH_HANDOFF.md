# Post-import refresh handoff — source contract

Status: design only / Class B / 2026-08-05. No service, topic, trigger, workflow execution, or
production object is created by this document.

## Problem

The SAP Gmail ingestor persists a matched LIVE import result, but a header is file-level evidence
only. A successful import still needs a fresh Unit 1 extract/load/mirror before immutable exported
identities can be reconciled. Calling the main workflow directly from the Gmail poller would make
mailbox retries capable of starting duplicate refreshes and would require reintroducing a broad
Apps Script OAuth scope that the current reviewed source deliberately removed.

## Required handoff

1. After one matched LIVE result is durably persisted, the ingestor writes one idempotent outbox
   record keyed by SAP `log_id` and delivery `export_run_id`. Its payload contains only those IDs,
   the manifest filename, normalized terminal import status, and source timestamp—never attachment
   text, row detail, or customer data.
2. The ingestor publishes that same key to a dedicated Pub/Sub topic using the narrow Pub/Sub OAuth
   scope. A publish retry is safe because the consumer deduplicates against the durable outbox key.
3. A private dispatcher, running as a dedicated service account, atomically claims a PENDING outbox
   record and starts a child **Unit 1-only** workflow execution linked to the delivery run. It must
   not run Units 2–5 or create another delivery file.
4. The dispatcher records the execution name and moves the outbox through `PENDING -> STARTED ->
   SUCCEEDED | TIMEOUT | HUMAN_ACTION`. Failed claims are retryable with bounded attempts; a
   terminal timeout/ambiguity alerts a human and is never reported as reconciliation success.
5. The child workflow performs the existing extract → loader commitment → mirror refresh gates,
   then invokes the exact identity reconciliation. Only that independent result can update row-level
   acknowledgement/rejection state.

## Non-negotiable controls

- A Gmail label or Pub/Sub delivery acknowledgement is not the durable handoff state.
- `log_id` alone is not enough: the outbox must bind it to the exact `export_run_id`/manifest.
- Duplicate Pub/Sub deliveries, Gmail polling retries, and dispatcher retries must start at most
  one active child execution for a key.
- The normalized terminal-status set must be documented from SAP result evidence before source
  admits non-`success` statuses; no status mapping is inferred from a free-text attachment.
- This does not enable production delivery. `delivery_enabled: false` remains the gate for the
  separate promotion path.

## Build order

1. Class-A DDL: durable outbox and claim/complete procedures with exact-key uniqueness.
2. Class-A Apps Script delta: persist outbox after result persistence, publish a minimal event, and
   retain the reviewed narrow OAuth model except for the dedicated Pub/Sub scope.
3. Class-A private dispatcher and Unit-1-only workflow entry mode; source review must prove
   idempotency, bounded timeout, and no Units 2–5/delivery path.
4. Rehearse with a synthetic non-production outbox key. Deployment requires separate scoped human
   approval for each deployed component.

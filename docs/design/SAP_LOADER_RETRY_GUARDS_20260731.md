# SAP loader retry guards — design only

Status: proposed after 2026-08-03. Do not apply during July close.

## Failure semantics

The loader is not transactional across BigQuery LOAD, GCS delete, and Pub/Sub acknowledgement.
HTTP 503 does **not** mean data was not loaded: BigQuery can commit successfully before the
container dies. This is the same observability pattern as two other project lessons:

1. Cloud Function terminal status does not prove export failure; all GCS writes may already exist.
2. `rows=0` is ambiguous without chunks, watermark movement, `caught_up`, and success marker.
3. Loader HTTP 503 does not prove load failure; inspect BigQuery job outcome and object lifecycle.

In all three, an outer orchestration status cannot substitute for the inner side-effect evidence.

## Guard 1 — daily SAP_LIVE LOAD-job count

Run after the loader window against
`region-asia-southeast1.INFORMATION_SCHEMA.JOBS_BY_PROJECT`, filtering destination
`sap_integration_v2.SAP_LIVE`, `job_type='LOAD'`, the loader service account, and the expected
calendar window. Alert when successful LOAD jobs exceed one. Zero requires correlation with
extract rows: zero is healthy when extraction produced no file, but a gap when a bronze file or
positive extract count exists.

Minimum output: load date, successful/failed LOAD count, first/last job timestamps, service
account, bronze objects present, and extract row count. The alert must fire within one day rather
than waiting for multi-day table growth.

Limitation: JOBS_BY_PROJECT does not expose LOAD `outputRows` directly. Incident diagnostics must
read each job's `statistics.load.outputRows`; prevention should not depend on that manual step.

## Guard 2 — dead-letter policy

Current subscription:

- `eventarc-asia-southeast1-trigger-sap-order-payment-initial-phase-sub-101`
- no dead-letter policy;
- ack deadline 10 seconds;
- retry backoff 10–600 seconds;
- message retention 86,400 seconds.

Proposal: attach a dedicated dead-letter topic and subscription, grant the required Pub/Sub
service-agent publisher/subscriber IAM, set `maxDeliveryAttempts=5`, and alert on every DLQ
message. Google Cloud permits 5–100 attempts; 5 is the real minimum/default. Delivery-attempt
counting is approximate/best-effort, so Pub/Sub may forward before or after the configured count.

Trade-off: a visible DLQ after approximately five failures is safer than unbounded retry for a
non-idempotent consumer, but it does **not** provide one-attempt semantics and can still create
roughly five duplicate commits. It is containment, not correctness.

## Permanent remediation

1. Deploy DDL 043's idempotent MERGE behavior so replay cannot add duplicate states.
2. Fix extraction chunking: the 20,000-row threshold must create bounded objects rather than only
   warn after a 61,133-row fetch.
3. Make acknowledgement/delete sequencing explicit and observable; log source object generation
   and BigQuery job ID together.
4. Retain the daily LOAD-count guard and DLQ even after idempotency, because they expose cost and
   operational failure quickly.

Raising memory to 4 GiB restored the 31-Jul request but is not the permanent fix.

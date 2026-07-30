# TASK — migrate `pacific-plating-282708` to `sap-b1-374202`

Source: `docs/knowledge/KNOWLEDGE_ADDENDUM_20260730_v3.md` §C  
Status: **PLANNED — BLOCKED ON C8 CONFIRMATIONS; DO NOT EXECUTE**

## Scope established from commit `19c49cf`

The old project ID appears 569 times across 80 files: 66 SQL, 11 Markdown, two
Python/YAML/JSON, and one shell file. The migration-owned datasets include
`sap_integration_v3`, `sap_integration_v2`, and `sap_view`. Whether `careos`,
`hydra_customer_prod`, and `sap_data_engineer` move is deliberately unresolved.

All relevant datasets are in `asia-southeast1`; every CLI/query operation must state that location.
Historical evidence in Markdown must retain the old project ID. Runtime source should move toward
a parameter/configuration seam rather than a global project-ID replacement.

## Bucket and vendor boundary

- `gs://interface-file` is read by the SAP vendor pull every 15 minutes. Do not move, rename, or
  change its cadence without Aware.
- Real extract output:
  `gs://rcb-bronze-zone/SAP/production_database/`.
- Real extract control:
  `gs://rcb-bronze-zone/SAP/_extract_control/`.
- The old B1 bucket name does not exist. The similarly named service account
  `sap-bucket-csv@pacific-plating-282708.iam.gserviceaccount.com` does exist and must not be
  confused with a bucket.
- Preferred but **not yet approved** approach: retain vendor-facing buckets in the original
  project and grant narrowly scoped cross-project IAM.

## Infrastructure to recreate

- Cloud Run Job `sap-extract-job` and VPC connector `sap-connector`.
- Cloud Run service `sap-order-payment-initial-phase`.
- Eventarc trigger/topic for `trigger-sap-order-payment-initial-phase`.
- Cloud Scheduler jobs `auto_load_sap_data_in_bucket_to_bigquery` and `sap-extract-schedule`.
- Scheduled state/reconciliation chain.
- Motor/non-motor interface Cloud Functions.
- New service accounts and least-privilege IAM.
- Secret Manager credentials; rotate once during migration rather than copying the exposed secret.

WireGuard and SAP-side importer/pull components are vendor-owned and remain outside agent authority.

## Evidence and cost controls

Before moving audit tables:

1. Export required `INFORMATION_SCHEMA.JOBS_BY_PROJECT` history to a retained table if Boat elects
   to preserve it. Query history, IAM, scheduled queries, authorized views, materialized views and
   time-travel history do not migrate automatically.
2. Capture per-batch row count, distinct DocEntry and content fingerprint for `SAP_LIVE`.
3. Create destination datasets in `asia-southeast1`.
4. Use `bq cp`, not CTAS, for same-region copies.
5. Verify every fingerprint at the destination.
6. Keep the old audit copy until `INCIDENT-SAP-MIRROR-20260726` closes and evidence retention is
   signed off.
7. New diagnostic/scratch tables require an expiration timestamp.

Do not use the migration to clean or deduplicate the append-only incident evidence.

## C8 — ⏳ CONFIRM before implementation

All six answers are owned by Boat. Agents must not infer them.

1. **CONFIRM:** Do `careos` and `hydra_customer_prod` move, or remain in the old project?
2. **CONFIRM:** Does `sap_data_engineer` move?
3. **CONFIRM:** Does `gs://interface-file` remain in the original project with cross-project IAM?
4. **CONFIRM:** Does `sap-b1-374202` already exist, and what datasets/data are already present?
5. **CONFIRM:** Is migration before or after closure of
   `INCIDENT-SAP-MIRROR-20260726` and the human review of `DocEntry 2345730`?
6. **CONFIRM:** Should `INFORMATION_SCHEMA` job history be materialized before migration?

## Proposed sequence — inactive until all C8 answers exist

1. Export elected job-history evidence.
2. Capture `SAP_LIVE` fingerprints in the old project.
3. Create destination datasets in `asia-southeast1`.
4. Create new service accounts/IAM and rotated secrets.
5. Copy with `bq cp`; verify fingerprints.
6. Parameterize runtime project references without rewriting historical evidence.
7. Create Cloud Run/Scheduler/Eventarc resources disabled.
8. Parallel-run only to a shadow prefix; never write to `gs://interface-file/**`.
9. Cut over only with Boat approval and a rollback executable in under five minutes.

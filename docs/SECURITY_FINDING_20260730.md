# SECURITY FINDING 2026-07-30 — plaintext SAP credentials in deployment surfaces

Status: **PARTIALLY REMEDIATED — SAP DB ROTATION CLOSED; ARCHIVE/SMTP HYGIENE OPEN**

Owner: **Boat** (notified; Boat will coordinate remediation)

Agent authority: **REPORT ONLY — do not read, print, rotate, revoke, or modify credentials**

## Finding

### Reconciliation 2026-08-01

SAP database credential rotation is **CLOSED**. Secret `sap-db-password` version 2 was created and
enabled at `2026-07-31T11:32:25Z`; the exposed version 1 is disabled. Execution
`sap-extract-job-k95ws` succeeded with the replacement secret. The live job binds
`SAP_DB_USER`/`SAP_DB_PASSWORD` through `secretKeyRef key=latest`; describing the job/execution
returns a secret reference, not the credential value. The earlier statement that live job metadata
returned plaintext SAP DB values is retracted.

This correction does not retract the independently observed plaintext assignments in deployed
source/deployment helper archives. Archive purge/history review/access restriction remain open.
The legacy interface functions' SMTP plaintext environment metadata is a separate credential and
also remains open for Boat-owned rotation and Secret Manager migration.

### Addendum 2026-07-31 — legacy interface functions

Read-only metadata inspection found that both deployed legacy interface producers expose an SMTP
credential through plaintext environment-variable metadata rather than a Secret Manager
reference: `rcb-motor-order-payment-sap-bucket-1` and
`rcb-nonmotor-order-payment-sap-bucket-1`. No value, fragment, or masked representation is retained
here. This broadens the existing remediation inventory; no credential was tested, changed, or
rotated by the agent.

The legacy SMTP control failure is plaintext environment metadata. Remediation is Boat-owned
credential rotation followed by a Secret Manager-backed binding and must cover both legacy
functions without agents retrieving or reusing the exposed value. This is not the live
`sap-extract-job` state, whose SAP DB binding is already `secretKeyRef`-backed.

The deployed `sap-extract-job` source/build archive exposed SAP database credentials in helper
files even though the current live runtime binding uses Secret Manager references.

Evidence was observed while performing the read-only
`INCIDENT-SAP-MIRROR-20260726` source audit:

- Cloud Run Job deployment:
  `sap-extract-job`, region `asia-southeast1`, project `pacific-plating-282708`.
- Audited deployed image digest:
  `sha256:ba260c3b828dc0085e8d7c5321c1847362b9204fdec7201a3501ca2bb96e6efe`.
- The deployed source archive contains plaintext credential assignments in deployment helper
  files including `deploy.sh`, `envvars.yaml`, and `update_env2.sh`.
- Cloud Run Job/execution metadata returns the Secret Manager reference. It is not evidence that
  the plaintext SAP DB value is retrievable from current runtime metadata.
- Source/build archive access exposes the same values to principals who can read the Cloud Run
  source-upload bucket or associated build artifacts.

No credential value, partial value, hash, prefix, suffix, or masked rendering is reproduced in
this repository. A temporary local audit copy was deleted immediately after inspection.

## Severity and recurrence

**Historical P0 / third known exposure; rotation closed.** `docs/knowledge/10_SAP_CONTEXT.md` GOVERNANCE already records at
least two earlier credential disclosures. This is a third exposure through different surfaces
(deployment source/archive and Cloud Run metadata), showing the underlying secret-handling control
has not been corrected systemically.

This finding intersects the incident's writer analysis: anyone with the exposed database
credential and network reachability could connect directly to SAP SQL Server. It does not prove
that such access occurred, and the incident's identified operational pathway remains BI interface
import, but credential possession expands the plausible access surface and must be closed.

## Required remediation — Boat/DevOps

1. **CLOSED 2026-07-31:** rotate the SAP database credential; version 2 enabled, version 1 disabled.
2. **CLOSED:** replacement stored in Google Secret Manager.
3. **VERIFIED:** `sap-extract-job` uses `secretKeyRef key=latest`; no rebind is required.
4. Remove credential-bearing helper files from future source archives/build contexts.
5. Determine whether plaintext values exist in Git history, Cloud Build logs/artifacts, source
   upload objects, old Cloud Run revisions, or execution metadata retained by the platform.
6. Restrict read access to source/build artifacts and Cloud Run configuration metadata.
7. Preserve only non-secret audit evidence of rotation time, owner, affected resources and
   verification outcome.
8. Separately rotate the legacy SMTP credential and replace plaintext function environment
   metadata with a Secret Manager reference.

Migration to `sap-b1-374202` should create only the rotated Secret Manager-backed configuration;
it must not copy the exposed value from the old deployment.

## Non-actions by agents

- No credential was changed, disabled, copied into repo, or tested.
- No SAP connection or write was performed.
- No deployed job, revision, loader, scheduler, IAM binding, source archive, or build artifact was
  modified.

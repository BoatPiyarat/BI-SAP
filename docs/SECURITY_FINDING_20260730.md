# SECURITY FINDING 2026-07-30 — plaintext SAP credentials in deployment surfaces

Status: **OPEN — P0**  
Owner: **Boat** (notified; Boat will coordinate remediation)  
Agent authority: **REPORT ONLY — do not read, print, rotate, revoke, or modify credentials**

## Finding

The deployed `sap-extract-job` supply chain exposes SAP database credentials as plaintext
configuration rather than Secret Manager references.

Evidence was observed while performing the read-only
`INCIDENT-SAP-MIRROR-20260726` source audit:

- Cloud Run Job deployment:
  `sap-extract-job`, region `asia-southeast1`, project `pacific-plating-282708`.
- Audited deployed image digest:
  `sha256:ba260c3b828dc0085e8d7c5321c1847362b9204fdec7201a3501ca2bb96e6efe`.
- The deployed source archive contains plaintext credential assignments in deployment helper
  files including `deploy.sh`, `envvars.yaml`, and `update_env2.sh`.
- Cloud Run Job/execution metadata returns the credential environment variables to principals
  who can describe/list executions or job revisions.
- Source/build archive access exposes the same values to principals who can read the Cloud Run
  source-upload bucket or associated build artifacts.

No credential value, partial value, hash, prefix, suffix, or masked rendering is reproduced in
this repository. A temporary local audit copy was deleted immediately after inspection.

## Severity and recurrence

**P0 / third known exposure.** `docs/knowledge/10_SAP_CONTEXT.md` GOVERNANCE already records at
least two earlier credential disclosures. This is a third exposure through different surfaces
(deployment source/archive and Cloud Run metadata), showing the underlying secret-handling control
has not been corrected systemically.

This finding intersects the incident's writer analysis: anyone with the exposed database
credential and network reachability could connect directly to SAP SQL Server. It does not prove
that such access occurred, and the incident's identified operational pathway remains BI interface
import, but credential possession expands the plausible access surface and must be closed.

## Required remediation — Boat/DevOps

1. Rotate the SAP database credential.
2. Store the replacement in Google Secret Manager.
3. Configure Cloud Run with Secret Manager references, not plaintext environment values.
4. Remove credential-bearing helper files from future source archives/build contexts.
5. Determine whether plaintext values exist in Git history, Cloud Build logs/artifacts, source
   upload objects, old Cloud Run revisions, or execution metadata retained by the platform.
6. Restrict read access to source/build artifacts and Cloud Run configuration metadata.
7. Preserve only non-secret audit evidence of rotation time, owner, affected resources and
   verification outcome.

Migration to `sap-b1-374202` should create only the rotated Secret Manager-backed configuration;
it must not copy the exposed value from the old deployment.

## Non-actions by agents

- No credential was changed, disabled, copied into repo, or tested.
- No SAP connection or write was performed.
- No deployed job, revision, loader, scheduler, IAM binding, source archive, or build artifact was
  modified.

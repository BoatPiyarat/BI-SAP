# V3 private delivery promoter — production deployment proposal

Status: **PROPOSED / NOT EXECUTED**  
Target: `projects/pacific-plating-282708/locations/asia-southeast1/services/sap-delivery-promoter`

## Why this is the next workflow prerequisite

The authenticated delivery-control-plane check at `2026-08-27T02:25:17.8741884Z` found the
private promoter absent. SQL prerequisites are now present, but the reviewed workflow replacement
must remain undeployed until this service contract exists. The workflow continues to hardcode
`delivery_enabled:false`; deploying the service does not enable delivery or create a schedule.

## Exact proposed source and runtime contract

- Source: `infra/sap_delivery_promoter/` at the separately reviewed commit.
- Region: `asia-southeast1`.
- Ingress: internal only.
- Authentication: no unauthenticated/public invocation.
- Runtime identity: `919786098205-compute@developer.gserviceaccount.com`.
- Environment:
  - `ARCHIVE_BUCKET=rcb-bronze-zone`
  - `PRODUCTION_BUCKET=interface-file`
  - `PRODUCTION_PREFIX=RCB_MOTOR`
- Invoker: only the workflow's approved default Compute service account (plus any Google-managed
  identities Cloud Run requires internally); never `allUsers` or `allAuthenticatedUsers`.

## Proposed production actions — require explicit scoped approval

From `infra/sap_delivery_promoter/`:

```powershell
gcloud run deploy sap-delivery-promoter `
  --project pacific-plating-282708 `
  --region asia-southeast1 `
  --source . `
  --service-account 919786098205-compute@developer.gserviceaccount.com `
  --ingress internal `
  --no-allow-unauthenticated `
  --set-env-vars ARCHIVE_BUCKET=rcb-bronze-zone,PRODUCTION_BUCKET=interface-file,PRODUCTION_PREFIX=RCB_MOTOR

gcloud run services add-iam-policy-binding sap-delivery-promoter `
  --project pacific-plating-282708 `
  --region asia-southeast1 `
  --member serviceAccount:919786098205-compute@developer.gserviceaccount.com `
  --role roles/run.invoker
```

These actions create a Cloud Run service and change its IAM policy. They must not be inferred from
SQL deployment approval.

## Acceptance before workflow replacement

1. Source tests pass with the pinned `requirements.txt`; image build and revision reach Ready.
2. Service ingress is exactly `internal`; no public invoker member exists.
3. Service account and all three environment values match exactly.
4. A non-mutating/invalid-request probe fails without copying an object; no production-path probe
   is allowed before separate exact-object rehearsal approval.
5. `scripts/check_v3_delivery_control_plane.ps1` reports the promoter present. The Scheduler may
   remain absent at this stage and `delivery_enabled` must remain false.
6. Record revision, image digest, service URL, IAM policy evidence, and checker output.

## Rollback

The prestate is **service absent**. Restoring it requires deleting the exact Cloud Run service and
removing its service-scoped IAM policy, which is destructive and requires separate rollback
approval. Until workflow/scheduler references exist, leaving a private, uninvoked service deployed
is safer than an unapproved deletion.

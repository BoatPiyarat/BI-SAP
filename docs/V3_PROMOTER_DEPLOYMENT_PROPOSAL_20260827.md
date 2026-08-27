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
- Runtime identity: legacy SAP interface identity
  `data-extraction@pacific-plating-282708.iam.gserviceaccount.com`.
- Environment:
  - `ARCHIVE_BUCKET=rcb-bronze-zone`
  - `PRODUCTION_BUCKET=interface-file`
  - `PRODUCTION_PREFIX=RCB_MOTOR`
- Invoker: the workflow's approved default Compute service account already has
  `run.routes.invoke` through its project Editor role. Other pre-existing project principals whose
  roles contain that permission may also invoke; this deployment adds no principal. Never add
  `allUsers` or `allAuthenticatedUsers`.

## Verified no-new-role path

Read-only project and bucket IAM inspection on 2026-08-27 established this no-new-role split:

- deployer `user:data@rabbit.co.th` has project `roles/editor`, including
  `run.services.create` and `iam.serviceAccounts.actAs`;
- caller `serviceAccount:919786098205-compute@developer.gserviceaccount.com` is the existing V3
  workflow identity and has project `roles/editor`, including `run.routes.invoke`;
- runtime `serviceAccount:data-extraction@pacific-plating-282708.iam.gserviceaccount.com` is the
  legacy `sap-interface-pipeline` workflow identity and already has project
  `roles/storage.objectAdmin`; it is also a legacy owner on `gs://interface-file`.

Therefore the workflow already has invocation permission, the deployer can attach the legacy
runtime identity, and that runtime can read the archive object and create the production object.
No service, project, service-account, or bucket IAM binding needs to be added. This proposal does
not broaden or otherwise modify any existing grant.

The IAM ceiling is materially broader than the promoter's intended behavior. Project-level
`roles/storage.objectAdmin` permits the legacy runtime to read, create, overwrite, and delete
objects across project buckets including `rcb-bronze-zone`; its direct
`roles/storage.legacyBucketOwner` on `gs://interface-file` also carries legacy bucket/ACL control.
Archive-read and production-create-only safety are therefore enforced by reviewed application
logic—especially the exact-generation source read and `if_generation_match=0` destination
rewrite—not by least-privilege IAM. Deployment acceptance must verify the reviewed image/source;
it must not describe the identity itself as read/create-only.

This identity is shared with the live `sap-interface-pipeline` workflow and
`demo-nonmotor-bucket` Cloud Run service. Reuse avoids an unavailable IAM grant but creates shared
credential/blast-radius coupling with those legacy paths. No change to either legacy resource is
authorized.

The pre-existing broad Editor role is not presented as an ideal least-privilege end state; changing
it is outside this deployment and would require a separately planned IAM migration.

## Proposed production action — requires explicit scoped approval

From `infra/sap_delivery_promoter/`:

```powershell
gcloud run deploy sap-delivery-promoter `
  --project pacific-plating-282708 `
  --region asia-southeast1 `
  --source . `
  --service-account data-extraction@pacific-plating-282708.iam.gserviceaccount.com `
  --ingress internal `
  --no-allow-unauthenticated `
  --set-env-vars ARCHIVE_BUCKET=rcb-bronze-zone,PRODUCTION_BUCKET=interface-file,PRODUCTION_PREFIX=RCB_MOTOR
```

This action creates a Cloud Run service but makes no IAM-policy change. Service creation must not
be inferred from SQL deployment approval.

## Acceptance before workflow replacement

1. Source tests pass with the pinned `requirements.txt`; image build and revision reach Ready.
2. Service ingress is exactly `internal`; no public invoker member exists and no IAM binding was
   added by this deployment.
3. Service account and all three environment values match exactly.
4. A non-mutating/invalid-request probe fails without copying an object; no production-path probe
   is allowed before separate exact-object rehearsal approval.
5. `scripts/check_v3_delivery_control_plane.ps1` reports the promoter present. The Scheduler may
   remain absent at this stage and `delivery_enabled` must remain false.
6. Record revision, image digest, service URL, IAM policy evidence, and checker output.

## Rollback

The prestate is **service absent**. Restoring it requires deleting the exact Cloud Run service,
which is destructive and requires separate rollback approval. There is no deployment-created IAM
binding to remove. Until workflow/scheduler references exist, leaving a private, uninvoked service
deployed is safer than an unapproved deletion.

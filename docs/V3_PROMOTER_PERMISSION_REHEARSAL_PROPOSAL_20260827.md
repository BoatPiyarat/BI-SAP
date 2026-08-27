# V3 promoter no-write permission rehearsal proposal — 2026-08-27

Status: source only; not deployed or executed.

## Purpose

Prove that the deployed workflow identity can invoke the private promoter and reach its application
validator without reading or writing GCS, running BigQuery, extracting SAP, or entering any normal
nightly/post-import path. Configuration readiness currently reports
`permission_rehearsal_required:true`; this closes that gate only.

## Source change

`infra/v3_nightly_orchestrator.workflows.yaml` adds boolean argument
`permission_rehearsal_only`, default false. When true, the first step after initialization:

1. requires the exact canonical promoter URL and forbids post-import arguments;
2. sends authenticated OIDC POST `{}` to exact `/promote`;
3. accepts only HTTP 400 containing validator text
   `missing required field: archive_bucket`;
4. returns `PROMOTER_AUTH_REACHED_VALIDATOR` with HTTP 400;
5. raises on any 2xx, 401/403/404, different 400, or transport/auth failure.

The branch is before post-import binding, run-log writes, extract, GCS, BigQuery, Units 2–6,
delivery, and alerts. It directly returns or raises and cannot fall through. The normal default
path is unchanged and retains literal `delivery_enabled:false`.

Static regression checker `scripts/check_v3_promoter_permission_rehearsal.py` was observed RED on
the pre-change source and now parses all 14 top-level YAML definitions and returns
`PROMOTER_PERMISSION_REHEARSAL_STATIC=PASS`. It checks branch ordering, exact URL/OIDC/empty-body/
expected-validator markers, delivery false, and absence of side-effect markers in the branch.

## Deployment boundary

After Class-A PASS, deploy only the revised workflow under its existing default Compute service
account. Keep the canonical Scheduler PAUSED. Do not execute the rehearsal until the deployment
progress/evidence update is reviewed and committed.

```powershell
gcloud workflows deploy v3-nightly-orchestrator `
  --project pacific-plating-282708 `
  --location asia-southeast1 `
  --source infra/v3_nightly_orchestrator.workflows.yaml `
  --service-account 919786098205-compute@developer.gserviceaccount.com `
  --quiet
```

Post-deploy require exact source identity except comment-only CLI serialization, ACTIVE state,
delivery false, Scheduler PAUSED, and zero executions since the deployment lower bound. Update
OneDrive evidence and obtain Class-A PASS before the rehearsal execution.

## Exact bounded execution

After the deployment checkpoint:

```powershell
$rehearsalLowerBound = [DateTimeOffset]::UtcNow.ToString('o')
$argument = @{
  permission_rehearsal_only = $true
  promotion_service_url = 'https://sap-delivery-promoter-3uymtccdma-as.a.run.app'
} | ConvertTo-Json -Compress
gcloud workflows run v3-nightly-orchestrator `
  --project pacific-plating-282708 `
  --location asia-southeast1 `
  --data=$argument
```

This is one manual execution only. Do not run or resume Scheduler and do not set delivery true.

## Required execution evidence

1. Exact execution state SUCCEEDED and result marker
   `PROMOTER_AUTH_REACHED_VALIDATOR` / HTTP 400.
2. Cloud Run request log on promoter revision `sap-delivery-promoter-00001-grm` showing the same
   request window and HTTP 400.
3. Cloud Audit Logs from `$rehearsalLowerBound` showing zero GCS create/update/delete events by
   promoter runtime `data-extraction@pacific-plating-282708.iam.gserviceaccount.com`.
4. BigQuery job audit from the same bound showing zero jobs by workflow identity
   `919786098205-compute@developer.gserviceaccount.com` attributable to the rehearsal window.
5. Query Cloud Run job executions for job `sap-extract-job` in project
   `pacific-plating-282708`, region `asia-southeast1`, using inclusive filter
   `createTime>=$rehearsalLowerBound`, limit 1, format `value(name,createTime,completionTime)`;
   require returned count zero. Scheduler must remain PAUSED and workflow delivery false.
6. OneDrive evidence/progress update plus Class-A PASS before any further deployment or run.

## Rollback

Scheduler stays PAUSED. Restore prior workflow revision/source `000010-daf` from commit `8a420d7`
under the same service account if the new revision fails static/live verification. The rehearsal
itself creates only immutable workflow/request logs; no compensating data deletion is required.

## Non-goals and retained blockers

This does not approve production GCS writes, delivery, Scheduler resume, scenario activation,
threshold bootstrap, SAP pickup/import, or ACK. Exact Unit 2 thresholds and the atomic legacy/V3
non-overlap cutover remain outstanding.

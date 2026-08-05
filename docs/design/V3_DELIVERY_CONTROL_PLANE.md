# V3 outbound delivery control plane

Status: source-only administrator handoff. This prepares an inert private promoter and a PAUSED
recurring trigger. It does not enable delivery, execute the workflow, write GCS, change SAP, or
replace the Gmail/post-import activation sequence.

Run only after the two-name delivery/result contract passes Class-A review. The deployment review
must cover the exact source commit and the commands below before an administrator runs them.

## Fixed boundary

```powershell
$project = 'pacific-plating-282708'
$projectNumber = '919786098205'
$region = 'asia-southeast1'
$workflow = 'v3-nightly-orchestrator'
$promoter = 'sap-delivery-promoter'
$scheduler = 'v3-nightly-orchestrator'
$promoterSa = "sap-delivery-promoter@$project.iam.gserviceaccount.com"
$triggerSa = "v3-nightly-trigger@$project.iam.gserviceaccount.com"
$workflowPrefix =
  "projects/$projectNumber/locations/$region/workflows/$workflow"
$archiveObjectPrefix =
  'projects/_/buckets/rcb-bronze-zone/objects/sap-interface-archive/'
$productionObjectPrefix =
  'projects/_/buckets/interface-file/objects/RCB_MOTOR/'
```

Use an administrator account with service-account, custom-role, project/bucket/Cloud Run IAM,
Cloud Build/Artifact Registry, Cloud Run deployment, Workflows deployment, and Cloud Scheduler
administration permissions. Do not substitute a broad runtime identity when one of the dedicated
identities cannot be created.

## Phase A — deploy the promoter privately

Create the dedicated identity if it does not already exist:

```powershell
gcloud iam service-accounts describe $promoterSa --project=$project
if ($LASTEXITCODE -ne 0) {
  gcloud iam service-accounts create 'sap-delivery-promoter' --project=$project `
    --display-name='SAP exact-generation delivery promoter'
}
```

Grant only the object operations used by the service. Every bucket binding is conditional; an
unconditioned bucket or project grant does not satisfy this runbook. Production needs both create
and get: `destination.rewrite(..., if_generation_match=0)` creates, then `destination.reload()`
reads back size/CRC32C/generation before the service returns evidence.

```powershell
$archiveCondition =
  "expression=resource.name.startsWith('$archiveObjectPrefix')," +
  'title=sap_archive_exact_prefix,' +
  'description=Read only retained V3 SAP archive objects'
$productionCondition =
  "expression=resource.name.startsWith('$productionObjectPrefix')," +
  'title=sap_production_exact_prefix,' +
  'description=Create only beneath the SAP RCB_MOTOR delivery prefix'

gcloud storage buckets add-iam-policy-binding gs://rcb-bronze-zone `
  --project=$project --member="serviceAccount:$promoterSa" `
  --role='roles/storage.objectViewer' --condition=$archiveCondition
gcloud storage buckets add-iam-policy-binding gs://interface-file `
  --project=$project --member="serviceAccount:$promoterSa" `
  --role='roles/storage.objectCreator' --condition=$productionCondition
gcloud storage buckets add-iam-policy-binding gs://interface-file `
  --project=$project --member="serviceAccount:$promoterSa" `
  --role='roles/storage.objectViewer' --condition=$productionCondition
```

Deploy without allowing public invocation. This creates runtime infrastructure but does not call
`POST /promote`; therefore it performs no GCS read or write.

```powershell
gcloud run deploy $promoter --project=$project --region=$region `
  --source='infra/sap_delivery_promoter' --service-account=$promoterSa `
  --ingress=internal --no-allow-unauthenticated `
  --set-env-vars='ARCHIVE_BUCKET=rcb-bronze-zone,PRODUCTION_BUCKET=interface-file,PRODUCTION_PREFIX=RCB_MOTOR'

$workflowSa = (
  gcloud workflows describe $workflow --project=$project --location=$region `
    --format='value(serviceAccount)'
)
if ($LASTEXITCODE -ne 0 -or -not $workflowSa) {
  throw 'Cannot resolve the deployed workflow service account'
}
$workflowSa = $workflowSa.Replace('projects/-/serviceAccounts/', '')
gcloud run services add-iam-policy-binding $promoter `
  --project=$project --region=$region `
  --member="serviceAccount:$workflowSa" --role='roles/run.invoker'
```

Do not invoke the promoter as a health check: a valid request writes the production bucket and an
invalid request does not prove GCS permissions. Ready revision, private IAM, environment, and
prefix-scoped bucket policies are the inert control-plane evidence.

## Phase B — create the recurring trigger PAUSED

The trigger receives only the private promoter URL. The workflow itself derives both shard-bearing
filenames after exactly-one archive-object census. It must not receive a filename from Scheduler.

Create a custom execution-creator role if absent. If it already exists, describe it and require
that its only included permission is `workflows.executions.create`.

```powershell
gcloud iam roles describe nightlyWorkflowCreator --project=$project
if ($LASTEXITCODE -ne 0) {
  gcloud iam roles create nightlyWorkflowCreator --project=$project `
    --title='Nightly V3 workflow execution creator' `
    --description='Create executions only; binding restricted to the V3 workflow.' `
    --permissions='workflows.executions.create' --stage=GA
}

gcloud iam service-accounts describe $triggerSa --project=$project
if ($LASTEXITCODE -ne 0) {
  gcloud iam service-accounts create 'v3-nightly-trigger' --project=$project `
    --display-name='V3 nightly workflow trigger'
}

$workflowCondition =
  "expression=resource.name.startsWith('$workflowPrefix')," +
  'title=v3_nightly_one_workflow,' +
  'description=Restrict nightly trigger to v3-nightly-orchestrator'
gcloud projects add-iam-policy-binding $project `
  --member="serviceAccount:$triggerSa" `
  --role="projects/$project/roles/nightlyWorkflowCreator" `
  --condition=$workflowCondition
```

Create with a dormant placeholder cadence, pause immediately, then update the intended cadence.
Do not create it directly at 20:30 because it could fire between creation and the pause command.

```powershell
$promoterUrl = (
  gcloud run services describe $promoter --project=$project --region=$region `
    --format='value(status.url)'
)
if ($LASTEXITCODE -ne 0 -or -not $promoterUrl) {
  throw 'Cannot resolve the promoter URL'
}
$executionUri =
  "https://workflowexecutions.googleapis.com/v1/projects/$project/locations/$region/" +
  "workflows/$workflow/executions"
$argument = @{ promotion_service_url = $promoterUrl } | ConvertTo-Json -Compress
$messageBody = @{ argument = $argument } | ConvertTo-Json -Compress

gcloud scheduler jobs create http $scheduler --project=$project --location=$region `
  --schedule='0 0 1 1 *' --time-zone='Asia/Bangkok' `
  --uri=$executionUri --http-method=POST `
  --oauth-service-account-email=$triggerSa `
  --oauth-token-scope='https://www.googleapis.com/auth/cloud-platform' `
  --headers='Content-Type=application/json' --message-body=$messageBody
gcloud scheduler jobs pause $scheduler --project=$project --location=$region
gcloud scheduler jobs update http $scheduler --project=$project --location=$region `
  --schedule='30 20 * * *' --time-zone='Asia/Bangkok' `
  --uri=$executionUri --http-method=POST `
  --oauth-service-account-email=$triggerSa `
  --oauth-token-scope='https://www.googleapis.com/auth/cloud-platform' `
  --headers='Content-Type=application/json' --message-body=$messageBody
```

Do not run or resume it here.

## Machine gate

Run:

```powershell
.\scripts\check_v3_delivery_control_plane.ps1
```

Require `safety_passed=true` and `control_plane_ready=true`. The checker requires:

- an ACTIVE workflow that still contains `delivery_enabled: false` and the two-name markers;
- a Ready, internal-only promoter on its dedicated identity with no public invoker;
- exact workflow identity `run.invoker`;
- conditional archive `objectViewer`, production `objectCreator`, and production `objectViewer`
  bindings on only the two closed prefixes;
- a GA `nightlyWorkflowCreator` role containing only `workflows.executions.create`, conditionally
  bound to the trigger identity on only the exact V3 workflow, with no predefined Workflows
  Invoker grant;
- exactly one PAUSED `20:30` Asia/Bangkok scheduler whose endpoint, OAuth identity, and decoded
  execution argument bind the exact workflow and promoter URL.

Retain the checker JSON and the full resource/IAM descriptions for the deployment review.

## Separate production gates

Control-plane readiness is not delivery authorization. The following remain separate, ordered
Class-A changes:

1. deploy DDL 070 before DDL 062, then the corrected DDL 074 and delivery-disabled workflow;
2. complete Apps Script owner OAuth and the post-import synthetic/one-mail-cycle rehearsal;
3. obtain a separately scoped production-GCS-write approval for one exact controlled file;
4. change the reviewed workflow source from `delivery_enabled: false` to `true`, deploy it, and
   run one bounded execution with the recurring trigger still PAUSED;
5. require exact archive/production generations, size, CRC32C, SHA-256, both filenames, SAP
   pickup, row-level result ingestion, second mirror, and conservation;
6. only then review one atomic cutover that resumes this trigger and pauses the overlapping legacy
   producers.

The scheduler remains PAUSED and delivery remains false if any gate fails.

## Rollback

Pause the V3 trigger first. Restore the prior delivery-disabled workflow revision; do not delete
the promoter, scheduler, IAM evidence, GCS objects, delivery manifests, mailbox rows, or workflow
executions. Re-enable a legacy producer only as part of the reviewed atomic cutover rollback, never
as an isolated guess about its current state.

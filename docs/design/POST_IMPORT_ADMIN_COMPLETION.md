# Post-import administrator completion

Status: source-only administrator handoff. These commands mutate IAM and runtime configuration.
Do not run until this artifact passes Class-A review. Do not set the Apps Script
`POST_IMPORT_REFRESH_TOPIC` in this runbook.

## Fixed resources

```powershell
$project = 'pacific-plating-282708'
$projectNumber = '919786098205'
$region = 'asia-southeast1'
$workflow = 'v3-nightly-orchestrator'
$dispatcher = 'sap-post-import-dispatcher'
$watchdog = 'sap-post-import-watchdog'
$dispatcherSa = "sap-post-import-dispatch@$project.iam.gserviceaccount.com"
$watchdogSa = "sap-post-import-watchdog@$project.iam.gserviceaccount.com"
$pushSa = "sap-post-import-push@$project.iam.gserviceaccount.com"
$pubsubAgent = "service-$projectNumber@gcp-sa-pubsub.iam.gserviceaccount.com"
$workflowPrefix =
  "projects/$projectNumber/locations/$region/workflows/$workflow"
$dispatcherUrl = (
  gcloud run services describe $dispatcher --project=$project --region=$region `
    --format='value(status.url)'
)
if ($LASTEXITCODE -ne 0 -or -not $dispatcherUrl) {
  throw 'Cannot resolve dispatcher URL'
}
```

Run under an administrator account that has `iam.roles.create`,
`resourcemanager.projects.setIamPolicy`, `run.services.setIamPolicy`,
`pubsub.topics.setIamPolicy`, `pubsub.subscriptions.setIamPolicy`,
`iam.serviceAccounts.setIamPolicy`, and the necessary BigQuery resource-policy permissions.

## Workflows roles — do not substitute predefined Invoker

The predefined `roles/workflows.invoker` combines create, get, and cancel. Keep dispatcher and
watchdog permissions separate:

```powershell
gcloud iam roles create postImportWorkflowCreator --project=$project `
  --title='Post-import workflow execution creator' `
  --description='Create executions only; binding restricted to V3 workflow.' `
  --permissions='workflows.executions.create' --stage=GA

gcloud iam roles create postImportWorkflowMonitor --project=$project `
  --title='Post-import workflow execution monitor' `
  --description='Get and cancel executions only; binding restricted to V3 workflow.' `
  --permissions='workflows.executions.get,workflows.executions.cancel' --stage=GA

$workflowCondition =
  "expression=resource.name.startsWith('$workflowPrefix')," +
  'title=post_import_one_workflow,' +
  'description=Restrict post-import runtime to v3-nightly-orchestrator'

gcloud projects add-iam-policy-binding $project `
  --member="serviceAccount:$dispatcherSa" `
  --role="projects/$project/roles/postImportWorkflowCreator" `
  --condition=$workflowCondition

gcloud projects add-iam-policy-binding $project `
  --member="serviceAccount:$watchdogSa" `
  --role="projects/$project/roles/postImportWorkflowMonitor" `
  --condition=$workflowCondition
```

After each command, inspect the returned policy. The custom roles must contain only the listed
permissions, and the condition must retain the exact workflow prefix.

## BigQuery boundary — explicit Boat decision required

Both runtimes require project-level job creation:

```powershell
gcloud projects add-iam-policy-binding $project `
  --member="serviceAccount:$dispatcherSa" --role='roles/bigquery.jobUser' --condition=None
gcloud projects add-iam-policy-binding $project `
  --member="serviceAccount:$watchdogSa" --role='roles/bigquery.jobUser' --condition=None
```

The current reviewed code also requires table-level Data Editor on exactly
`v3_post_import_refresh_outbox`; it must not receive dataset-level Data Editor. This exact-table
grant allows direct DML outside the procedures. Run the following block only after Boat explicitly
approves that risk:

```powershell
bq add-iam-policy-binding --table `
  --member="serviceAccount:$dispatcherSa" --role='roles/bigquery.dataEditor' `
  "${project}:sap_integration_v3.v3_post_import_refresh_outbox"
bq add-iam-policy-binding --table `
  --member="serviceAccount:$watchdogSa" --role='roles/bigquery.dataEditor' `
  "${project}:sap_integration_v3.v3_post_import_refresh_outbox"

bq add-iam-policy-binding --routine `
  --member="serviceAccount:$dispatcherSa" --role='roles/bigquery.dataViewer' `
  "${project}:sap_integration_v3.sp_claim_v3_post_import_refresh"
bq add-iam-policy-binding --routine `
  --member="serviceAccount:$dispatcherSa" --role='roles/bigquery.dataViewer' `
  "${project}:sap_integration_v3.sp_release_v3_post_import_claim"
bq add-iam-policy-binding --routine `
  --member="serviceAccount:$watchdogSa" --role='roles/bigquery.dataViewer' `
  "${project}:sap_integration_v3.sp_release_v3_post_import_claim"
bq add-iam-policy-binding --routine `
  --member="serviceAccount:$watchdogSa" --role='roles/bigquery.dataViewer' `
  "${project}:sap_integration_v3.sp_complete_v3_post_import_refresh"
```

If Boat does not approve, stop. The alternative is a separately reviewed authorized-routine
design in a different dataset; BigQuery documents authorized routines as cross-dataset resources,
which conflicts with the current v3-only DDL rule.

## Exact service and Pub/Sub IAM

```powershell
gcloud run services add-iam-policy-binding $dispatcher `
  --project=$project --region=$region `
  --member="serviceAccount:$pushSa" --role='roles/run.invoker' --condition=None

gcloud pubsub topics add-iam-policy-binding v3-orchestrator-alerts `
  --project=$project --member="serviceAccount:$watchdogSa" `
  --role='roles/pubsub.publisher' --condition=None

gcloud iam service-accounts add-iam-policy-binding $pushSa --project=$project `
  --member="serviceAccount:$pubsubAgent" `
  --role='roles/iam.serviceAccountTokenCreator' --condition=None

gcloud pubsub topics add-iam-policy-binding sap-post-import-refresh-dlq `
  --project=$project --member="serviceAccount:$pubsubAgent" `
  --role='roles/pubsub.publisher' --condition=None
```

Create the authenticated push subscription only after all bindings above succeed:

```powershell
$pushEndpoint = "$dispatcherUrl/dispatch"
gcloud pubsub subscriptions create sap-post-import-refresh-push `
  --project=$project --topic=sap-post-import-refresh `
  --push-endpoint=$pushEndpoint --push-auth-service-account=$pushSa `
  --push-auth-token-audience=$pushEndpoint `
  --dead-letter-topic=sap-post-import-refresh-dlq --max-delivery-attempts=5 `
  --ack-deadline=600 --min-retry-delay=10s --max-retry-delay=600s `
  --message-retention-duration=14d --expiration-period=never

gcloud pubsub subscriptions add-iam-policy-binding sap-post-import-refresh-push `
  --project=$project --member="serviceAccount:$pubsubAgent" `
  --role='roles/pubsub.subscriber' --condition=None
```

## Watchdog scheduler — create paused, do not execute

Allow the watchdog identity to invoke only its job:

```powershell
gcloud run jobs add-iam-policy-binding $watchdog `
  --project=$project --region=$region `
  --member="serviceAccount:$watchdogSa" --role='roles/run.invoker' --condition=None
```

Cloud Scheduler has no create-paused flag. Create it with a deliberately dormant leap-day
schedule, pause it immediately, then update the cadence while it remains paused:

```powershell
$runUri =
  "https://${region}-run.googleapis.com/apis/run.googleapis.com/v1/" +
  "namespaces/$projectNumber/jobs/${watchdog}:run"

gcloud scheduler jobs create http $watchdog --project=$project --location=$region `
  --schedule='0 0 29 2 *' --time-zone='Asia/Bangkok' `
  --uri=$runUri --http-method=POST --headers='Content-Type=application/json' `
  --message-body='{}' `
  --oauth-service-account-email=$watchdogSa `
  --oauth-token-scope='https://www.googleapis.com/auth/cloud-platform' `
  --attempt-deadline=900s
if ($LASTEXITCODE -ne 0) { throw 'Scheduler creation failed' }
gcloud scheduler jobs pause $watchdog --project=$project --location=$region
if ($LASTEXITCODE -ne 0) { throw 'Scheduler pause failed; stop and inspect immediately' }
gcloud scheduler jobs update http $watchdog --project=$project --location=$region `
  --schedule='*/2 * * * *' --time-zone='Asia/Bangkok'
```

Do not resume the scheduler here.

## Verification and next gate

Run:

```powershell
.\scripts\check_post_import_activation.ps1
```

Require `safety_passed=true`, `rehearsal_ready=true`, the watchdog scheduler `PAUSED`, and no
watchdog executions. Then run the separately reviewed ten-case synthetic rehearsal. Only after
that rehearsal may the Apps Script owner set `POST_IMPORT_REFRESH_TOPIC=sap-post-import-refresh`,
perform one bounded mailbox poll, and later resume the watchdog scheduler. Production delivery
remains separately gated by `delivery_enabled: false`.

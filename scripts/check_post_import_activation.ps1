[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$project = 'pacific-plating-282708'
$region = 'asia-southeast1'
$workflowName = 'v3-nightly-orchestrator'
$dispatcherName = 'sap-post-import-dispatcher'
$watchdogName = 'sap-post-import-watchdog'
$pushSubscriptionName = 'sap-post-import-refresh-push'
$watchdogSchedulerName = 'sap-post-import-watchdog'
$dispatcherServiceAccount =
  'sap-post-import-dispatch@pacific-plating-282708.iam.gserviceaccount.com'
$watchdogServiceAccount =
  'sap-post-import-watchdog@pacific-plating-282708.iam.gserviceaccount.com'
$pushServiceAccount =
  'serviceAccount:sap-post-import-push@pacific-plating-282708.iam.gserviceaccount.com'

function Invoke-GcloudJson {
  param(
    [Parameter(Mandatory)] [string[]]$CommandArgs
  )

  $output = & gcloud @CommandArgs --format=json
  if ($LASTEXITCODE -ne 0) {
    throw "gcloud $($CommandArgs -join ' ') failed with exit code $LASTEXITCODE"
  }
  return ($output | ConvertFrom-Json)
}

function Get-EnvMap {
  param(
    [Parameter(Mandatory)] $Variables
  )

  $result = @{}
  foreach ($variable in @($Variables)) {
    $result[$variable.name] = $variable.value
  }
  return $result
}

$workflow = Invoke-GcloudJson @(
  'workflows', 'describe', $workflowName,
  "--project=$project", "--location=$region"
)
$dispatcher = Invoke-GcloudJson @(
  'run', 'services', 'describe', $dispatcherName,
  "--project=$project", "--region=$region"
)
$dispatcherPolicy = Invoke-GcloudJson @(
  'run', 'services', 'get-iam-policy', $dispatcherName,
  "--project=$project", "--region=$region"
)
$watchdog = Invoke-GcloudJson @(
  'run', 'jobs', 'describe', $watchdogName,
  "--project=$project", "--region=$region"
)
$topics = @(
  Invoke-GcloudJson @('pubsub', 'topics', 'list', "--project=$project")
)
$subscriptions = @(
  Invoke-GcloudJson @('pubsub', 'subscriptions', 'list', "--project=$project")
)
$schedulers = @(
  Invoke-GcloudJson @(
    'scheduler', 'jobs', 'list', "--project=$project", "--location=$region"
  )
)

$workflowSource = [string]$workflow.sourceContents
$dispatcherAnnotations = $dispatcher.metadata.annotations
$dispatcherEnv = Get-EnvMap $dispatcher.spec.template.spec.containers[0].env
$watchdogExecutionSpec = $watchdog.spec.template.spec
$watchdogTaskSpec = $watchdogExecutionSpec.template.spec
$watchdogEnv = Get-EnvMap $watchdogTaskSpec.containers[0].env
$dispatcherMembers = @()
if ($dispatcherPolicy.PSObject.Properties.Name -contains 'bindings') {
  $dispatcherMembers = @(
    $dispatcherPolicy.bindings |
      ForEach-Object { $_.members } |
      Where-Object { $_ }
  )
}
$topicNames = @($topics | ForEach-Object { $_.name })
$pushSubscription = @(
  $subscriptions |
    Where-Object { $_.name -eq "projects/$project/subscriptions/$pushSubscriptionName" }
)
$watchdogScheduler = @(
  $schedulers |
    Where-Object { $_.name -eq "projects/$project/locations/$region/jobs/$watchdogSchedulerName" }
)

$safetyFailures = @()
if ($workflow.state -ne 'ACTIVE') {
  $safetyFailures += "workflow state is $($workflow.state), not ACTIVE"
}
if ($workflowSource -notmatch 'delivery_enabled:\s*false') {
  $safetyFailures += 'workflow delivery_enabled is not visibly false'
}
if ($workflowSource -notmatch 'sp_reconcile_v3_post_import_rows') {
  $safetyFailures += 'workflow lacks the exact post-import reconciliation marker'
}
if ($dispatcherAnnotations.'run.googleapis.com/ingress' -ne 'internal') {
  $safetyFailures += 'dispatcher ingress is not internal'
}
if ($dispatcher.status.latestReadyRevisionName -ne
    $dispatcher.status.latestCreatedRevisionName) {
  $safetyFailures += 'dispatcher latest revision is not Ready'
}
if ($dispatcher.spec.template.spec.serviceAccountName -ne $dispatcherServiceAccount) {
  $safetyFailures += 'dispatcher uses the wrong service account'
}
if ($dispatcherMembers -contains 'allUsers') {
  $safetyFailures += 'dispatcher permits unauthenticated allUsers invocation'
}
if ($watchdogTaskSpec.serviceAccountName -ne $watchdogServiceAccount) {
  $safetyFailures += 'watchdog uses the wrong service account'
}
if ([int]$watchdogTaskSpec.maxRetries -ne 0 -or
    [int]$watchdogExecutionSpec.parallelism -ne 1) {
  $safetyFailures += 'watchdog retry/parallelism bounds differ from 0/1'
}
if ($watchdogEnv.CLAIM_TIMEOUT_SECONDS -ne '600' -or
    $watchdogEnv.EXECUTION_TIMEOUT_SECONDS -ne '900' -or
    $watchdogEnv.CANCEL_WAIT_SECONDS -ne '120') {
  $safetyFailures += 'watchdog timeout configuration differs from 600/900/120'
}
foreach ($topic in @(
  "projects/$project/topics/sap-post-import-refresh",
  "projects/$project/topics/sap-post-import-refresh-dlq"
)) {
  if ($topicNames -notcontains $topic) {
    $safetyFailures += "missing topic $topic"
  }
}

$readinessBlockers = @()
if ($dispatcherMembers -notcontains $pushServiceAccount) {
  $readinessBlockers += 'push identity lacks dispatcher run.invoker'
}
if ($pushSubscription.Count -ne 1) {
  $readinessBlockers += 'authenticated push subscription is absent'
}
if ($watchdogScheduler.Count -ne 1) {
  $readinessBlockers += 'watchdog scheduler is absent'
}
elseif ($watchdogScheduler[0].state -ne 'PAUSED') {
  $readinessBlockers +=
    "watchdog scheduler must remain PAUSED before rehearsal (state=$($watchdogScheduler[0].state))"
}

[pscustomobject]@{
  checked_at = (Get-Date).ToUniversalTime().ToString('o')
  project = $project
  workflow_revision = $workflow.revisionId
  dispatcher_revision = $dispatcher.status.latestReadyRevisionName
  dispatcher_environment = $dispatcherEnv
  watchdog_image = $watchdogTaskSpec.containers[0].image
  watchdog_environment = $watchdogEnv
  safety_passed = ($safetyFailures.Count -eq 0)
  safety_failures = $safetyFailures
  rehearsal_ready = ($safetyFailures.Count -eq 0 -and $readinessBlockers.Count -eq 0)
  readiness_blockers = $readinessBlockers
} | ConvertTo-Json -Depth 6

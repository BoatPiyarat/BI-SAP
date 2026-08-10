[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$project = 'pacific-plating-282708'
$projectNumber = '919786098205'
$region = 'asia-southeast1'
$workflowName = 'v3-nightly-orchestrator'
$promoterName = 'sap-delivery-promoter'
$schedulerName = 'v3-nightly-orchestrator'
$defaultServiceAccountEmail =
  '919786098205-compute@developer.gserviceaccount.com'
$promoterServiceAccountEmail = $defaultServiceAccountEmail
$triggerServiceAccountEmail = $defaultServiceAccountEmail
$executionUri =
  "https://workflowexecutions.googleapis.com/v1/projects/$project/locations/$region/" +
  "workflows/$workflowName/executions"

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

function ConvertFrom-Base64Json {
  param(
    [Parameter(Mandatory)] [string]$Value
  )

  try {
    $bytes = [Convert]::FromBase64String($Value)
    return ([Text.Encoding]::UTF8.GetString($bytes) | ConvertFrom-Json)
  }
  catch {
    return $null
  }
}

$workflow = Invoke-GcloudJson @(
  'workflows', 'describe', $workflowName,
  "--project=$project", "--location=$region"
)
$services = @(
  Invoke-GcloudJson @(
    'run', 'services', 'list', "--project=$project", "--region=$region"
  )
)
$schedulers = @(
  Invoke-GcloudJson @(
    'scheduler', 'jobs', 'list', "--project=$project", "--location=$region"
  )
)
$workflowSource = [string]$workflow.sourceContents
$workflowServiceAccountEmail = ([string]$workflow.serviceAccount) -replace (
  '^projects/[^/]+/serviceAccounts/', ''
)
$promoterSummary = @(
  $services |
    Where-Object { $_.metadata.name -eq $promoterName }
)
$schedulerSummary = @(
  $schedulers |
    Where-Object {
      $_.name -eq "projects/$project/locations/$region/jobs/$schedulerName"
    }
)
$safetyFailures = @()
if ($workflow.state -ne 'ACTIVE') {
  $safetyFailures += "workflow state is $($workflow.state), not ACTIVE"
}
if ($workflowSource -notmatch '(?m)^\s*-\s+delivery_enabled:\s*false\s*$' -or
    $workflowSource -match '(?m)^\s*-\s+delivery_enabled:\s*true\s*$') {
  $safetyFailures += 'workflow must remain delivery-disabled before cutover'
}
if ($workflowServiceAccountEmail -ne $defaultServiceAccountEmail) {
  $safetyFailures += 'workflow does not use the approved default Compute service account'
}
foreach ($marker in @(
  'production_file_name',
  'sap_result_file_name',
  'RCB_MOTOR_',
  'sp_mark_v3_exact_delivery'
)) {
  if ($workflowSource -notmatch [regex]::Escape($marker)) {
    $safetyFailures += "workflow lacks two-name delivery marker: $marker"
  }
}
if ($schedulerSummary.Count -gt 1) {
  $safetyFailures += 'multiple recurring V3 schedulers have the canonical name'
}
if ($schedulerSummary.Count -eq 1 -and $schedulerSummary[0].state -ne 'PAUSED') {
  $safetyFailures +=
    "recurring V3 scheduler must remain PAUSED before cutover " +
    "(state=$($schedulerSummary[0].state))"
}

$readinessBlockers = @()
$promoter = $null
$promoterPolicy = $null
$promoterEnv = @{}
if ($promoterSummary.Count -ne 1) {
  $readinessBlockers += 'private delivery promoter is absent'
}
else {
  $promoter = Invoke-GcloudJson @(
    'run', 'services', 'describe', $promoterName,
    "--project=$project", "--region=$region"
  )
  $promoterPolicy = Invoke-GcloudJson @(
    'run', 'services', 'get-iam-policy', $promoterName,
    "--project=$project", "--region=$region"
  )
  $promoterEnv = Get-EnvMap $promoter.spec.template.spec.containers[0].env
  $promoterMembers = @(
    $promoterPolicy.bindings |
      ForEach-Object { $_.members } |
      Where-Object { $_ }
  )
  if ($promoter.metadata.annotations.'run.googleapis.com/ingress' -ne 'internal') {
    $readinessBlockers += 'promoter ingress is not internal'
  }
  if ($promoter.status.latestReadyRevisionName -ne
      $promoter.status.latestCreatedRevisionName) {
    $readinessBlockers += 'promoter latest revision is not Ready'
  }
  if ($promoter.spec.template.spec.serviceAccountName -ne
      $promoterServiceAccountEmail) {
    $readinessBlockers += 'promoter uses the wrong service account'
  }
  if ($promoterMembers -contains 'allUsers' -or
      $promoterMembers -contains 'allAuthenticatedUsers') {
    $readinessBlockers += 'promoter permits a public invocation principal'
  }
  if ($promoterEnv.ARCHIVE_BUCKET -ne 'rcb-bronze-zone' -or
      $promoterEnv.PRODUCTION_BUCKET -ne 'interface-file' -or
      $promoterEnv.PRODUCTION_PREFIX -ne 'RCB_MOTOR') {
    $readinessBlockers += 'promoter bucket/prefix environment differs from the closed contract'
  }
}

if ($schedulerSummary.Count -ne 1) {
  $readinessBlockers += 'PAUSED recurring V3 scheduler is absent'
}
else {
  $scheduler = $schedulerSummary[0]
  if ($scheduler.schedule -ne '30 20 * * *' -or
      $scheduler.timeZone -ne 'Asia/Bangkok') {
    $readinessBlockers += 'recurring V3 scheduler cadence/time zone differs from 20:30 ICT'
  }
  if ($scheduler.httpTarget.uri -ne $executionUri -or
      $scheduler.httpTarget.httpMethod -ne 'POST') {
    $readinessBlockers += 'recurring V3 scheduler targets the wrong executions endpoint/method'
  }
  if ($scheduler.httpTarget.oauthToken.serviceAccountEmail -ne
      $triggerServiceAccountEmail) {
    $readinessBlockers += 'recurring V3 scheduler uses the wrong OAuth service account'
  }
  $schedulerBody = ConvertFrom-Base64Json ([string]$scheduler.httpTarget.body)
  if ($null -eq $schedulerBody -or
      -not ($schedulerBody.PSObject.Properties.Name -contains 'argument')) {
    $readinessBlockers += 'recurring V3 scheduler body is not a valid execution argument'
  }
  else {
    try {
      $argument = [string]$schedulerBody.argument | ConvertFrom-Json
      if ([string]::IsNullOrEmpty([string]$argument.promotion_service_url) -or
          $null -eq $promoter -or
          $argument.promotion_service_url -ne $promoter.status.url) {
        $readinessBlockers += 'scheduler argument does not bind the exact promoter URL'
      }
    }
    catch {
      $readinessBlockers += 'scheduler argument is not valid JSON'
    }
  }
}

[pscustomobject]@{
  checked_at = [DateTimeOffset]::UtcNow.ToString('o')
  project = $project
  project_number = $projectNumber
  activation_model = 'existing-default-compute-service-account-no-iam-mutation'
  default_service_account = $defaultServiceAccountEmail
  workflow_revision = $workflow.revisionId
  workflow_service_account = $workflowServiceAccountEmail
  delivery_enabled = $false
  promoter_revision = if ($null -eq $promoter) {
    $null
  } else {
    $promoter.status.latestReadyRevisionName
  }
  scheduler_state = if ($schedulerSummary.Count -eq 1) {
    $schedulerSummary[0].state
  } else {
    $null
  }
  safety_passed = ($safetyFailures.Count -eq 0)
  safety_failures = $safetyFailures
  control_plane_ready = (
    $safetyFailures.Count -eq 0 -and $readinessBlockers.Count -eq 0
  )
  permission_rehearsal_required = $true
  readiness_blockers = $readinessBlockers
} | ConvertTo-Json -Depth 6

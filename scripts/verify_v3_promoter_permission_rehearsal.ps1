[CmdletBinding()]
param(
  [Parameter(Mandatory)] [string]$LowerBound,
  [Parameter(Mandatory)] [string]$Execution
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$project = 'pacific-plating-282708'
$region = 'asia-southeast1'
$workflow = 'v3-nightly-orchestrator'
$promoter = 'sap-delivery-promoter'
$promoterRevision = 'sap-delivery-promoter-00001-grm'
$promoterRuntime = 'data-extraction@pacific-plating-282708.iam.gserviceaccount.com'
$workflowRuntime = '919786098205-compute@developer.gserviceaccount.com'
$checkedAt = [DateTime]::UtcNow.ToString('o')
$requestCandidateLimit = 1000
$gcsCandidateLimit = 1000
$bigQueryCandidateLimit = 1000

function Invoke-GcloudJson {
  param([Parameter(Mandatory)] [string[]]$CommandArgs)
  $output = & gcloud @CommandArgs --format=json
  if ($LASTEXITCODE -ne 0) {
    throw "gcloud $($CommandArgs -join ' ') failed"
  }
  if ([string]::IsNullOrWhiteSpace(($output -join ''))) {
    return @()
  }
  return ($output | ConvertFrom-Json)
}

$executionState = Invoke-GcloudJson @(
  'workflows', 'executions', 'describe', $Execution,
  "--workflow=$workflow", "--project=$project", "--location=$region"
)
$executionResult = [string]$executionState.result | ConvertFrom-Json

$requestFilter = @(
  'resource.type="cloud_run_revision"',
  "resource.labels.service_name=`"$promoter`"",
  "resource.labels.revision_name=`"$promoterRevision`"",
  'httpRequest.status=400'
) -join ' AND '
$requestLogCandidates = @(
  Invoke-GcloudJson @(
    'logging', 'read', $requestFilter, "--project=$project", '--freshness=1h',
    "--limit=$requestCandidateLimit"
  )
)
$requestLogs = @(
  $requestLogCandidates | Where-Object {
    [DateTimeOffset]$_.timestamp -ge [DateTimeOffset]$LowerBound -and
    [DateTimeOffset]$_.timestamp -le [DateTimeOffset]$checkedAt
  }
)

$gcsMutationFilter = @(
  "protoPayload.authenticationInfo.principalEmail=`"$promoterRuntime`"",
  'resource.type="gcs_bucket"',
  '(protoPayload.methodName="storage.objects.create" OR protoPayload.methodName="storage.objects.delete" OR protoPayload.methodName="storage.objects.update")'
) -join ' AND '
$gcsMutationCandidates = @(
  Invoke-GcloudJson @(
    'logging', 'read', $gcsMutationFilter, "--project=$project", '--freshness=1h',
    "--limit=$gcsCandidateLimit"
  )
)
$gcsMutations = @(
  $gcsMutationCandidates | Where-Object {
    [DateTimeOffset]$_.timestamp -ge [DateTimeOffset]$LowerBound -and
    [DateTimeOffset]$_.timestamp -le [DateTimeOffset]$checkedAt
  }
)

$bigQueryAuditFilter = @(
  'protoPayload.serviceName="bigquery.googleapis.com"',
  "protoPayload.authenticationInfo.principalEmail=`"$workflowRuntime`""
) -join ' AND '
$bigQueryAuditCandidates = @(
  Invoke-GcloudJson @(
    'logging', 'read', $bigQueryAuditFilter, "--project=$project", '--freshness=1h',
    "--limit=$bigQueryCandidateLimit"
  )
)
$bigQueryAuditEvents = @(
  $bigQueryAuditCandidates | Where-Object {
    [DateTimeOffset]$_.timestamp -ge [DateTimeOffset]$LowerBound -and
    [DateTimeOffset]$_.timestamp -le [DateTimeOffset]$checkedAt
  }
)

$extractFilter = "metadata.creationTimestamp>=$LowerBound AND metadata.creationTimestamp<=$checkedAt"
$extractExecutions = @(
  Invoke-GcloudJson @(
    'run', 'jobs', 'executions', 'list', '--job=sap-extract-job',
    "--project=$project", "--region=$region", "--filter=$extractFilter", '--limit=1'
  )
)

$scheduler = Invoke-GcloudJson @(
  'scheduler', 'jobs', 'describe', $workflow,
  "--project=$project", "--location=$region"
)
$workflowState = Invoke-GcloudJson @(
  'workflows', 'describe', $workflow,
  "--project=$project", "--location=$region"
)
$source = [string]$workflowState.sourceContents
$deliveryFalse = $source -match '(?m)^\s*-\s+delivery_enabled:\s*false\s*$'
$deliveryTrue = $source -match '(?m)^\s*-\s+delivery_enabled:\s*true\s*$'
$lowerBoundTime = [DateTimeOffset]$LowerBound
$checkedAtTime = [DateTimeOffset]$checkedAt
$executionStartTime = [DateTimeOffset]$executionState.startTime
$executionEndTime = [DateTimeOffset]$executionState.endTime
$windowCoversExecution = (
  $lowerBoundTime -le $executionStartTime -and
  $executionEndTime -le $checkedAtTime -and
  $lowerBoundTime -ge $checkedAtTime.AddHours(-1)
)
$candidateCapsClear = (
  $requestLogCandidates.Count -lt $requestCandidateLimit -and
  $gcsMutationCandidates.Count -lt $gcsCandidateLimit -and
  $bigQueryAuditCandidates.Count -lt $bigQueryCandidateLimit
)

$passed = (
  $executionState.state -eq 'SUCCEEDED' -and
  $executionState.workflowRevisionId -eq '000011-291' -and
  $executionResult.permission_rehearsal -eq 'PROMOTER_AUTH_REACHED_VALIDATOR' -and
  $executionResult.http_code -eq 400 -and
  $executionResult.production_write_expected -eq $false -and
  $windowCoversExecution -and
  $candidateCapsClear -and
  $requestLogs.Count -eq 1 -and
  $gcsMutations.Count -eq 0 -and
  $bigQueryAuditEvents.Count -eq 0 -and
  $extractExecutions.Count -eq 0 -and
  $scheduler.state -eq 'PAUSED' -and
  $deliveryFalse -and
  -not $deliveryTrue
)

[pscustomobject]@{
  checked_at = $checkedAt
  lower_bound = $LowerBound
  execution = $executionState.name
  execution_state = $executionState.state
  workflow_revision = $executionState.workflowRevisionId
  result = $executionResult
  execution_start_time = $executionState.startTime
  execution_end_time = $executionState.endTime
  window_covers_execution = $windowCoversExecution
  promoter_request_filter = $requestFilter
  promoter_candidate_limit = $requestCandidateLimit
  promoter_candidate_count = $requestLogCandidates.Count
  promoter_http_400_count = $requestLogs.Count
  promoter_request_timestamps = @($requestLogs | ForEach-Object { $_.timestamp })
  gcs_mutation_filter = $gcsMutationFilter
  gcs_candidate_limit = $gcsCandidateLimit
  gcs_candidate_count = $gcsMutationCandidates.Count
  gcs_mutation_count = $gcsMutations.Count
  bigquery_audit_filter = $bigQueryAuditFilter
  bigquery_audit_window_end = $checkedAt
  bigquery_workflow_runtime = $workflowRuntime
  bigquery_candidate_limit = $bigQueryCandidateLimit
  bigquery_candidate_count = $bigQueryAuditCandidates.Count
  bigquery_audit_event_count = $bigQueryAuditEvents.Count
  bigquery_audit_events = $bigQueryAuditEvents
  extract_execution_filter = $extractFilter
  extract_execution_count = $extractExecutions.Count
  scheduler_state = $scheduler.state
  delivery_false = $deliveryFalse
  delivery_true = $deliveryTrue
  candidate_caps_clear = $candidateCapsClear
  verification_passed = $passed
} | ConvertTo-Json -Depth 8

if (-not $passed) {
  exit 1
}

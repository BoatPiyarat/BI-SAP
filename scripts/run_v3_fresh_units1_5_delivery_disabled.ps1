[CmdletBinding()]
param(
  [ValidatePattern('^Boat-chat-[A-Za-z0-9._-]+$')]
  [string]$ApprovalReference,
  [switch]$PreflightOnly
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$project = 'pacific-plating-282708'
$region = 'asia-southeast1'
$workflow = 'v3-nightly-orchestrator'
$expectedRevision = '000011-291'
$v3Scheduler = 'v3-nightly-orchestrator'
$legacyScheduler = 'sap-extract-schedule'
$flagsFile = Join-Path $PSScriptRoot 'v3_fresh_units1_5_delivery_disabled.flags.yaml'
$repoRoot = Split-Path -Parent $PSScriptRoot
$safeQuery = 'scripts/bq_safe_query.sh'
$preflightSql = 'sql/operator/20260827_preflight_fresh_v3_units1_5_pilot_v1.sql'
$reportSql = 'sql/operator/20260827_report_fresh_v3_units1_5_pilot_v1.sql'
$bash = 'C:\Program Files\Git\bin\bash.exe'

if (-not $PreflightOnly -and [string]::IsNullOrWhiteSpace($ApprovalReference)) {
  throw 'A Boat chat approval reference is mandatory for production execution'
}

function Invoke-GcloudJson {
  param([Parameter(Mandatory)] [string[]]$CommandArgs)
  $output = & gcloud @CommandArgs --format=json
  if ($LASTEXITCODE -ne 0) {
    throw "gcloud $($CommandArgs -join ' ') failed"
  }
  return ($output | ConvertFrom-Json)
}

Push-Location $repoRoot
try {
  $censusRaw = & (Join-Path $PSScriptRoot 'build_v3_common_execution_census.ps1') `
    -ExpectedRevision $expectedRevision
  if ($LASTEXITCODE -ne 0) {
    throw 'Workflow identity/concurrency census failed'
  }
  $census = $censusRaw | ConvertFrom-Json
  if (-not $census.verification_passed) {
    throw 'Workflow identity/concurrency census did not PASS'
  }

  $v3Job = Invoke-GcloudJson @(
    'scheduler', 'jobs', 'describe', $v3Scheduler,
    "--project=$project", "--location=$region"
  )
  $legacyJob = Invoke-GcloudJson @(
    'scheduler', 'jobs', 'describe', $legacyScheduler,
    "--project=$project", "--location=$region"
  )
  if ($v3Job.state -ne 'PAUSED' -or $v3Job.schedule -ne '30 20 * * *' -or
      $v3Job.timeZone -ne 'Asia/Bangkok') {
    throw 'Canonical V3 Scheduler is not the exact PAUSED 20:30 ICT resource'
  }
  if ($legacyJob.state -ne 'ENABLED' -or $legacyJob.schedule -ne '30 20 * * *' -or
      $legacyJob.timeZone -ne 'Asia/Bangkok') {
    throw 'Legacy Scheduler prestate changed; manual run overlap safety cannot be proven'
  }

  $extractExecutions = @(
    Invoke-GcloudJson @(
      'run', 'jobs', 'executions', 'list', '--job=sap-extract-job',
      "--project=$project", "--region=$region", '--limit=20'
    )
  )
  $activeExtractExecutions = @(
    $extractExecutions | Where-Object { -not $_.status.completionTime }
  )
  if ($activeExtractExecutions.Count -ne 0) {
    throw 'An SAP extract execution is already active; refusing overlap'
  }

  $bronzeObjects = @(
    Invoke-GcloudJson @(
      'storage', 'objects', 'list',
      'gs://rcb-bronze-zone/SAP/production_database/**', '--limit=1'
    )
  )
  if ($bronzeObjects.Count -ne 0) {
    throw 'SAP bronze data prefix is not empty; refusing to take ownership of an existing batch'
  }

  try {
    $bangkokZone = [TimeZoneInfo]::FindSystemTimeZoneById('SE Asia Standard Time')
  }
  catch {
    $bangkokZone = [TimeZoneInfo]::FindSystemTimeZoneById('Asia/Bangkok')
  }
  $bangkokNow = [TimeZoneInfo]::ConvertTime([DateTimeOffset]::UtcNow, $bangkokZone)
  $minuteOfDay = 60 * $bangkokNow.Hour + $bangkokNow.Minute
  if ($minuteOfDay -ge 1170 -and $minuteOfDay -lt 1320) {
    throw 'Manual execution is blocked from 19:30 through 21:59 ICT to avoid the legacy 20:30 run'
  }

  & $bash $safeQuery --project $project -f $preflightSql -- --location=$region
  if ($LASTEXITCODE -ne 0) {
    throw 'Exact Unit 2 pilot BigQuery preflight failed'
  }

  if ($PreflightOnly) {
    Write-Output 'FRESH_UNITS1_5_PREFLIGHT=PASS'
    Write-Output "PREFLIGHT_WORKFLOW_REVISION=$expectedRevision"
    Write-Output 'PREFLIGHT_EXECUTION_CREATED=false'
    return
  }

  $lowerBound = [DateTimeOffset]::UtcNow.ToString('o')
  Write-Output "RUN_APPROVAL_REFERENCE=$ApprovalReference"
  Write-Output "RUN_LOWER_BOUND=$lowerBound"
  Write-Output "RUN_WORKFLOW_REVISION=$expectedRevision"
  Write-Output 'RUN_BOUNDARY=SAP read + bronze/load + Units 1-5 + possible restricted archive; interface delivery disabled'

  $executionRaw = & gcloud workflows run $workflow `
    --project $project `
    --location $region `
    "--flags-file=$flagsFile" `
    --format=json
  if ($LASTEXITCODE -ne 0) {
    throw "Workflow execution failed or held; inspect executions started after $lowerBound"
  }
  $execution = $executionRaw | ConvertFrom-Json
  if ($execution.state -ne 'SUCCEEDED' -or
      $execution.workflowRevisionId -ne $expectedRevision) {
    throw 'Workflow did not return SUCCEEDED on the exact reviewed revision'
  }
  $runId = [string]$execution.result | ConvertFrom-Json
  if ([string]::IsNullOrWhiteSpace($runId) -or -not $runId.StartsWith('V3NIGHTLY-')) {
    throw 'Workflow result did not contain the expected pipeline run ID'
  }

  Write-Output "RUN_EXECUTION=$($execution.name)"
  Write-Output "RUN_PIPELINE_RUN_ID=$runId"
  & $bash $safeQuery --project $project -f $reportSql -- `
    --location=$region "--parameter=run_id::$runId"
  if ($LASTEXITCODE -ne 0) {
    throw 'Fresh Units 1-5 post-run report failed'
  }
}
finally {
  Pop-Location
}

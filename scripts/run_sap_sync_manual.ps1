[CmdletBinding()]
param(
  [int]$LoaderTimeoutSeconds = 300
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$projectId = 'pacific-plating-282708'
$region = 'asia-southeast1'
$bronzePath = 'gs://rcb-bronze-zone/SAP/production_database/'
$extractJob = 'sap-extract-job'
$loaderScheduler = 'auto_load_sap_data_in_bucket_to_bigquery'

function Invoke-Checked {
  param(
    [Parameter(Mandatory)] [string]$Label,
    [Parameter(Mandatory)] [scriptblock]$Command
  )

  Write-Host "== $Label"
  & $Command
  if ($LASTEXITCODE -ne 0) {
    throw "$Label failed with exit code $LASTEXITCODE"
  }
}

function Get-BronzeObjects {
  $output = & gsutil ls $bronzePath 2>$null
  if ($LASTEXITCODE -notin 0, 1) {
    throw "Unable to inspect $bronzePath (exit $LASTEXITCODE)"
  }
  return @($output | Where-Object { $_ })
}

function Invoke-V3Procedure {
  param(
    [Parameter(Mandatory)] [string]$Procedure,
    [Parameter(Mandatory)] [string]$JobSuffix,
    [string]$Arguments = ''
  )

  $sql = "CALL ``$projectId.sap_integration_v3.$Procedure``($Arguments);"
  $jobTimestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
  $jobId = "manual_v3_${JobSuffix}_${jobTimestamp}"

  Invoke-Checked "Dry-run $Procedure" {
    $sql | & bq query --project_id=$projectId --use_legacy_sql=false --location=$region `
      --dry_run --format=prettyjson
  }
  Invoke-Checked "Run $Procedure as $jobId" {
    $sql | & bq query --project_id=$projectId --use_legacy_sql=false --location=$region `
      --maximum_bytes_billed=21474836480 --job_id=$jobId --format=prettyjson
  }
}

$objects = Get-BronzeObjects
if ($objects.Count -gt 1) {
  throw "Found $($objects.Count) pending bronze objects. Stop to avoid combining/reloading batches."
}

if ($objects.Count -eq 0) {
  Invoke-Checked 'Execute SAP extract and wait' {
    & gcloud run jobs execute $extractJob --region $region --project $projectId --wait
  }
  $objects = Get-BronzeObjects
}
else {
  Write-Host 'One pending bronze object already exists; skip extract to avoid a duplicate batch.'
}

if ($objects.Count -gt 1) {
  throw "Extract left $($objects.Count) bronze objects. Stop before loader trigger."
}

if ($objects.Count -eq 1) {
  Invoke-Checked 'Trigger loader exactly once' {
    & gcloud scheduler jobs run $loaderScheduler --location $region --project $projectId
  }

  $deadline = (Get-Date).AddSeconds($LoaderTimeoutSeconds)
  do {
    Start-Sleep -Seconds 5
    $objects = Get-BronzeObjects
    if ($objects.Count -gt 1) {
      throw "Loader window contains $($objects.Count) objects. Stop; do not trigger again."
    }
  } while ($objects.Count -eq 1 -and (Get-Date) -lt $deadline)

  if ($objects.Count -ne 0) {
    throw "Loader timeout: bronze object still exists. Do not trigger the scheduler again; inspect Cloud Run logs."
  }
  Write-Host 'Loader consumed the bronze object.'
}
else {
  Write-Host 'Extract produced no bronze object (healthy zero-row window or no delta); skip loader trigger.'
}

# Separate jobs are intentional. A single CALL of the wrapper procedure exceeded the cumulative
# 20 GiB ceiling on 2026-08-01 after partially committing earlier steps.
$v3Steps = @(
  @('sp_refresh_stg_order_dim', 'order_dim', ''),
  @('sp_refresh_stg_payment_events', 'payment_events', ''),
  @('sp_refresh_stg_schedule', 'schedule', ''),
  @('sp_refresh_sap_mirror_doc_incremental', 'mirror_doc', "'ADHOC:manual-operator'"),
  @('sp_refresh_sap_mirror_state', 'mirror_state', "'ADHOC:manual-operator'"),
  @('sp_recon_all_charges', 'recon', ''),
  @('sp_refresh_expected_state', 'expected', ''),
  @('sp_run_validation', 'validation', ''),
  @('sp_refresh_delta_export', 'delta', ''),
  @('sp_refresh_interface_daily_status', 'daily_status', '')
)

foreach ($step in $v3Steps) {
  Invoke-V3Procedure -Procedure $step[0] -JobSuffix $step[1] -Arguments $step[2]
}

Write-Host 'Manual SAP sync completed: extract/load (if needed) and all V3 refresh steps succeeded.'

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$lowerBound = [DateTimeOffset]::UtcNow.ToString('o')
$flagsFile = Join-Path $PSScriptRoot 'v3_promoter_permission_rehearsal.flags.yaml'
$argument = '{"permission_rehearsal_only":true,"promotion_service_url":"https://sap-delivery-promoter-3uymtccdma-as.a.run.app"}'

Write-Output "REHEARSAL_LOWER_BOUND=$lowerBound"
Write-Output "REHEARSAL_ARGUMENT=$argument"

& gcloud workflows run v3-nightly-orchestrator `
  --project pacific-plating-282708 `
  --location asia-southeast1 `
  "--flags-file=$flagsFile"

if ($LASTEXITCODE -ne 0) {
  throw "Permission rehearsal execution failed with exit code $LASTEXITCODE"
}

[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [ValidatePattern('^[A-Za-z0-9_-]{20,}$')]
  [string]$ScriptId,

  [Parameter(Mandatory = $true)]
  [string]$OutputDirectory
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot = Split-Path -Parent $PSScriptRoot
$sourceFile = Join-Path $repoRoot 'workflows\sap_result_ingestion.gs'
$manifestFile = Join-Path $repoRoot 'workflows\sap_result_ingestion.appsscript.json'
$resolvedOutput = [System.IO.Path]::GetFullPath($OutputDirectory)
$resolvedRepo = [System.IO.Path]::GetFullPath($repoRoot).TrimEnd('\') + '\'

if (-not (Test-Path -LiteralPath $sourceFile -PathType Leaf)) {
  throw "Apps Script source is missing: $sourceFile"
}
if (-not (Test-Path -LiteralPath $manifestFile -PathType Leaf)) {
  throw "Apps Script manifest is missing: $manifestFile"
}
if ($resolvedOutput.StartsWith($resolvedRepo, [StringComparison]::OrdinalIgnoreCase)) {
  throw 'OutputDirectory must be outside the repository so .clasp.json cannot be committed'
}
if (Test-Path -LiteralPath $resolvedOutput) {
  if (-not (Test-Path -LiteralPath $resolvedOutput -PathType Container)) {
    throw "OutputDirectory exists and is not a directory: $resolvedOutput"
  }
  if (@(Get-ChildItem -Force -LiteralPath $resolvedOutput).Count -ne 0) {
    throw "OutputDirectory must be empty: $resolvedOutput"
  }
}
else {
  New-Item -ItemType Directory -Path $resolvedOutput | Out-Null
}

$manifest = Get-Content -Raw -Encoding UTF8 -LiteralPath $manifestFile |
  ConvertFrom-Json
if ([string]$manifest.timeZone -ne 'Asia/Bangkok') {
  throw 'Apps Script manifest timeZone must be Asia/Bangkok'
}
$requiredScopes = @(
  'https://www.googleapis.com/auth/gmail.modify',
  'https://www.googleapis.com/auth/bigquery',
  'https://www.googleapis.com/auth/pubsub',
  'https://www.googleapis.com/auth/devstorage.read_write',
  'https://www.googleapis.com/auth/script.external_request',
  'https://www.googleapis.com/auth/script.send_mail',
  'https://www.googleapis.com/auth/script.scriptapp'
)
foreach ($scope in $requiredScopes) {
  if (@($manifest.oauthScopes) -notcontains $scope) {
    throw "Apps Script manifest lacks required scope: $scope"
  }
}
if (@($manifest.oauthScopes).Count -ne $requiredScopes.Count) {
  throw 'Apps Script manifest contains an unreviewed extra OAuth scope'
}

Copy-Item -LiteralPath $sourceFile -Destination (Join-Path $resolvedOutput 'Code.gs')
Copy-Item -LiteralPath $manifestFile -Destination (Join-Path $resolvedOutput 'appsscript.json')
@{
  scriptId = $ScriptId
  rootDir = '.'
} |
  ConvertTo-Json |
  Set-Content -Encoding UTF8 -LiteralPath (Join-Path $resolvedOutput '.clasp.json')

[pscustomobject]@{
  output_directory = $resolvedOutput
  source_file = (Join-Path $resolvedOutput 'Code.gs')
  manifest_file = (Join-Path $resolvedOutput 'appsscript.json')
  clasp_config_file = (Join-Path $resolvedOutput '.clasp.json')
  pushed = $false
  oauth_authorized = $false
} | ConvertTo-Json

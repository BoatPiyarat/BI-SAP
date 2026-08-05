[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [ValidatePattern('^[0-9]{14}$')]
  [string]$Nonce
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$activationScript = Join-Path $PSScriptRoot 'check_post_import_activation.ps1'
$queryTemplate = Join-Path $repoRoot 'sql\adhoc\20260805_verify_post_import_rehearsal.sql'
$safeQuery = Join-Path $repoRoot 'scripts\bq_safe_query.sh'
$gitBash = 'C:\Program Files\Git\bin\bash.exe'
$token = '__REPLACE_14_DIGIT_NONCE__'

function Convert-ToGitBashPath([string]$Path) {
  $resolved = [System.IO.Path]::GetFullPath($Path)
  if ($resolved -notmatch '^(?<drive>[A-Za-z]):(?<rest>\\.*)$') {
    throw "Cannot convert non-drive path to Git Bash form: $resolved"
  }
  $drive = $Matches.drive.ToLowerInvariant()
  $rest = $Matches.rest.Replace('\', '/')
  return "/$drive$rest"
}

if (-not (Test-Path -LiteralPath $activationScript -PathType Leaf)) {
  throw "Activation checker is missing: $activationScript"
}
if (-not (Test-Path -LiteralPath $queryTemplate -PathType Leaf)) {
  throw "Rehearsal query template is missing: $queryTemplate"
}
if (-not (Test-Path -LiteralPath $safeQuery -PathType Leaf)) {
  throw "Mandatory BigQuery safety wrapper is missing: $safeQuery"
}
if (-not (Test-Path -LiteralPath $gitBash -PathType Leaf)) {
  throw "Git Bash is missing: $gitBash"
}

$activationJson = & $activationScript | Out-String
if ($LASTEXITCODE -ne 0) {
  throw 'Activation checker failed; rehearsal result verification was not run'
}
$activation = $activationJson | ConvertFrom-Json
if ($activation.safety_passed -ne $true) {
  throw "Activation safety check failed: $($activation.safety_failures -join '; ')"
}
if ($activation.rehearsal_ready -ne $true) {
  throw "Rehearsal is not ready: $($activation.readiness_blockers -join '; ')"
}

$template = Get-Content -Raw -Encoding UTF8 -LiteralPath $queryTemplate
$tokenCount = ([regex]::Matches($template, [regex]::Escape($token))).Count
if ($tokenCount -ne 1) {
  throw "Expected exactly one nonce token in the query template; found $tokenCount"
}
$query = $template.Replace($token, $Nonce)

$temporaryQuery = New-TemporaryFile
try {
  Set-Content -Encoding UTF8 -LiteralPath $temporaryQuery.FullName -Value $query
  $bashQuery = Convert-ToGitBashPath $temporaryQuery.FullName
  $bashWrapper = Convert-ToGitBashPath $safeQuery

  & $gitBash $bashWrapper -f $bashQuery -- --location=asia-southeast1 --format=prettyjson
  if ($LASTEXITCODE -ne 0) {
    throw "Exact rehearsal verification failed for nonce $Nonce"
  }
}
finally {
  if (Test-Path -LiteralPath $temporaryQuery.FullName) {
    Remove-Item -LiteralPath $temporaryQuery.FullName -Force
  }
}

[pscustomobject]@{
  nonce = $Nonce
  checked_at = [DateTimeOffset]::UtcNow.ToString('o')
  workflow_revision = $activation.workflow_revision
  dispatcher_revision = $activation.dispatcher_revision
  exact_cases_passed = 3
  safety_passed = $activation.safety_passed
  rehearsal_ready = $activation.rehearsal_ready
} | ConvertTo-Json

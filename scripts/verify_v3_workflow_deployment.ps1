[CmdletBinding()]
param(
  [Parameter(Mandatory)] [string]$ExpectedRevision,
  [string]$CandidateSource = 'infra/v3_nightly_orchestrator.workflows.yaml'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$project = 'pacific-plating-282708'
$region = 'asia-southeast1'
$workflow = 'v3-nightly-orchestrator'
$expectedServiceAccount =
  'projects/pacific-plating-282708/serviceAccounts/' +
  '919786098205-compute@developer.gserviceaccount.com'
$executionLimit = 1

$liveJson = & gcloud workflows describe $workflow `
  "--project=$project" "--location=$region" --format=json
if ($LASTEXITCODE -ne 0) {
  throw 'Unable to describe the deployed workflow'
}
$live = $liveJson | ConvertFrom-Json
$liveSource = [string]$live.sourceContents
$revisionCreatedAt = [string]$live.revisionCreateTime
$executionFilter = "startTime>=$revisionCreatedAt"
$candidate = Get-Content -Raw -Encoding UTF8 -LiteralPath $CandidateSource

function Get-SourceHash {
  param([Parameter(Mandatory)] [string]$Value)
  $sha = [Security.Cryptography.SHA256]::Create()
  try {
    $bytes = [Text.Encoding]::UTF8.GetBytes($Value)
    return [BitConverter]::ToString($sha.ComputeHash($bytes)).Replace('-', '').ToLowerInvariant()
  }
  finally {
    $sha.Dispose()
  }
}

$candidateLines = $candidate -split "`r?`n"
$mismatches = @()
$shorterLength = [Math]::Min($liveSource.Length, $candidate.Length)
for ($index = 0; $index -lt $shorterLength; $index++) {
  if ($liveSource[$index] -cne $candidate[$index]) {
    $line = 1 + @(
      $candidate.Substring(0, $index).ToCharArray() |
        Where-Object { $_ -eq "`n" }
    ).Count
    $candidateLine = $candidateLines[$line - 1]
    $mismatches += [pscustomobject]@{
      index = $index
      line = $line
      live_codepoint = [int][char]$liveSource[$index]
      candidate_codepoint = [int][char]$candidate[$index]
      comment_only = $candidateLine.TrimStart().StartsWith('#')
    }
  }
}

$executionRows = @(
  & gcloud workflows executions list $workflow `
    "--project=$project" "--location=$region" `
    "--filter=$executionFilter" "--limit=$executionLimit" `
    '--format=value(name,startTime,state)'
)
if ($LASTEXITCODE -ne 0) {
  throw 'Unable to list workflow executions'
}

$allowedCommentSerialization = @(
  $mismatches | Where-Object {
    -not ($_.comment_only -and $_.candidate_codepoint -eq 8212 -and $_.live_codepoint -eq 63)
  }
).Count -eq 0
$sourceIdentityPassed = (
  $liveSource.Length -eq $candidate.Length -and
  $allowedCommentSerialization
)
$deliveryFalse = $liveSource -match '(?m)^\s*-\s+delivery_enabled:\s*false\s*$'
$deliveryTrue = $liveSource -match '(?m)^\s*-\s+delivery_enabled:\s*true\s*$'
$verificationPassed = (
  $live.revisionId -eq $ExpectedRevision -and
  $live.state -eq 'ACTIVE' -and
  $live.serviceAccount -eq $expectedServiceAccount -and
  $sourceIdentityPassed -and
  $deliveryFalse -and
  -not $deliveryTrue -and
  $executionRows.Count -eq 0
)

[pscustomobject]@{
  checked_at = [DateTimeOffset]::UtcNow.ToString('o')
  project = $project
  region = $region
  workflow = $workflow
  expected_revision = $ExpectedRevision
  live_revision = $live.revisionId
  revision_create_time = $live.revisionCreateTime
  state = $live.state
  expected_service_account = $expectedServiceAccount
  service_account = $live.serviceAccount
  candidate_source = $CandidateSource
  live_source_hash = Get-SourceHash $liveSource
  candidate_source_hash = Get-SourceHash $candidate
  live_source_length = $liveSource.Length
  candidate_source_length = $candidate.Length
  mismatch_count = $mismatches.Count
  mismatches = $mismatches
  source_identity_passed = $sourceIdentityPassed
  delivery_false = $deliveryFalse
  delivery_true = $deliveryTrue
  execution_query = [pscustomobject]@{
    command = 'gcloud workflows executions list'
    project = $project
    location = $region
    workflow = $workflow
    filter = $executionFilter
    limit = $executionLimit
    format = 'value(name,startTime,state)'
    returned_count = $executionRows.Count
  }
  verification_passed = $verificationPassed
} | ConvertTo-Json -Depth 6

if (-not $verificationPassed) {
  exit 1
}

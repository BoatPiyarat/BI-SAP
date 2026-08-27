[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$project = 'pacific-plating-282708'
$projectNumber = '919786098205'
$region = 'asia-southeast1'
$workflowName = 'v3-nightly-orchestrator'
$schedulerName = 'v3-nightly-orchestrator'
$promoterName = 'sap-delivery-promoter'
$expectedWorkflowRevision = '000010-daf'
$expectedPromoterRevision = 'sap-delivery-promoter-00001-grm'
$defaultServiceAccount = "${projectNumber}-compute@developer.gserviceaccount.com"
$schedulerServiceAgent = "service-${projectNumber}@gcp-sa-cloudscheduler.iam.gserviceaccount.com"
$canonicalSchedulerResource =
  "projects/$project/locations/$region/jobs/$schedulerName"

function Invoke-GcloudJson {
  param([Parameter(Mandatory)] [string[]]$CommandArgs)
  $output = & gcloud @CommandArgs --format=json
  if ($LASTEXITCODE -ne 0) {
    throw "gcloud $($CommandArgs -join ' ') failed"
  }
  return ($output | ConvertFrom-Json)
}

$checkedAt = [DateTimeOffset]::UtcNow.ToString('o')
$activeAccount = (& gcloud config get account).Trim()
if ($LASTEXITCODE -ne 0 -or -not $activeAccount) {
  throw 'Unable to resolve active gcloud account'
}
$editor = Invoke-GcloudJson @('iam', 'roles', 'describe', 'roles/editor')
$policy = Invoke-GcloudJson @('projects', 'get-iam-policy', $project)
$schedulers = @(Invoke-GcloudJson @(
    'scheduler', 'jobs', 'list', "--project=$project", "--location=$region"
  ))
$workflow = Invoke-GcloudJson @(
  'workflows', 'describe', $workflowName,
  "--project=$project", "--location=$region"
)
$promoter = Invoke-GcloudJson @(
  'run', 'services', 'describe', $promoterName,
  "--project=$project", "--region=$region"
)

$defaultMember = "serviceAccount:$defaultServiceAccount"
$schedulerAgentMember = "serviceAccount:$schedulerServiceAgent"
$activeMember = "user:$activeAccount"
$defaultRoles = @(
  $policy.bindings |
    Where-Object { $_.members -contains $defaultMember } |
    ForEach-Object { $_.role }
)
$schedulerAgentRoles = @(
  $policy.bindings |
    Where-Object { $_.members -contains $schedulerAgentMember } |
    ForEach-Object { $_.role }
)
$activeAccountRoles = @(
  $policy.bindings |
    Where-Object { $_.members -contains $activeMember } |
    ForEach-Object { $_.role }
)
$canonicalSchedulers = @(
  $schedulers | Where-Object { $_.name -eq $canonicalSchedulerResource }
)
$workflowSource = [string]$workflow.sourceContents
$executionFilter = "startTime>=$($workflow.revisionCreateTime)"
$postRevisionExecutions = @(
  & gcloud workflows executions list $workflowName `
    "--project=$project" "--location=$region" `
    "--filter=$executionFilter" '--limit=1' `
    '--format=value(name,startTime,state)'
)
if ($LASTEXITCODE -ne 0) {
  throw 'Unable to query post-revision executions'
}

$preflightPassed = (
  $canonicalSchedulers.Count -eq 0 -and
  $editor.includedPermissions -contains 'workflows.executions.create' -and
  $editor.includedPermissions -contains 'iam.serviceAccounts.actAs' -and
  $defaultRoles -contains 'roles/editor' -and
  $schedulerAgentRoles -contains 'roles/cloudscheduler.serviceAgent' -and
  $activeAccountRoles -contains 'roles/cloudscheduler.admin' -and
  $activeAccountRoles -contains 'roles/editor' -and
  $workflow.revisionId -eq $expectedWorkflowRevision -and
  $workflow.state -eq 'ACTIVE' -and
  $workflowSource -match '(?m)^\s*-\s+delivery_enabled:\s*false\s*$' -and
  $workflowSource -notmatch '(?m)^\s*-\s+delivery_enabled:\s*true\s*$' -and
  $postRevisionExecutions.Count -eq 0 -and
  $promoter.status.latestReadyRevisionName -eq $expectedPromoterRevision -and
  $promoter.status.latestCreatedRevisionName -eq $expectedPromoterRevision -and
  $promoter.metadata.annotations.'run.googleapis.com/ingress' -eq 'internal' -and
  $promoter.status.url -eq 'https://sap-delivery-promoter-3uymtccdma-as.a.run.app'
)

[pscustomobject]@{
  checked_at = $checkedAt
  project = $project
  region = $region
  active_account = $activeAccount
  active_account_roles = $activeAccountRoles
  editor_has_workflow_execution_create =
    ($editor.includedPermissions -contains 'workflows.executions.create')
  editor_has_service_account_act_as =
    ($editor.includedPermissions -contains 'iam.serviceAccounts.actAs')
  default_service_account = $defaultServiceAccount
  default_service_account_roles = $defaultRoles
  scheduler_service_agent = $schedulerServiceAgent
  scheduler_service_agent_roles = $schedulerAgentRoles
  canonical_scheduler_resource = $canonicalSchedulerResource
  canonical_scheduler_count = $canonicalSchedulers.Count
  workflow_revision = $workflow.revisionId
  workflow_revision_create_time = $workflow.revisionCreateTime
  workflow_delivery_false =
    ($workflowSource -match '(?m)^\s*-\s+delivery_enabled:\s*false\s*$')
  post_revision_execution_query = [pscustomobject]@{
    filter = $executionFilter
    limit = 1
    returned_count = $postRevisionExecutions.Count
  }
  promoter_revision = $promoter.status.latestReadyRevisionName
  promoter_url = $promoter.status.url
  promoter_ingress = $promoter.metadata.annotations.'run.googleapis.com/ingress'
  preflight_passed = $preflightPassed
} | ConvertTo-Json -Depth 6

if (-not $preflightPassed) {
  exit 1
}

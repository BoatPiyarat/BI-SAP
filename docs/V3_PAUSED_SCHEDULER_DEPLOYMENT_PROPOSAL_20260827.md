# V3 recurring Scheduler PAUSED deployment proposal — 2026-08-27

Status: staged complete, not activated. The canonical job exists PAUSED at 20:30 ICT; do not rerun
the create step, run the job, or resume it. Final evidence:
`docs/reviews/2026-08-27-v3-paused-scheduler-deploy-evidence-codex.md`.

## Purpose and boundary

Stage the canonical recurring V3 trigger as a disabled production resource so the complete control
plane can be verified before activation. This proposal does not execute the workflow, enable
delivery, resume the Scheduler, pause the still-live SAP extract schedule, or change IAM.

## Read-only preflight

Durable read-only preflight `scripts/check_v3_paused_scheduler_preflight.ps1` runs the exact
`gcloud iam roles describe`, project IAM-policy read, Scheduler list, workflow describe/execution
list, and promoter describe calls and fails nonzero unless every fact below passes. Its timestamped
output is recorded in the review/deployment evidence rather than relying on this proposal's prose.

Required results after workflow revision `000010-daf` deployment:

- canonical Scheduler matches: 0;
- default Compute identity includes required pre-existing `roles/editor` (the script also records
  its other roles as non-gating inventory);
- authoritative `roles/editor` includes `workflows.executions.create` and
  `iam.serviceAccounts.actAs`;
- active deployer includes existing `roles/cloudscheduler.admin` and `roles/editor`;
- Scheduler service agent already has `roles/cloudscheduler.serviceAgent`;
- private promoter canonical URL:
  `https://sap-delivery-promoter-3uymtccdma-as.a.run.app`;
- workflow remains `delivery_enabled:false` and no post-deploy execution exists.

Observed run at `2026-08-27T07:15:01.2932865Z` returned `preflight_passed:true`. It additionally
recorded active deployer `data@rabbit.co.th` with existing `roles/cloudscheduler.admin` and
`roles/editor`; workflow revision `000010-daf`; promoter revision
`sap-delivery-promoter-00001-grm`, internal ingress; canonical Scheduler count zero; and an exact
workflow execution query with filter
`startTime>=2026-08-27T06:57:59.068010683Z`, limit 1, returned count zero. This document plus the
committed verifier source is the durable preflight artifact.

No IAM grant is proposed. Existing broad permissions are reused under
`docs/design/DEFAULT_COMPUTE_SA_AUTOMATION_WORKAROUND.md`.

## Exact staged deployment

The installed gcloud command has no create-in-PAUSED flag. To eliminate a firing window at the
real cadence, create with a dormant January-only schedule, pause it, then update its cadence while
it is PAUSED. On 2026-08-27, `0 0 1 1 *` in `Asia/Bangkok` cannot fire between create and pause.
If pause fails, the job remains on that dormant cadence; do not run the update. If update fails,
the job remains PAUSED on its prior cadence.

```powershell
$project = 'pacific-plating-282708'
$region = 'asia-southeast1'
$scheduler = 'v3-nightly-orchestrator'
$triggerSa = '919786098205-compute@developer.gserviceaccount.com'
$promoterUrl = 'https://sap-delivery-promoter-3uymtccdma-as.a.run.app'
$executionUri =
  'https://workflowexecutions.googleapis.com/v1/projects/pacific-plating-282708/' +
  'locations/asia-southeast1/workflows/v3-nightly-orchestrator/executions'
$argument = @{ promotion_service_url = $promoterUrl } | ConvertTo-Json -Compress
$messageBody = @{ argument = $argument } | ConvertTo-Json -Compress
$createLowerBound = [DateTimeOffset]::UtcNow.ToString('o')
Write-Output "SCHEDULER_CREATE_LOWER_BOUND_UTC=$createLowerBound"

gcloud scheduler jobs create http $scheduler `
  --project=$project --location=$region `
  --description='V3 nightly orchestrator; KEEP PAUSED until atomic cutover approval' `
  --schedule='0 0 1 1 *' --time-zone='Asia/Bangkok' `
  --uri=$executionUri --http-method=POST `
  --oauth-service-account-email=$triggerSa `
  --oauth-token-scope='https://www.googleapis.com/auth/cloud-platform' `
  --headers='Content-Type=application/json' `
  --message-body=$messageBody `
  --max-retry-attempts=0 --quiet
if ($LASTEXITCODE -ne 0) { throw 'Scheduler create failed' }

gcloud scheduler jobs pause $scheduler `
  --project=$project --location=$region --quiet
if ($LASTEXITCODE -ne 0) {
  throw 'Scheduler pause failed; job remains on dormant January-only cadence'
}

gcloud scheduler jobs update http $scheduler `
  --project=$project --location=$region `
  --description='V3 nightly orchestrator; KEEP PAUSED until atomic cutover approval' `
  --schedule='30 20 * * *' --time-zone='Asia/Bangkok' `
  --uri=$executionUri --http-method=POST `
  --oauth-service-account-email=$triggerSa `
  --oauth-token-scope='https://www.googleapis.com/auth/cloud-platform' `
  --update-headers='Content-Type=application/json' `
  --message-body=$messageBody `
  --max-retry-attempts=0 --quiet
if ($LASTEXITCODE -ne 0) { throw 'Scheduler update failed; keep job PAUSED' }
```

CLI correction recorded after the first staged attempt: this installed gcloud accepts `--headers`
for `jobs create http` but requires `--update-headers` for `jobs update http`. Local
`gcloud scheduler jobs update http --help` is the red/green feedback source. The initial update
failed on the old flag after pause, leaving the job safely PAUSED on its dormant schedule; see
`docs/reviews/2026-08-27-v3-paused-scheduler-partial-deploy-evidence-codex.md`.

Do not run `gcloud scheduler jobs run` or `resume`.

## Mandatory postchecks before progress commit

1. Describe the Scheduler and require state `PAUSED`, schedule `30 20 * * *`, timezone
   `Asia/Bangkok`, exact execution URI, POST, exact OAuth identity/scope, zero retries, and decoded
   argument containing only the exact promoter URL.
2. Run `scripts/check_v3_delivery_control_plane.ps1`; require `safety_passed:true` and
   `control_plane_ready:true` while `delivery_enabled:false` and Scheduler state is PAUSED.
3. Query workflow executions with the captured `SCHEDULER_CREATE_LOWER_BOUND_UTC` (which precedes
   the create API call) as the inclusive lower bound; require zero. Record the exact filter,
   selector, limit, format, timestamp, and returned count.
4. Recheck legacy/other Scheduler states. Do not pause or resume any of them in this deployment.
5. Update OneDrive deployment evidence/session progress and obtain Class-A PASS before any next
   deployment or activation.

## Rollback

Immediate containment is idempotent pause:

```powershell
gcloud scheduler jobs pause v3-nightly-orchestrator `
  --project=pacific-plating-282708 --location=asia-southeast1 --quiet
```

The pre-deployment state is resource absent, so full rollback requires deleting exactly the newly
created canonical job:

```powershell
gcloud scheduler jobs delete v3-nightly-orchestrator `
  --project=pacific-plating-282708 --location=asia-southeast1 --quiet
```

Deletion is destructive, is not part of this deployment, and must not be executed without a
separate explicit approval. If configuration is wrong, the default response is to leave it PAUSED
and correct it through a separately reviewed update.

## Activation blockers retained

- The 20:30 legacy `sap-extract-schedule` remains ENABLED, so resuming this V3 Scheduler would
  overlap and is forbidden until an atomic non-overlap cutover pauses the legacy producer.
- Exact Unit 2 magnitude thresholds and approval provenance remain missing; no fresh Scenario 1 or
  Scenario 3 release build can pass until they are supplied and bootstrapped.
- Delivery remains false. No scenario is SAP pickup/import/ACK verified for recurring activation.

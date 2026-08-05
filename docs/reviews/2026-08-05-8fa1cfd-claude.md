# Review — RQ-20260805-2031-post-import-inert-runtime-deployment

Reviewer: Claude Code
Artifact: commit `8fa1cfd`; live deployment evidence in
`docs/design/POST_IMPORT_AUTOMATION_DEPLOYMENT.md`, `docs/AS_BUILT_V3.md`, progress, and changelog.
Verdict: **PASS**

## Checked against the request's own checklist — every live claim independently re-verified via
`gcloud`/BigQuery, not read from the commit's own prose

- **Dispatcher is private with no invoker**: `gcloud run services describe
  sap-post-import-dispatcher` shows the exact claimed revision
  `sap-post-import-dispatcher-00001-qd4`. `gcloud run services get-iam-policy` returns only an
  `etag`, no `bindings` at all — genuinely no principal (not even `allUsers` or the push service
  account) can invoke it yet.
- **Watchdog is unscheduled, unexecuted, single-task, explicitly configured**: `gcloud run jobs
  describe sap-post-import-watchdog` shows `Ready: True`, `observedGeneration: 1` (never
  redeployed/reconfigured since creation); `gcloud run jobs executions list` returns **0 items** —
  genuinely never run. Its env vars are exactly `CLAIM_TIMEOUT_SECONDS=600`,
  `EXECUTION_TIMEOUT_SECONDS=900`, `CANCEL_WAIT_SECONDS=120`, `ALERT_TOPIC=.../v3-orchestrator-alerts`
  — matching the claim precisely, and reusing the existing alert topic rather than a new one.
- **Timeout calculation — verified to the decimal, not just "plausible"**: pulled the five most
  recent `v3-nightly-orchestrator` executions directly via `gcloud workflows executions list`
  and computed wall-clock duration from `startTime`/`endTime` myself:
  `315.4s, 89.9s, 57.8s, 35.2s, 34.0s`. The longest is **exactly 315.4 seconds**, and
  `900 / 315.4 = 2.853...` — both figures in the claim match to the decimal. (This is the *full*
  workflow's historical wall time, appropriately used as a conservative stand-in since no
  post-import-only execution has run yet — the claim itself correctly flags that "a healthy
  post-import Unit-1 measurement is still required during rehearsal" rather than overstating this
  interim number as final.)
- **Only inert input/DLQ topics and a retained DLQ subscription exist**: `gcloud pubsub topics
  list` shows exactly `sap-post-import-refresh` and `sap-post-import-refresh-dlq` and nothing else
  matching this feature. `gcloud pubsub subscriptions list` shows **exactly one** subscription,
  attached to the *DLQ* topic, not the main input topic — confirming no push subscription exists
  anywhere that could actually deliver a message to the dispatcher. `gcloud pubsub subscriptions
  describe sap-post-import-refresh-dlq-retain` shows `messageRetentionDuration: 1209600s` (exactly
  14 days) and `expirationPolicy: {}` (empty policy = never expires) — both match the claim exactly.
- **IAM denials recorded without substituting broader roles**: `gcloud projects get-iam-policy
  --filter="bindings.members:sap-post-import"` returns **nothing** — none of the three new service
  accounts (`sap-post-import-dispatch`, `-watchdog`, `-push`, all confirmed to exist via `gcloud iam
  service-accounts list`) hold any project-level role yet. This is consistent with the claim that
  the custom-role creation and `run.services.setIamPolicy` grant were denied and nothing broader
  (e.g. a predefined `roles/workflows.invoker`, which the doc explicitly says not to substitute) was
  granted instead. I cannot re-attempt the denied IAM actions myself to reproduce the exact denial
  (doing so would itself be an IAM mutation attempt, outside this review's read-only boundary and
  outside Claude Code's role in this project) — the live absence of any binding is the strongest
  available independent confirmation that no workaround was applied.
- **No-trigger/no-execution boundary**: no push subscription (confirmed above) means nothing can
  reach `/dispatch`; the watchdog has 0 executions and no Cloud Scheduler job was created for it
  (not present in this or the prior review's scheduler inventory). The workflow itself remains
  ACTIVE at revision `000008-4e4` with `delivery_enabled: false`, unchanged from the prior review.
- **Least-privilege stop and exact remaining administrator actions**: the doc's required-grants list
  (create-only Workflows role for the dispatcher, get/cancel-only role for the watchdog, `run.invoker`
  scoped to the one dispatcher service, `pubsub.publisher` scoped to the one alert topic,
  `iam.serviceAccountTokenCreator` scoped to the one push account, and table-scoped
  `bigquery.dataEditor` flagged as needing Boat's explicit informed approval because it's broader
  than the ideal authorized-routine model) is internally consistent with everything independently
  observed: nothing broader than this has actually been granted, and BigQuery access for both
  runtimes is confirmed still absent.
- **No source deploy beyond the already-PASS artifacts occurred**: this commit is documentation only
  (`docs/design/...`, `docs/AS_BUILT_V3.md`, progress, changelog) — no `.sql`, `.py`, or `.yaml`
  source file changed. The infrastructure changes it *describes* are exactly the artifacts already
  reviewed and passed this session (DDL 072/073, dispatcher, watchdog); no new, unreviewed code was
  deployed.

## Verdict

PASS. Every concrete, checkable claim in this commit — revision names, IAM policy emptiness,
environment variable values, topic/subscription existence and retention settings, and the timeout
arithmetic down to the decimal — was independently reproduced against live GCP and BigQuery state,
not taken on trust. The deployed runtime is genuinely inert: it cannot currently receive, process,
or act on anything, and the remaining gap to activation is entirely administrator-side IAM grants
that this artifact correctly declines to work around with broader permissions. No mutation, IAM
change, or production action was performed by me in this review.

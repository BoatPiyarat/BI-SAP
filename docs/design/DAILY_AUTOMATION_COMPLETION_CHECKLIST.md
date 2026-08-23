# Daily CareOS → SAP automation completion checklist

Status at 2026-08-22 12:45 ICT: **NOT YET UNATTENDED**. Refreshed against live checkers this
session — see `docs/HANDOFF_QUEUE.md` 2026-08-22 12:45 ICT for the exact current-state execution
list. **§2 below is stale**: `POST_IMPORT_ADMIN_COMPLETION.md` was superseded 2026-08-06 by
`DEFAULT_COMPUTE_SA_AUTOMATION_WORKAROUND.md` (reuse the existing default Compute service account,
no IAM grants at all) — do not follow §2's dedicated-identity/IAM-grant steps.

This is the short operational index. Exact commands and evidence requirements remain in
`DEFAULT_COMPUTE_SA_AUTOMATION_WORKAROUND.md` (current), `POST_IMPORT_ADMIN_COMPLETION.md`
(superseded, history only), `POST_IMPORT_AUTOMATION_DEPLOYMENT.md`,
`SAP_RESULT_INGESTION_DEPLOYMENT.md`, `V3_ORCHESTRATOR_UNIT1_RUNBOOK.md`, and
`V3_DELIVERY_CONTROL_PLANE.md`.

## 1. Live and reviewed, but deliberately inert

- [x] DDL 072 atomic outbox claim/bind/release/complete procedures are live, including canonical
  numeric Workflows execution-name support.
- [x] DDL 073 row-level post-import reconciliation is live.
- [x] DDL 074 retained synthetic fixture procedure is live and has never been called.
- [x] `v3-nightly-orchestrator` revision `000009-e96` is ACTIVE and self-binds with
  `GOOGLE_CLOUD_PROJECT_NUMBER`.
- [x] `delivery_enabled: false` remains live.
- [x] Private dispatcher, unscheduled watchdog job, input/DLQ topics, and retained DLQ evidence
  subscription exist.
- [x] Read-only activation checker returns `safety_passed=true` and `rehearsal_ready=true` as of
  `2026-08-23T16:02:57.4067671Z`; permission rehearsal has not been run.
- [x] Dispatcher authenticated push subscription exists (`sap-post-import-refresh-push`).
- [x] Watchdog scheduler exists in PAUSED state (`sap-post-import-watchdog`, `*/2 * * * *`).
- [x] ~~Post-import runtime IAM is complete~~ — superseded item. Under the 2026-08-06 default-SA
  workaround, no new IAM grant is required for Track 1 at all; nothing to complete here.
- [ ] Gmail attachment-ingestion Apps Script is deployed and authorized. Owner identified
  2026-08-22: `data@rabbit.co.th` (Boat) — Script ID/OAuth still outstanding.
- [ ] A recurring V3 workflow trigger exists.
- [ ] Finance cutoff registry and reviewed automatic monthly transition are live.
- [ ] DDL 067 completeness snapshot is live: healthy-zero after Units 2–5; nonzero only after
  terminal post-import row reconciliation with no residual.
- [ ] Completeness-mail dispatcher, distinct primary/fallback recipients, and trigger are proven.
- [ ] DDL 066/068 numeric alert configurations, schedules, and human-delivery tests are live.

No post-import workflow execution, rehearsal fixture call, Gmail publication, production GCS
delivery, or SAP action was created by this activation work.

## 2. Human and administrator prerequisites

1. Boat explicitly accepts or rejects exact-table `roles/bigquery.dataEditor` on only
   `v3_post_import_refresh_outbox` for the dispatcher and watchdog identities. This role permits
   direct DML outside the procedures; general approval of reviewed work is not the same as
   informed acceptance of that residual permission.
2. A GCP IAM administrator runs the reviewed post-import administrator-completion sequence:
   narrow custom Workflows roles, exact service/resource bindings, authenticated push
   subscription, and create→pause→update of the watchdog scheduler.
3. Boat/Apps Script owner supplies or creates the Script ID and completes mailbox-owner OAuth.
   Deploy the reviewed ingestion source with `POST_IMPORT_REFRESH_TOPIC` blank.
4. Aware/Boat supplies a different accepted SAP source or explicit mapping for insurer codes
   `30`, `46`, `48`, `49`. The canonical live check found zero positive-DocEntry SAP rows and zero
   master rows for all four, so they remain held.

## 3. Activation rehearsal, still with delivery disabled

1. Run `scripts/check_post_import_activation.ps1`.
2. Require `safety_passed=true`, `rehearsal_ready=true`, watchdog scheduler `PAUSED`, and zero
   watchdog executions.
3. Use an approved window outside the enabled 20:30 ICT legacy extract and any other extract/load.
   Post-import mode runs the real Unit-1 SAP extract, bronze load, and mirror refresh even though
   delivery is disabled.
4. Call DDL 074 once with a unique 14-digit UTC nonce.
5. Run the reviewed ten-case rehearsal: claim/start, duplicate suppression, canonical self-bind,
   post-import early return, ACK, exact reject precedence, residual human action + received alert,
   overdue cancel/terminal TIMEOUT, bounded stale-claim retry, and malformed-message dead letter.
   Run ACK, REJECT, and RESIDUAL one at a time, waiting for terminal state before the next; only
   the deliberate duplicate redelivery overlaps its original child.
6. Run `scripts/check_post_import_rehearsal.ps1 -Nonce <nonce>`; require exactly three exact ledger
   cases and all expected states TRUE.
7. Retain Pub/Sub message IDs, workflow names/revisions/states, Cloud Run revision/job names,
   BigQuery rows, and human alert receipt timestamp. Do not delete rehearsal evidence.

Do not use production LogID 21153/21183 or replay a production file.

## 4. Post-import production activation

Only after section 3 passes:

1. Set Apps Script `POST_IMPORT_REFRESH_TOPIC=sap-post-import-refresh`.
2. Run one bounded mailbox poll and prove persisted header/detail → outbox → dispatcher → one
   post-import Unit-1 child → exact reconciliation.
3. Resume the two-minute watchdog scheduler.
4. Observe and review one real daily import-result cycle. Blank the topic and pause the watchdog
   immediately if any conservation residual, duplicate amplification, missing alert, or timeout
   classification is wrong.

## 5. Full daily CareOS → SAP cutover

Post-import activation alone does not make the outbound interface automatic. The final cutover is
a separate reviewed production change:

1. prove the delivery-enabled configuration against the exact-byte manifest, filename, generation,
   hash, 56-column contract, mapping/hold gates, and current OPEN accounting period;
2. deploy and rehearse the two-name filename contract: exact production object basename
   (`INSURANCE_RCB_...`) plus exact SAP-reported result name
   (`RCB_MOTOR_<production basename>`). Current one-name DDL/workflow/Apps Script binding cannot
   match the confirmed LogID 21183 shape;
3. deploy the reviewed private promoter and create the recurring V3 workflow trigger PAUSED;
   require `scripts/check_v3_delivery_control_plane.ps1` to return `safety_passed=true` and
   `control_plane_ready=true` before any one-file production rehearsal;
4. after controlled healthy-zero or terminal post-import reconciliation is final, deploy and
   rehearse the separate completeness snapshot/dispatcher path from
   `../FINDINGS_DAILY_COMPLETENESS_RUNTIME_GAP_20260805.md`;
5. keep legacy extract/query schedules until the V3 trigger and delivery path pass the defined
   overlap/shadow gate, then pause legacy producers in one rollback-safe cutover;
6. never enable a recurring trigger while `delivery_enabled: false` and call the result “daily
   interface automation”;
7. retain July close `2026-08-03 15:00 ICT` and August close
   `2026-09-01 14:00 ICT`; Finance supplies future monthly cutoffs. The current workflow does not
   call `sp_close_open_period`, and that procedure requires the next cutoff at call time; close
   `../FINDINGS_MONTHLY_CUTOFF_AUTOMATION_GAP_20260805.md` before claiming automation across a
   month boundary.

Rollback is configuration-first: blank Gmail publication, pause the watchdog and V3 recurring
trigger, disable authenticated push delivery through a separately reviewed resource/IAM change,
restore the prior workflow revision if needed, and re-enable the legacy producers. Do not delete
ledgers, messages, manifests, or execution history.

## 6. Goal acceptance

Declare the goal reached only after five consecutive business days where:

- the outbound file is generated and delivered automatically before the SAP processing window;
- SAP pickup and import result are ingested automatically;
- exact row-level ACK/reject and second-mirror conservation complete;
- every hold/error appears in the human report;
- the heartbeat and failure alert reach a human;
- no manual extract, rename, upload, mailbox parsing, reconciliation, or scheduler repair is
  required.

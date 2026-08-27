# V3 PAUSED Scheduler final deployment evidence — 2026-08-27

## Outcome

The canonical recurring V3 Scheduler is staged with the exact reviewed contract and remains
PAUSED. The corrected update completed at `2026-08-27T07:20:51.7388612Z`. The workflow was not
executed, delivery remains disabled, and the still-enabled legacy SAP extract schedule was not
changed.

## Deployment continuation

- Progress checkpoint before retry: commit `e02a8a2`.
- Update lower bound: `2026-08-27T07:20:48.3083649Z`.
- Only `gcloud scheduler jobs update http v3-nightly-orchestrator` was retried.
- Correct installed-CLI flag: `--update-headers='Content-Type=application/json'`.
- Resulting user update time: `2026-08-27T07:20:50.746373Z`.
- No create, IAM, run, resume, workflow-execute, or legacy-Scheduler command was included in the
  retry.

## Final resource contract

Read-only describe proves:

- exact resource:
  `projects/pacific-plating-282708/locations/asia-southeast1/jobs/v3-nightly-orchestrator`;
- state `PAUSED`;
- schedule `30 20 * * *`, timezone `Asia/Bangkok`;
- target is the exact `v3-nightly-orchestrator` Workflow Executions API URI using POST;
- OAuth identity is the default Compute service account with cloud-platform scope;
- message has `Content-Type: application/json` and the reviewed nested argument containing only
  promoter URL `https://sap-delivery-promoter-3uymtccdma-as.a.run.app`;
- retry attempts were explicitly set to zero; the API omits the zero-valued field and reports
  `maxRetryDuration: 0s`, consistent with the installed gcloud default/command.

## No-execution and non-overlap evidence

At `2026-08-27T07:21:18.8767067Z`, exact read-only execution query
`gcloud workflows executions list v3-nightly-orchestrator` used project
`pacific-plating-282708`, location `asia-southeast1`, inclusive filter
`startTime>=2026-08-27T07:16:43.5752068Z` captured before the original create, limit 1, format
`value(name,startTime,state)`, and returned zero rows.

Scheduler inventory at the same checkpoint shows:

- `v3-nightly-orchestrator`: PAUSED, `30 20 * * *`, Asia/Bangkok;
- `sap-extract-schedule`: still ENABLED, `30 20 * * *`, Asia/Bangkok;
- `sap-order-payment`: PAUSED;
- `sap-order-payment-non-motor`: PAUSED;
- `sap-post-import-watchdog`: PAUSED.

Therefore staging caused no overlap, but resuming V3 now would overlap the enabled 20:30 extract
producer and remains forbidden until an atomic cutover pauses the legacy schedule.

## Machine gate

At `2026-08-27T07:21:33.5545331Z`,
`scripts/check_v3_delivery_control_plane.ps1` reported:

- workflow revision `000010-daf` and promoter revision
  `sap-delivery-promoter-00001-grm`;
- `delivery_enabled:false`;
- Scheduler `PAUSED`;
- `safety_passed:true` with no failures;
- `control_plane_ready:true` with no readiness blockers;
- `permission_rehearsal_required:true`.

Control-plane readiness is configuration readiness only. It is not permission-rehearsal success,
delivery approval, scenario activation, SAP pickup/import, or ACK proof.

## Rollback and retained blockers

Immediate containment is already PAUSED. Full rollback to the absent prestate requires separately
approved deletion of exactly this canonical job and was not performed. Exact Unit 2 magnitude
thresholds/provenance remain missing; Scenario 1/3 fresh release builds remain blocked. Delivery,
bounded permission rehearsal, atomic non-overlap cutover, and SAP lifecycle verification all remain
separate reviewed gates.

## Review

The final PAUSED deployment evidence received local two-axis Class-A PASS for Standards/Safety and
Spec. See `docs/reviews/2026-08-27-v3-paused-scheduler-deploy-class-a.md`.

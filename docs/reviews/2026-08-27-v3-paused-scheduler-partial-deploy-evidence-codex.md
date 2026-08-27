# V3 PAUSED Scheduler partial deployment evidence — 2026-08-27

## Outcome

The canonical Scheduler resource was created on the reviewed dormant January-only cadence and
successfully paused. The subsequent update to the intended 20:30 ICT cadence failed before making
a change because this installed gcloud rejects create-only flag `--headers` on `jobs update http`.
The resource is safe but incomplete: PAUSED on `0 0 1 1 *`, not yet the canonical cadence.

No retry or later production mutation occurred before this evidence/progress checkpoint.

## Exact mutation sequence and boundary

- Captured pre-create lower bound: `2026-08-27T07:16:43.5752068Z`.
- `gcloud scheduler jobs create http v3-nightly-orchestrator` succeeded with the dormant schedule,
  exact endpoint/OAuth/body contract, zero retry attempts, and state initially ENABLED.
- `gcloud scheduler jobs pause v3-nightly-orchestrator` succeeded.
- `gcloud scheduler jobs update http ... --headers=Content-Type=application/json` failed locally
  with `unrecognized arguments`; no update API mutation occurred.
- The command sequence contained no IAM, workflow execute, Scheduler run/resume, legacy-Scheduler,
  delivery, BigQuery, SAP, or ACK operation.

## Read-only postchecks

Scheduler describe after the failure reported:

- resource:
  `projects/pacific-plating-282708/locations/asia-southeast1/jobs/v3-nightly-orchestrator`;
- state `PAUSED`;
- schedule `0 0 1 1 *`, timezone `Asia/Bangkok`;
- exact Workflow Executions API URI, POST, default Compute OAuth identity, cloud-platform scope;
- JSON content header and the reviewed base64 message body;
- user update time `2026-08-27T07:16:48.426596Z`.

At `2026-08-27T07:17:39.4639018Z`, exact read-only execution query
`gcloud workflows executions list v3-nightly-orchestrator` used project
`pacific-plating-282708`, location `asia-southeast1`, filter
`startTime>=2026-08-27T07:16:43.5752068Z`, limit 1, format
`value(name,startTime,state)`, and returned zero rows.

The control-plane checker at `2026-08-27T07:17:52.7831252Z` reported
`safety_passed:true`, `delivery_enabled:false`, Scheduler PAUSED, and
`control_plane_ready:false`. Its only readiness blocker was the deliberately incomplete cadence.

## Diagnosis and correction

The exact red-capable reproduction is the rejected update flag. Installed local help proves update
supports `--clear-headers`, `--remove-headers`, and `--update-headers`, not `--headers`. The minimal
source correction changes only the update command to
`--update-headers='Content-Type=application/json'`; create retains `--headers`.

## Containment and rollback

Current containment is already satisfied because the job is PAUSED on a non-firing-until-January
cadence. Full rollback to the absent prestate is exact deletion of this canonical job and requires
separate explicit destructive approval. It was not performed. The safe forward fix is a separately
reviewed update while PAUSED, followed by zero-execution and full control-plane verification.

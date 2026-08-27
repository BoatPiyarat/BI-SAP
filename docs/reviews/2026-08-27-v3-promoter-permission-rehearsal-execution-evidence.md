# V3 promoter no-write permission-rehearsal execution evidence

Date: 2026-08-27

Workflow revision: `000011-291`

Runner commit: `1d38a78`

Rehearsal lower bound: `2026-08-27T11:45:54.5711309Z`

## Execution result

- Execution: `3011a2fa-9b8e-4a28-9789-47c8a181c2eb`
- Created/started: `2026-08-27T11:45:57.284593073Z`
- Ended: `2026-08-27T11:46:00.764043548Z`
- Duration: `3.479450475s`
- State: SUCCEEDED
- Terminal step: `return_expected_validator_rejection`
- Result:
  `{"http_code":400,"permission_rehearsal":"PROMOTER_AUTH_REACHED_VALIDATOR","production_write_expected":false}`

This proves the Workflow identity reached the private promoter application validator. It does not
activate delivery or prove a valid promotion request.

## Exact-window no-side-effect proof

At `2026-08-27T11:53:36.4100570Z`, durable verifier
`scripts/verify_v3_promoter_permission_rehearsal.ps1` returned
`verification_passed:true` for the inclusive lower-bound window:

- promoter revision `sap-delivery-promoter-00001-grm`: exactly one HTTP 400 request log, timestamp
  `2026-08-27T11:45:57.470605Z`
- GCS object create/update/delete audit events by
  `data-extraction@pacific-plating-282708.iam.gserviceaccount.com`: `0`
- all BigQuery audit events by
  `919786098205-compute@developer.gserviceaccount.com`: `0`
- `sap-extract-job` executions with
  `metadata.creationTimestamp>=2026-08-27T11:45:54.5711309Z` and
  `metadata.creationTimestamp<=2026-08-27T11:53:36.4100570Z`: `0`
- Scheduler state: PAUSED
- Workflow delivery literal false: true
- Workflow delivery literal true: false

Cloud Logging queries read the last hour then apply exact lower/upper timestamps locally. This
avoids Windows shell damage to colon-bearing timestamp filter literals. The first verifier draft's
read-only BigQuery INFORMATION_SCHEMA query failed during command handoff and was replaced by the
stronger exact-principal BigQuery Cloud Audit census; it did not run as the Workflow identity.
The final verifier fails if the lower bound does not precede execution start, execution end is not
inside the checked window, the window exceeds the one-hour read, or any candidate query reaches its
1,000-row cap. Final candidate counts were promoter `1`, GCS mutation `0`, and BigQuery `1`; all caps
were clear, and the sole BigQuery candidate was outside the exact rehearsal window.

## Scope and retained holds

The rehearsal created only immutable Workflow and request logs. It did not perform a valid promoter
request, GCS promotion, BigQuery pipeline job, SAP extraction, delivery marker, Scheduler resume,
SAP import, or ACK. Delivery remains disabled and the canonical V3 Scheduler remains PAUSED.

Before any further production deployment or run, this evidence and verifier must pass both Class-A
axes and be committed. Exact Unit 2 thresholds and the atomic legacy/V3 non-overlap cutover remain
outstanding.

## Class-A result

- Standards / safety: **PASS** after adding execution-window coverage and logging candidate-cap
  fail-closed gates.
- Spec: **PASS** after changing the promoter request condition from at-least-one to exactly one.
- Final verdict: **PASS**. The no-write promoter permission rehearsal is complete. This does not
  approve delivery enablement or Scheduler resume.

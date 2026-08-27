# Class-A review — V3 promoter no-write permission rehearsal source

Date: 2026-08-27

Fixed point: `ae421b0`

Scope:

- `infra/v3_nightly_orchestrator.workflows.yaml`
- `scripts/check_v3_promoter_permission_rehearsal.py`
- `docs/V3_PROMOTER_PERMISSION_REHEARSAL_PROPOSAL_20260827.md`

Review mode: local, read-only, independent Standards/Safety and Spec axes.

## Standards / safety — PASS

The final structural checker scopes every load-bearing assertion to the rehearsal branch: exact
single `http.post`, canonical URL, OIDC/audience, empty body, exact HTTP 400 validator text,
terminal accepted return, both failure raises, and ordering before post-import/logging. Recursive
call census excludes any additional external call. Static YAML/check run passes.

The branch cannot fall through. Expected validator rejection returns; HTTP success, auth/transport
failure, and any other response raise. Default false preserves the normal path and delivery remains
false. Deployment and execution are separate checkpoints with Scheduler PAUSED.

## Spec — PASS

The proposal requires exact workflow/Cloud Run result, GCS mutation, BigQuery job, and
`sap-extract-job` execution evidence from a captured lower bound. It retains delivery/Scheduler/
activation blocks and rollback to revision `000010-daf` / commit `8a420d7`.

## Final verdict

**PASS.** Safe to commit and deploy the delivery-disabled source. Do not execute the rehearsal
until the deployment evidence has its own reviewed/committed checkpoint.

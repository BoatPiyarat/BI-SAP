# V3 delivery-disabled workflow production deployment evidence — 2026-08-27

## Outcome

The full reviewed V3 workflow candidate is deployed as revision `000010-daf`. The deployment did
not execute the workflow, enable delivery, or create/enable a Scheduler. The control plane remains
fail-closed and intentionally not ready for unattended execution.

## Review and source identity

- Reviewed full replacement delta: live-proved base `65ebde3` through candidate `8a420d7`;
  `docs/reviews/2026-08-27-8a420d7-full-delta-claude.md` is PASS WITH NOTES.
- `git diff --quiet 8a420d7..HEAD -- infra/v3_nightly_orchestrator.workflows.yaml` passed immediately
  before deployment: no later commit changed the reviewed workflow source.
- Local PyYAML parsing passed with 14 top-level keys and `main` present.
- All reviewed prerequisites were staged before this deployment: live 13-parameter DDL 062, live
  DDL 070 schema dependency, corrected transactional DDL 067, and private promoter revision
  `sap-delivery-promoter-00001-grm`.

## Deployment identity

- Command scope: deploy only `v3-nightly-orchestrator` from
  `infra/v3_nightly_orchestrator.workflows.yaml`, preserving the existing default Compute service
  account; no execute or Scheduler command was included.
- Operation: `operation-1787813877441-65a01db16e570-b9b0c990-303a87ed`
- Prior revision: `000009-e96`, ACTIVE, `delivery_enabled: false`
- New revision: `000010-daf`, ACTIVE
- Revision create time: `2026-08-27T06:57:59.068010683Z`
- Update time: `2026-08-27T06:57:59.335503384Z`
- Service account:
  `919786098205-compute@developer.gserviceaccount.com`

## Post-deployment verification

Durable verifier `scripts/verify_v3_workflow_deployment.ps1` was executed as:

```powershell
./scripts/verify_v3_workflow_deployment.ps1 `
  -ExpectedRevision 000010-daf
```

At `2026-08-27T07:07:00.0609995Z`, it reported equal source character lengths (64,276) and
exactly two codepoint differences: index 41 / candidate line 1 and index 16,319 / candidate line
331. Both candidate characters are U+2014, both live characters are ASCII `?`, and both lines are
comments. Every other character matched; neither mismatch is executable YAML. Live SHA-256 was
`97f8d99ea4b98b9762d42ec5cfd3ecbc1af5b0d3692bd3f70dc6e69ac4c0e921`; UTF-8 candidate
SHA-256 was `114895ea2fbd521a3ac2d4a90b028a22d135d15a0401c391b0eca8e6c569e7ab`.

The same postcheck proved:

- live revision `000010-daf` is ACTIVE under the intended service account;
- live source contains literal `delivery_enabled: false` and no literal enabled assignment;
- exact approved service account is part of the verifier's pass gate;
- zero workflow executions have `startTime` at or after the live revision's own create time. The verifier's
  cutoff is derived from live `revisionCreateTime`; its exact read-only query is
  `gcloud workflows executions list v3-nightly-orchestrator` against
  project `pacific-plating-282708`, location `asia-southeast1`, filter
  `startTime>=2026-08-27T06:57:59.068010683Z`, limit 1, format
  `value(name,startTime,state)`; returned count was zero.

The live control-plane checker at `2026-08-27T06:58:41.5549783Z` reported:

- workflow revision `000010-daf`;
- promoter revision `sap-delivery-promoter-00001-grm`;
- `delivery_enabled: false`;
- `scheduler_state: null`;
- `safety_passed: true`, with no safety failures;
- `control_plane_ready: false`, with the sole readiness blocker
  `PAUSED recurring V3 scheduler is absent`.

This is the intended staged state. No workflow runtime, interface delivery, SAP pickup/import, or
ACK success is claimed.

## Rollback boundary

The rollback target is prior live revision/source `000009-e96`, whose repository baseline is
commit `65ebde3`, with the same default Compute service account and delivery disabled. Restoring it
would require a separate reviewed `gcloud workflows deploy` of that source. Rollback was not
needed or executed. Scheduler remains absent, so there is no recurring trigger to pause first.

Exact rollback preparation/deploy sequence (not executed):

```powershell
$rollbackDir = Join-Path $env:TEMP 'v3-workflow-rollback-65ebde3'
git worktree add --detach $rollbackDir 65ebde3
gcloud workflows deploy v3-nightly-orchestrator `
  --project pacific-plating-282708 `
  --location asia-southeast1 `
  --source (Join-Path $rollbackDir 'infra/v3_nightly_orchestrator.workflows.yaml') `
  --service-account 919786098205-compute@developer.gserviceaccount.com `
  --quiet
```

Before activation, rehearse and time this rollback in a non-production workflow target to prove
the documented under-five-minute objective; this production deployment does not claim that timing
proof.

## Review

The final durable verifier and bounded deployment evidence received local two-axis Class-A PASS
for both Standards/Safety and Spec. The successive review BLOCKs and their corrections are recorded
in `docs/reviews/2026-08-27-v3-workflow-deploy-evidence-class-a.md`.

# Class-A review — V3 promoter deployment evidence and checker fix

Date: 2026-08-27

Fixed point: `1b45d9f`

Scope:

- `scripts/check_v3_delivery_control_plane.ps1`
- `docs/reviews/2026-08-27-v3-promoter-deployment-evidence-codex.md`
- promoter deployment section in `docs/sessions/2026-08-27-codex.md`

Review mode: local, read-only, independent two-axis review. The attempted external Claude handoff
was rejected before transmission because the combined payload exceeded the approved disclosure
scope; no workaround was attempted.

## Standards / safety — PASS

- The final evidence records the GCS audit timestamp, project, complete filter, output format,
  limit, and exact zero-row result, and bounds the conclusion to the named runtime identity and
  audit-visible methods.
- Broader statements are limited to operations absent from the deploy command and directly
  observed post-deployment state, with an explicit disclaimer for other actors/systems.
- The checker safely initializes an empty member collection and tests for the `bindings` property
  before dereferencing it. Command failures still throw and public principals remain blockers.
- Rollback wording is honest: deletion is identified but was not executed or claimed as tested.

## Spec — PASS

- The contradictory original wording “No promoter request” was replaced by the truthful boundary
  that no valid promotion/delivery request was accepted, consistent with the invalid-body probe.
- The service is consistently labelled private and staged. Delivery remains false, Scheduler is
  absent, and no SAP pickup/import/ACK success is claimed.
- The required post-deployment OneDrive progress entry is present.
- No scope creep was found.

## Final verdict

**PASS.** Safe to commit these artifacts and proceed to a separately gated workflow deployment
while delivery and Scheduler remain disabled.

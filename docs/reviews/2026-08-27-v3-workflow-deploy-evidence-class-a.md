# Class-A review — V3 workflow deployment evidence and verifier

Date: 2026-08-27

Fixed point: `07ea3b9`

Scope:

- `scripts/verify_v3_workflow_deployment.ps1`
- `docs/reviews/2026-08-27-v3-workflow-deployment-evidence-codex.md`
- workflow deployment section in `docs/sessions/2026-08-27-codex.md`

Review mode: local, read-only, independent Standards/Safety and Spec axes.

## Standards / safety — PASS

Initial review BLOCKed narrative-only source identity and zero-execution claims. The final durable
verifier closes both: it records the exact workflow/project/location/filter/limit/format/count,
compares every character with hashes/lengths/codepoints/indices/lines, permits only U+2014 to `?`
serialization on comment-only lines, and fails nonzero on any other mismatch.

A second BLOCK found that the execution cutoff was caller-controlled. The final verifier removes
that parameter, derives the cutoff from live `revisionCreateTime`, and includes the exact approved
service account in `verification_passed`. The corrected live run returned true. Command failures
remain fatal under StrictMode.

Rollback wording and exact preparation/deploy sequence are honest. Under-five-minute timing is
explicitly not claimed and remains a pre-activation rehearsal requirement.

## Spec — PASS

The evidence proves the unchanged reviewed workflow was deployed separately, retains literal
delivery false, has no execution since its live revision creation time, has no recurring Scheduler,
and keeps the private promoter staged. It documents the prior rollback target without claiming a
rollback was executed. No SAP pickup/import/ACK success is claimed. The post-deployment OneDrive
progress update is present before any later deployment.

## Final verdict

**PASS.** The deployment evidence and verifier are safe to commit. Any later Scheduler creation,
workflow execution, delivery activation, or scenario activation remains a separate gate.

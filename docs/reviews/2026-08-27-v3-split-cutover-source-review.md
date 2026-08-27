# Review — V3 common cutover and split activation source

Date: 2026-08-27

Fixed point: `74b594f`

Scope:

- `docs/design/V3_PRODUCTION_CUTOVER_AND_SPLIT_ACTIVATION.md`
- current Workflow revision `000011-291` source
- deployed DDL 098 source

Independent review status: unavailable; both review workers failed because workspace credits were
exhausted. The review below is a local two-axis audit and is not represented as independent Class-A
PASS.

## Standards / safety

The design is fail-closed and makes no production mutation. It retains delivery false, exact
threshold/approval gates, ordered pause-before-resume sequencing, exact Scheduler prestate, fresh
paginated inventory, rollback verification, and manual fallback. It does not infer unread audit
rows or broaden approvals.

## Spec

**BLOCK for execution.** The current implementation cannot yet satisfy the requested split routine
activation and rollback proof:

1. the global Workflow lacks a scenario selector;
2. flow-scoped DDL 098 cannot own the common preparation Scheduler;
3. DDL 098 has no abort transition from `PRESTATE_CAPTURED` after an external mutation failure;
4. seven flows lack the universal flow/run-bound export-to-SAP lifecycle evidence required by the
   nine-flow audit.

## Verdict

**BLOCK.** The design is safe to commit as source/decision evidence, but Scheduler resume, delivery
enablement, and any new flow-specific scheduler remain forbidden. Re-review independently after
credits return and after the common cutover ledger/abort path is implemented.

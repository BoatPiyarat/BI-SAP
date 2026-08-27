# Review — DDL 102 common Scheduler cutover control

Date: 2026-08-27

Fixed point: `28a6cc4`

Scope:

- `sql/ddl/102_v3_common_scheduler_cutover_control.sql`
- `scripts/check_v3_common_cutover_control.py`
- `sql/operator/20260827_v3_common_scheduler_cutover_manual_fallback.sql`

Independent review status: unavailable because both review workers failed with exhausted workspace
credits. This is a local Standards/Spec audit, not an independent Class-A PASS.

## Standards / safety

Static checker `scripts/check_v3_common_cutover_control.py` returns
`V3_COMMON_CUTOVER_CONTROL_STATIC=PASS`. It gates the five expected procedures, V3-only object
scope, absence of external CALL/export/GCS/interface paths, threshold/fresh-run requirements,
immutable typed runtime evidence, registered Scheduler inventories, exact config hashes, singleton
mutex, state transitions, overlap checks, and read-only fallback.

Local review found and corrected before this checkpoint:

1. unregistered raw rehearsal/census JSON;
2. Scheduler poststate not cryptographically bound to inventory/prestate;
3. no serialization of concurrent common cutover claims;
4. mismatch between flattened rehearsal fields and the exact nested verifier output;
5. restored legacy inventory lacked an explicit zero-overlap assertion.

## Spec

The source supplies the previously missing common preparation approval, claim, finalize, ABORTED,
and ROLLED_BACK states without calling Scheduler from SQL. It requires one active Unit 2 config, a
fresh non-bootstrap magnitude PASS, exact no-write promoter evidence, delivery-disabled zero-active
Workflow census, fresh full Scheduler inventories, exact job configurations, and the human fallback
query.

## Verdict

**BLOCK pending independent Class-A review and authenticated canonical-wrapper dry-run.** Safe to
commit as source only. Do not deploy DDL 102, register evidence/approval, claim a cutover, or change
either Scheduler. The current V3 Scheduler remains PAUSED.

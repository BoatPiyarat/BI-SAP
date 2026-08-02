# V3 Unit 4 period-state evidence — 2026-08-02

Status: rehearsal passed; production definition/seed evidence is appended only after execution.

## Rehearsal

- Job: `v3_unit4_rollback_rehearsal_20260802_1942`
- Scope: BigQuery TEMP tables only; no persistent object changed
- Passed: exact-one OPEN before and after transition
- Passed: calendar adjacency July → August → September
- Passed: July CLOSED and August OPEN are committed together
- Passed: legacy compatibility retains exactly one active row
- Passed: old backlog clamps to 2026-08-01, August remains raw, September is held
- Passed: deliberate assertion failure after a mutation rolled the transaction back to its original value

## Production boundary

Deploying 053 creates the state table and procedures but does not close July. The one-time seed may
copy the single authoritative active legacy row into July OPEN plus August PLANNED. The close CALL
refuses to run before the stored July `closing_at`; it also requires the next month's authoritative
closing timestamp. Therefore this release must not advance July merely because rehearsal passed.

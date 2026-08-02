# V3 Unit 4 period-state evidence — 2026-08-02

Status: rehearsal, production definition deployment, and one-time seed passed. July was not closed.

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

## Production evidence

- Source commit: `e807f65`
- Definition deploy: `v3_unit4_053_e807f65_deploy_20260802_1948`, DONE, 0 bytes
- One-time seed: `v3_unit4_seed_from_lock_20260802_1949`, DONE, 39 bytes processed,
  31,457,280 bytes billed; inserted exactly 2 state rows
- Verification: `v3_unit4_seed_verify_20260802_1950`, DONE, 105 bytes processed,
  20,971,520 bytes billed
- Result: July 2026 is OPEN with `closing_at=2026-08-03T07:00:00Z` (14:00 ICT), August 2026 is
  PLANNED, and the legacy table still has exactly one active row for July.

`sp_close_open_period` was not called. It remains time-gated and also requires the authoritative
August closing timestamp.

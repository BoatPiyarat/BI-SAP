# Failed-closed deployment evidence — DDL 058 `37b5a9b`

Recorded: 2026-08-28 00:49 ICT

## Approved boundary

Boat supplied `Deploy OK` for the pending definition-only deployment of exact DDL 058 commit
`37b5a9b`: create the additive required-value hold table and replace only
`sp_build_v3_newpayment_shadow`. No procedure CALL, Units 1–5 run, GCS/promoter action,
Workflow/Scheduler/IAM change, or retry was authorized.

## Preflight

- Claude Class-A review commit `1944208`: **PASS WITH NOTES**, no BLOCK.
- Exact working DDL and regression checker matched commit `37b5a9b` and passed static validation.
- Live routine remained the one-argument rollback definition, normalized SHA-256
  `24f08a59b2a0831be923be9118cf6669aaafcaad14c85d51099a5d6a750defce`.
- Mandatory safety-wrapper self-test: 7/7 PASS.
- Authenticated DDL dry-run: 0 bytes.

## Attempt and terminal result

- Job: `codex_v3_ddl058_required_hold_20260828_0049_ict`
- Location: `asia-southeast1`
- Principal: `data@rabbit.co.th`
- State: `DONE` with `invalidQuery`
- Processed/billed: 0 / 0 bytes
- Exact error: `NOT NULL cannot be applied to ARRAY field 'invalid_fields'. NULL arrays are
  always stored as an empty array. at [51:1]`

BigQuery's dry-run accepted the script but the real DDL validator rejected the unsupported
`invalid_fields ARRAY<STRING> NOT NULL` declaration. No retry was attempted.

## Zero-impact postcheck

- `v3_unit5_candidate_required_hold` does not exist.
- Live routine `lastModifiedTime` remains `1787786021961`.
- Live routine normalized SHA-256 remains
  `24f08a59b2a0831be923be9118cf6669aaafcaad14c85d51099a5d6a750defce`, exactly the rollback
  source.
- Therefore neither the hold table nor the procedure definition changed. No CALL, payload build,
  production delivery row, GCS write, promoter invocation, or Scheduler/IAM action occurred.

## Corrective boundary

The minimal source correction removes only `NOT NULL` from `invalid_fields ARRAY<STRING>`;
BigQuery ARRAY values are intrinsically stored as arrays. The checker now rejects the invalid
declaration. The first zero-byte temporary fixture job
`codex_v3_ddl058_array_fixture_20260828_0052_ict` proved the nullable ARRAY declaration compiles,
then failed only because its test assertion used unsupported direct ARRAY equality; the corrected
fixture compares `TO_JSON_STRING` instead. This new delta requires Class-A review and a new
explicit deploy approval before any second production attempt.

Corrected fixture job `codex_v3_ddl058_array_fixture_20260828_0054_ict` then completed
successfully: 0 bytes, one temporary row inserted, both assertions PASS, and no persistent object.

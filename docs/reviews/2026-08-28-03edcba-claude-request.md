# Claude Code Class-A delta review request — `03edcba`

Reviewer: Claude Code
Class: A — blocking
Mode: read-only. Do not deploy, CALL a mutating procedure, write GCS, or change Scheduler,
Workflow, IAM, SAP, or interface state.

## Exact review range and files

Review the executable delta from `37b5a9b` to `03edcba` in:

1. `sql/ddl/058_v3_unit5_newpayment_shadow.sql`
2. `scripts/check_v3_unit5_required_hold_fix.py`
3. `sql/operator/20260827_verify_v3_unit5_required_hold_fixture.sql`

Context only: `docs/reviews/2026-08-27-37b5a9b-claude.md`,
`docs/AGENT_RULES.md`, `docs/design/SAP_INTERFACE_PRE_EXPORT_GATE.md`, and
`docs/design/MO_RCL_RECOVERY_V3.md`.

## Why this delta exists

Claude's first review passed `37b5a9b` with notes. A recommended independent second pass then
found two real blockers:

- Paid completeness and other item-level validations still ran before the NULL hold, so one bad
  item could abort unrelated clean items instead of being durably quarantined.
- the changed source used wide `SELECT *` projections in positional publication.

Commit `03edcba` closes both. It materializes PII-safe rule-code issues for incomplete spines,
invalid status, duplicate period/invoice identities, overlong PolicyNo, blank Paid required fields,
SQL/literal NULL, invalid required dates, and invalid nonblank PaymentDate. Any issue holds the
complete OrderItem; only issue-free items enter release, producer hash, ready publication, and
identity publication. Every wide projection and INSERT touched by this unit now names its columns
explicitly. Missing/blank OrderItem remains a file-level abort because no durable item identity
exists to quarantine.

This delta does not change the already-approved `InsuredID='-'` representation (F1 evidence in
`docs/FINDINGS_E1_E3_F1_F3_20260801.md`) or the confirmed Pending blank-field rules. It does not
modify source values, mappings, payment amounts, InvoiceNo generation, scheduling, delivery, or
archive behavior.

## Evidence

- Historical regression: checker against `1f5c20c` is RED.
- Current static regression: `V3_UNIT5_REQUIRED_HOLD_STATIC=PASS`.
- Static scan finds no `SELECT *` or `SELECT DISTINCT *` in DDL 058.
- Mandatory-wrapper authenticated DDL dry-run: PASS, 0 bytes, 2026-08-28 00:52–00:54 ICT.
- First expanded fixture execution `codex_v3_unit5_item_hold_fixture_20260828_0054` correctly
  exposed a non-decorrelatable field-array subquery; no result was used. The implementation and
  fixture were changed to an explicit pre-aggregated invalid-field table.
- Corrected fixture job `codex_v3_unit5_item_hold_fixture_20260828_0057`: SUCCESS,
  2026-08-28 00:54:38 ICT, 6,007 bytes processed / 188,743,680 billed. Stored result:
  `PASS`, 7 mixed invalid items held, 1 mixed clean item released, zero-held case released,
  zero-released case retained.
- `git diff --check`: clean.
- Live prestate is still the prior routine definition (metadata `lastModifiedTime=1787786021961`);
  the proposed hold table does not exist. Reviewed rollback is exact redeployment of the pre-delta
  DDL 058 source at `6354d5b`; an additive hold table, if later created, remains inert and is not
  dropped.

## Review questions

1. Does every applicable item-level pre-export failure now produce one durable whole-item hold
   without weakening file-level identity/schema/mapping assertions?
2. Can any held item leak into producer hash/count, ready rows, event identity, DDL 059, or archive?
3. Are release + hold item sets conserved for ordinary, zero-held, and zero-released populations?
4. Are issue and field aggregations PII-safe, deterministic, and at exact OrderItem grain?
5. Are all positional 56-column projections and INSERTs explicit and order-preserving?
6. Are transaction claim, hold publication, ready publication, and identity publication
   replay-safe and atomic?
7. Does the fixture materially exercise each newly item-scoped rule and the prior Paid-before-hold
   defect?
8. Is rollback exact and safe given the new table is absent before deployment?

Return PASS, PASS WITH NOTES, or BLOCK. A PASS authorizes neither definition deployment nor a
procedure CALL; each still requires a separate scoped Boat approval, and production delivery,
Scheduler activation, GCS promotion, and SAP import remain closed.

# Codex receipt — Claude Class-A review for `37b5a9b`

Recorded: 2026-08-28 (Asia/Bangkok)

## Result

- Claude review commit: `1944208`
- Review file: `docs/reviews/2026-08-27-37b5a9b-claude.md`
- Verdict: **PASS WITH NOTES**
- Blocking findings: none
- No duplicate review transfer was sent after the review commit was discovered on the current
  branch and `origin/p0/stg-sap-state`.

Claude confirmed whole-OrderItem quarantine, released/held conservation, exclusion of held items
from producer hash/ready/identity paths, transaction/replay behavior, complete-spine preservation,
PII-safe field-name evidence, and exact rollback feasibility. Its non-blocking notes are:

1. `POLICYNO_TOO_LONG` and Paid-completeness remain candidate-wide aborts and may later merit the
   same item-level policy after an explicit scope decision.
2. DDL 059/downstream behavior was accepted structurally rather than independently re-derived
   line-by-line.
3. Notification/morning-report integration is a future requirement before recurring or
   delivery-enabled operation, not a blocker for the delivery-disabled pilot.

## Live prestate and rollback proof

Metadata-only `bq show --routine` after the review proved the live object is a one-argument SQL
procedure and its normalized definition body exactly equals rollback source commit `6354d5b`:

- live normalized body SHA-256:
  `24f08a59b2a0831be923be9118cf6669aaafcaad14c85d51099a5d6a750defce`
- `6354d5b` normalized body SHA-256:
  `24f08a59b2a0831be923be9118cf6669aaafcaad14c85d51099a5d6a750defce`
- exact equality: `true`

Rollback is therefore an exact redeployment of DDL 058 from `6354d5b`. The additive hold table
must remain inert and must not be dropped or cleaned during rollback.

## Remaining approval boundary

This review PASS authorizes no mutation. A separate Boat `deploy OK` is required to execute exact
DDL 058 from `37b5a9b`. That deployment creates the additive hold table if absent and replaces only
`sp_build_v3_newpayment_shadow`; it does not CALL the procedure, run Units 1–5, write GCS, invoke
the promoter, or change Workflow/Scheduler/IAM state. Any later fresh production run requires a
second, separate exact approval.

# Claude Code Class-A review request — `37b5a9b`

Opened: 2026-08-27T22:53:01+07:00
Reviewer: Claude Code (Anthropic)
Class: A — blocking
Mode: read-only; do not deploy, execute a mutating procedure, query production, write GCS, or
change Workflow/Scheduler/IAM state.

## Exact files proposed for user-authorized review packet

1. `sql/ddl/058_v3_unit5_newpayment_shadow.sql`
2. `scripts/check_v3_unit5_required_hold_fix.py`
3. `sql/operator/20260827_verify_v3_unit5_required_hold_fixture.sql`
4. `sql/adhoc/20260827_repro_failed_fresh_newpayment_null.sql`
5. `docs/reviews/2026-08-27-fresh-units1-5-pilot-run-evidence-codex.md`
6. `docs/AGENT_RULES.md`
7. `docs/AGENT_REVIEW_PROTOCOL.md`
8. `docs/design/SAP_INTERFACE_PRE_EXPORT_GATE.md`
9. `docs/design/MO_RCL_RECOVERY_V3.md`
10. `docs/tasks/TASK_1_15AUG_MISSING_INTERFACE_20260817.md`
11. `sql/ddl/059_v3_unit5_balance_hold.sql`
12. `sql/ddl/061_v3_units2_5_nightly_wrapper.sql`
13. `sql/ddl/088_v3_rcl_later_newpayment_split.sql`

Review exact artifact commit `37b5a9b`; production-attempt evidence is commit `1f5c20c`. Files
6–13 are read-only context and are not part of the proposed deployment delta.

## Incident and claimed correction

The one approved delivery-disabled run
`V3NIGHTLY-2026-08-27T15:26:08-01480a29` failed closed in
`sp_build_v3_newpayment_shadow` on the candidate SQL/literal-NULL assertion. Targeted read-only job
`bqjob_r7974197aa5c6752c_000001a043e6090a_1` (9.405 GiB dry-run estimate) found only two
un-normalized source fields: installment `LastName` SQL NULL on 22 spine rows and `PolicyNo` SQL
NULL on 20 spine rows. It returned field names, counts, and hashed keys only.

The canonical contract prohibits converting these required values to blank strings. Commit
`37b5a9b` therefore replaces the candidate-wide NULL abort with whole-OrderItem quarantine:

- any candidate row containing SQL NULL or literal `"NULL"` holds the complete item spine;
- held items and invalid field names are recorded in a new append-only, run-scoped hold table;
- only `_candidate_release` contributes the producer count/hash, mutable ready table, and event
  identity ledger;
- hold publication and release publication occur in the existing transaction;
- clean items remain eligible for the unchanged downstream balance gate; no delivery code,
  Scheduler, promoter, or GCS path changed.

## Evidence already run

- Production repro query: RED, exactly LastName 22 and PolicyNo 20 occurrences; job above.
- Static regression:
  - `python scripts/check_v3_unit5_required_hold_fix.py --git-ref 1f5c20c` → RED (exit 1)
  - `python scripts/check_v3_unit5_required_hold_fix.py` → PASS (exit 0)
- Zero-byte BigQuery fixture job `bqjob_r1c9d98b97be32ded_000001a043eb1b21_1` → PASS: two bad
  items held in full, one two-period clean item released, zero NULL in release.
- Authenticated safe-wrapper dry-run of DDL 058 → PASS, 0 bytes; no real DDL execution.
- `git diff --check` → clean.

## Required review questions

Apply all 12 checks in `AGENT_REVIEW_PROTOCOL.md`, and explicitly answer:

1. Does the new logic enforce Boat's whole-item quarantine rule without weakening the 56-column
   required-value contract or silently replacing required business data?
2. Are held and released item sets conserved, and can a held target event still leak into
   `v3_unit5_payload_identity`, the producer hash, delivery-ready, or archive path?
3. Are the hold ledger and release publication atomic/replay-safe under the existing run-state
   claim, including zero-held and zero-released runs?
4. Does excluding an entire item preserve complete `1..TotalPeriods` spines for every released
   item, and is the unchanged DDL 059 identity/balance conservation still satisfiable?
5. Is using field names (not values) in `invalid_fields` PII-safe and sufficient audit evidence?
6. Does the fix need an explicit notification/morning-report integration before deployment, or is
   the durable hold table sufficient for this shorter-piece delivery-disabled pilot?
7. Identify any other candidate-wide assertion in DDL 058 that should remain fail-closed versus
   become item-level; do not expand this review into an unrelated refactor.
8. Confirm rollback is exact redeployment of DDL 058 from commit `1f5c20c`/last source commit
   `6354d5b`; the new hold table may remain inert and must not be dropped or cleaned automatically.

Verdict must be `PASS`, `PASS WITH NOTES`, or `BLOCK`. A PASS authorizes neither deployment nor a
new production run; each requires separate Boat approval after Codex records the review result.

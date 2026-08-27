# Delta review: DDL 100 lifecycle CASE ordering fix

Reviewer: Claude Code
Artifact: commit `5c8d4e7`; `sql/ddl/100_v3_scenario3_archive_and_lifecycle.sql` line 476, plus new
`scripts/check_v3_lifecycle_case_order.py`
Prior BLOCK: `docs/reviews/2026-08-27-051543b-claude.md` (RQ-20260827-0916)
Verdict: **PASS**

## The one required correction

Prior BLOCK: `WHEN terminal_import_rows != 1 THEN 'PICKED_UP_PENDING_TERMINAL_IMPORT'` swallowed
the `> 1` (multiple terminal LogIDs) case before the cardinality check on the next line could ever
fire, making `'BLOCKED_IMPORT_LOG_ID_CARDINALITY'` permanently unreachable.

Fix: the branch is now `WHEN terminal_import_rows = 0 THEN 'PICKED_UP_PENDING_TERMINAL_IMPORT'`.
Tracing all three cases:
- `terminal_import_rows = 0` → matches this branch → `'PICKED_UP_PENDING_TERMINAL_IMPORT'` (correct
  — genuinely not yet imported).
- `terminal_import_rows = 1` → this branch is false, falls to
  `ARRAY_LENGTH(terminal_log_ids) != 1` → also false (one terminal row means array length 1) →
  falls through to the real reconciliation checks below, exactly as before the fix.
- `terminal_import_rows > 1` → this branch is false, falls to the cardinality check → true (array
  length > 1) → `'BLOCKED_IMPORT_LOG_ID_CARDINALITY'`. This is the case that was previously
  unreachable; it now fires correctly.

This is a single-line, minimal-diff fix with no side effects on any other branch — I checked the
surrounding branches (`duplicate_pickup_key_rows`, `successful_pickup_rows`,
`duplicate_log_id_rows`) are untouched and still precede this one in the same order.

## The added regression guard

`scripts/check_v3_lifecycle_case_order.py` statically asserts the fixed branch
(`WHEN terminal_import_rows = 0`) appears before the cardinality guard, and that no
`terminal_import_rows != 1` branch exists ahead of it. This is a reasonable lightweight guard
against the same ordering mistake recurring in a future edit, consistent with this project's
existing pattern of small static-check scripts.

## Checklist 1–12

1. **Traceability — PASS.** Exact prior BLOCK cited, exact line fixed, exact commit.
2. **Provenance — PASS.** Fixes the named defect only; does not re-litigate or re-derive anything
   already reviewed.
3. **NULL-safety — PASS.** `IFNULL(terminal_log_ids, ARRAY<STRING>[])` unchanged and still correct.
4. **Ordering — PASS.** This delta *is* an ordering fix; traced all three cases above.
5. **Column order — N/A.**
6. **Grain — N/A.** No grain change.
7. **Distribution — N/A.**
8. **Knowledge consistency — PASS.** Now correctly distinguishes the multiple-LogIDs case this
   project's own `V3_SCENARIO1_MANUAL_FALLBACK.md` step 6 requires as a distinct state.
9. **Scope — PASS.** One line changed in the view, plus one new standalone verification script;
   nothing else touched.
10. **Rollback — N/A.** Not deployed.
11. **Cost hygiene — N/A.** Pure text edit to an undeployed view definition.
12. **Honest labelling — PASS.** No claim beyond "this fixes the ordering bug."

No further round needed. Both prior BLOCK items (NULL-safety framing and knowledge-consistency) in
`docs/reviews/2026-08-27-051543b-claude.md` are resolved by this one-line change.

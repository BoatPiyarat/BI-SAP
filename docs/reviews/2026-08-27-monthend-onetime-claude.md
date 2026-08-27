# Claude Code Class-A review — reusable month-end ONETIME candidate/export query

Date: 2026-08-27

Reviewer: Claude Code (Anthropic), read-only review

Verdict: **BLOCK**

Artifact reviewed:
`sql/operator/20260827_monthend_missing_sap_onetime.sql`

Pre-transmission artifact SHA-256:
`03a9111dd0b90c92d08f41773b5ae7fdefd515ea90a3807725aee22ec78d010d`

Claude reported that it could not independently calculate the hash with its read-only tool set;
therefore the reviewer verified the supplied path and content, while Codex recorded the hash before
transmission. The user explicitly approved sending the artifact and the five named reference files.
No BigQuery query, deployment, GCS write, Workflow execution, procedure call, repository mutation,
or SAP action was part of the review.

## Standards and safety findings

1. **Terminal-state classification is unsafe.** The query treats `PICKED_UP` as terminal in its
   archive exclusion. The canonical Unit 2 classifier treats a delivery without terminal SAP result
   as `PENDING_ACK`; the July baseline excludes only `DELIVERED` and `ACKNOWLEDGED`. The current rule
   can hide rows still missing terminal SAP acknowledgement. This is the primary blocker.
2. **The export contract is implicit.** The final payload uses `SELECT c.*`, contrary to the
   canonical rule requiring an explicit 56-column positional export contract and a column/order
   assertion.
3. **The final filtered output lacks complete invariant checks.** Policy-number length, required
   Paid fields, dates, and population conservation are checked in intermediate tables but are not
   re-asserted over the actual output population.
4. **Held rows are not durable.** Hold reasons exist only in temporary tables and do not satisfy the
   `EXCLUDED != DELETED` expectation represented by `sap_excluded_records` in the reference design.
5. **The two-result-set workflow has a time-of-check/time-of-use gap.** Re-running the live query to
   produce CSV can yield a different population than the operator reviewed. There is no immutable
   run identity or snapshot.
6. **The operator instructions omit the mandatory safe-query wrapper and cost ceiling.**
7. **The month boundary uses UTC rather than ICT.** `DATE(pe.charge_time)` must classify timestamps
   with `Asia/Bangkok` for the stated ICT calendar-month specification.
8. The payload-source deduplication is deterministic.
9. No duplicate-charge fanout was found because `expected_state` already collapses to the first
   successful charge.

## Specification findings

1. The `PICKED_UP` rule can hide records absent from terminal SAP acknowledgement.
2. The query has no explicit source-flow versus declared-flow consistency check and relies on the
   payload view to imply ONETIME/CREATE scope.
3. Intermediate population conservation is present and valid.
4. Change-order separation and the three July validation categories are preserved.
5. The claim that the output is ready for manual export is stronger than the implemented controls
   because holds are not durable and the reviewed population is not immutable.

## Required disposition

Do not use this source for a real SAP upload. Correct the terminal classifier and ICT boundary, make
the 56-column contract and final invariants explicit, add flow consistency, and resolve durable hold
plus immutable-snapshot/TOCTOU requirements. Submit the exact corrected bytes for a fresh independent
Class-A review. A future source PASS would still not authorize execution or export.

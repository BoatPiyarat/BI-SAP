# Review — RQ-20260804-1245-contiguous-period-spines (delta)

Reviewer: Claude Code
Artifact: commit `d0eff7e`; deltas in `sql/ddl/058_v3_unit5_newpayment_shadow.sql`,
`sql/ddl/059_v3_unit5_balance_hold.sql`, `sql/ddl/069_v3_manual_newpayment_archive.sql`, and
`sql/adhoc/20260804_period_spine_range_fixture.sql`.
Answers: shared hardening note in `docs/reviews/2026-08-04-62fa5e0-claude.md`.
Verdict: **PASS — note resolved**

## What changed

All three files' spine `HAVING` clause changes from `period_n != total_n` to
`total_value_n!=1 OR first_period!=1 OR last_period!=total_n OR period_n!=total_n`, adding
`MIN(Period)`, `MAX(Period)`, and `COUNT(DISTINCT TotalPeriods)`.

## Verification — this is now a rigorous contiguity proof, not just cardinality

Worked through the math directly rather than trusting the fixture alone: given `period_n` distinct
integers with `first_period=1` and `last_period=total_n`, the range spanned is exactly
`total_n - 1 + 1 = total_n` values; if the count of distinct values present (`period_n`) also equals
`total_n`, then by pigeonhole `period_n` distinct integers fill the entire `[1, total_n]` range with
no gap and no value outside it. That's a genuine proof of contiguity, not the cardinality-only check
flagged in the original note. Traced this against three cases by hand:
- `{1,2,4}`, `total_n=3` (the exact case named in the prior note): `period_n=3=total_n`,
  `first_period=1`, but `last_period=4≠3` — now correctly flagged. The old check missed this.
- `{2,3}`, `total_n=2` (missing period 1, an extra period 3): `period_n=2=total_n`, but
  `first_period=2≠1` — also now correctly flagged (the old check would have missed this too, not
  just the originally-named case).
- `{1,2,3}`, `total_n=3`: all four conditions pass, correctly not flagged.

The added `total_value_n!=1` check is a bonus not asked for but reasonable: it rejects an `OrderItem`
whose rows disagree on their own `TotalPeriods` value, a data-consistency issue independent of the
spine question.

## Fixture

Re-derived all three fixture cases against the exact `HAVING` expression and confirm agreement,
including `gap_with_same_cardinality` (the `{1,2,4}`/total-3 case named explicitly, by name, in the
fixture) and the new `inconsistent_total` case. Fixture is literal-only (`UNNEST`/`STRUCT`
construction), matching its own "no production tables are read or written" header.

## Consistency across the three files

Confirmed identical `HAVING` expression text applied verbatim in `058`, `059`, and `069` — no
file-specific drift in the fix, matching the "shared hardening note" framing of the original review.

Delta verified against the specific note it answers; note resolved.

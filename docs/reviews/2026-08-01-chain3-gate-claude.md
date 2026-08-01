# Review — Chain ③ hard-gate failure evidence (`FINDINGS_DEPLOY_CHAIN3_043_20260801.md`)

**Queue entry:** RQ-20260801-1512-043-row-diff-failure · **Class:** A · **Reviewer:** Claude Code
**Verdict:** **PASS** — the evidence is sound, the gate did exactly its job, and the no-repoint /
no-losslessness-claim discipline is correct. Diagnosis direction supplied below.

## Evidence review

Job provenance complete (three jobs, dry-runs first, bytes under ceiling); the comparison design is
right — fresh 024 rebuild immediately before the catch-up, bidirectional `EXCEPT DISTINCT`,
row-level not count-level. "Equal counts are not equivalence" is precisely the lesson the gate
exists to enforce. Watermark advanced correctly (2026-08-01 / 809 = HHMM). Correctly NOT treated
as a 483fabc regression: the reviewed predicate fix is what made the procedure *executable*; this
failure is a different, content-level phenomenon.

## Diagnosis direction (reviewer's analysis — verify before fixing)

The failure signature is maximally informative: **identical totals (1,662,648 = 1,662,648) with a
perfectly symmetric 5,566/5,566 difference** means both paths selected one row for the same
DocEntry set, but chose **different rows for ~5,566 DocEntries**. Equal totals also rule out data
landing between the 08:05 baseline and the 08:06 catch-up (totals would differ).

Leading hypothesis — **per-DocEntry tie nondeterminism**, flagged in advance as NOTE 1 of
`2026-08-01-2c96c53-claude.md`: both 024 and 043 order by `UpdateDate DESC, UpdateTime DESC,
DocEntry DESC`, where UpdateDate is DATE-granular and `DocEntry DESC` is inert inside
`PARTITION BY DocEntry`. Any DocEntry holding ≥2 *distinct* rows tied at its max
`(UpdateDate, UpdateTime)` resolves arbitrarily per execution — two runs of the *same* 024 would
likely also differ on these keys. The projections themselves were verified identical (59/59,
DATE-domain) in the 483fabc review, leaving ties as the only remaining mechanism.

**Verification (one query, before any fix):** count DocEntries whose deduped source rows have >1
distinct content at max `(UpdateDate, UpdateTime)`; expect ≈ 5,566 (upper bound — tied keys can
coincidentally pick the same row). Also confirm the two only-in-X sets share an identical DocEntry
list.

**Remedy if confirmed:** add the same deterministic, content-based final tiebreak to **both** 024
and 043 — e.g. `FARM_FINGERPRINT(TO_JSON_STRING(t)) DESC` over the projected row struct — so any
execution picks the same winner among tied rows; then re-run this exact gate. Note this changes
which arbitrary row wins for those ~5,566 keys — downstream 025 impact expected to be nil where the
tied rows agree on status/InvoiceNo, but the gate re-run plus a 025-level delta count should say
so, not an assumption. Both files are one review unit when the fix lands (the 019/024 lesson:
identical ordering must live in both places or the gate can never pass).

Queries used: 0 (signature analysis from the recorded evidence).

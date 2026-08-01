# Review — aba1aad (RULE-09 old-year rescue in live-source 037)

**Queue entry:** RQ-20260731-2243-rule09-old-year-rescue · **Class:** A · **Reviewer:** Claude Code
**Verdict:** **PASS WITH NOTES**

## Checked

- **Both gates verified from the diff, mechanically consistent**: (1) `OLD_YEAR_NO_TOUCH` register
  INSERT now excludes rows in the rescue window; (2) population WHERE admits
  `basis_year > year_no_touch_max OR old_year_rescued`. A rescued row is therefore absent from the
  register and present in `expected_state` with `old_year_rescued=TRUE` — exactly the claim.
- **RULE-08 holds**: `raw_payment_date` exists only in `_enriched`/`_rules` temp tables; the final
  `expected_state` SELECT list does not include it. Only the BOOL markers persist.
- **Window is the open calendar month** (`[open_period_start, +1 MONTH)`), not `lock_datetime` — per claim.
- **Coherent with RULE-01**: rescued rows have `raw >= open_period_start`, so the GREATEST clamp is
  a no-op and `payment_date_clamped=FALSE` — no double-transformation.
- 034 untouched (README marks it historical). Honest evidence: standalone 037 dry-run failed closed
  because 044 isn't live — reported, not hidden; combined 044→037 dry-run passed.

## NOTE 1 — the period-lock guard (Boat: highest residual risk; full spec, hand to Codex)

`lock_datetime` is **never read** in 037 (verified: grep shows only `open_period_start` uses).
`DECLARE open_period_start = (SELECT MAX(open_period_start) FROM sap_period_lock)` fails two ways:
1. A mistyped/future-dated row instantly clamps **every** PaymentDate forward *and* shifts the
   RULE-09 rescue window — both silently.
2. Sequencing: the moment an August row (`2026-08-01`) is inserted, `MAX()` switches — if that
   happens before July's close finishes (03/08 14:00), July's final sends clamp to `01082026`.

Required guard (uses the schema as designed):
```sql
DECLARE open_period_start DATE DEFAULT (
  SELECT open_period_start FROM `...sap_period_lock`
  WHERE lock_datetime > CURRENT_TIMESTAMP()
  ORDER BY open_period_start LIMIT 1);
ASSERT open_period_start IS NOT NULL AS '...no unlocked period...';
ASSERT open_period_start <= CURRENT_DATE('Asia/Bangkok') AS '...future period row...';
```
(earliest not-yet-locked period = the open one; a prematurely inserted August row then cannot win
while July's `lock_datetime` is still in the future.)

## NOTE 2 — duplicated predicate

The register INSERT re-derives the rescue window inline instead of `AND NOT old_year_rescued`
(equivalent today because `basis_year <= year_no_touch_max` is already asserted in that WHERE, but
two copies of the window logic can drift apart; collapse to the marker).

Queries used: 0.

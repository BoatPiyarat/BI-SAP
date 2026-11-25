# Sanity checks before reporting a number

1. **Grain check** — `COUNT(*) = COUNT(DISTINCT key)` at the grain you claim. A mismatch means a
   join duplicated rows.
2. **NULL check** — `COUNT(DISTINCT x)` ignores NULLs. Report how many rows had NULL in the date or
   key you filtered on (e.g. items with no approval date yet).
3. **Total check** — compare your total with a simple single-table total for the same period
   (e.g. P1 in `query_patterns.sql`). If your fancy query is bigger, you fanned out.
4. **Cancelled check** — state whether cancelled items are in or out, and how many there were.
5. **Unit check** — CarePay amounts are satang (÷100). Report-table amounts are baht.
6. **Time-zone check** — CareOS order/item timestamps are already Bangkok time (`DATE(ts)`); CarePay timestamps are UTC (`DATE(ts, 'Asia/Bangkok')`).
7. **Impossible-number check** — 100%, perfectly round, or a jump > 2× vs last period → assume the
   query is wrong; investigate before reporting.
8. **Freshness check** — run P9; today's numbers are partial and dashboards may refresh at different times than report tables. Say "ข้อมูลถึง
   ณ วันที่ …".

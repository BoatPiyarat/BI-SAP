"""
Boat's ask: hold input constant (PaymentChannel + whether Expected==Actual) and see whether the
JE outcome (account) for that SAME input shape changed between before-Jul-2025 and Jul-2025-on.
If the account-selection rule is stable per input shape across both periods, the interface/input
must have changed (more/fewer records of a given shape). If the SAME input shape maps to a
different account before vs after, the posting behavior itself changed on stable input.
Full population (not just 5-sample), company customers (blank U_Title) only. SELECT only.
"""
import os
import csv
import pyodbc
from collections import defaultdict

USER = os.environ["RCB_DB_USER"]
PASSWORD = os.environ["RCB_DB_PASSWORD"]
conn_str = f"DRIVER={{SQL Server}};SERVER=172.25.25.3,1433;DATABASE=RCB_LIVE_DB;UID={USER};PWD={PASSWORD};"
conn = pyodbc.connect(conn_str, timeout=120)
cur = conn.cursor()

cur.execute("""
    SELECT
      FORMAT(o.RefDate, 'yyyy-MM') AS ym,
      i.U_PaymentChannel,
      i.U_ExpectedReceived,
      i.U_ActualReceived,
      j.Account
    FROM JDT1 j
    JOIN OJDT o ON o.TransId = j.TransId
    JOIN [dbo].[@INSURANCE] i
      ON i.U_OrderItem = LEFT(j.LineMemo, CASE WHEN CHARINDEX('_', j.LineMemo) = 0 THEN LEN(j.LineMemo) ELSE CHARINDEX('_', j.LineMemo) - 1 END)
    WHERE j.Account IN ('1134-01','1135-01') AND j.Debit > 0
      AND j.LineMemo LIKE '%-V[0-9]%'
      AND o.RefDate >= '2025-05-01' AND o.RefDate < '2026-09-01'
      AND (i.U_Title = '' OR i.U_Title IS NULL)
""")
rows = cur.fetchall()
print(f"total rows: {len(rows)}")

# bucket by (period, channel, match) -> {account: count}
buckets = defaultdict(lambda: defaultdict(int))
for ym, channel, exp, act, acct in rows:
    channel = channel or "(NULL)"
    period = "before_2025-07" if ym < "2025-07" else "2025-07_onward"
    match = "EXACT" if exp is not None and act is not None and abs(float(exp) - float(act)) < 0.02 else "GAP"
    key = (period, channel, match)
    buckets[key][acct] += 1

print(f"\n{'period':16s} {'channel':30s} {'match':6s} {'1134-01':>8s} {'1135-01':>8s} {'rate_1134':>10s}")
for key in sorted(buckets.keys()):
    period, channel, match = key
    d = buckets[key]
    w = d.get('1134-01', 0)
    c = d.get('1135-01', 0)
    total = w + c
    if total < 5:
        continue
    rate = f"{w/total*100:.1f}%"
    print(f"{period:16s} {str(channel)[:30]:30s} {match:6s} {w:8d} {c:8d} {rate:>10s}")

out_path = r"C:\Users\Developer\OneDrive - Rabbit Internet\Documents\03 Project - Partner\02 SAP\Phase1.1\agentic_bootstrap\tmp_controlled_comparison_raw.csv"
with open(out_path, "w", newline="", encoding="utf-8-sig") as f:
    w = csv.writer(f)
    w.writerow(["ym", "PaymentChannel", "ExpectedReceived", "ActualReceived", "Account"])
    for row in rows:
        w.writerow(list(row))
print(f"\nraw rows written to {out_path}")

cur.close()
conn.close()

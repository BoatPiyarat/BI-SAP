"""
GOAL: investigate until 100% confident, scoped to August 2026 company customers only.
Properly classify every order-item's JE shape (not a crude threshold) by pulling every JE line
that touches 1134-01, 1135-01, or 2142-10 for each order-item, then bucket by exact structural
signature. SELECT only.
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
      LEFT(j.LineMemo, CHARINDEX('_', j.LineMemo) - 1) AS oi,
      o.TransId,
      o.RefDate,
      j.Account,
      j.Debit,
      j.Credit
    FROM JDT1 j
    JOIN OJDT o ON o.TransId = j.TransId
    JOIN [dbo].[@INSURANCE] i
      ON i.U_OrderItem = LEFT(j.LineMemo, CASE WHEN CHARINDEX('_', j.LineMemo) = 0 THEN LEN(j.LineMemo) ELSE CHARINDEX('_', j.LineMemo) - 1 END)
    WHERE j.LineMemo LIKE '%-V[0-9]%' AND CHARINDEX('_', j.LineMemo) > 0
      AND j.Account IN ('1134-01', '1135-01', '2142-10')
      AND o.RefDate >= '2026-08-01' AND o.RefDate < '2026-08-22'
      AND (i.U_Title = '' OR i.U_Title IS NULL)
    ORDER BY oi, o.TransId
""")
rows = cur.fetchall()
print(f"total lines: {len(rows)}")

per_order = defaultdict(lambda: {"1134-01": [0, 0], "1135-01": [0, 0], "2142-10": [0, 0]})
for oi, transid, refdate, acct, debit, credit in rows:
    per_order[(oi, transid)][acct][0] += float(debit)
    per_order[(oi, transid)][acct][1] += float(credit)

buckets = defaultdict(list)
for (oi, transid), accts in per_order.items():
    net_1134 = accts["1134-01"][0] - accts["1134-01"][1]
    net_1135 = accts["1135-01"][0] - accts["1135-01"][1]
    net_2142 = accts["2142-10"][0] - accts["2142-10"][1]
    has_1135 = net_1135 > 0
    has_1134 = abs(net_1134) > 0.01
    has_2142 = abs(net_2142) > 0.01

    if not has_1134:
        sig = "clean_1135_only" if has_1135 else "no_1134_no_1135(other-acct-only)"
    elif has_1134 and not has_1135:
        sig = "TYPE_A_full_misposting"
    elif has_1134 and has_1135 and has_2142 and abs(net_1134 - net_2142) < 0.02:
        sig = "TYPE_B_wht_residual_dup"
    elif has_1134 and has_1135:
        sig = "TYPE_D_both_no_2142_match"
    else:
        sig = "unclassified"
    buckets[sig].append((oi, transid, net_1134, net_1135, net_2142))

print(f"\n{'signature':35s} {'count':>6s}")
for sig, items in sorted(buckets.items(), key=lambda x: -len(x[1])):
    print(f"{sig:35s} {len(items):6d}")

for sig in ["TYPE_A_full_misposting", "TYPE_D_both_no_2142_match", "unclassified"]:
    print(f"\n=== sample of {sig} ===")
    for item in buckets[sig][:8]:
        print(item)

out_path = r"C:\Users\Developer\OneDrive - Rabbit Internet\Documents\03 Project - Partner\02 SAP\Phase1.1\agentic_bootstrap\tmp_august_company_classified.csv"
with open(out_path, "w", newline="", encoding="utf-8-sig") as f:
    w = csv.writer(f)
    w.writerow(["signature", "OrderItem", "TransId", "net_1134", "net_1135", "net_2142"])
    for sig, items in buckets.items():
        for oi, transid, n1134, n1135, n2142 in items:
            w.writerow([sig, oi, transid, n1134, n1135, n2142])
print(f"\nwritten to {out_path}")

cur.close()
conn.close()

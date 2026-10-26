"""
CORRECTED methodology: compute the NET (debit - credit) impact on 1134-01 per order, and whether
1135-01 ALSO carries the full/bulk amount, to correctly separate:
  A) TRUE full misposting: net 1134-01 > 0 substantial, no 1135-01 line at all for that order.
  B) WHT-residual duplicate: net 1134-01 > 0 but small (WHT-sized), AND a full 1135-01 line exists.
  C) Self-offsetting: net 1134-01 == 0.
Run for company customers (blank U_Title), 2025-05 to 2026-08, per month. SELECT only.
"""
import os
import pyodbc
from collections import defaultdict

USER = os.environ["RCB_DB_USER"]
PASSWORD = os.environ["RCB_DB_PASSWORD"]
conn_str = f"DRIVER={{SQL Server}};SERVER=172.25.25.3,1433;DATABASE=RCB_LIVE_DB;UID={USER};PWD={PASSWORD};"
conn = pyodbc.connect(conn_str, timeout=120)
cur = conn.cursor()

cur.execute("""
    WITH orderitem_lines AS (
      SELECT
        LEFT(j.LineMemo, CHARINDEX('_', j.LineMemo) - 1) AS oi,
        o.TransId,
        FORMAT(o.RefDate, 'yyyy-MM') AS ym,
        SUM(CASE WHEN j.Account = '1134-01' THEN j.Debit - j.Credit ELSE 0 END) AS net_1134,
        SUM(CASE WHEN j.Account = '1135-01' THEN j.Debit - j.Credit ELSE 0 END) AS net_1135,
        MAX(CASE WHEN j.Account = '1135-01' AND j.Debit > 0 THEN 1 ELSE 0 END) AS has_1135_line
      FROM JDT1 j
      JOIN OJDT o ON o.TransId = j.TransId
      JOIN [dbo].[@INSURANCE] i
        ON i.U_OrderItem = LEFT(j.LineMemo, CASE WHEN CHARINDEX('_', j.LineMemo) = 0 THEN LEN(j.LineMemo) ELSE CHARINDEX('_', j.LineMemo) - 1 END)
      WHERE j.LineMemo LIKE '%-V[0-9]%' AND CHARINDEX('_', j.LineMemo) > 0
        AND o.RefDate >= '2025-05-01' AND o.RefDate < '2026-09-01'
        AND (i.U_Title = '' OR i.U_Title IS NULL)
      GROUP BY LEFT(j.LineMemo, CHARINDEX('_', j.LineMemo) - 1), o.TransId, FORMAT(o.RefDate, 'yyyy-MM')
    )
    SELECT ym, oi, net_1134, net_1135, has_1135_line
    FROM orderitem_lines
    WHERE net_1134 <> 0
""")
rows = cur.fetchall()
print(f"total order-lines with nonzero net 1134-01: {len(rows)}")

by_month = defaultdict(lambda: {"true_misposting": 0, "wht_residual_dup": 0, "other": 0})
for ym, oi, net_1134, net_1135, has_1135 in rows:
    net_1134 = float(net_1134)
    if has_1135 == 1 and net_1134 < 2000:
        by_month[ym]["wht_residual_dup"] += 1
    elif has_1135 == 0 and net_1134 > 2000:
        by_month[ym]["true_misposting"] += 1
    else:
        by_month[ym]["other"] += 1

print(f"\n{'month':10s} {'true_misposting':>16s} {'wht_residual_dup':>18s} {'other':>8s}")
for ym in sorted(by_month.keys()):
    d = by_month[ym]
    print(f"{ym:10s} {d['true_misposting']:16d} {d['wht_residual_dup']:18d} {d['other']:8d}")

cur.close()
conn.close()

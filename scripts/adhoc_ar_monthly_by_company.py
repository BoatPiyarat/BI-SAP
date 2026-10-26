"""
Split the monthly V-item misposting rate by company (blank U_Title) vs individual customer,
2025-05 to 2026-08, to see whether the July-2025 onset is a rate change or a volume change.
SELECT only.
"""
import os
import pyodbc

USER = os.environ["RCB_DB_USER"]
PASSWORD = os.environ["RCB_DB_PASSWORD"]
conn_str = f"DRIVER={{SQL Server}};SERVER=172.25.25.3,1433;DATABASE=RCB_LIVE_DB;UID={USER};PWD={PASSWORD};"
conn = pyodbc.connect(conn_str, timeout=60)
cur = conn.cursor()

cur.execute("""
    SELECT
      FORMAT(o.RefDate, 'yyyy-MM') AS ym,
      CASE WHEN i.U_Title = '' OR i.U_Title IS NULL THEN 'company' ELSE 'individual' END AS cust_type,
      j.Account,
      COUNT(*) AS n
    FROM JDT1 j
    JOIN OJDT o ON o.TransId = j.TransId
    JOIN [dbo].[@INSURANCE] i
      ON i.U_OrderItem = LEFT(j.LineMemo, CASE WHEN CHARINDEX('_', j.LineMemo) = 0 THEN LEN(j.LineMemo) ELSE CHARINDEX('_', j.LineMemo) - 1 END)
    WHERE j.Account IN ('1134-01','1135-01') AND j.Debit > 0
      AND j.LineMemo LIKE '%-V[0-9]%'
      AND o.RefDate >= '2025-05-01' AND o.RefDate < '2026-09-01'
    GROUP BY FORMAT(o.RefDate, 'yyyy-MM'),
      CASE WHEN i.U_Title = '' OR i.U_Title IS NULL THEN 'company' ELSE 'individual' END,
      j.Account
    ORDER BY ym, cust_type, j.Account
""")
rows = cur.fetchall()
data = {}
for ym, ctype, acc, n in rows:
    data.setdefault((ym, ctype), {})[acc] = n

print(f"{'month':10s} {'type':10s} {'wrong':>8s} {'correct':>8s} {'rate':>8s}")
for (ym, ctype) in sorted(data.keys()):
    d = data[(ym, ctype)]
    w = d.get('1134-01', 0)
    c = d.get('1135-01', 0)
    total = w + c
    rate = f"{w/total*100:.1f}%" if total else "n/a"
    print(f"{ym:10s} {ctype:10s} {w:8d} {c:8d} {rate:>8s}")

cur.close()
conn.close()

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
      j.Account,
      COUNT(*) AS n
    FROM JDT1 j
    JOIN OJDT o ON o.TransId = j.TransId
    WHERE j.Account IN ('1134-01','1135-01') AND j.Debit > 0
      AND j.LineMemo LIKE '%-V[0-9]%'
    GROUP BY FORMAT(o.RefDate, 'yyyy-MM'), j.Account
    ORDER BY ym, j.Account
""")
rows = cur.fetchall()
by_month = {}
for ym, acc, n in rows:
    by_month.setdefault(ym, {})[acc] = n

print(f"{'month':10s} {'1134-01':>10s} {'1135-01':>10s} {'rate_wrong':>12s}")
for ym in sorted(by_month.keys()):
    d = by_month[ym]
    w = d.get('1134-01', 0)
    c = d.get('1135-01', 0)
    total = w + c
    rate = f"{w/total*100:.1f}%" if total else "n/a"
    print(f"{ym:10s} {w:10d} {c:10d} {rate:>12s}")

cur.close()
conn.close()

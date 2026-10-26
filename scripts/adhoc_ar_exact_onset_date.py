"""
Narrow the onset to an exact date (day-level) around the 2025-07 boundary, and check whether
August 2026 specifically stands out in dollar terms (which might explain why the issue surfaced
now rather than earlier). SELECT only.
"""
import os
import pyodbc

USER = os.environ["RCB_DB_USER"]
PASSWORD = os.environ["RCB_DB_PASSWORD"]
conn_str = f"DRIVER={{SQL Server}};SERVER=172.25.25.3,1433;DATABASE=RCB_LIVE_DB;UID={USER};PWD={PASSWORD};"
conn = pyodbc.connect(conn_str, timeout=60)
cur = conn.cursor()

print("=== day-level rate around the 2025-06-20..2025-07-10 boundary (all V-items, not just company) ===")
cur.execute("""
    SELECT
      o.RefDate,
      j.Account,
      COUNT(*) AS n
    FROM JDT1 j
    JOIN OJDT o ON o.TransId = j.TransId
    WHERE j.Account IN ('1134-01','1135-01') AND j.Debit > 0
      AND j.LineMemo LIKE '%-V[0-9]%'
      AND o.RefDate >= '2025-06-15' AND o.RefDate < '2025-07-15'
    GROUP BY o.RefDate, j.Account
    ORDER BY o.RefDate, j.Account
""")
for row in cur.fetchall():
    print(row)

print("\n=== monthly WRONG dollar amount (1134-01 debit sum) vs CORRECT dollar amount, all V-items, full range ===")
cur.execute("""
    SELECT
      FORMAT(o.RefDate, 'yyyy-MM') AS ym,
      j.Account,
      SUM(j.Debit) AS total_debit,
      COUNT(*) AS n
    FROM JDT1 j
    JOIN OJDT o ON o.TransId = j.TransId
    WHERE j.Account IN ('1134-01','1135-01') AND j.Debit > 0
      AND j.LineMemo LIKE '%-V[0-9]%'
      AND o.RefDate >= '2025-01-01' AND o.RefDate < '2026-09-01'
    GROUP BY FORMAT(o.RefDate, 'yyyy-MM'), j.Account
    ORDER BY ym, j.Account
""")
for row in cur.fetchall():
    print(row)

cur.close()
conn.close()

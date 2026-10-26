"""
Boat wants fresh examples of the WHT-duplication pattern (1134-01 + 2142-10 paired, same amount)
that are NOT from the V2/M2 reinterfaced backfill batch - i.e., ordinary, still-current orders
showing this is an ongoing, systemic issue. SELECT only.
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
      LEFT(j.LineMemo, CHARINDEX('_', j.LineMemo) - 1) AS item,
      MAX(o.RefDate) AS RefDate,
      SUM(CASE WHEN j.Account = '1135-01' THEN j.Debit ELSE 0 END) AS bulk_1135,
      SUM(CASE WHEN j.Account = '1134-01' THEN j.Debit - j.Credit ELSE 0 END) AS net_1134,
      SUM(CASE WHEN j.Account = '2142-10' THEN j.Debit ELSE 0 END) AS wht_2142
    FROM JDT1 j
    JOIN OJDT o ON o.TransId = j.TransId
    WHERE j.LineMemo LIKE '%-V[0-9]%' AND CHARINDEX('_', j.LineMemo) > 0
      AND j.Account IN ('1134-01','1135-01','2142-10')
      AND o.RefDate >= '2026-08-20' AND o.RefDate < '2026-08-27'
      AND LEFT(j.LineMemo, CHARINDEX('_', j.LineMemo) - 1) NOT LIKE '%-V2'
      AND LEFT(j.LineMemo, CHARINDEX('_', j.LineMemo) - 1) NOT LIKE '%-M2'
    GROUP BY LEFT(j.LineMemo, CHARINDEX('_', j.LineMemo) - 1)
    HAVING SUM(CASE WHEN j.Account = '1135-01' THEN j.Debit ELSE 0 END) > 0
       AND SUM(CASE WHEN j.Account = '2142-10' THEN j.Debit ELSE 0 END) > 0
       AND SUM(CASE WHEN j.Account = '1134-01' THEN j.Debit - j.Credit ELSE 0 END) > 0
    ORDER BY RefDate DESC
""")
rows = cur.fetchall()
print(f"found: {len(rows)}")
for r in rows[:10]:
    print(r)

cur.close()
conn.close()

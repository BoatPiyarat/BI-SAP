"""
User wants a historical example where WHT posted correctly: 2142-10 nonzero, but 1134-01 does
NOT pick up any residual (net zero or absent entirely) - the "clean" WHT posting pattern.
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
      LEFT(j.LineMemo, CHARINDEX('_', j.LineMemo) - 1) AS item,
      MAX(o.RefDate) AS RefDate,
      SUM(CASE WHEN j.Account = '2142-10' THEN j.Debit ELSE 0 END) AS wht_2142,
      SUM(CASE WHEN j.Account = '1134-01' THEN j.Debit - j.Credit ELSE 0 END) AS net_1134,
      SUM(CASE WHEN j.Account = '1135-01' THEN j.Debit ELSE 0 END) AS bulk_1135
    FROM JDT1 j
    JOIN OJDT o ON o.TransId = j.TransId
    WHERE j.LineMemo LIKE '%-V[0-9]%' AND CHARINDEX('_', j.LineMemo) > 0
      AND j.Account IN ('1134-01','1135-01','2142-10')
    GROUP BY LEFT(j.LineMemo, CHARINDEX('_', j.LineMemo) - 1)
    HAVING SUM(CASE WHEN j.Account = '2142-10' THEN j.Debit ELSE 0 END) > 0
       AND SUM(CASE WHEN j.Account = '1134-01' THEN j.Debit - j.Credit ELSE 0 END) = 0
       AND SUM(CASE WHEN j.Account = '1135-01' THEN j.Debit ELSE 0 END) > 0
    ORDER BY RefDate ASC
""")
rows = cur.fetchall()
print(f"clean WHT examples found (2142-10>0, net 1134-01=0, 1135-01>0): {len(rows)}")
for r in rows[:10]:
    print("EARLIEST:", r)
for r in rows[-10:]:
    print("LATEST:", r)

cur.close()
conn.close()

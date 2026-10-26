"""
Boat's hypothesis: is the WHT-driven misposting specific to company (juristic) customers, not
individuals? Check U_Title/U_FirstName in @INSURANCE for a sample of known-misposted V items vs
correctly-posted ones. SELECT only.
"""
import os
import pyodbc

USER = os.environ["RCB_DB_USER"]
PASSWORD = os.environ["RCB_DB_PASSWORD"]
conn_str = f"DRIVER={{SQL Server}};SERVER=172.25.25.3,1433;DATABASE=RCB_LIVE_DB;UID={USER};PWD={PASSWORD};"
conn = pyodbc.connect(conn_str, timeout=30)
cur = conn.cursor()

cur.execute("""
    SELECT
      j.Account,
      i.U_Title,
      COUNT(*) AS n
    FROM JDT1 j
    JOIN OJDT o ON o.TransId = j.TransId
    JOIN [dbo].[@INSURANCE] i
      ON i.U_OrderItem = LEFT(j.LineMemo, CASE WHEN CHARINDEX('_', j.LineMemo) = 0 THEN LEN(j.LineMemo) ELSE CHARINDEX('_', j.LineMemo) - 1 END)
    WHERE j.Account IN ('1134-01','1135-01') AND j.Debit > 0
      AND j.LineMemo LIKE '%-V[0-9]%'
      AND o.RefDate >= '2025-05-01' AND o.RefDate < '2026-09-01'
    GROUP BY j.Account, i.U_Title
    ORDER BY j.Account, n DESC
""")
print("=== Account x U_Title, 2025-05..2026-08 ===")
for row in cur.fetchall():
    print(row)

cur.close()
conn.close()

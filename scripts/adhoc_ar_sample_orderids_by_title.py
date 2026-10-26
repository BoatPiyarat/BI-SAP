import os
import pyodbc

USER = os.environ["RCB_DB_USER"]
PASSWORD = os.environ["RCB_DB_PASSWORD"]
conn_str = f"DRIVER={{SQL Server}};SERVER=172.25.25.3,1433;DATABASE=RCB_LIVE_DB;UID={USER};PWD={PASSWORD};"
conn = pyodbc.connect(conn_str, timeout=30)
cur = conn.cursor()

cur.execute("""
    SELECT DISTINCT TOP 30 i.U_OrderId
    FROM JDT1 j
    JOIN OJDT o ON o.TransId = j.TransId
    JOIN [dbo].[@INSURANCE] i
      ON i.U_OrderItem = LEFT(j.LineMemo, CASE WHEN CHARINDEX('_', j.LineMemo) = 0 THEN LEN(j.LineMemo) ELSE CHARINDEX('_', j.LineMemo) - 1 END)
    WHERE j.Account = '1134-01' AND j.Debit > 0
      AND j.LineMemo LIKE '%-V[0-9]%'
      AND o.RefDate >= '2025-05-01' AND o.RefDate < '2026-09-01'
      AND (i.U_Title = '' OR i.U_Title IS NULL)
""")
blank_title_ids = [r[0] for r in cur.fetchall()]
print("blank-title 1134-01 OrderIDs:", blank_title_ids)

cur.execute("""
    SELECT DISTINCT TOP 30 i.U_OrderId
    FROM JDT1 j
    JOIN OJDT o ON o.TransId = j.TransId
    JOIN [dbo].[@INSURANCE] i
      ON i.U_OrderItem = LEFT(j.LineMemo, CASE WHEN CHARINDEX('_', j.LineMemo) = 0 THEN LEN(j.LineMemo) ELSE CHARINDEX('_', j.LineMemo) - 1 END)
    WHERE j.Account = '1134-01' AND j.Debit > 0
      AND j.LineMemo LIKE '%-V[0-9]%'
      AND o.RefDate >= '2025-05-01' AND o.RefDate < '2026-09-01'
      AND i.U_Title IN (N'นาย', N'นางสาว', N'นาง', N'คุณ')
""")
individual_title_ids = [r[0] for r in cur.fetchall()]
print("individual-title 1134-01 OrderIDs:", individual_title_ids)

cur.close()
conn.close()

import os
import pyodbc

USER = os.environ["RCB_DB_USER"]
PASSWORD = os.environ["RCB_DB_PASSWORD"]
conn_str = f"DRIVER={{SQL Server}};SERVER=172.25.25.3,1433;DATABASE=RCB_LIVE_DB;UID={USER};PWD={PASSWORD};"
conn = pyodbc.connect(conn_str, timeout=30)
cur = conn.cursor()

cur.execute("""
    SELECT TOP 5 i.U_OrderItem, i.U_OrderId, i.U_PaymentChannel, i.U_ExpectedReceived,
           i.U_ActualReceived, i.U_TotalAmount, i.U_Discount, i.U_BatchRunDate
    FROM JDT1 j
    JOIN OJDT o ON o.TransId = j.TransId
    JOIN [dbo].[@INSURANCE] i
      ON i.U_OrderItem = LEFT(j.LineMemo, CASE WHEN CHARINDEX('_', j.LineMemo) = 0 THEN LEN(j.LineMemo) ELSE CHARINDEX('_', j.LineMemo) - 1 END)
    WHERE j.Account = '1135-01' AND j.Debit > 0
      AND j.LineMemo LIKE '%-V[0-9]%'
      AND i.U_PaymentChannel = 'RCB-EDC-KBANK'
      AND o.RefDate >= '2026-08-01' AND o.RefDate < '2026-08-22'
      AND (i.U_Title = '' OR i.U_Title IS NULL)
    ORDER BY o.RefDate DESC
""")
rows = cur.fetchall()
for row in rows:
    print(row)

if rows:
    oi = rows[0].U_OrderItem
    print(f"\n=== full JE for {oi} ===")
    cur.execute("""
        SELECT j.Account, a.AcctName, j.Debit, j.Credit
        FROM JDT1 j LEFT JOIN OACT a ON a.AcctCode = j.Account
        WHERE j.LineMemo LIKE ?
        ORDER BY j.Line_ID
    """, f"{oi}_%")
    for row in cur.fetchall():
        print(row)

cur.close()
conn.close()

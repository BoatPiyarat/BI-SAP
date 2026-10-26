import os
import pyodbc

USER = os.environ["RCB_DB_USER"]
PASSWORD = os.environ["RCB_DB_PASSWORD"]
conn_str = f"DRIVER={{SQL Server}};SERVER=172.25.25.3,1433;DATABASE=RCB_LIVE_DB;UID={USER};PWD={PASSWORD};"
conn = pyodbc.connect(conn_str, timeout=30)
cur = conn.cursor()

print("=== L80580491-V2 : full JE ===")
cur.execute("""
    SELECT j.Account, a.AcctName, j.Debit, j.Credit, o.RefDate, j.TransId, j.Line_ID
    FROM JDT1 j
    LEFT JOIN OACT a ON a.AcctCode = j.Account
    LEFT JOIN OJDT o ON o.TransId = j.TransId
    WHERE j.LineMemo LIKE 'L80580491-V2_%'
    ORDER BY o.RefDate, j.TransId, j.Line_ID
""")
for row in cur.fetchall():
    print(row)

print("\n=== @INSURANCE row for L80580491-V2 ===")
cur.execute("""
    SELECT U_OrderItem, U_ExpectedReceived, U_ActualReceived, U_TotalAmount, U_Discount, U_BatchRunDate
    FROM [dbo].[@INSURANCE] WHERE U_OrderItem = 'L80580491-V2'
""")
for row in cur.fetchall():
    print(row)

cur.close()
conn.close()

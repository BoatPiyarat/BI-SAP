import os
import pyodbc

USER = os.environ["RCB_DB_USER"]
PASSWORD = os.environ["RCB_DB_PASSWORD"]
conn_str = f"DRIVER={{SQL Server}};SERVER=172.25.25.3,1433;DATABASE=RCB_LIVE_DB;UID={USER};PWD={PASSWORD};"
conn = pyodbc.connect(conn_str, timeout=30)
cur = conn.cursor()

print("=== L80691957-V1 : full JE, all lines ===")
cur.execute("""
    SELECT j.Account, a.AcctName, j.Debit, j.Credit, o.RefDate, j.TransId, j.Line_ID, j.LineMemo
    FROM JDT1 j
    LEFT JOIN OACT a ON a.AcctCode = j.Account
    LEFT JOIN OJDT o ON o.TransId = j.TransId
    WHERE j.LineMemo LIKE 'L80691957-V1_%'
    ORDER BY o.RefDate, j.TransId, j.Line_ID
""")
for row in cur.fetchall():
    print(row)

print("\n=== @INSURANCE row for L80691957-V1 ===")
cur.execute("""
    SELECT U_OrderItem, U_ExpectedReceived, U_ActualReceived, U_TotalAmount, U_Discount,
           U_PaymentMethod, U_PaymentChannel, U_BatchRunDate, U_PaymentStatus
    FROM [dbo].[@INSURANCE] WHERE U_OrderItem = 'L80691957-V1'
""")
for row in cur.fetchall():
    print(row)

cur.close()
conn.close()

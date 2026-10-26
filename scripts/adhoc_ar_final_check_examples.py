import os
import pyodbc

USER = os.environ["RCB_DB_USER"]
PASSWORD = os.environ["RCB_DB_PASSWORD"]
conn_str = f"DRIVER={{SQL Server}};SERVER=172.25.25.3,1433;DATABASE=RCB_LIVE_DB;UID={USER};PWD={PASSWORD};"
conn = pyodbc.connect(conn_str, timeout=30)
cur = conn.cursor()

print("=== L78745610-V1 full JE (clean type-A candidate, company) ===")
cur.execute("""
    SELECT j.Account, a.AcctName, j.Debit, j.Credit, o.RefDate
    FROM JDT1 j LEFT JOIN OACT a ON a.AcctCode = j.Account
    LEFT JOIN OJDT o ON o.TransId = j.TransId
    WHERE j.LineMemo LIKE 'L78745610-V1_%'
    ORDER BY j.Line_ID
""")
for row in cur.fetchall():
    print(row)

cur.execute("""
    SELECT U_OrderItem, U_OrderId, U_PaymentMethod, U_PaymentChannel, U_ExpectedReceived,
           U_ActualReceived, U_TotalAmount, U_Discount, U_BatchRunDate
    FROM [dbo].[@INSURANCE] WHERE U_OrderItem = 'L78745610-V1'
""")
for row in cur.fetchall():
    print("INSURANCE:", row)

cur.close()
conn.close()

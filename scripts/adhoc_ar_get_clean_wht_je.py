import os
import pyodbc

USER = os.environ["RCB_DB_USER"]
PASSWORD = os.environ["RCB_DB_PASSWORD"]
conn_str = f"DRIVER={{SQL Server}};SERVER=172.25.25.3,1433;DATABASE=RCB_LIVE_DB;UID={USER};PWD={PASSWORD};"
conn = pyodbc.connect(conn_str, timeout=30)
cur = conn.cursor()

for oi in ["L80669519-V1", "L80591763-V1"]:
    print(f"\n=== {oi} full JE (clean WHT example) ===")
    cur.execute("""
        SELECT j.Account, a.AcctName, j.Debit, j.Credit
        FROM JDT1 j LEFT JOIN OACT a ON a.AcctCode = j.Account
        WHERE j.LineMemo LIKE ?
        ORDER BY j.Line_ID
    """, f"{oi}_%")
    for row in cur.fetchall():
        print(row)
    cur.execute("""
        SELECT U_ExpectedReceived, U_ActualReceived, U_TotalAmount, U_PaymentChannel, U_BatchRunDate
        FROM [dbo].[@INSURANCE] WHERE U_OrderItem = ?
    """, oi)
    for row in cur.fetchall():
        print("INSURANCE:", row)

cur.close()
conn.close()

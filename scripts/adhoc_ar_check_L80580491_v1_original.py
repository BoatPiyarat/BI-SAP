"""
Aware asked for the "original version" (-V1, before resubmission as -V2) example that posted
wrong / never touched WHT (2142-10) at all - to understand what a batch-fix for already-posted
items needs to correct. SELECT only.
"""
import os
import pyodbc

USER = os.environ["RCB_DB_USER"]
PASSWORD = os.environ["RCB_DB_PASSWORD"]
conn_str = f"DRIVER={{SQL Server}};SERVER=172.25.25.3,1433;DATABASE=RCB_LIVE_DB;UID={USER};PWD={PASSWORD};"
conn = pyodbc.connect(conn_str, timeout=30)
cur = conn.cursor()

print("=== L80580491-V1 (ORIGINAL, before resubmission) full JE ===")
cur.execute("""
    SELECT j.Account, a.AcctName, j.Debit, j.Credit, o.RefDate, j.TransId
    FROM JDT1 j
    LEFT JOIN OACT a ON a.AcctCode = j.Account
    LEFT JOIN OJDT o ON o.TransId = j.TransId
    WHERE j.LineMemo LIKE 'L80580491-V1_%'
    ORDER BY o.RefDate, j.TransId, j.Line_ID
""")
for row in cur.fetchall():
    print(row)

print("\n=== @INSURANCE row(s) for L80580491-V1 ===")
cur.execute("""
    SELECT U_OrderItem, U_ExpectedReceived, U_ActualReceived, U_TotalAmount, U_WHTAmt,
           U_Discount, U_PaymentMethod, U_PaymentChannel, U_BatchRunDate
    FROM [dbo].[@INSURANCE] WHERE U_OrderItem = 'L80580491-V1'
""")
for row in cur.fetchall():
    print(row)

cur.close()
conn.close()

import os
import pyodbc

USER = os.environ["RCB_DB_USER"]
PASSWORD = os.environ["RCB_DB_PASSWORD"]
conn_str = f"DRIVER={{SQL Server}};SERVER=172.25.25.3,1433;DATABASE=RCB_LIVE_DB;UID={USER};PWD={PASSWORD};"
conn = pyodbc.connect(conn_str, timeout=30)
cur = conn.cursor()

cur.execute("""
    SELECT U_OrderItem, U_ExpectedReceived, U_ActualReceived, U_TotalAmount, U_WHTAmt,
           U_Discount, U_PaymentMethod, U_PaymentChannel, U_InsurerCode
    FROM [dbo].[@INSURANCE] WHERE U_OrderItem = 'L78667850-V2'
""")
for row in cur.fetchall():
    print(row)

cur.close()
conn.close()

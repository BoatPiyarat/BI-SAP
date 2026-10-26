import os
import pyodbc

USER = os.environ["RCB_DB_USER"]
PASSWORD = os.environ["RCB_DB_PASSWORD"]
conn_str = f"DRIVER={{SQL Server}};SERVER=172.25.25.3,1433;DATABASE=RCB_LIVE_DB;UID={USER};PWD={PASSWORD};"
conn = pyodbc.connect(conn_str, timeout=30)
cur = conn.cursor()

for oi in ["L78772038-V1", "L77161975-V1", "L80580491-V2", "L78737504-V1"]:
    cur.execute("""
        SELECT U_OrderItem, U_ExpectedReceived, U_ActualReceived, U_TotalAmount, U_WHTAmt, U_TotalEIRAmt, U_TotalSBTAmt
        FROM [dbo].[@INSURANCE] WHERE U_OrderItem = ?
    """, oi)
    for row in cur.fetchall():
        print(row)

cur.close()
conn.close()

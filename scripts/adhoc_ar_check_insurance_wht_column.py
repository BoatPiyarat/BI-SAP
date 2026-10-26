import os
import pyodbc

USER = os.environ["RCB_DB_USER"]
PASSWORD = os.environ["RCB_DB_PASSWORD"]
conn_str = f"DRIVER={{SQL Server}};SERVER=172.25.25.3,1433;DATABASE=RCB_LIVE_DB;UID={USER};PWD={PASSWORD};"
conn = pyodbc.connect(conn_str, timeout=30)
cur = conn.cursor()

cur.execute("""
    SELECT COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_NAME = '@INSURANCE' AND (COLUMN_NAME LIKE '%WHT%' OR COLUMN_NAME LIKE '%TotalEIR%' OR COLUMN_NAME LIKE '%TotalSBT%')
""")
for row in cur.fetchall():
    print(row)

cur.execute("SELECT U_WHT, U_TotalEIR, U_TotalSBT FROM [dbo].[@INSURANCE] WHERE U_OrderItem = 'L78772038-V1'")
for row in cur.fetchall():
    print("values:", row)

cur.close()
conn.close()

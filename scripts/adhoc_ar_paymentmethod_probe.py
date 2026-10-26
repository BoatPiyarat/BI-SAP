import os
import pyodbc

USER = os.environ["RCB_DB_USER"]
PASSWORD = os.environ["RCB_DB_PASSWORD"]
conn_str = f"DRIVER={{SQL Server}};SERVER=172.25.25.3,1433;DATABASE=RCB_LIVE_DB;UID={USER};PWD={PASSWORD};"
conn = pyodbc.connect(conn_str, timeout=20)
cur = conn.cursor()

cur.execute("SELECT * FROM [dbo].[@PAYMENTMETHOD]")
cols = [d[0] for d in cur.description]
print("=== @PAYMENTMETHOD columns ===")
print(cols)
print("=== rows ===")
for row in cur.fetchall():
    print(row)

cur.close()
conn.close()

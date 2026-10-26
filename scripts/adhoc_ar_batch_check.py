import os
import pyodbc

USER = os.environ["RCB_DB_USER"]
PASSWORD = os.environ["RCB_DB_PASSWORD"]
conn_str = f"DRIVER={{SQL Server}};SERVER=172.25.25.3,1433;DATABASE=RCB_LIVE_DB;UID={USER};PWD={PASSWORD};"
conn = pyodbc.connect(conn_str, timeout=30)
cur = conn.cursor()

for transid in (79424, 77568, 79432):
    cur.execute("""
        SELECT Account, COUNT(*) FROM JDT1
        WHERE TransId = ? AND Account IN ('1134-01','1135-01') AND Debit > 0 AND LineMemo LIKE '%-V%[_]%'
        GROUP BY Account
    """, transid)
    print(f"TransId {transid} (V-item debit lines):", cur.fetchall())

cur.close()
conn.close()

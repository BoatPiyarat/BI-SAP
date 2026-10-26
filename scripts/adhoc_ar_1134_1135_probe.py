"""
Read-only schema probe for the AR 1134-01/1135-01 misposting investigation.
Connects to RCB_LIVE_DB over the existing WireGuard tunnel. SELECT only.
Credentials are read from environment variables, never hardcoded/printed.
"""
import os
import sys
import pyodbc

SERVER = "172.25.25.3,1433"
DATABASE = "RCB_LIVE_DB"
USER = os.environ["RCB_DB_USER"]
PASSWORD = os.environ["RCB_DB_PASSWORD"]

conn_str = (
    "DRIVER={SQL Server};"
    f"SERVER={SERVER};DATABASE={DATABASE};UID={USER};PWD={PASSWORD};"
)

def run(cur, sql, label):
    print(f"\n=== {label} ===")
    try:
        cur.execute(sql)
        cols = [d[0] for d in cur.description]
        print(" | ".join(cols))
        for row in cur.fetchmany(5):
            print(" | ".join(str(v) for v in row))
    except Exception as e:
        print(f"ERROR: {e}")

conn = pyodbc.connect(conn_str, timeout=10)
conn.autocommit = True
cur = conn.cursor()

run(cur, "SELECT TOP 3 * FROM [dbo].[@INSURANCE]", "@INSURANCE sample")
run(cur, "SELECT TOP 3 * FROM OJDT", "OJDT sample")
run(cur, "SELECT TOP 3 * FROM JDT1", "JDT1 sample")
run(cur, "SELECT TOP 3 * FROM OACT WHERE AcctCode IN ('1134-01','1135-01')", "OACT 1134-01/1135-01")

cur.close()
conn.close()
print("\nDone.")

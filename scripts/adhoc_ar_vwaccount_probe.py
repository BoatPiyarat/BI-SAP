import os
import pyodbc

USER = os.environ["RCB_DB_USER"]
PASSWORD = os.environ["RCB_DB_PASSWORD"]
conn_str = f"DRIVER={{SQL Server}};SERVER=172.25.25.3,1433;DATABASE=RCB_LIVE_DB;UID={USER};PWD={PASSWORD};"
conn = pyodbc.connect(conn_str, timeout=20)
cur = conn.cursor()

cur.execute("SELECT OBJECT_DEFINITION(OBJECT_ID('dbo.vw_Account'))")
row = cur.fetchone()
print("=== vw_Account definition ===")
print(row[0] if row else "(no definition / not accessible)")

# Business Partner master control account for the insurers appearing in our misposted JEs
cur.execute("""
SELECT TOP 10 CardCode, CardName, GroupNum
FROM OCRD WHERE CardName LIKE N'%ธนชาต%' OR CardCode = 'THC-28'
""")
print("\n=== OCRD sample for THC-28 (most frequent insurer in the misposted set) ===")
for row in cur.fetchall():
    print(row)

cur.execute("""
SELECT GroupNum, GroupName FROM OCRG
""")
print("\n=== OCRG (BP groups + their control accounts, if column exists) ===")
cols = [d[0] for d in cur.description]
print(cols)
for row in cur.fetchall()[:20]:
    print(row)

cur.close()
conn.close()

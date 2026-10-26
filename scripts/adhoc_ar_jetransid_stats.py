import os
import pyodbc

USER = os.environ["RCB_DB_USER"]
PASSWORD = os.environ["RCB_DB_PASSWORD"]
conn_str = f"DRIVER={{SQL Server}};SERVER=172.25.25.3,1433;DATABASE=RCB_LIVE_DB;UID={USER};PWD={PASSWORD};"
conn = pyodbc.connect(conn_str, timeout=15)
cur = conn.cursor()

cur.execute("""
SELECT
  COUNT(*) AS total,
  SUM(CASE WHEN U_JETransId IS NOT NULL AND U_JETransId <> '' THEN 1 ELSE 0 END) AS has_jetransid,
  SUM(CASE WHEN U_PaymentMethod = 'EDC EDC' THEN 1 ELSE 0 END) AS edc_total,
  SUM(CASE WHEN U_PaymentMethod = 'EDC EDC' AND U_JETransId IS NOT NULL AND U_JETransId <> '' THEN 1 ELSE 0 END) AS edc_has_jetransid
FROM [dbo].[@INSURANCE]
""")
print(cur.fetchone())

cur.execute("SELECT TOP 5 U_OrderItem, U_JETransId, U_PaymentMethod, U_JETransId FROM [dbo].[@INSURANCE] WHERE U_PaymentMethod = 'EDC EDC' AND U_JETransId IS NOT NULL AND U_JETransId <> '' ORDER BY CreateDate DESC")
for row in cur.fetchall():
    print(row)

# find JDT1 rows referencing this order by other means: search LineMemo / U_OrderNo for one known order
cur.execute("SELECT TOP 5 TransId, Line_ID, Account, Debit, Credit, LineMemo, U_OrderNo FROM JDT1 WHERE U_OrderNo LIKE 'L78667850%'")
for row in cur.fetchall():
    print("U_OrderNo match:", row)

cur.execute("SELECT TOP 5 TransId, Line_ID, Account, Debit, Credit, LineMemo, U_OrderNo FROM JDT1 WHERE LineMemo LIKE '%L78667850%'")
for row in cur.fetchall():
    print("LineMemo match:", row)

cur.execute("SELECT TOP 3 BaseRef, Ref1, Ref2, Memo FROM OJDT WHERE Ref1 LIKE '%L78667850%' OR Ref2 LIKE '%L78667850%' OR Memo LIKE '%L78667850%' OR BaseRef LIKE '%L78667850%'")
for row in cur.fetchall():
    print("OJDT match:", row)

cur.close()
conn.close()

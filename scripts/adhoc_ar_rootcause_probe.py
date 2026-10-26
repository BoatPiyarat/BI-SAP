"""
Root-cause probe: is the wrong AR account (1134-01 vs 1135-01) coming from the interface file
itself (PaymentMethod/PaymentChannel sent wrong from BI/CareOS), or decided inside SAP's own
import/posting logic? SELECT only.
"""
import os
import pyodbc

USER = os.environ["RCB_DB_USER"]
PASSWORD = os.environ["RCB_DB_PASSWORD"]
conn_str = f"DRIVER={{SQL Server}};SERVER=172.25.25.3,1433;DATABASE=RCB_LIVE_DB;UID={USER};PWD={PASSWORD};"
conn = pyodbc.connect(conn_str, timeout=20)
cur = conn.cursor()

# 1. find any table with 'temp' + 'insurance' in the name
cur.execute("""
SELECT TABLE_SCHEMA, TABLE_NAME
FROM INFORMATION_SCHEMA.TABLES
WHERE LOWER(TABLE_NAME) LIKE '%temp%insurance%' OR LOWER(TABLE_NAME) LIKE '%insurance%temp%'
""")
print("=== candidate temp/staging tables ===")
for row in cur.fetchall():
    print(row)

# 2. also list any table containing 'account' in name, might hold posting-rule mapping
cur.execute("""
SELECT TABLE_SCHEMA, TABLE_NAME
FROM INFORMATION_SCHEMA.TABLES
WHERE LOWER(TABLE_NAME) LIKE '%account%' OR LOWER(TABLE_NAME) LIKE '%mapping%' OR LOWER(TABLE_NAME) LIKE '%payment%method%'
""")
print("\n=== candidate account/mapping tables ===")
for row in cur.fetchall():
    print(row)

# 3. does @INSURANCE itself carry any GL-account-looking field beyond what we've seen? re-list columns with 'acc' or 'gl' in name
cur.execute("""
SELECT COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = '@INSURANCE' AND (LOWER(COLUMN_NAME) LIKE '%acc%' OR LOWER(COLUMN_NAME) LIKE '%gl%')
""")
print("\n=== @INSURANCE columns matching acc/gl ===")
for row in cur.fetchall():
    print(row)

cur.close()
conn.close()

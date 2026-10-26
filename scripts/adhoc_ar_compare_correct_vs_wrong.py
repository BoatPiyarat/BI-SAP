"""
Root-cause probe part 3: EDC EDC / RCB-EDC-KBANK orders are NOT 100% misposted system-wide (the
independent sample split ~50/50 1134-01 vs 1135-01) - so Pui's 224-order list is a curated
"known-bad" list, not proof of a total account-mapping misconfiguration. This script pulls full
@INSURANCE rows for a few correctly-posted (1135-01) vs incorrectly-posted (1134-01) EDC/KBANK
orders side by side to find what actually differs between them. SELECT only.
"""
import os
import pyodbc

USER = os.environ["RCB_DB_USER"]
PASSWORD = os.environ["RCB_DB_PASSWORD"]
conn_str = f"DRIVER={{SQL Server}};SERVER=172.25.25.3,1433;DATABASE=RCB_LIVE_DB;UID={USER};PWD={PASSWORD};"
conn = pyodbc.connect(conn_str, timeout=30)
cur = conn.cursor()

cur.execute("""
SELECT TOP 60 U_OrderId, U_OrderItem, U_BatchRunDate, U_InsurerCode, U_InsuranceType, U_ProductType,
       U_PaymentMethod, U_PaymentChannel, U_TotalPeriods, U_PaymentStatus, U_ApprovalStatus,
       U_SubmissionStatus, DataSource, Creator, CreateDate, U_PolicyType
FROM [dbo].[@INSURANCE]
WHERE U_PaymentMethod = 'EDC EDC' AND U_PaymentChannel = 'RCB-EDC-KBANK'
  AND U_TotalPeriods = 1 AND U_PaymentStatus = 'Fully paid'
ORDER BY U_BatchRunDate DESC
""")
sample = cur.fetchall()
cols = [d[0] for d in cur.description]
by_item = {r.U_OrderItem: r for r in sample}
order_items = list(by_item.keys())

placeholders = " OR ".join(["j.LineMemo LIKE ?" for _ in order_items])
params = [f"{oi}_%" for oi in order_items]
cur.execute(f"""
SELECT j.LineMemo, j.Account
FROM JDT1 j
WHERE j.Account IN ('1134-01','1135-01') AND j.Debit > 0 AND ({placeholders})
""", params)

item_to_account = {}
for row in cur.fetchall():
    oi = row.LineMemo.split("_")[0]
    item_to_account[oi] = row.Account

correct_items = [oi for oi, acc in item_to_account.items() if acc == "1135-01"][:5]
wrong_items = [oi for oi, acc in item_to_account.items() if acc == "1134-01"][:5]

print("cols:", cols)
print("\n=== CORRECTLY posted to 1135-01 ===")
for oi in correct_items:
    print(by_item[oi])

print("\n=== INCORRECTLY posted to 1134-01 ===")
for oi in wrong_items:
    print(by_item[oi])

cur.close()
conn.close()

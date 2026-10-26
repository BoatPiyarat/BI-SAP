"""
Confirm hypothesis: AR account selection tracks item-type suffix (M=Compulsory vs V=Voluntary),
not PaymentMethod. Pull a larger sample (200) of EDC/KBANK TotalPeriods=1 Fully-paid orders and
cross-tab item suffix x posted account. SELECT only.
"""
import os
import re
import pyodbc

USER = os.environ["RCB_DB_USER"]
PASSWORD = os.environ["RCB_DB_PASSWORD"]
conn_str = f"DRIVER={{SQL Server}};SERVER=172.25.25.3,1433;DATABASE=RCB_LIVE_DB;UID={USER};PWD={PASSWORD};"
conn = pyodbc.connect(conn_str, timeout=30)
cur = conn.cursor()

cur.execute("""
SELECT TOP 300 U_OrderItem, U_InsuranceType
FROM [dbo].[@INSURANCE]
WHERE U_PaymentMethod = 'EDC EDC' AND U_PaymentChannel = 'RCB-EDC-KBANK'
  AND U_TotalPeriods = 1 AND U_PaymentStatus = 'Fully paid'
ORDER BY U_BatchRunDate DESC
""")
sample = cur.fetchall()
order_items = [r.U_OrderItem for r in sample]
itype_by_item = {r.U_OrderItem: r.U_InsuranceType for r in sample}

placeholders = " OR ".join(["j.LineMemo LIKE ?" for _ in order_items])
params = [f"{oi}_%" for oi in order_items]
cur.execute(f"""
SELECT j.LineMemo, j.Account
FROM JDT1 j
WHERE j.Account IN ('1134-01','1135-01') AND j.Debit > 0 AND ({placeholders})
""", params)

crosstab = {}  # (suffix, account) -> count
mismatch_examples = []
for row in cur.fetchall():
    oi = row.LineMemo.split("_")[0]
    m = re.search(r"-([A-Za-z]?\d+)$", oi)
    suffix_letter = re.sub(r"\d", "", m.group(1)) if m else "?"
    suffix_letter = suffix_letter or "V(numeric-only)"
    key = (suffix_letter, row.Account)
    crosstab[key] = crosstab.get(key, 0) + 1

print(f"sampled_order_items={len(order_items)}")
print("crosstab (item_suffix_letter, account) -> count:")
for k, v in sorted(crosstab.items()):
    print(k, v)

cur.close()
conn.close()

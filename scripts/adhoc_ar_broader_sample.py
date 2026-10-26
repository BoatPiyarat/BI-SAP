"""
Root-cause probe part 2: is this misposting scoped to Pui's reported batch, or does EVERY
EDC EDC / RCB-EDC-KBANK order post to 1134-01, system-wide? Pull an independent sample of such
orders straight from @INSURANCE (not from Pui's list) and check their JE account via LineMemo.
Also spot-check whether ANY EDC/KBANK order has ever correctly landed on 1135-01, and whether a
different, non-EDC payment channel correctly posts to 1135-01 (to isolate this to EDC-KBANK
specifically vs. a broader 1135-01 account-selection failure). SELECT only.
"""
import os
import pyodbc

USER = os.environ["RCB_DB_USER"]
PASSWORD = os.environ["RCB_DB_PASSWORD"]
conn_str = f"DRIVER={{SQL Server}};SERVER=172.25.25.3,1433;DATABASE=RCB_LIVE_DB;UID={USER};PWD={PASSWORD};"
conn = pyodbc.connect(conn_str, timeout=30)
cur = conn.cursor()

print("=== independent sample: 40 most recent EDC EDC / RCB-EDC-KBANK, TotalPeriods=1, Fully paid orders (any, not just Pui's list) ===")
cur.execute("""
SELECT TOP 40 U_OrderId, U_OrderItem, U_PaymentMethod, U_PaymentChannel, U_TotalPeriods, U_PaymentStatus, U_BatchRunDate
FROM [dbo].[@INSURANCE]
WHERE U_PaymentMethod = 'EDC EDC' AND U_PaymentChannel = 'RCB-EDC-KBANK'
  AND U_TotalPeriods = 1 AND U_PaymentStatus = 'Fully paid'
ORDER BY U_BatchRunDate DESC
""")
sample = cur.fetchall()
order_items = [r.U_OrderItem for r in sample]
for r in sample[:5]:
    print(r)
print(f"... {len(sample)} total sampled")

placeholders = " OR ".join(["j.LineMemo LIKE ?" for _ in order_items])
params = [f"{oi}_%" for oi in order_items]
sql = f"""
SELECT j.LineMemo, j.Account, j.Debit, j.Credit
FROM JDT1 j
WHERE j.Account IN ('1134-01','1135-01') AND ({placeholders})
"""
cur.execute(sql, params)
rows = cur.fetchall()
by_account = {}
for r in rows:
    if float(r.Debit) > 0:
        by_account[r.Account] = by_account.get(r.Account, 0) + 1
print("\n=== JE account distribution for the DEBIT (primary AR) line, independent sample ===")
print(by_account)

print("\n=== control check: does ANY row anywhere in JDT1 show an EDC/KBANK-linked LineMemo landing on 1135-01 as the DEBIT (primary) line? ===")
cur.execute("""
SELECT TOP 10 LineMemo, Account, Debit, Credit
FROM JDT1
WHERE Account = '1135-01' AND Debit > 0
""")
for row in cur.fetchall():
    print(row)

print("\n=== control check 2: a non-EDC payment channel (e.g. Omise Credit Card) - does it post its DEBIT line to 1135-01 correctly? ===")
cur.execute("""
SELECT TOP 10 U_OrderId, U_OrderItem, U_PaymentMethod, U_PaymentChannel
FROM [dbo].[@INSURANCE]
WHERE U_PaymentMethod LIKE '%Omise Credit Card%' AND U_TotalPeriods = 1 AND U_PaymentStatus = 'Fully paid'
ORDER BY U_BatchRunDate DESC
""")
omise_sample = cur.fetchall()
for r in omise_sample:
    print(r)
if omise_sample:
    oi_list = [r.U_OrderItem for r in omise_sample]
    ph = " OR ".join(["j.LineMemo LIKE ?" for _ in oi_list])
    pr = [f"{oi}_%" for oi in oi_list]
    cur.execute(f"SELECT LineMemo, Account, Debit, Credit FROM JDT1 j WHERE Account IN ('1134-01','1135-01') AND ({ph})", pr)
    for row in cur.fetchall():
        print("OMISE JE:", row)

cur.close()
conn.close()

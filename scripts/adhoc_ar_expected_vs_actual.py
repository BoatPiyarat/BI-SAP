"""
Boat's ask: within Voluntary (-V) items only, compare U_ExpectedReceived vs U_ActualReceived
pattern between correctly-posted (1135-01) and incorrectly-posted (1134-01) orders, to find the
real discriminator. SELECT only.
"""
import os
import pyodbc

USER = os.environ["RCB_DB_USER"]
PASSWORD = os.environ["RCB_DB_PASSWORD"]
conn_str = f"DRIVER={{SQL Server}};SERVER=172.25.25.3,1433;DATABASE=RCB_LIVE_DB;UID={USER};PWD={PASSWORD};"
conn = pyodbc.connect(conn_str, timeout=30)
cur = conn.cursor()

cur.execute("""
SELECT TOP 500 U_OrderItem, U_ExpectedReceived, U_ActualReceived, U_TotalAmount,
       U_ProcessingFee, U_ShippingFee, U_Discount, U_RefundAmt
FROM [dbo].[@INSURANCE]
WHERE U_PaymentMethod = 'EDC EDC' AND U_PaymentChannel = 'RCB-EDC-KBANK'
  AND U_TotalPeriods = 1 AND U_PaymentStatus = 'Fully paid'
  AND U_OrderItem LIKE '%-V%'
ORDER BY U_BatchRunDate DESC
""")
rows = cur.fetchall()
by_item = {r.U_OrderItem: r for r in rows}
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

def bucket(exp, act):
    if exp is None or act is None:
        return "NULL"
    d = float(exp) - float(act)
    if abs(d) < 0.01:
        return "EXACT_MATCH"
    elif d > 0:
        return "EXPECTED_GT_ACTUAL (shortage)"
    else:
        return "EXPECTED_LT_ACTUAL (overage)"

stats = {}  # account -> bucket -> count
diffs = {}  # account -> list of diffs (non-exact)
for oi, acc in item_to_account.items():
    r = by_item.get(oi)
    if not r:
        continue
    b = bucket(r.U_ExpectedReceived, r.U_ActualReceived)
    stats.setdefault(acc, {}).setdefault(b, 0)
    stats[acc][b] += 1
    if b != "EXACT_MATCH" and r.U_ExpectedReceived is not None and r.U_ActualReceived is not None:
        diffs.setdefault(acc, []).append(float(r.U_ExpectedReceived) - float(r.U_ActualReceived))

print("=== bucket counts by account ===")
for acc, d in stats.items():
    print(acc, d)

print("\n=== sample diffs (non-exact) ===")
for acc, dl in diffs.items():
    print(acc, "n=", len(dl), "min=", min(dl) if dl else None, "max=", max(dl) if dl else None)
    print(" sample:", dl[:15])

print("\n=== raw sample rows: WRONG (1134-01) ===")
count = 0
for oi, acc in item_to_account.items():
    if acc == "1134-01" and count < 8:
        r = by_item[oi]
        print(oi, "Exp=", r.U_ExpectedReceived, "Act=", r.U_ActualReceived, "Total=", r.U_TotalAmount,
              "ProcFee=", r.U_ProcessingFee, "ShipFee=", r.U_ShippingFee, "Disc=", r.U_Discount, "Refund=", r.U_RefundAmt)
        count += 1

print("\n=== raw sample rows: CORRECT (1135-01) ===")
count = 0
for oi, acc in item_to_account.items():
    if acc == "1135-01" and count < 8:
        r = by_item[oi]
        print(oi, "Exp=", r.U_ExpectedReceived, "Act=", r.U_ActualReceived, "Total=", r.U_TotalAmount,
              "ProcFee=", r.U_ProcessingFee, "ShipFee=", r.U_ShippingFee, "Disc=", r.U_Discount, "Refund=", r.U_RefundAmt)
        count += 1

cur.close()
conn.close()

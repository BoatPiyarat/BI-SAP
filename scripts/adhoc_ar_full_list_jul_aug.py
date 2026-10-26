"""
Boat confirmed: he personally ran the manual backfill that force-converts EDC/CREDIT_CARD_
INSTALLMENT orders classified as multi-period back to onetime. Get the FULL list of matching
records (EDC EDC, ExpectedReceived=TotalAmount, ActualReceived=0 pattern) for July-August 2026
BatchRunDate, to scope the population for the Aware conversation. SELECT only.
"""
import os
import csv
import pyodbc

USER = os.environ["RCB_DB_USER"]
PASSWORD = os.environ["RCB_DB_PASSWORD"]
conn_str = f"DRIVER={{SQL Server}};SERVER=172.25.25.3,1433;DATABASE=RCB_LIVE_DB;UID={USER};PWD={PASSWORD};"
conn = pyodbc.connect(conn_str, timeout=60)
cur = conn.cursor()

cur.execute("""
    SELECT U_OrderId, U_OrderItem, U_ExpectedReceived, U_ActualReceived, U_TotalAmount,
           U_PaymentMethod, U_PaymentChannel, U_BatchRunDate, U_PaymentStatus
    FROM [dbo].[@INSURANCE]
    WHERE U_PaymentMethod = 'EDC EDC'
      AND U_ActualReceived = 0
      AND U_ExpectedReceived = U_TotalAmount
      AND U_ExpectedReceived > 0
      AND U_BatchRunDate >= '2026-07-01' AND U_BatchRunDate < '2026-09-01'
      AND U_OrderItem LIKE '%-V%'
    ORDER BY U_BatchRunDate, U_OrderId
""")
rows = cur.fetchall()
print(f"total matching rows: {len(rows)}")

out_path = r"C:\Users\Developer\OneDrive - Rabbit Internet\Documents\03 Project - Partner\02 SAP\Phase1.1\agentic_bootstrap\tmp_full_list_jul_aug_backfill_pattern.csv"
with open(out_path, "w", newline="", encoding="utf-8-sig") as f:
    w = csv.writer(f)
    w.writerow(["OrderId", "OrderItem", "ExpectedReceived", "ActualReceived", "TotalAmount",
                "PaymentMethod", "PaymentChannel", "BatchRunDate", "PaymentStatus"])
    for r in rows:
        w.writerow(list(r))
print(f"written to {out_path}")

# monthly breakdown
by_month = {}
for r in rows:
    ym = str(r.U_BatchRunDate)[:7]
    by_month[ym] = by_month.get(ym, 0) + 1
print("\nby month:")
for ym in sorted(by_month.keys()):
    print(ym, by_month[ym])

cur.close()
conn.close()

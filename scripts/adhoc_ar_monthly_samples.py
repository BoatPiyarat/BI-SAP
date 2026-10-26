"""
Pull 5 correctly-posted (1135-01) + 5 incorrectly-posted (1134-01) company-customer (blank
U_Title) Voluntary-item order records per month, 2025-05 through 2026-08, with the @INSURANCE
interface fields as SAP actually received them. Single-pass query (one table scan of the date
range), sampling done in Python to avoid 32 separate round trips. SELECT only.
"""
import os
import csv
import pyodbc
from collections import defaultdict

USER = os.environ["RCB_DB_USER"]
PASSWORD = os.environ["RCB_DB_PASSWORD"]
conn_str = f"DRIVER={{SQL Server}};SERVER=172.25.25.3,1433;DATABASE=RCB_LIVE_DB;UID={USER};PWD={PASSWORD};"
conn = pyodbc.connect(conn_str, timeout=120)
cur = conn.cursor()

cur.execute("""
    SELECT
      FORMAT(o.RefDate, 'yyyy-MM') AS ym,
      j.Account,
      i.U_OrderItem, i.U_OrderId, i.U_ExpectedReceived, i.U_ActualReceived,
      i.U_TotalAmount, i.U_ProcessingFee, i.U_Discount, i.U_PaymentMethod,
      i.U_PaymentChannel, i.U_TotalPeriods, i.U_BatchRunDate, j.Debit
    FROM JDT1 j
    JOIN OJDT o ON o.TransId = j.TransId
    JOIN [dbo].[@INSURANCE] i
      ON i.U_OrderItem = LEFT(j.LineMemo, CASE WHEN CHARINDEX('_', j.LineMemo) = 0 THEN LEN(j.LineMemo) ELSE CHARINDEX('_', j.LineMemo) - 1 END)
    WHERE j.Account IN ('1134-01','1135-01') AND j.Debit > 0
      AND j.LineMemo LIKE '%-V[0-9]%'
      AND o.RefDate >= '2025-05-01' AND o.RefDate < '2026-09-01'
      AND (i.U_Title = '' OR i.U_Title IS NULL)
    ORDER BY o.RefDate
""")
cols = ["month", "account", "OrderItem", "OrderId", "ExpectedReceived", "ActualReceived",
        "TotalAmount", "ProcessingFee", "Discount", "PaymentMethod", "PaymentChannel",
        "TotalPeriods", "BatchRunDate", "JE_Debit"]

buckets = defaultdict(list)
for row in cur.fetchall():
    ym, acct = row[0], row[1]
    buckets[(ym, acct)].append(list(row))

out_rows = []
for (ym, acct), rows in sorted(buckets.items()):
    out_rows.extend(rows[:5])

out_path = r"C:\Users\Developer\OneDrive - Rabbit Internet\Documents\03 Project - Partner\02 SAP\Phase1.1\agentic_bootstrap\tmp_monthly_company_samples.csv"
with open(out_path, "w", newline="", encoding="utf-8-sig") as f:
    w = csv.writer(f)
    w.writerow(cols)
    for r in out_rows:
        w.writerow(r)

print(f"total_rows_scanned={sum(len(v) for v in buckets.values())} sampled_rows={len(out_rows)} written to {out_path}")
cur.close()
conn.close()

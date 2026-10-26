"""
Find real, same-channel, same-shape (GAP, isCompany=TRUE) paired examples in a recent month
(2026-08, falling back to 2026-07 if thin) - one correctly posted, one wrong - for a message to
Aware showing identical input pattern -> different JE outcome. SELECT only.
"""
import os
import pyodbc

USER = os.environ["RCB_DB_USER"]
PASSWORD = os.environ["RCB_DB_PASSWORD"]
conn_str = f"DRIVER={{SQL Server}};SERVER=172.25.25.3,1433;DATABASE=RCB_LIVE_DB;UID={USER};PWD={PASSWORD};"
conn = pyodbc.connect(conn_str, timeout=60)
cur = conn.cursor()

for ym_start, ym_end, label in [("2026-08-01", "2026-09-01", "2026-08"), ("2026-07-01", "2026-08-01", "2026-07")]:
    print(f"\n########## {label} ##########")
    cur.execute("""
        SELECT
          j.Account, i.U_OrderId, i.U_OrderItem, i.U_PaymentMethod, i.U_PaymentChannel,
          i.U_ExpectedReceived, i.U_ActualReceived, i.U_TotalAmount, i.U_Discount,
          i.U_ProcessingFee, i.U_BatchRunDate, j.Debit
        FROM JDT1 j
        JOIN OJDT o ON o.TransId = j.TransId
        JOIN [dbo].[@INSURANCE] i
          ON i.U_OrderItem = LEFT(j.LineMemo, CASE WHEN CHARINDEX('_', j.LineMemo) = 0 THEN LEN(j.LineMemo) ELSE CHARINDEX('_', j.LineMemo) - 1 END)
        WHERE j.Account IN ('1134-01','1135-01') AND j.Debit > 0
          AND j.LineMemo LIKE '%-V[0-9]%'
          AND o.RefDate >= ? AND o.RefDate < ?
          AND (i.U_Title = '' OR i.U_Title IS NULL)
          AND i.U_ExpectedReceived <> i.U_ActualReceived
        ORDER BY i.U_PaymentChannel, j.Account
    """, ym_start, ym_end)
    rows = cur.fetchall()
    by_channel = {}
    for r in rows:
        by_channel.setdefault(r.U_PaymentChannel, {"1134-01": [], "1135-01": []})[r.Account].append(r)

    for channel, accs in by_channel.items():
        if accs["1134-01"] and accs["1135-01"]:
            print(f"\n--- channel with BOTH outcomes present: {channel} ---")
            print("CORRECT (1135-01):", accs["1135-01"][0])
            print("WRONG   (1134-01):", accs["1134-01"][0])

cur.close()
conn.close()

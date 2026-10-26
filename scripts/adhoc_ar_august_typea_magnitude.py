"""
Refine TYPE_A (has 1134-01, no 1135-01 line): split by whether net_1134 is large (comparable to
the order's real premium - genuine full misposting) vs small/negative (something else entirely -
needs separate explanation). Cross-reference against @INSURANCE TotalAmount/ExpectedReceived.
SELECT only.
"""
import os
import pyodbc

USER = os.environ["RCB_DB_USER"]
PASSWORD = os.environ["RCB_DB_PASSWORD"]
conn_str = f"DRIVER={{SQL Server}};SERVER=172.25.25.3,1433;DATABASE=RCB_LIVE_DB;UID={USER};PWD={PASSWORD};"
conn = pyodbc.connect(conn_str, timeout=60)
cur = conn.cursor()

cur.execute("""
    WITH ol AS (
      SELECT
        LEFT(j.LineMemo, CHARINDEX('_', j.LineMemo) - 1) AS oi,
        o.TransId,
        SUM(CASE WHEN j.Account = '1134-01' THEN j.Debit - j.Credit ELSE 0 END) AS net_1134,
        MAX(CASE WHEN j.Account = '1135-01' AND j.Debit > 0 THEN 1 ELSE 0 END) AS has_1135
      FROM JDT1 j
      JOIN OJDT o ON o.TransId = j.TransId
      JOIN [dbo].[@INSURANCE] i
        ON i.U_OrderItem = LEFT(j.LineMemo, CASE WHEN CHARINDEX('_', j.LineMemo) = 0 THEN LEN(j.LineMemo) ELSE CHARINDEX('_', j.LineMemo) - 1 END)
      WHERE j.LineMemo LIKE '%-V[0-9]%' AND CHARINDEX('_', j.LineMemo) > 0
        AND o.RefDate >= '2026-08-01' AND o.RefDate < '2026-08-22'
        AND (i.U_Title = '' OR i.U_Title IS NULL)
      GROUP BY LEFT(j.LineMemo, CHARINDEX('_', j.LineMemo) - 1), o.TransId
    )
    SELECT ol.oi, ol.TransId, ol.net_1134, i.U_TotalAmount, i.U_ExpectedReceived, i.U_ActualReceived,
           i.U_PaymentChannel, i.U_ApprovalStatus, i.U_SubmissionStatus, i.U_PaymentStatus
    FROM ol
    JOIN [dbo].[@INSURANCE] i ON i.U_OrderItem = ol.oi
    WHERE ABS(ol.net_1134) > 0.01 AND ol.has_1135 = 0
    ORDER BY ol.net_1134 DESC
""")
rows = cur.fetchall()
print(f"total TYPE_A rows: {len(rows)}")

large = [r for r in rows if float(r.net_1134) > 1000]
small_pos = [r for r in rows if 0 < float(r.net_1134) <= 1000]
neg = [r for r in rows if float(r.net_1134) < 0]

print(f"large (>1000, genuine full misposting candidate): {len(large)}")
print(f"small positive (<=1000): {len(small_pos)}")
print(f"negative: {len(neg)}")

print("\n=== LARGE sample (genuine full misposting candidates) ===")
for r in large[:10]:
    print(r)

print("\n=== SMALL POSITIVE sample ===")
for r in small_pos[:10]:
    print(r)

print("\n=== NEGATIVE sample ===")
for r in neg[:10]:
    print(r)

cur.close()
conn.close()

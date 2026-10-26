"""
Aware (Boyd/June) confirmed: SAP's rule is ExpectedReceived=0 -> Dr Payment Channel / Cr 1134-01
(full ActualReceived). Verify this against the ORIGINAL Pui-reported list's type-A misposting
examples (simple 2-line JE, no WHT/fee lines) to see if ExpectedReceived=0 explains them too.
SELECT only.
"""
import os
import pyodbc

USER = os.environ["RCB_DB_USER"]
PASSWORD = os.environ["RCB_DB_PASSWORD"]
conn_str = f"DRIVER={{SQL Server}};SERVER=172.25.25.3,1433;DATABASE=RCB_LIVE_DB;UID={USER};PWD={PASSWORD};"
conn = pyodbc.connect(conn_str, timeout=60)
cur = conn.cursor()

examples = ['L78667850-V1', 'L80512637-V1', 'L78795358-V1']
for oi in examples:
    cur.execute("""
        SELECT U_OrderItem, U_ExpectedReceived, U_ActualReceived, U_TotalAmount, U_PaymentChannel
        FROM [dbo].[@INSURANCE] WHERE U_OrderItem = ?
    """, oi)
    for row in cur.fetchall():
        print(row)

print("\n=== broader check: for ALL 142 originally-flagged simple-2-line-JE orders, what fraction have ExpectedReceived=0? ===")
cur.execute("""
    WITH je AS (
      SELECT
        LEFT(j.LineMemo, CHARINDEX('_', j.LineMemo) - 1) AS oi,
        o.TransId,
        COUNT(*) AS n_lines,
        SUM(j.Debit) AS total_debit_1134,
        MAX(CASE WHEN j.Account = '1135-01' THEN 1 ELSE 0 END) AS has_1135
      FROM JDT1 j
      JOIN OJDT o ON o.TransId = j.TransId
      WHERE j.Account = '1134-01' AND j.Debit > 0
        AND j.LineMemo LIKE '%-V[0-9]%' AND CHARINDEX('_', j.LineMemo) > 0
        AND o.RefDate >= '2026-08-01' AND o.RefDate < '2026-08-22'
      GROUP BY LEFT(j.LineMemo, CHARINDEX('_', j.LineMemo) - 1), o.TransId
      HAVING MAX(CASE WHEN j.Account = '1135-01' THEN 1 ELSE 0 END) = 0
    )
    SELECT
      SUM(CASE WHEN i.U_ExpectedReceived = 0 THEN 1 ELSE 0 END) AS expected_zero,
      SUM(CASE WHEN i.U_ExpectedReceived <> 0 THEN 1 ELSE 0 END) AS expected_nonzero,
      COUNT(*) AS total
    FROM je
    JOIN [dbo].[@INSURANCE] i ON i.U_OrderItem = je.oi
""")
for row in cur.fetchall():
    print(row)

cur.close()
conn.close()

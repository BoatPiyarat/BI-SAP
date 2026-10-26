"""
Find real type-A (true full misposting, no 1135-01 line at all) examples among company customers
in a recent month, plus a same-channel correctly-posted company-customer example, for an accurate
Aware message. SELECT only.
"""
import os
import pyodbc

USER = os.environ["RCB_DB_USER"]
PASSWORD = os.environ["RCB_DB_PASSWORD"]
conn_str = f"DRIVER={{SQL Server}};SERVER=172.25.25.3,1433;DATABASE=RCB_LIVE_DB;UID={USER};PWD={PASSWORD};"
conn = pyodbc.connect(conn_str, timeout=60)
cur = conn.cursor()

cur.execute("""
    WITH orderitem_lines AS (
      SELECT
        LEFT(j.LineMemo, CHARINDEX('_', j.LineMemo) - 1) AS oi,
        o.TransId,
        o.RefDate,
        SUM(CASE WHEN j.Account = '1134-01' THEN j.Debit - j.Credit ELSE 0 END) AS net_1134,
        MAX(CASE WHEN j.Account = '1135-01' AND j.Debit > 0 THEN 1 ELSE 0 END) AS has_1135_line,
        COUNT(*) AS n_lines
      FROM JDT1 j
      JOIN OJDT o ON o.TransId = j.TransId
      JOIN [dbo].[@INSURANCE] i
        ON i.U_OrderItem = LEFT(j.LineMemo, CASE WHEN CHARINDEX('_', j.LineMemo) = 0 THEN LEN(j.LineMemo) ELSE CHARINDEX('_', j.LineMemo) - 1 END)
      WHERE j.LineMemo LIKE '%-V[0-9]%' AND CHARINDEX('_', j.LineMemo) > 0
        AND o.RefDate >= '2026-07-01' AND o.RefDate < '2026-09-01'
        AND (i.U_Title = '' OR i.U_Title IS NULL)
      GROUP BY LEFT(j.LineMemo, CHARINDEX('_', j.LineMemo) - 1), o.TransId, o.RefDate
    )
    SELECT TOP 15 oi, TransId, RefDate, net_1134, has_1135_line, n_lines
    FROM orderitem_lines
    WHERE net_1134 > 2000 AND has_1135_line = 0
    ORDER BY RefDate DESC
""")
print("=== type-A true misposting candidates, company customers, Jul-Aug 2026 ===")
type_a = cur.fetchall()
for row in type_a:
    print(row)

if type_a:
    oi = type_a[0].oi
    print(f"\n=== full JE for {oi} ===")
    cur.execute("""
        SELECT j.Account, a.AcctName, j.Debit, j.Credit
        FROM JDT1 j LEFT JOIN OACT a ON a.AcctCode = j.Account
        WHERE j.LineMemo LIKE ?
        ORDER BY j.Line_ID
    """, f"{oi}_%")
    for row in cur.fetchall():
        print(row)

    # get its payment channel / expected / actual from @INSURANCE
    cur.execute("""
        SELECT U_OrderItem, U_PaymentChannel, U_ExpectedReceived, U_ActualReceived, U_TotalAmount, U_Discount
        FROM [dbo].[@INSURANCE] WHERE U_OrderItem LIKE ?
    """, f"{oi}-%")
    for row in cur.fetchall():
        print("INSURANCE:", row)

cur.close()
conn.close()

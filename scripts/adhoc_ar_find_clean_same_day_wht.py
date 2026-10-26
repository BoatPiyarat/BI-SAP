"""
Find historical clean examples: ExpectedReceived=ActualReceived, U_WHTAmt>0, JE RefDate matches
the @INSURANCE BatchRunDate (same day - not a later manual adjustment), no 1134-01 line at all.
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
    WITH je AS (
      SELECT
        LEFT(j.LineMemo, CHARINDEX('_', j.LineMemo) - 1) AS item,
        MIN(o.RefDate) AS RefDate,
        SUM(CASE WHEN j.Account = '2142-10' THEN j.Debit ELSE 0 END) AS wht_2142,
        SUM(CASE WHEN j.Account = '1134-01' THEN j.Debit - j.Credit ELSE 0 END) AS net_1134,
        SUM(CASE WHEN j.Account = '1135-01' THEN j.Debit ELSE 0 END) AS bulk_1135,
        COUNT(DISTINCT j.TransId) AS n_transids
      FROM JDT1 j
      JOIN OJDT o ON o.TransId = j.TransId
      WHERE j.LineMemo LIKE '%-V[0-9]%' AND CHARINDEX('_', j.LineMemo) > 0
        AND j.Account IN ('1134-01','1135-01','2142-10')
      GROUP BY LEFT(j.LineMemo, CHARINDEX('_', j.LineMemo) - 1)
      HAVING SUM(CASE WHEN j.Account = '2142-10' THEN j.Debit ELSE 0 END) > 0
         AND SUM(CASE WHEN j.Account = '1134-01' THEN j.Debit - j.Credit ELSE 0 END) = 0
         AND SUM(CASE WHEN j.Account = '1135-01' THEN j.Debit ELSE 0 END) > 0
         AND COUNT(DISTINCT j.TransId) = 1
    )
    SELECT je.item, je.RefDate, je.wht_2142, i.U_ExpectedReceived, i.U_ActualReceived,
           i.U_WHTAmt, i.U_BatchRunDate, i.U_PaymentChannel
    FROM je
    JOIN [dbo].[@INSURANCE] i ON i.U_OrderItem = je.item
    WHERE i.U_ExpectedReceived = i.U_ActualReceived
      AND i.U_WHTAmt = je.wht_2142
      AND CAST(je.RefDate AS DATE) = CAST(i.U_BatchRunDate AS DATE)
    ORDER BY je.RefDate DESC
""")
rows = cur.fetchall()
print(f"clean, single-TransId, same-day, Expected=Actual, WHTAmt-matches examples: {len(rows)}")
for r in rows[:15]:
    print(r)

cur.close()
conn.close()

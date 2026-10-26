"""
The 3 confirmed TRUE misposting cases (card/gateway channel, company, Aug 2026) all have
anomalous U_ActualReceived (zero or negative) in @INSURANCE. Check whether this is a clean
discriminator: do any of the 183 correctly-posted orders also have zero/negative ActualReceived?
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
      SELECT DISTINCT
        LEFT(j.LineMemo, CHARINDEX('_', j.LineMemo) - 1) AS oi,
        o.TransId
      FROM JDT1 j
      JOIN OJDT o ON o.TransId = j.TransId
      JOIN [dbo].[@INSURANCE] i
        ON i.U_OrderItem = LEFT(j.LineMemo, CASE WHEN CHARINDEX('_', j.LineMemo) = 0 THEN LEN(j.LineMemo) ELSE CHARINDEX('_', j.LineMemo) - 1 END)
      WHERE j.LineMemo LIKE '%-V[0-9]%' AND CHARINDEX('_', j.LineMemo) > 0
        AND o.RefDate >= '2026-08-01' AND o.RefDate < '2026-08-22'
        AND (i.U_Title = '' OR i.U_Title IS NULL)
        AND (i.U_PaymentChannel LIKE 'RCB-EDC-%' OR i.U_PaymentChannel LIKE 'RCB-Omise%')
    ),
    agg AS (
      SELECT
        ol.oi, ol.TransId,
        SUM(CASE WHEN j.Account = '1134-01' THEN j.Debit - j.Credit ELSE 0 END) AS net_1134,
        SUM(CASE WHEN j.Account = '1135-01' THEN j.Debit - j.Credit ELSE 0 END) AS net_1135
      FROM ol
      JOIN JDT1 j ON CHARINDEX('_', j.LineMemo) > 0 AND LEFT(j.LineMemo, CHARINDEX('_', j.LineMemo) - 1) = ol.oi
      WHERE j.Account IN ('1134-01', '1135-01')
      GROUP BY ol.oi, ol.TransId
    )
    SELECT
      agg.oi,
      CASE WHEN agg.net_1135 > 0 THEN 'CORRECT' ELSE 'WRONG' END AS bucket,
      i.U_ActualReceived,
      i.U_ExpectedReceived
    FROM agg
    JOIN [dbo].[@INSURANCE] i ON i.U_OrderItem = agg.oi
""")
rows = cur.fetchall()
correct = [r for r in rows if r.bucket == 'CORRECT']
wrong = [r for r in rows if r.bucket == 'WRONG']

correct_anomalous = [r for r in correct if float(r.U_ActualReceived) <= 0]
wrong_anomalous = [r for r in wrong if float(r.U_ActualReceived) <= 0]

print(f"CORRECT total: {len(correct)}, with ActualReceived<=0: {len(correct_anomalous)}")
print(f"WRONG total: {len(wrong)}, with ActualReceived<=0: {len(wrong_anomalous)}")
print("\nCORRECT anomalous examples:", correct_anomalous[:5])
print("WRONG examples:", wrong)

cur.close()
conn.close()

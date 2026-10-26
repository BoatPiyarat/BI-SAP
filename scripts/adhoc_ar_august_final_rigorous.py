"""
FINAL rigorous pass, scoped to August 2026 company customers, restricted to card/gateway payment
channels only (RCB-EDC-*, RCB-Omise Credit Card-*, RCB-Omise QR Prompt Pay-*) - the only channels
where 1135-01 is even the structurally-correct target account. Transfer/Credit-Shell channels are
excluded because they never touch 1135-01 by design (bank transfer has no card/gateway leg), so
comparing them against 1135-01 was a category error in earlier analysis. SELECT only.
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
      CASE WHEN net_1135 > 0 THEN 'has_1135_full' ELSE 'NO_1135_true_misposting' END AS bucket,
      COUNT(*) AS n,
      SUM(net_1134) AS total_net_1134
    FROM agg
    GROUP BY CASE WHEN net_1135 > 0 THEN 'has_1135_full' ELSE 'NO_1135_true_misposting' END
""")
for row in cur.fetchall():
    print(row)

print("\n=== the TRUE misposting list (card/gateway channel, company, Aug 2026, no 1135-01 line at all) ===")
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
    SELECT oi, TransId, net_1134, net_1135 FROM agg WHERE net_1135 <= 0 AND net_1134 > 500
    ORDER BY net_1134 DESC
""")
for row in cur.fetchall():
    print(row)

cur.close()
conn.close()

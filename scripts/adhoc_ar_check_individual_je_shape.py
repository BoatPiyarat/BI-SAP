import os
import pyodbc

USER = os.environ["RCB_DB_USER"]
PASSWORD = os.environ["RCB_DB_PASSWORD"]
conn_str = f"DRIVER={{SQL Server}};SERVER=172.25.25.3,1433;DATABASE=RCB_LIVE_DB;UID={USER};PWD={PASSWORD};"
conn = pyodbc.connect(conn_str, timeout=30)
cur = conn.cursor()

# individual-title order confirmed isCompany=false earlier
cur.execute("""
    SELECT j.Account, a.AcctName, j.Debit, j.Credit, o.RefDate, j.TransId, j.Line_ID
    FROM JDT1 j
    LEFT JOIN OACT a ON a.AcctCode = j.Account
    LEFT JOIN OJDT o ON o.TransId = j.TransId
    WHERE j.LineMemo LIKE 'L78636974-V%'
    ORDER BY o.RefDate, j.TransId, j.Line_ID
""")
print("=== L78636974-V* (individual, isCompany=false, from earlier check) ===")
for row in cur.fetchall():
    print(row)

# also check: how many DISTINCT JE-line-count "shapes" exist overall for 1134-01-touching V items, split by company/individual
cur.execute("""
    WITH linecounts AS (
      SELECT
        LEFT(j.LineMemo, CHARINDEX('_', j.LineMemo) - 1) AS oi,
        o.TransId,
        COUNT(*) AS n_lines,
        SUM(CASE WHEN j.Account = '2142-10' THEN 1 ELSE 0 END) AS has_wht_variance
      FROM JDT1 j
      JOIN OJDT o ON o.TransId = j.TransId
      WHERE j.LineMemo LIKE '%-V[0-9]%' AND CHARINDEX('_', j.LineMemo) > 0
        AND o.RefDate >= '2026-08-01' AND o.RefDate < '2026-08-22'
      GROUP BY LEFT(j.LineMemo, CHARINDEX('_', j.LineMemo) - 1), o.TransId
    )
    SELECT n_lines, has_wht_variance, COUNT(*) FROM linecounts
    GROUP BY n_lines, has_wht_variance
    ORDER BY n_lines
""")
print("\n=== JE line-count shape distribution, all V-items, Aug 2026 ===")
for row in cur.fetchall():
    print(row)

cur.close()
conn.close()

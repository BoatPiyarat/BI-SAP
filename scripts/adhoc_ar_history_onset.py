"""
Find the historical onset: when did Voluntary (-V) items start posting to 1134-01 instead of
1135-01? Pull the earliest/latest RefDate per (item-suffix-letter, Account) across the FULL JE
history (not scoped to August), to see whether this is a longstanding pattern or a recent
regression. SELECT only.
"""
import os
import re
import pyodbc

USER = os.environ["RCB_DB_USER"]
PASSWORD = os.environ["RCB_DB_PASSWORD"]
conn_str = f"DRIVER={{SQL Server}};SERVER=172.25.25.3,1433;DATABASE=RCB_LIVE_DB;UID={USER};PWD={PASSWORD};"
conn = pyodbc.connect(conn_str, timeout=60)
cur = conn.cursor()

# table size sanity check first (cheap)
cur.execute("SELECT COUNT(*) FROM JDT1 WHERE Account IN ('1134-01','1135-01')")
print("row count JDT1 (1134/1135 only):", cur.fetchone()[0])

cur.execute("""
    SELECT MIN(o.RefDate), MAX(o.RefDate) FROM JDT1 j
    JOIN OJDT o ON o.TransId = j.TransId
    WHERE j.Account IN ('1134-01','1135-01')
""")
print("overall RefDate range for 1134/1135:", cur.fetchone())

# Earliest/latest per account, for lines whose LineMemo looks like an OrderItem with -V or -M suffix
cur.execute("""
    SELECT
      CASE WHEN j.LineMemo LIKE '%-M[0-9]%' THEN 'M'
           WHEN j.LineMemo LIKE '%-V[0-9]%' THEN 'V'
           ELSE 'OTHER' END AS item_type,
      j.Account,
      MIN(o.RefDate) AS earliest,
      MAX(o.RefDate) AS latest,
      COUNT(*) AS n
    FROM JDT1 j
    JOIN OJDT o ON o.TransId = j.TransId
    WHERE j.Account IN ('1134-01','1135-01') AND j.Debit > 0
    GROUP BY
      CASE WHEN j.LineMemo LIKE '%-M[0-9]%' THEN 'M'
           WHEN j.LineMemo LIKE '%-V[0-9]%' THEN 'V'
           ELSE 'OTHER' END,
      j.Account
    ORDER BY item_type, j.Account
""")
print("\n=== earliest/latest RefDate by item_type x account (debit lines only) ===")
for row in cur.fetchall():
    print(row)

cur.close()
conn.close()

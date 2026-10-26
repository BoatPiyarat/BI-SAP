import os
import pyodbc

USER = os.environ["RCB_DB_USER"]
PASSWORD = os.environ["RCB_DB_PASSWORD"]
conn_str = f"DRIVER={{SQL Server}};SERVER=172.25.25.3,1433;DATABASE=RCB_LIVE_DB;UID={USER};PWD={PASSWORD};"
conn = pyodbc.connect(conn_str, timeout=30)
cur = conn.cursor()

for oi in ['L80407119-V1', 'L78771994-V1', 'L78879036-V1']:
    print(f"\n=== {oi} : full JE ===")
    cur.execute("""
        SELECT j.Account, a.AcctName, j.Debit, j.Credit, o.RefDate, j.TransId, j.Line_ID
        FROM JDT1 j
        LEFT JOIN OACT a ON a.AcctCode = j.Account
        LEFT JOIN OJDT o ON o.TransId = j.TransId
        WHERE j.LineMemo LIKE ?
        ORDER BY o.RefDate, j.TransId, j.Line_ID
    """, f"{oi}_%")
    for row in cur.fetchall():
        print(row)

cur.close()
conn.close()

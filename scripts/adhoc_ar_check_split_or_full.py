"""
Critical check: for orders where the 1134-01 debit looked small (~1% of ActualReceived, WHT-sized),
does the SAME order also have a 1135-01 line for the bulk amount (meaning 1134-01 is being used
correctly as a small WHT-clearing/variance line, not a full misposting)? Or is there no 1135-01
line at all (meaning the bulk amount is genuinely missing/misposted elsewhere)? Check a handful of
concrete examples from the monthly sample. SELECT only.
"""
import os
import pyodbc

USER = os.environ["RCB_DB_USER"]
PASSWORD = os.environ["RCB_DB_PASSWORD"]
conn_str = f"DRIVER={{SQL Server}};SERVER=172.25.25.3,1433;DATABASE=RCB_LIVE_DB;UID={USER};PWD={PASSWORD};"
conn = pyodbc.connect(conn_str, timeout=30)
cur = conn.cursor()

examples = ['L77760142-V1', 'L78795317-V1', 'L77603344-V1', 'L78399012-V1', 'L78641085-V1']

for oi in examples:
    print(f"\n=== {oi} : ALL JDT1 debit/credit lines to any account, not just 1134/1135 ===")
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

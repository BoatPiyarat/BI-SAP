import os
import csv
import pyodbc

USER = os.environ["RCB_DB_USER"]
PASSWORD = os.environ["RCB_DB_PASSWORD"]
conn_str = f"DRIVER={{SQL Server}};SERVER=172.25.25.3,1433;DATABASE=RCB_LIVE_DB;UID={USER};PWD={PASSWORD};"
conn = pyodbc.connect(conn_str, timeout=60)
cur = conn.cursor()

ITEMS = """L78667850-V2,L78718741-V2,L80544554-V2,L78627148-V2,L78654214-V2,L78825767-V2,L78651200-V2,L78734195-V2,
L78751566-V2,L78759207-V2,L78836201-V2,L78547453-V2,L78646885-V2,L78731512-V2,L78744150-V2,L78800163-V2,
L78810593-V2,L78620491-V2,L78714081-V2,L78706510-V2,L78814855-V2,L78667839-V2,L78703129-V2,L78714461-V2""".replace("\n", "").split(",")
ITEMS = [x.strip() for x in ITEMS if x.strip()]

cur.execute(f"""
    SELECT j.LineMemo, j.Account, a.AcctName, j.Debit, j.Credit, o.RefDate, j.TransId
    FROM JDT1 j
    LEFT JOIN OACT a ON a.AcctCode = j.Account
    LEFT JOIN OJDT o ON o.TransId = j.TransId
    WHERE ({" OR ".join(["j.LineMemo LIKE ?" for _ in ITEMS])})
    ORDER BY j.LineMemo, j.Line_ID
""", [f"{it}_%" for it in ITEMS])
rows = cur.fetchall()
print(f"any-account JE lines found for 24-item sample: {len(rows)}")
for r in rows[:60]:
    print(r)

cur.close()
conn.close()

"""
Pui reports the same orders, now re-interfaced as -V2/-M2 item suffixes. Check whether the account
code posted correctly (1135-01) this time, or whether it's still landing on 1134-01. SELECT only.
"""
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
L78810593-V2,L78620491-V2,L78714081-V2,L78706510-V2,L78814855-V2,L78667839-V2,L78703129-V2,L78714461-V2,
L78717818-V2,L78795358-V2,L80391981-V2,L78614447-V2,L78677072-V2,L78678557-V2,L78743551-V2,L78756478-V2,
L78807719-V2,L80512637-V2,L78755505-V2,L78763080-V2,L78601967-V2,L78763422-V2,L80557168-V2,L78615473-V2,
L78732191-V2,L78771541-V2,L78818315-V2,L80402389-V2,L80561597-V2,L80561716-V2,L80556911-V2,L78722782-V2,
L78711654-V2,L78734117-V2,L78781395-V2,L80569003-V2,L78242486-V2,L78765007-V2,L78681437-V2,L78687447-V2,
L78702707-V2,L78733657-V2,L78755560-V2,L78684050-V2,L80569001-V2,L78849805-V2,L78702562-V2,L78703619-V2,
L78738064-V2,L78751291-V2,L80570943-V2,L78478651-V2,L78756227-V2,L78833147-V2,L78862761-V2,L78871824-V2,
L80580491-V2,L78765176-V2,L80568956-V2,L78724278-V2,L78761222-V2,L80586903-V2,L78605728-V2,L78755473-V2,
L80543404-V2,L78792818-V2,L80546815-V2,L78760721-V2,L78632191-V2,L78593580-V2,L78755597-V2,L78758780-V2,
L78700804-V2,L78754798-V2,L78755483-V2,L78833158-V2,L80616959-V2,L78754788-V2,L78708635-V2,L78738326-V2,
L78744077-V2,L78745610-V2,L79000663-V2,L78733632-V2,L78738696-V2,L78821771-V2,L78599289-V2,L78751654-V2,
L78755696-V2,L80617742-M2,L80625366-V2,L78751314-V2,L78759553-V2,L78771773-V2,L78782238-V2,L80569506-V2,
L80613305-V2,L78833631-V2,L78533160-V2,L78706070-V2,L78756538-V2,L78672821-V2,L80616875-V2,L78525515-V2,
L78771825-V2,L78782122-V2,L78784495-V2,L78692913-V2,L78753526-V2,L78755514-V2,L80624528-M2,L80637933-M2,
L78822322-V2,L78771946-V2,L78784734-V2,L80427627-V2,L80624143-V2,L78881733-V2,L78678543-V2,L78809920-V2,
L78687385-V2,L78733984-V2,L80597383-V2,L80691957-M2""".replace("\n", "").split(",")
ITEMS = [x.strip() for x in ITEMS if x.strip()]
print(f"total items requested: {len(ITEMS)}")

placeholders = ",".join("?" for _ in ITEMS)
cur.execute(f"""
    SELECT j.LineMemo, j.Account, a.AcctName, j.Debit, j.Credit, o.RefDate, j.TransId
    FROM JDT1 j
    LEFT JOIN OACT a ON a.AcctCode = j.Account
    LEFT JOIN OJDT o ON o.TransId = j.TransId
    WHERE j.Account IN ('1134-01','1135-01')
      AND ({" OR ".join(["j.LineMemo LIKE ?" for _ in ITEMS])})
""", ITEMS)
rows = cur.fetchall()
print(f"JE lines found (1134/1135 only): {len(rows)}")

out_path = r"C:\Users\Developer\OneDrive - Rabbit Internet\Documents\03 Project - Partner\02 SAP\Phase1.1\agentic_bootstrap\tmp_v2_reinterface_check.csv"
with open(out_path, "w", newline="", encoding="utf-8-sig") as f:
    w = csv.writer(f)
    w.writerow(["LineMemo", "Account", "AcctName", "Debit", "Credit", "RefDate", "TransId"])
    for r in rows:
        w.writerow(list(r))
print(f"written to {out_path}")

# which requested items have ANY JE line at all (in @INSURANCE / JDT1 broadly)?
placeholders_like = " OR ".join(["i.U_OrderItem = ?" for _ in ITEMS])
cur.execute(f"""
    SELECT U_OrderItem, U_ExpectedReceived, U_ActualReceived, U_TotalAmount, U_BatchRunDate
    FROM [dbo].[@INSURANCE] i
    WHERE {placeholders_like}
""", ITEMS)
insurance_rows = cur.fetchall()
print(f"\n@INSURANCE rows found: {len(insurance_rows)}")
out_path2 = r"C:\Users\Developer\OneDrive - Rabbit Internet\Documents\03 Project - Partner\02 SAP\Phase1.1\agentic_bootstrap\tmp_v2_insurance_check.csv"
with open(out_path2, "w", newline="", encoding="utf-8-sig") as f:
    w = csv.writer(f)
    w.writerow(["OrderItem", "ExpectedReceived", "ActualReceived", "TotalAmount", "BatchRunDate"])
    for r in insurance_rows:
        w.writerow(list(r))
print(f"written to {out_path2}")

cur.close()
conn.close()

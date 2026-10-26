"""
This is the "82 not found in JE" subset of the original 224-order list flagged by Pui. Check what
state they're in now: do they exist in @INSURANCE at all? Any JE lines at all (any account)?
SELECT only.
"""
import os
import csv
import pyodbc

USER = os.environ["RCB_DB_USER"]
PASSWORD = os.environ["RCB_DB_PASSWORD"]
conn_str = f"DRIVER={{SQL Server}};SERVER=172.25.25.3,1433;DATABASE=RCB_LIVE_DB;UID={USER};PWD={PASSWORD};"
conn = pyodbc.connect(conn_str, timeout=60)
cur = conn.cursor()

ORDER_IDS = """L79195511,L78714047,L80613571,L78628442,L78637454,L78792160,L79015255,L78748349,
L78759564,L78846575,L78625146,L78643267,L78747985,L78807595,L78991525,L79663641,
L77345647,L78821726,L80629921,L80652157,L80656585,L80662792,L78903861,L78475128,
L78758626,L78776033,L78791146,L78839900,L80664175,L78738836,L78791945,L78848508,
L78856527,L80672218,L78723346,L78772029,L78783299,L78844455,L78913151,L80648796,
L80671966,L80672208,L80661724,L80581406,L78734118,L78787330,L78803542,L78831654,
L78842846,L78882186,L80511602,L78714370,L78748814,L78771818,L78771819,L78786538,
L78786751,L78828290,L79657780,L80520162,L80552406,L80645388,L80650542,L80672197,
L78734206,L78771885,L80625890,L80688112,L80691070,L78745527,L78759985,L78776248,
L80688560,L78680587,L78763114,L78764563,L78784751,L80692050,L78750358,L78807891,
L80531214,L80681863,L78666996,L80518964""".replace("\n", "").split(",")
ORDER_IDS = [o.strip() for o in ORDER_IDS if o.strip()]
print(f"total order IDs: {len(ORDER_IDS)}")

placeholders = ",".join("?" for _ in ORDER_IDS)
cur.execute(f"""
    SELECT U_OrderId, U_OrderItem, U_ExpectedReceived, U_ActualReceived, U_TotalAmount,
           U_WHTAmt, U_PaymentMethod, U_PaymentChannel, U_BatchRunDate, U_PaymentStatus,
           U_SubmissionStatus, U_ApprovalStatus
    FROM [dbo].[@INSURANCE]
    WHERE U_OrderId IN ({placeholders})
    ORDER BY U_OrderId, U_OrderItem
""", ORDER_IDS)
rows = cur.fetchall()
print(f"@INSURANCE rows found: {len(rows)}")

found_orderids = set(r.U_OrderId for r in rows)
missing_entirely = [o for o in ORDER_IDS if o not in found_orderids]
print(f"OrderIDs with ZERO @INSURANCE rows at all: {len(missing_entirely)}")
print(missing_entirely)

out_path = r"C:\Users\Developer\OneDrive - Rabbit Internet\Documents\03 Project - Partner\02 SAP\Phase1.1\agentic_bootstrap\tmp_82_group_insurance.csv"
with open(out_path, "w", newline="", encoding="utf-8-sig") as f:
    w = csv.writer(f)
    w.writerow(["OrderId","OrderItem","ExpectedReceived","ActualReceived","TotalAmount","WHTAmt",
                "PaymentMethod","PaymentChannel","BatchRunDate","PaymentStatus","SubmissionStatus","ApprovalStatus"])
    for r in rows:
        w.writerow(list(r))
print(f"written to {out_path}")

cur.close()
conn.close()

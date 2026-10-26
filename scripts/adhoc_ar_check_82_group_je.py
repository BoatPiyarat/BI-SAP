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

placeholders = " OR ".join(["j.LineMemo LIKE ?" for _ in ORDER_IDS])
cur.execute(f"""
    SELECT
      LEFT(j.LineMemo, CHARINDEX('_', j.LineMemo) - 1) AS item,
      j.Account, j.Debit, j.Credit
    FROM JDT1 j
    WHERE ({placeholders}) AND j.Account IN ('1134-01','1135-01')
""", [f"{it}-%" for it in ORDER_IDS])
rows = cur.fetchall()
print(f"1134/1135 JE lines found: {len(rows)}")

by_item = {}
for item, acct, debit, credit in rows:
    by_item.setdefault(item, {})[acct] = by_item.get(item, {}).get(acct, 0) + float(debit) - float(credit)

correct = sum(1 for v in by_item.values() if v.get('1135-01', 0) > 0 and v.get('1134-01', 0) == 0)
wrong = sum(1 for v in by_item.values() if v.get('1134-01', 0) != 0)
print(f"items with any 1134/1135 line: {len(by_item)}")
print(f"correct (1135-01 only, no 1134-01): {correct}")
print(f"still has 1134-01 nonzero: {wrong}")
for item, v in by_item.items():
    if v.get('1134-01', 0) != 0:
        print("WRONG:", item, v)

cur.close()
conn.close()

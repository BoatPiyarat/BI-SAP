"""Read-only: do the RCL CreditShell orders have journal entries in SAP RAB and SAP RCL?

Searches OJDT/JDT1 in every company DB on the SAP server whose name looks like RCB/RCL, matching the
order id in JDT1.LineMemo/Ref1/Ref2/Ref3Line and OJDT.Memo/Ref1/Ref2/Ref3.
Needs WireGuard up and RCB_DB_USER / RCB_DB_PASSWORD set.

Usage:
  python -I scripts/adhoc_rcl_creditshell_je_check_20261019.py              # the 10 reported orders
  python -I scripts/adhoc_rcl_creditshell_je_check_20261019.py --csv FILE   # OrderID column of a CSV
"""
import argparse
import csv
import os

import pyodbc

ORDERS = ["L81019162", "L81021191", "L81025264", "L81025633", "L81025701",
          "L81025704", "L81025975", "L81027931", "L81027939", "L81028493"]

parser = argparse.ArgumentParser()
parser.add_argument("--csv")
parser.add_argument("--out", default="rcl_creditshell_je_check_20261019.csv")
args = parser.parse_args()
if args.csv:
    with open(args.csv, encoding="utf-8-sig") as f:
        ORDERS = sorted({r["OrderID"] for r in csv.DictReader(f)})

USER = os.environ["RCB_DB_USER"]
PASSWORD = os.environ["RCB_DB_PASSWORD"]
BASE = f"DRIVER={{SQL Server}};SERVER=172.25.25.3,1433;UID={USER};PWD={PASSWORD};"

master = pyodbc.connect(BASE + "DATABASE=master;", timeout=60)
dbs = [r[0] for r in master.cursor().execute(
    "SELECT name FROM sys.databases WHERE name LIKE '%RCB%' OR name LIKE '%RCL%' OR name LIKE '%RAB%'")]
master.close()
print("company DBs found:", dbs)

SQL = """
SELECT ? AS order_id, h.TransId, h.TransType, h.RefDate, h.Memo, h.Ref1, h.Ref2,
       l.Line_ID, l.Account, a.AcctName, l.Debit, l.Credit, l.LineMemo, l.Ref1 AS LRef1, l.Ref2 AS LRef2
FROM JDT1 l
JOIN OJDT h ON h.TransId = l.TransId
LEFT JOIN OACT a ON a.AcctCode = l.Account
WHERE h.RefDate >= '2026-09-01'
  AND h.TransId IN (
    SELECT l2.TransId FROM JDT1 l2
    WHERE l2.LineMemo LIKE ? OR l2.Ref1 LIKE ? OR l2.Ref2 LIKE ? OR l2.Ref3Line LIKE ?
    UNION
    SELECT h2.TransId FROM OJDT h2
    WHERE h2.Memo LIKE ? OR h2.Ref1 LIKE ? OR h2.Ref2 LIKE ? OR h2.Ref3 LIKE ?)
ORDER BY h.TransId, l.Line_ID
"""

rows_out, summary = [], {}
for db in dbs:
    try:
        conn = pyodbc.connect(BASE + f"DATABASE={db};", timeout=120)
    except pyodbc.Error as e:
        print(f"{db}: cannot connect ({e.args[0]})")
        continue
    cur = conn.cursor()
    for order in ORDERS:
        pat = f"%{order}%"
        cur.execute(SQL, [order] + [pat] * 8)
        hits = cur.fetchall()
        summary[(db, order)] = len({r.TransId for r in hits})
        for r in hits:
            rows_out.append([db, order, r.TransId, r.TransType, r.RefDate, r.Memo, r.Ref1, r.Ref2,
                             r.Line_ID, r.Account, r.AcctName, float(r.Debit), float(r.Credit),
                             r.LineMemo, r.LRef1, r.LRef2])
    conn.close()

print("\nJE count (distinct TransId, RefDate >= 2026-09-01) per order:")
print("order".ljust(12) + "".join(db.ljust(16) for db in dbs))
for order in ORDERS:
    print(order.ljust(12) + "".join(str(summary.get((db, order), "n/a")).ljust(16) for db in dbs))

with open(args.out, "w", newline="", encoding="utf-8-sig") as f:
    w = csv.writer(f)
    w.writerow(["db", "order_id", "TransId", "TransType", "RefDate", "Memo", "Ref1", "Ref2", "Line_ID",
                "Account", "AcctName", "Debit", "Credit", "LineMemo", "LineRef1", "LineRef2"])
    w.writerows(rows_out)
print(f"\nJE lines written to {args.out} ({len(rows_out)} lines)")

"""Read-only: compare RCB_LIVE_DB.[@INSURANCE] row shapes of the 10 RCL-missing orders against
Motor V1 RCL CreditShell orders (Oct 2026) that DID book RCL JEs. Needs RCB_DB_USER/RCB_DB_PASSWORD."""
import collections, csv, os, re
import pyodbc

E = "docs/evidence/rcl_creditshell_routed_to_rcb_20261019/"
rows = list(csv.DictReader(open(E + "je_status_205_items.csv", encoding="utf-8-sig")))
TARGET = [r["OrderID"] for r in rows if r["status"].startswith("RCL_NO")]
CONTROL = [r["OrderID"] for r in rows if r["status"] == "RCL_yes/RAB_yes" and r["OrderItem"].endswith("-V1")
           and r["first_batch"] >= "2026-10-01"]
B = f"DRIVER={{SQL Server}};SERVER=172.25.25.3,1433;UID={os.environ['RCB_DB_USER']};PWD={os.environ['RCB_DB_PASSWORD']};"
cur = pyodbc.connect(B + "DATABASE=RCB_LIVE_DB;", timeout=60).cursor()
ids = TARGET + CONTROL
cur.execute(f"SELECT * FROM [@INSURANCE] WHERE U_OrderID IN ({','.join('?'*len(ids))})", ids)
cols = [d[0] for d in cur.description]
data = [dict(zip(cols, r)) for r in cur.fetchall()]

SKIP_PII = {"U_FirstName", "U_LastName", "U_Title", "U_BillingAddress", "U_InsuredID", "U_ChassisNo", "U_LicensePlate"}
IDS = {"DocEntry", "DocNum", "U_OrderId", "U_OrderItem", "U_RefOrder", "U_PolicyNo", "LogInst", "U_JETransId"}

def shape(col, v, row):
    if v is None: return "NULL"
    if isinstance(v, str):
        if v.strip() == "": return "BLANK"
        if v == "NULL": return "'NULL'"
        if col == "U_InvoiceNo": return re.sub(r"[a-z0-9]{10,}$", "<id>", v)
        if col in SKIP_PII or col in IDS: return "<value>"
        return v if len(v) < 40 else "<text>"
    if hasattr(v, "year"):  # dates: relation to order date
        od = row.get("U_OrderDate")
        return "date=OrderDate" if od and v == od else ("date<OrderDate" if od and v < od else "date>OrderDate")
    if isinstance(v, (int, float)) or v.__class__.__name__ == "Decimal":
        if col in IDS or col in ("CreateTime", "UpdateTime", "UserSign", "Period"): return "<num>" if col not in ("UserSign",) else str(v)
        return "0" if float(v) == 0 else ("neg" if float(v) < 0 else "pos")
    return type(v).__name__

def seg(row):
    st = (row.get("U_PolicyStatus") or "").lower()
    return f"P1-{st}" if row.get("U_Period") == 1 else f"P2+-{st}"

stats = collections.defaultdict(lambda: {"T": collections.Counter(), "C": collections.Counter()})
for row in data:
    grp = "T" if row["U_OrderId"] in TARGET else "C"
    for c in cols:
        stats[(seg(row), c)][grp][shape(c, row[c], row)] += 1

print(f"target orders {len(TARGET)}, control orders {len(CONTROL)}, rows {len(data)}")
print(f"target rows {sum(r['U_OrderId'] in TARGET for r in data)}, control rows {sum(r['U_OrderId'] not in TARGET for r in data)}\n")
print("Columns where a target value-shape never appears in control (same segment):")
found = 0
for (sg, c), s in sorted(stats.items()):
    if c in ("CreateDate", "UpdateDate", "CreateTime", "UpdateTime"): continue
    new = {k: n for k, n in s["T"].items() if k not in s["C"]}
    if new:
        found += 1
        print(f"  [{sg}] {c}: target {dict(s['T'])} | control {dict(s['C'].most_common(6))}")
if not found: print("  none")

"""Offline static gate for DDL 103 and its exact 56-column human fallback."""

from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[1]
DDL = ROOT / "sql/ddl/103_v3_monthend_onetime_immutable_snapshot.sql"
OPERATOR = ROOT / "sql/operator/20260827_export_v3_monthend_onetime_snapshot.sql"


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(f"V3_MONTHEND_ONETIME_STATIC=FAIL: {message}")


ddl = DDL.read_text(encoding="utf-8")
operator = OPERATOR.read_text(encoding="utf-8")
combined = ddl + "\n" + operator

require(
    not re.search(r"CREATE\s+(?:OR\s+REPLACE\s+)?(?:TABLE|VIEW|PROCEDURE)\s+`pacific-plating-282708\.(?!sap_integration_v3\.)", ddl, re.I),
    "DDL target outside sap_integration_v3",
)
require(not re.search(r"SELECT\s+(?:DISTINCT\s+)?\*", combined, re.I), "wide SELECT * projection")
require("gs://" not in combined and "EXPORT DATA" not in combined.upper(), "file or GCS write present")
require("gcloud scheduler" not in combined.lower(), "scheduler command present")
require("DATE(e.charge_time,'Asia/Bangkok')" in ddl, "ICT payment-date classification missing")
require("DATE(e.charge_time)" not in ddl, "UTC DATE(charge_time) classification present")
require("'NOT_EXPORT_PENDING_TERMINAL_ACK'" in ddl, "PICKED_UP pending-ACK hold missing")
require("IN ('DELIVERED','PICKED_UP')" in ddl, "delivered/picked-up lifecycle branch missing")
require("'NOT_EXPORT_TERMINAL_ACKNOWLEDGED'" in ddl, "terminal ACK branch missing")
require("BEGIN TRANSACTION" in ddl and "COMMIT TRANSACTION" in ddl, "atomic snapshot transaction missing")
for object_name in (
    "v3_monthend_onetime_payload",
    "v3_monthend_onetime_identity",
    "v3_monthend_onetime_hold",
    "v3_monthend_onetime_manifest",
):
    require(object_name in ddl, f"durable object missing: {object_name}")
require("source_event_count" in ddl and "payload_count" in ddl and "hold_count" in ddl,
        "manifest population conservation fields missing")
require("Every event must end in the immutable payload or durable hold" in ddl,
        "build-time population conservation assertion missing")
require("TO_JSON_STRING(STRUCT(" in ddl and "payload_hash" in ddl,
        "exact positional payload hash missing")
require("scripts/bq_safe_query.sh" in operator and "Never use direct `bq query`" in operator,
        "mandatory safe-query operator instruction missing")
require("REPLACE_WITH_REVIEWED_SNAPSHOT_RUN_ID" in operator, "fail-closed run sentinel missing")
require("DATE(built_at)=target_snapshot_date" in operator, "payload/identity partition filter missing")
require("DATE(detected_at)=target_snapshot_date" in operator, "hold partition filter missing")
require("p.payload_hash!=TO_HEX(SHA256(TO_JSON_STRING(STRUCT(" in operator,
        "operator does not recompute exact payload hash")

final_select = re.search(r"\nSELECT CompanyDB,(.*?)\nFROM _target_payload", operator, re.S | re.I)
require(final_select is not None, "final immutable export SELECT missing")
columns = ["CompanyDB"] + [
    column.strip() for column in final_select.group(1).replace("\n", " ").split(",")
]
require(len(columns) == 56, f"final export has {len(columns)} columns, expected 56")
require(columns[:4] == ["CompanyDB", "OrderID", "OrderItem", "InvoiceNo"],
        "final export prefix differs from contract")
require(columns[-4:] == ["RefundAmountBeforeFee", "RefundAmountAfterFee", "BillingAddress", "BatchRunDate"],
        "final export suffix differs from contract")

print("V3_MONTHEND_ONETIME_STATIC=PASS")
print("V3_MONTHEND_ONETIME_EXPORT_COLUMNS=56")

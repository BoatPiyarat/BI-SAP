#!/usr/bin/env python3
"""Static regression guard for Unit 5 whole-item required-value quarantine."""

import argparse
import re
import subprocess
from pathlib import Path


parser = argparse.ArgumentParser()
parser.add_argument("--git-ref", help="check the DDL at a historical git ref")
args = parser.parse_args()

ddl_path = "sql/ddl/058_v3_unit5_newpayment_shadow.sql"
if args.git_ref:
    result = subprocess.run(
        ["git", "show", f"{args.git_ref}:{ddl_path}"],
        check=True,
        capture_output=True,
        text=True,
        encoding="utf-8",
    )
    ddl = result.stdout
else:
    ddl = Path(ddl_path).read_text(encoding="utf-8")

required_tokens = (
    "v3_unit5_candidate_required_hold",
    "_candidate_validation_issue",
    "_candidate_required_hold",
    "HOLD_SPINE_PREEXPORT_VALIDATION",
    "REQUIRED_VALUE_NULL_OR_LITERAL_NULL",
    "PAID_REQUIRED_FIELD_BLANK",
    "POLICYNO_TOO_LONG",
    "SPINE_INCOMPLETE",
    "DUPLICATE_PERIOD_INVOICE_IDENTITY",
    "DATE_FORMAT_INVALID",
    "_candidate_release",
    "Released plus validation-held NEWPAYMENT items do not conserve",
    "Released NEWPAYMENT item still has a validation issue",
    "FROM _candidate_release c) s",
    "WHERE EXISTS (SELECT 1 FROM _candidate_release q WHERE q.OrderItem=c.OrderItem)",
)
missing = [required for required in required_tokens if required not in ddl]
if missing:
    raise SystemExit(f"RED: missing whole-item quarantine token: {missing[0]}")

unsafe_abort = (
    "ASSERT (SELECT COUNT(*) FROM _candidate c\n"
    "    WHERE REGEXP_CONTAINS(TO_JSON_STRING(c),r':null|:\"NULL\"'))=0"
)
unsafe_candidate_aborts = (
    unsafe_abort,
    "AS 'NEWPAYMENT full period spine is incomplete'",
    "AS 'NEWPAYMENT status must be exactly Paid or Pending'",
    "AS 'NEWPAYMENT full period spine has duplicate identities'",
    "AS 'POLICYNO_TOO_LONG in NEWPAYMENT candidate'",
    "AS 'Paid completeness failed'",
)
if any(token in ddl for token in unsafe_candidate_aborts):
    raise SystemExit("RED: item-level validation still aborts unrelated clean items")
if re.search(r"\bSELECT\s+(?:DISTINCT\s+)?\*", ddl, flags=re.IGNORECASE):
    raise SystemExit("RED: wide SELECT-star projection remains in DDL 058")

issue_build = ddl.index("CREATE TEMP TABLE _candidate_validation_issue")
hold_build = ddl.index("CREATE TEMP TABLE _candidate_required_hold", issue_build)
release_build = ddl.index("CREATE TEMP TABLE _candidate_release", hold_build)
transaction = ddl.index("BEGIN TRANSACTION;", release_build)
hold_insert = ddl.index(
    "INSERT INTO `pacific-plating-282708.sap_integration_v3.v3_unit5_candidate_required_hold`",
    transaction,
)
ready_insert = ddl.index(
    "INSERT INTO `pacific-plating-282708.sap_integration_v3.v3_unit5_newpayment_ready`",
    transaction,
)
commit = ddl.index("COMMIT TRANSACTION;", transaction)
if not issue_build < hold_build < release_build < transaction < hold_insert < ready_insert < commit:
    raise SystemExit("RED: hold and release are not atomically published in safe order")

print("V3_UNIT5_REQUIRED_HOLD_STATIC=PASS")

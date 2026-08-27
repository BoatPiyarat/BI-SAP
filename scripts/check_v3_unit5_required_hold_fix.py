#!/usr/bin/env python3
"""Static regression guard for Unit 5 whole-item required-value quarantine."""

import argparse
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
    "_candidate_required_hold",
    "HOLD_SPINE_REQUIRED_VALUE_INVALID",
    "ARRAY_AGG(DISTINCT field_name ORDER BY field_name)",
    "_candidate_release",
    "Released plus required-value-held NEWPAYMENT items do not conserve",
    "FROM _candidate_release c) s",
    "SELECT * FROM _candidate_release;",
    "WHERE EXISTS (SELECT 1 FROM _candidate_release q WHERE q.OrderItem=c.OrderItem)",
)
missing = [required for required in required_tokens if required not in ddl]
if missing:
    raise SystemExit(f"RED: missing whole-item quarantine token: {missing[0]}")

unsafe_abort = (
    "ASSERT (SELECT COUNT(*) FROM _candidate c\n"
    "    WHERE REGEXP_CONTAINS(TO_JSON_STRING(c),r':null|:\"NULL\"'))=0"
)
if unsafe_abort in ddl:
    raise SystemExit("RED: candidate-wide NULL assertion still aborts unrelated clean items")

release_build = ddl.index("CREATE TEMP TABLE _candidate_release")
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
if not transaction < hold_insert < ready_insert < commit:
    raise SystemExit("RED: hold and release are not atomically published in safe order")

print("V3_UNIT5_REQUIRED_HOLD_STATIC=PASS")

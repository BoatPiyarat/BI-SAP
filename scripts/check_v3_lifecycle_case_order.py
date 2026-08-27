"""Fail if the lifecycle view can hide multiple terminal SAP LogIDs as pending."""

from pathlib import Path


DDL = Path(__file__).parents[1] / "sql" / "ddl" / "100_v3_scenario3_archive_and_lifecycle.sql"
source = DDL.read_text(encoding="utf-8")

cardinality_guard = source.index("WHEN ARRAY_LENGTH(IFNULL(terminal_log_ids")
unsafe_broad_branch = source.find("WHEN terminal_import_rows != 1")
zero_import_pending = source.find("WHEN terminal_import_rows = 0")

if unsafe_broad_branch != -1 and unsafe_broad_branch < cardinality_guard:
    raise SystemExit(
        "RED: distinct-LogID blocker is unreachable because the broad terminal-import "
        "branch comes first"
    )

if zero_import_pending == -1:
    raise SystemExit("RED: zero terminal imports do not have an explicit pending branch")

print("PASS: distinct-LogID cardinality is blocked before the zero-import pending state")

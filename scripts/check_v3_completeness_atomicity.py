"""Fail if the daily-completeness snapshot can leave replayable partial evidence."""

from pathlib import Path


DDL = Path(__file__).parents[1] / "sql" / "ddl" / "067_v3_daily_completeness_snapshot.sql"
source = DDL.read_text(encoding="utf-8")

first_metric_insert = source.index("INSERT INTO `pacific-plating-282708.sap_integration_v3.v3_daily_completeness_metric`")
evidence_insert = source.index("INSERT INTO `pacific-plating-282708.sap_integration_v3.v3_daily_completeness_evidence`")
run_insert = source.index("INSERT INTO `pacific-plating-282708.sap_integration_v3.v3_daily_completeness_run`")
transaction_begin = source.rfind("BEGIN TRANSACTION;", 0, first_metric_insert)
transaction_commit = source.find("COMMIT TRANSACTION;", run_insert)

required_partial_guards = (
    "completeness metric rows already exist; immutable replay refused",
    "completeness evidence rows already exist; immutable replay refused",
)

if transaction_begin == -1 or transaction_commit == -1:
    raise SystemExit("RED: the three completeness inserts are not one transaction")
if not (transaction_begin < first_metric_insert < evidence_insert < run_insert < transaction_commit):
    raise SystemExit("RED: the completeness transaction does not enclose all three inserts")
for guard in required_partial_guards:
    if guard not in source:
        raise SystemExit(f"RED: missing partial-replay guard: {guard}")

print("PASS: completeness metric, evidence, and run inserts are atomic and replay-guarded")

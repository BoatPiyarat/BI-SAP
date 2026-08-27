#!/usr/bin/env python3
"""Static fail-closed checks for the fresh delivery-disabled Units 1-5 operator."""

from pathlib import Path


runner = Path("scripts/run_v3_fresh_units1_5_delivery_disabled.ps1").read_text(encoding="utf-8")
flags = Path("scripts/v3_fresh_units1_5_delivery_disabled.flags.yaml").read_text(encoding="utf-8")
preflight = Path("sql/operator/20260827_preflight_fresh_v3_units1_5_pilot_v1.sql").read_text(
    encoding="utf-8"
)
report = Path("sql/operator/20260827_report_fresh_v3_units1_5_pilot_v1.sql").read_text(
    encoding="utf-8"
)

for required in (
    "$ErrorActionPreference = 'Stop'",
    "Set-StrictMode -Version Latest",
    "[ValidatePattern('^Boat-chat-[A-Za-z0-9._-]+$')]",
    "[switch]$PreflightOnly",
    "-not $PreflightOnly -and [string]::IsNullOrWhiteSpace($ApprovalReference)",
    "$expectedRevision = '000011-291'",
    "build_v3_common_execution_census.ps1",
    "$v3Job.state -ne 'PAUSED'",
    "$legacyJob.state -ne 'ENABLED'",
    "$minuteOfDay -ge 1170 -and $minuteOfDay -lt 1320",
    "scripts/bq_safe_query.sh",
    "20260827_preflight_fresh_v3_units1_5_pilot_v1.sql",
    "20260827_report_fresh_v3_units1_5_pilot_v1.sql",
    "gcloud workflows run",
    "--flags-file=$flagsFile",
    "'run', 'jobs', 'executions', 'list'",
    "$activeExtractExecutions.Count -ne 0",
    "'storage', 'objects', 'list', 'gs://rcb-bronze-zone'",
    "'--filter=name~^SAP/production_database/', '--limit=1'",
    "$execution.state -ne 'SUCCEEDED'",
    "$execution.workflowRevisionId -ne $expectedRevision",
    "$runId.StartsWith('V3NIGHTLY-')",
    '"--parameter=run_id::$runId"',
    "FRESH_UNITS1_5_PREFLIGHT=PASS",
    "PREFLIGHT_EXECUTION_CREATED=false",
):
    assert required in runner, required

for forbidden in (
    "scheduler jobs pause",
    "scheduler jobs resume",
    "scheduler jobs run",
    "workflows deploy",
    "gs://interface-file",
    "promotion_service_url",
):
    assert forbidden not in runner.lower(), forbidden

assert flags == (
    "--data: '{}'\n"
    "--call-log-level: log-errors-only\n"
    "--disable-concurrency-quota-overflow-buffering: true\n"
    "--labels: 'operator=codex,run_class=unit2_pilot_v1'\n"
)
assert "UNIT2-PILOT-20260827-V1" in preflight
assert "INTERVAL 2 HOUR" in preflight
assert "compared_cells = 39" in preflight
assert "effective_end > TIMESTAMP_ADD(v_checked_at, INTERVAL 2 HOUR)" in preflight
assert "@run_id" in report
assert "HELD_MAGNITUDE_REVIEW" in report
assert "PASS_DELIVERY_DISABLED" in report
assert "magnitude_run_rows = 1" in report
assert "magnitude_result_cells = compared_cells" in report
assert "production_delivery_rows = 0" in report
assert "EXPORT DATA" not in preflight.upper()
assert "EXPORT DATA" not in report.upper()

print("V3_FRESH_UNITS1_5_OPERATOR_STATIC=PASS")

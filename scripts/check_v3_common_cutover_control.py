#!/usr/bin/env python3
"""Static fail-closed checks for DDL 102 common Scheduler cutover control."""

from pathlib import Path
import re

path = Path("sql/ddl/102_v3_common_scheduler_cutover_control.sql")
text = path.read_text(encoding="utf-8")
code = re.sub(r"--[^\n]*", "", text)
fallback_path = Path(
    "sql/operator/20260827_v3_common_scheduler_cutover_manual_fallback.sql"
)
fallback = fallback_path.read_text(encoding="utf-8")
fallback_code = re.sub(r"--[^\n]*", "", fallback)

procedures = re.findall(r"CREATE OR REPLACE PROCEDURE\s+`([^`]+)`", code)
assert procedures == [
    "pacific-plating-282708.sap_integration_v3.sp_register_v3_common_cutover_runtime_evidence",
    "pacific-plating-282708.sap_integration_v3.sp_register_v3_common_cutover_approval",
    "pacific-plating-282708.sap_integration_v3.sp_claim_v3_common_scheduler_cutover",
    "pacific-plating-282708.sap_integration_v3.sp_finalize_v3_common_scheduler_cutover",
    "pacific-plating-282708.sap_integration_v3.sp_close_v3_common_scheduler_cutover",
]
assert "vw_v3_common_scheduler_cutover_control" in code

for reference in re.findall(r"`([^`]+)`", code):
    if reference.startswith("pacific-plating-282708."):
        assert reference.startswith("pacific-plating-282708.sap_integration_v3."), reference

for forbidden in ("EXECUTE IMMEDIATE", "EXPORT DATA", "gs://", "interface-file"):
    assert forbidden not in code.upper() if forbidden.isupper() else forbidden not in code
assert not re.search(r"\bCALL\s+`", code)

assert "cutover_state IN ('CLAIMED','ACTIVATED')" in code
assert "p_terminal_state IN ('ABORTED','ROLLED_BACK')" in code
assert "IF(p_terminal_state='ABORTED','CLAIMED','ACTIVATED')" in code
assert "cutover_state='ACTIVATED'" in code
assert "cutover_state=p_terminal_state" in code

assert "exactly one active Unit 2 magnitude configuration" in code
assert "m.pipeline_run_id!=m.baseline_run_id" in code
assert "m.status='PASS'" in code
assert "l.step='UNITS_2_5_ARCHIVE'" in code
assert "active_execution_count" in code and "INTERVAL 5 MINUTE" in code
assert "PROMOTER_AUTH_REACHED_VALIDATOR" in code
assert "$.execution_state" in code
assert "$.result.permission_rehearsal" in code
assert "$.result.http_code" in code
assert "production_write_expected')='false'" in code
assert "verification_passed')='true'" in code
assert code.count("v3_common_cutover_runtime_evidence") >= 5
assert code.count("v3_common_cutover_mutex") >= 4
assert "lock_version=lock_version+1" in code
assert "Concurrent cutover ID exists or another common cutover is live" in code
assert "evidence_type='PERMISSION_REHEARSAL'" in code
assert "evidence_type='EXECUTION_CENSUS'" in code
assert code.count("evidence_sha256=TO_HEX(SHA256(TO_JSON_STRING") >= 2

assert code.count("v3_scheduler_inventory_evidence") >= 3
assert code.count("paginationComplete')='true'") >= 3
assert code.count("horizonMinuteCount") >= 2
assert code.count("legacy_config_hash") >= 5
assert code.count("v3_config_hash") >= 5
assert code.count("Fresh complete inventory does not prove zero Scheduler overlap") == 1
assert code.count("Restored inventory does not prove zero Scheduler overlap") == 1

assert code.count("BEGIN TRANSACTION;") == 1
assert code.count("COMMIT TRANSACTION;") == 1
assert "legacy_scheduler_name=v_legacy_name" in code
assert "v3_scheduler_name=v_v3_name" in code
assert text.count("30 20 * * *") >= 7
assert text.count("Asia/Bangkok") >= 7

assert "REPLACE_WITH_APPROVED_CUTOVER_ID" in fallback_code
assert "cutover_state IN ('CLAIMED','ACTIVATED')" in fallback_code
assert "required_ledger_transition" in fallback_code
assert "legacy_config_hash" in fallback_code and "v3_config_hash" in fallback_code
assert not re.search(
    r"(?im)^\s*(CREATE|ALTER|DROP|TRUNCATE|INSERT|UPDATE|DELETE|MERGE|CALL|EXPORT)\b",
    fallback_code,
)

print("V3_COMMON_CUTOVER_CONTROL_STATIC=PASS")

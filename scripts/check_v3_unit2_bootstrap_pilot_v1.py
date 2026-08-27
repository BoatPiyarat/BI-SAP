#!/usr/bin/env python3
"""Verify the approved filled Unit 2 pilot is only a value substitution."""

from pathlib import Path


root = Path(__file__).resolve().parents[1]
template_path = root / "sql/operator/20260827_bootstrap_v3_unit2_magnitude_after_approval.sql"
filled_path = root / "sql/operator/20260827_execute_unit2_bootstrap_pilot_v1.sql"
template = template_path.read_text(encoding="utf-8")
filled = filled_path.read_text(encoding="utf-8")

replacements = {
    "DECLARE v_config_id STRING DEFAULT CAST(NULL AS STRING);":
        "DECLARE v_config_id STRING DEFAULT 'UNIT2-PILOT-20260827-V1';",
    "DECLARE v_effective_start TIMESTAMP DEFAULT CAST(NULL AS TIMESTAMP);":
        "DECLARE v_effective_start TIMESTAMP DEFAULT TIMESTAMP '2026-08-27 14:51:46+00';",
    "DECLARE v_effective_end TIMESTAMP DEFAULT CAST(NULL AS TIMESTAMP); -- optional":
        "DECLARE v_effective_end TIMESTAMP DEFAULT TIMESTAMP '2026-08-31 17:00:00+00';",
    "DECLARE v_records_absolute INT64 DEFAULT CAST(NULL AS INT64);":
        "DECLARE v_records_absolute INT64 DEFAULT 25;",
    "DECLARE v_records_percentage NUMERIC DEFAULT CAST(NULL AS NUMERIC);":
        "DECLARE v_records_percentage NUMERIC DEFAULT 0.05;",
    "DECLARE v_orders_absolute INT64 DEFAULT CAST(NULL AS INT64);":
        "DECLARE v_orders_absolute INT64 DEFAULT 10;",
    "DECLARE v_orders_percentage NUMERIC DEFAULT CAST(NULL AS NUMERIC);":
        "DECLARE v_orders_percentage NUMERIC DEFAULT 0.05;",
    "DECLARE v_amount_satang_absolute INT64 DEFAULT CAST(NULL AS INT64);":
        "DECLARE v_amount_satang_absolute INT64 DEFAULT 500000;",
    "DECLARE v_amount_percentage NUMERIC DEFAULT CAST(NULL AS NUMERIC);":
        "DECLARE v_amount_percentage NUMERIC DEFAULT 0.05;",
    "DECLARE v_approval_reference STRING DEFAULT CAST(NULL AS STRING);":
        "DECLARE v_approval_reference STRING DEFAULT 'Boat-chat-20260827-UNIT2-PILOT-20260827-V1';",
    "DECLARE v_approved_by STRING DEFAULT CAST(NULL AS STRING);":
        "DECLARE v_approved_by STRING DEFAULT 'Boat';",
    "DECLARE v_approved_at TIMESTAMP DEFAULT CAST(NULL AS TIMESTAMP);":
        "DECLARE v_approved_at TIMESTAMP DEFAULT TIMESTAMP '2026-08-27 14:51:46+00';",
}

expected = template
for sentinel, approved in replacements.items():
    assert template.count(sentinel) == 1, sentinel
    assert filled.count(approved) == 1, approved
    expected = expected.replace(sentinel, approved)

assert filled == expected, "filled operator differs from the reviewed template beyond approved values"
assert filled.count(
    "CALL `pacific-plating-282708.sap_integration_v3.sp_bootstrap_v3_unit2_magnitude`("
) == 1
assert "EXPORT DATA" not in filled
assert "gs://" not in filled

print("V3_UNIT2_BOOTSTRAP_PILOT_V1_STATIC=PASS")

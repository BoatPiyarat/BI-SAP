#!/usr/bin/env python3
"""Static fail-closed checks for the human-filled Unit 2 bootstrap operator."""

from pathlib import Path
import re


path = Path("sql/operator/20260827_bootstrap_v3_unit2_magnitude_after_approval.sql")
text = path.read_text(encoding="utf-8")

assert "MUTATING WHEN FILLED AND EXECUTED" in text
assert "Run only through scripts/bq_safe_query.sh" in text
assert "V3NIGHTLY-2026-08-25T22:21:31-manual" in text

human_variables = (
    "v_config_id",
    "v_effective_start",
    "v_effective_end",
    "v_records_absolute",
    "v_records_percentage",
    "v_orders_absolute",
    "v_orders_percentage",
    "v_amount_satang_absolute",
    "v_amount_percentage",
    "v_approval_reference",
    "v_approved_by",
    "v_approved_at",
)
for variable in human_variables:
    assert re.search(
        rf"DECLARE {variable} [A-Z0-9]+ DEFAULT CAST\(NULL AS [A-Z0-9]+\);",
        text,
    ), variable

assert text.index("all six approved magnitude thresholds are required") < text.index("CALL `")
assert text.index("approval_reference, approved_by, and approved_at are required") < text.index(
    "CALL `"
)
assert text.count("CALL `pacific-plating-282708.sap_integration_v3.sp_bootstrap_v3_unit2_magnitude`(") == 1

call = re.search(
    r"CALL `pacific-plating-282708\.sap_integration_v3\.sp_bootstrap_v3_unit2_magnitude`\((.*?)\);",
    text,
    re.DOTALL,
)
assert call is not None
arguments = [argument.strip() for argument in call.group(1).split(",")]
assert arguments == ["v_baseline_run_id", *human_variables]

for required in (
    "an active Unit 2 magnitude configuration already exists",
    "config_id already exists",
    "baseline already has a magnitude result",
    "exact approved configuration was not committed",
    "exact self-baseline PASS row is missing",
    "magnitude results do not conserve distribution cells",
):
    assert required in text, required

assert "EXPORT DATA" not in text
assert "gs://" not in text
assert not re.search(r"\b(?:CREATE|ALTER|DROP|DELETE|UPDATE|MERGE)\b", text)

print("V3_UNIT2_BOOTSTRAP_OPERATOR_STATIC=PASS")

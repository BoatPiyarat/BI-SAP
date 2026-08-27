#!/usr/bin/env python3
"""Static fail-closed checks for the nine-flow lifecycle adapter matrix."""

from pathlib import Path
import re


path = Path("docs/design/V3_FLOW_LIFECYCLE_ADAPTER_MATRIX.md")
text = path.read_text(encoding="utf-8")

flows = [
    "ORDINARY_ONETIME_CREATE",
    "RCL_FIRST_PERIOD_CREATE",
    "RCL_LATER_PERIOD_NEWPAYMENT",
    "EDC_ONETIME",
    "RCL_CMI",
    "PLAIN_CANCEL",
    "CHANGE_ORDER_CANCEL",
    "CREDITSHELL_REPLACEMENT",
    "PAYMENT_ADJUSTMENT_INTENT",
]
matrix_rows = re.findall(r"^\| `([A-Z0-9_]+)` \|", text, re.MULTILINE)
assert matrix_rows == flows, matrix_rows
assert len(set(matrix_rows)) == 9

for required in (
    "v3_flow_export_claim",
    "vw_v3_flow_export_lifecycle",
    "release_ready_count>0",
    "canonical 56-column object",
    "pickup→import→row-ACK",
    "DDL 101 registers exact manual-delivery evidence",
    "DDL 100 native archive and lifecycle",
    "Never point multiple scenario schedulers at the current global Workflow",
):
    assert required in text, required

assert text.count("Hold report only:") == 7
assert text.count("Export fallback:") == 2
assert text.count("| absent | absent |") == 2
assert "None of the other seven may skip its mapping/approval step" in text
assert "Do not turn hold rows into release identities" in text

print("V3_FLOW_LIFECYCLE_MATRIX_STATIC=PASS")

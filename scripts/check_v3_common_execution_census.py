#!/usr/bin/env python3
"""Static fail-closed checks for the common Workflow execution census."""

from pathlib import Path
import re


path = Path("scripts/build_v3_common_execution_census.ps1")
text = path.read_text(encoding="utf-8")

for required in (
    "$ErrorActionPreference = 'Stop'",
    "Set-StrictMode -Version Latest",
    "[Parameter(Mandatory)] [string]$ExpectedRevision",
    "infra/v3_nightly_orchestrator.workflows.yaml",
    "workflows', 'describe'",
    "workflows', 'executions', 'list'",
    "--filter=state=ACTIVE",
    "--filter=state=QUEUED",
    "$activeExecutionCount = $activeExecutions.Count + $queuedExecutions.Count",
    "$live.revisionId -eq $ExpectedRevision",
    "$live.state -eq 'ACTIVE'",
    "$live.serviceAccount -eq $expectedServiceAccount",
    "$sourceIdentityPassed",
    "$deliveryFalse",
    "-not $deliveryTrue",
    "$activeExecutionCount -eq 0",
    "workflow_revision = $live.revisionId",
    "workflow_state = $live.state",
    "delivery_enabled = $false",
    "source_identity_passed = $sourceIdentityPassed",
    "active_execution_count = $activeExecutionCount",
    "verification_passed = $verificationPassed",
    "if (-not $verificationPassed)",
    "exit 1",
):
    assert required in text, required

assert text.count("'--limit=1'") == 2
assert "execution_states_checked = @('ACTIVE', 'QUEUED')" in text
assert "ConvertTo-Json -Depth 6" in text

gcloud_groups = re.findall(r"Invoke-GcloudJson\s+@\((.*?)\n\s*\)", text, re.DOTALL)
assert len(gcloud_groups) == 3
assert all("'workflows'" in group for group in gcloud_groups)
for forbidden in (
    "'deploy'",
    "'execute'",
    "'cancel'",
    "'delete'",
    "'update'",
    "'create'",
    "'pause'",
    "'resume'",
    "'scheduler'",
    "'storage'",
    "'bigquery'",
):
    assert forbidden not in text.lower(), forbidden

print("V3_COMMON_EXECUTION_CENSUS_STATIC=PASS")

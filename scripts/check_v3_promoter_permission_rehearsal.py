"""Static fail-closed contract check for the no-write promoter permission rehearsal."""

from pathlib import Path

import yaml


SOURCE = Path("infra/v3_nightly_orchestrator.workflows.yaml")
text = SOURCE.read_text(encoding="utf-8")
document = yaml.safe_load(text)

assert isinstance(document, dict) and "main" in document
assert "- delivery_enabled: false" in text
assert "- delivery_enabled: true" not in text

steps = document["main"]["steps"]
step_names = [next(iter(step)) for step in steps]
rehearsal_index = step_names.index("maybe_rehearse_promoter_permission")
assert rehearsal_index < step_names.index("maybe_bind_post_import_execution")
assert rehearsal_index < step_names.index("log_start")

init_assignments = {
    next(iter(item)): next(iter(item.values())) for item in steps[0]["init"]["assign"]
}
assert init_assignments["permission_rehearsal_only"] == (
    '${default(map.get(args, "permission_rehearsal_only"), false)}'
)

rehearsal = steps[rehearsal_index]["maybe_rehearse_promoter_permission"]
branches = rehearsal["switch"]
assert len(branches) == 1
assert branches[0]["condition"] == "${permission_rehearsal_only}"
rehearsal_steps = branches[0]["steps"]
assert [next(iter(step)) for step in rehearsal_steps] == [
    "gate_permission_rehearsal_contract",
    "invoke_expected_invalid_probe",
    "reject_unexpected_rehearsal_success",
]

gate = rehearsal_steps[0]["gate_permission_rehearsal_contract"]["switch"]
assert len(gate) == 1
assert "https://sap-delivery-promoter-3uymtccdma-as.a.run.app" in gate[0]["condition"]
assert "post_import_log_id" in gate[0]["condition"]
assert "post_import_claim_token" in gate[0]["condition"]
assert gate[0]["raise"].startswith("permission rehearsal requires the exact promoter URL")

probe = rehearsal_steps[1]["invoke_expected_invalid_probe"]
assert probe["try"]["call"] == "http.post"
assert probe["try"]["args"] == {
    "url": '${promotion_service_url + "/promote"}',
    "auth": {"type": "OIDC", "audience": "${promotion_service_url}"},
    "body": {},
}
assert probe["try"]["result"] == "unexpected_rehearsal_success"
assert probe["except"]["as"] == "e"

except_steps = probe["except"]["steps"]
assert [next(iter(step)) for step in except_steps] == [
    "inspect_rehearsal_rejection",
    "return_expected_validator_rejection",
    "raise_unexpected_rehearsal_failure",
]
inspection_assignments = {
    next(iter(item)): next(iter(item.values()))
    for item in except_steps[0]["inspect_rehearsal_rejection"]["assign"]
}
assert inspection_assignments["rehearsal_error_text"] == (
    '${json.encode_to_string(default(map.get(e, "body"), ""))}'
)
accepted = except_steps[1]["return_expected_validator_rejection"]["switch"]
assert len(accepted) == 1
assert "rehearsal_http_code == 400" in accepted[0]["condition"]
assert "missing required field: archive_bucket" in accepted[0]["condition"]
assert accepted[0]["return"] == {
    "permission_rehearsal": "PROMOTER_AUTH_REACHED_VALIDATOR",
    "http_code": "${rehearsal_http_code}",
    "production_write_expected": False,
}
assert except_steps[2]["raise_unexpected_rehearsal_failure"]["raise"].startswith(
    '${"promoter permission rehearsal failed before expected validator response; HTTP "'
)
assert rehearsal_steps[2]["reject_unexpected_rehearsal_success"]["raise"] == (
    "invalid permission rehearsal unexpectedly succeeded"
)


def collect_calls(value):
    calls = []
    if isinstance(value, dict):
        for key, child in value.items():
            if key == "call":
                calls.append(child)
            calls.extend(collect_calls(child))
    elif isinstance(value, list):
        for child in value:
            calls.extend(collect_calls(child))
    return calls


assert collect_calls(rehearsal) == ["http.post"]

print("PROMOTER_PERMISSION_REHEARSAL_STATIC=PASS")

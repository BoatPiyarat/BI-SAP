# Unit 1 source self-verification — Boat review waiver

Status: **SOURCE READY / independent Claude review explicitly waived by Boat for this Unit 1
iteration because Claude credit is unavailable / not deploy evidence**.

Boat approved the two escalated corrections and instructed Codex to execute without Claude review.
Codex remains the single deployer. This exception does not waive validation or future Class A
review generally.

Verified before production mutation:

- BigQuery job ID derives through `text.replace_all_regex(..., "[^A-Za-z0-9_-]", "_")`.
- `jobs.cancel` enters a polling loop and cannot exit until `jobs.get` reports `DONE`.
- Live control object read at 2026-08-02 has only `last_watermark_utc`/`updated_at`; source now uses
  `SAP/_extract_control/_watermark_state.json` and those real fields.
- Healthy zero additionally requires the exact Cloud Run execution log marker containing
  `success:`, `0 rows`, and `caught_up=True`.
- Local YAML parse passed with top-level workflows `main`, evidence gates, BigQuery runner,
  run-log writer, and fail-closed handler.
- Existing extract and loader schedulers remain enabled; no cutover is permitted during initial
  workflow deployment/rehearsal.

Known deployment prerequisites remain hard gates: human-reaching alert path, least-privilege
workflow service account, Workflows compiler acceptance, and a non-overlapping rehearsal window.

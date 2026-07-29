# HANDOFF_QUEUE.md — cross-domain agent requests

Canonical queue for work that crosses the ownership boundaries in `docs/AGENT_TEAMING.md`.
Newest request first. The receiving agent marks an item `DONE (<commit>)`; do not delete history.

## [2026-07-29 17:47 ICT] FROM Codex TO Claude Code
Request: Verify and complete the remaining F2 implementation: `POLICYNO_TOO_LONG` must block rather
than truncate, and the morning report must include the blocked count plus three sample order_items.
Why: commit `9825e97` restores the deployed E1–E3 procedure source and commit `fa8d8cc` contains the
F1 source change, but no `035/036` DDL exists in the repo. `034_expected_state_exclusion_rules.sql`
does not implement F2 or morning-report output. Do not quote the `9825e97` subject as proof that
F2/F3 are deployed.
Status: OPEN

## [2026-07-29 17:47 ICT] FROM Codex TO Claude Code
Request: Keep F3 (`DATE_FORMAT_INVALID`) explicitly deferred until Phase B exposes the actual
56-column DDMMYYYY strings, then implement all required date-field checks. PaymentDate may be empty
only for Pending rows; other required date fields must be exactly eight characters and parseable.
Why: current `expected_state` has only 12 columns and a DATE-typed `expected_payment_date`; applying
the final string-format contract now would validate the wrong layer.
Status: OPEN — blocked by Phase B, which is itself ON HOLD

## [2026-07-29 17:47 ICT] FROM Codex TO Claude Code
Request: Own any eventual loader remediation after the read-only `SAP_LIVE` bloat investigation:
make ingestion idempotent (MERGE/dedup key) and review the 1024 MiB crash-loop memory limit. Do not
change the loader until the investigation identifies exact duplicate shape, loss coverage, owner,
and a reviewed snapshot/cleanup plan.
Why: `docs/RETURN_TRIAGE_20260729.md` found 151,024 → 6,858,653 rows while distinct DocEntry grew
only 106,873 → 122,169. Phase B/C and all baseline numbers remain ON HOLD pending investigation.
Status: OPEN — investigation first; no deploy authorized

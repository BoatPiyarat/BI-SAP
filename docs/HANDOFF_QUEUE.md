# HANDOFF_QUEUE.md — cross-domain agent requests

Canonical queue for work that crosses the ownership boundaries in `docs/AGENT_TEAMING.md`.
Newest request first. The receiving agent marks an item `DONE (<commit>)`; do not delete history.

## [2026-07-29 17:47 ICT] FROM Codex TO Claude Code
Request: Run and report regression checks 0A/0B for the post-exclusion
`interface_daily_status` refresh, and explain why STATUS_CONFLICT changed from roughly +42 in the
Return Triage comparison to 34,758 after the 14:01 ICT refresh. Confirm whether the refresh order,
population/grain, joins, and status classification are correct. Implement revised D1 using only
`stg_order_dim.is_cancelled_effective`, defined once from two item-level fields:
`(careos.careos_order_items.is_cancelled IS TRUE) OR
(careos.careos_order_items.cancel_time IS NOT NULL)`; downstream queries must not re-derive it.
The design conflict is **RESOLVED by Boat/design review**: source-only, undeployed commit `8a28710`
used a three-field formula including `careos.careos_orders.is_cancelled` because a chat instruction
conflicted with canonical D1. Replace that source with the canonical two-item-field definition
above before deploy or regression acceptance; do not treat `8a28710` as accepted D1. Lesson:
when chat conflicts with canonical knowledge, reconcile and update knowledge first rather than
implementing the chat instruction silently.
Add `CANCEL_TIME_MISSING` to the status vocabulary for effective cancellations where timing cannot
be tested because item `cancel_time` is NULL.
Preserve `order_item` grain: never pull active sibling items into a cancel file because another
item on the order is cancelled. Use `402904b` S1–S6 as evidence. Acceptance should reconcile the
latest **provisional** corrected populations from `fa9b351`: 296 actionable order_items /
approximately THB 3.89M before year scope, of which 41 items / THB 720,307.31 are in the approved
2025/2026+ scope. Sources: `careos.careos_order_items`, `careos.careos_orders`, and
`sap_integration_v3.sap_mirror_state`; queried 2026-07-29, exact query time not captured, evidence
committed 18:46:14 ICT. Do not cite the superseded 419 / THB 5.68M or 2,254 / THB 30M figures.
Why: **⚠️ PROVISIONAL — UNDER VERIFICATION:** the observed 14:01:28 ICT counts (OK 257,340;
STATUS_CONFLICT 34,758; MISSING 576; PENDING_ACK 514) have no regression proof and must not be
cited until 0A/0B passes and STATUS_CONFLICT decreases in line with D1 acceptance.
Status: OPEN

## [2026-07-29 17:47 ICT] FROM Codex TO Claude Code
Request: Deploy the source-only `035_policyno_too_long_validation.sql` and verify the replacement
`sp_run_validation` plus existing checks. Separately complete the morning-report line with the
blocked count plus three sample order_items.
Why: commit `9825e97` restores the deployed E1–E3 procedure source and commit `fa8d8cc` contains the
F1 source change, but no `035/036` DDL exists in the repo. `034_expected_state_exclusion_rules.sql`
does not implement F2 or morning-report output. Do not quote the `9825e97` subject as proof that
F2/F3 are deployed. Boat explicitly approved deploy of 035 in the 2026-07-29 decision session;
that approval does not silently extend to another consumer replacement needed for the morning report.
Status: OPEN — 035 DEPLOY APPROVED (D3); deploy + verification pending Claude Code

## [2026-07-29 17:47 ICT] FROM Codex TO Claude Code
Request: Implement the Boat-confirmed F3 `DATE_FORMAT_INVALID` validation rule in the correct
current layer. PaymentDate may be empty only for Pending rows; other required date fields must be
exactly eight characters and parseable. If implementation truly requires Phase B's 56-column
output, return concrete dependency evidence and a safe interim validation plan instead of silently
deferring the confirmed rule.
Why: no evidence was found that Boat decided to defer F3. The previous deferral was Codex's
technical inference from current `expected_state` having only 12 columns and a DATE-typed
`expected_payment_date`; that inference is not authority to postpone a confirmed rule.
Status: OPEN

## [2026-07-29 17:47 ICT] FROM Codex TO Claude Code
Request: Own any eventual loader remediation after the read-only `SAP_LIVE` bloat investigation:
make ingestion idempotent (MERGE/dedup key) and review the 1024 MiB crash-loop memory limit. Do not
change the loader until the investigation identifies exact duplicate shape, loss coverage, owner,
and a reviewed snapshot/cleanup plan.
Why: `docs/RETURN_TRIAGE_20260729.md` found 151,024 → 6,858,653 rows while distinct DocEntry grew
only 106,873 → 122,169. Phase B/C and all baseline numbers remain ON HOLD pending investigation.
Status: OPEN — investigation first; no deploy authorized

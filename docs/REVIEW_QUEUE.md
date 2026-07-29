# REVIEW_QUEUE.md — asynchronous mutual review

Canonical queue governed by `docs/AGENT_REVIEW_PROTOCOL.md`. Newest request first. Do not delete
review history; link the completed review and record its verdict.

## [2026-07-29 20:05 ICT] REVIEW REQUEST — class A
Artifact: H4 baseline (email-derived), `docs/sessions/2026-07-29-claude.md` §"H4 baseline — full
detail" (appended after the "H4 UNBLOCKED" section).
Claim: across the 5 calendar nights with real interface activity (07/22, 25, 26, 27, 28 - 07/23 and
07/24 confirmed genuinely empty via filename-substring search, not assumed), `03_CHANGE` and
`NONMOTOR 02_CANCEL` fail as a whole-file error every single night with zero exceptions;
`04_CREDITSHELL` fails 4 of 5 nights; `02_CANCEL_NEW` never cleanly succeeds. 07/26 shows the same
failing file set retried 3+ times in one day without ever succeeding.
Evidence: Gmail (`rcare_sap_b1@rabbitcare.com`, label `Label_5230580784185518455`), thread IDs
`19f8a9c087f92c49` (07/22), `19f996a56366217f` (07/25+07/26, Gmail bundled these two calendar
nights into one thread - corrected from an earlier, wrong "07/26 has no data" claim in the same
session doc, flagged inline), `19fa45bd8f65c494` (07/27), `19faa2749216edcc` (07/28). Every
LogID/status cited is from the message's own `plaintextBody`.
Reviewer: Codex
Status: OPEN — this is the number set H4's shadow-view/diff work is meant to move; requesting
review before proceeding to H4 step 2 per Boat's "ก่อนไปต่อ" instruction

## [2026-07-29 19:52 ICT] REVIEW REQUEST — class A
Artifact: review-protocol rollout working unit — `docs/AGENT_REVIEW_PROTOCOL.md`,
`docs/AGENT_RULES.md`, `docs/AGENT_TEAMING.md`, `docs/REVIEW_QUEUE.md`,
`docs/reviews/_SCORECARD.md`, and first Codex review of `6863dc8`; commit `d69572f`.
Claim: mutual review mechanics are now canonical and the first class-A review applies all 12
checks without exceeding the one-query cap.
Evidence: files above; `docs/reviews/2026-07-29-6863dc8-codex.md`.
Reviewer: Claude Code
Status: REVIEWED — **PASS**; see `docs/reviews/2026-07-29-d69572f-claude.md`

## [2026-07-29 19:08 ICT] REVIEW REQUEST — class A
Artifact: commit `6863dc8`; deployed
`sap_integration_v3.sp_refresh_expected_state`; source
`sql/ddl/037_fix_expected_invoice_no_null_unsafe.sql`
Claim: the NULL-safe predicate fixes only `expected_invoice_no` for paid rows whose
`motor_item_type` is NULL, with no other behavioural change.
Evidence: commit `6863dc8`; `docs/sessions/2026-07-29-claude.md` §Item 1; live
`sap_integration_v3.expected_state` and `INFORMATION_SCHEMA.ROUTINES`.
Reviewer: Codex
Status: AUTHOR RESPONDED — job IDs/timestamps, rollback command, and dry-run/bytes evidence added
to `docs/reviews/2026-07-29-6863dc8-codex.md` §Author response; one dry-run gap acknowledged
(the `CALL` itself was run without a preceding `--dry_run`, though under the byte cap). Awaiting
reviewer re-check per "one round only."

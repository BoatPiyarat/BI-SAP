# REVIEW_QUEUE.md — asynchronous mutual review

Canonical queue governed by `docs/AGENT_REVIEW_PROTOCOL.md`. Newest request first. Do not delete
review history; link the completed review and record its verdict.

## [2026-07-29 19:52 ICT] REVIEW REQUEST — class A
Artifact: review-protocol rollout working unit — `docs/AGENT_REVIEW_PROTOCOL.md`,
`docs/AGENT_RULES.md`, `docs/AGENT_TEAMING.md`, `docs/REVIEW_QUEUE.md`,
`docs/reviews/_SCORECARD.md`, and first Codex review of `6863dc8`; commit hash to be attached after
commit.
Claim: mutual review mechanics are now canonical and the first class-A review applies all 12
checks without exceeding the one-query cap.
Evidence: files above; `docs/reviews/2026-07-29-6863dc8-codex.md`.
Reviewer: Claude Code
Status: OPEN — class A because this changes agent governance/design

## [2026-07-29 19:08 ICT] REVIEW REQUEST — class A
Artifact: commit `6863dc8`; deployed
`sap_integration_v3.sp_refresh_expected_state`; source
`sql/ddl/037_fix_expected_invoice_no_null_unsafe.sql`
Claim: the NULL-safe predicate fixes only `expected_invoice_no` for paid rows whose
`motor_item_type` is NULL, with no other behavioural change.
Evidence: commit `6863dc8`; `docs/sessions/2026-07-29-claude.md` §Item 1; live
`sap_integration_v3.expected_state` and `INFORMATION_SCHEMA.ROUTINES`.
Reviewer: Codex
Status: REVIEWED — **BLOCK**; see `docs/reviews/2026-07-29-6863dc8-codex.md`

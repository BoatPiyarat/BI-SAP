# TASK: V2 stop / V3 cutover — 2026-08-24

Owner of the instruction: Boat, verbatim, 2026-08-24 (~09:2x ICT), relayed via Claude Code, not
executed by Claude Code. See `docs/INPUTS_NEEDED.md`'s "URGENT OPEN 2026-08-24" entry for the
exact quote and the three open questions that need an answer before this proceeds as literally
worded. **This document does not authorize any action by itself — it is the readiness map Codex
needs to plan against, and the checklist Claude Code will use to review whatever Codex does.**

## Why this needs a plan, not a straight execution

"Stop V2 production and all schedule" + "push V3 up and running tonight" reads as one atomic
swap. It isn't one today. V3's own as-built inventory and the most recent Class-A review
(yesterday, `RQ-20260823-2304`, PASSed) both confirm `delivery_enabled: false` and zero GCS writes
ever performed by V3. Stopping V2 without V3 actually serving the interface file means a real
delivery gap, not a migration. This plan exists to make that gap and its size explicit so Boat's
answer to the three open questions in `INPUTS_NEEDED.md` is informed, and so Codex isn't executing
"stop everything" against an assumption that V3 is already a working replacement.

## Readiness checklist (source: `docs/design/V3_DELIVERY_CONTROL_PLANE.md`, `docs/AS_BUILT_V3.md`,
`docs/REVIEW_QUEUE.md`)

Gate status as of this document's creation — Codex should re-verify every line live before relying
on it; nothing here should be treated as still-current without a fresh check given how fast this
project's state moves.

- [ ] **Deploy remaining contract DDLs** the delivery control plane depends on (name each one
  explicitly when re-checking; `V3_DELIVERY_CONTROL_PLANE.md` lists which).
- [ ] **Fix or re-confirm the 3 non-matching case-type views**: `RCL_Motor_process_1_create` and
  `RCL_NonMotor_process_2_newpayment` (drifted from reviewed baseline per `RQ-20260801-0040`),
  `RCL_Motor_process_2_newpayment` (no baseline at all), and the separate production-copy drift on
  `RCB_NonMotor_process_1_create`. A full V3 cutover cannot claim case-type parity with these
  unresolved.
- [ ] **Wire `sp_check_column_contract()`** (`sql/ddl/028_column_contract_guard.sql`) into the
  actual nightly/export chain — it exists but is currently called from nowhere live, so it would
  not catch a bad 56-column export tonight.
- [ ] **Complete the Apps Script rehearsal** step from the delivery control plane (distinct from
  the post-import rehearsal already PASSed yesterday — confirm which rehearsal, if either, this
  refers to before assuming it's done).
- [ ] **Get the separately-scoped GCS-write approval** the control-plane doc requires before
  `delivery_enabled` flips — this is explicitly called out as its own decision, not implied by
  general V3-build approval.
- [ ] **One bounded, monitored `delivery_enabled: true` execution**, then verify generation, CRC/
  SHA, and actual SAP pickup — before treating it as steady-state production.
- [ ] **A dedicated, reviewed cutover step** — the control-plane doc frames this as its own future
  Class-A review, separate from building the pieces. No such review has happened.

## Options for tonight (for Boat to choose between, not for Codex to pick unilaterally)

1. **Full stop tonight, accept the gap.** Stop all V2 schedules now; SAP receives no interface
   file until every checklist item above closes. Needs explicit sign-off given the business
   impact (see `INPUTS_NEEDED.md` Q2) and ideally advance notice to Finance/Aware.
2. **Narrow stop.** Stop only the specific V2 object(s)/schedule(s) actually producing "continuing
   production errors" (Boat: which ones, specifically? — the CreditShell misroute already fixed
   today is one candidate; if there are others, name them) while V2 otherwise keeps delivering and
   V3 closes the checklist above in parallel, un-rushed.
3. **Scoped V3-tonight.** Interpret "push V3 up and running tonight" narrowly — e.g., only the
   CreditShell classification path already reviewed and deployed today — rather than the full
   12-case-type interface. State explicitly which case types this does and does not cover if
   chosen.

## Claude Code's role from here

- Will not stop any V2 schedule, flip `delivery_enabled`, or execute any DDL/GCS mutation — that
  remains Codex's single-deployer role per `AGENT_RULES.md`.
- Will review every Class-A artifact Codex produces toward this cutover under the normal
  `docs/REVIEW_QUEUE.md` protocol, same as today's CreditShell/post-import reviews.
- Once Boat answers the three open questions, will update this document's checklist status and
  help verify each gate as Codex closes it, plus independently re-check the final cutover claim
  (row/item counts, contract compliance, actual SAP pickup evidence) before it's treated as done —
  the same "reproduce, don't trust the description" standard applied to every review so far today.

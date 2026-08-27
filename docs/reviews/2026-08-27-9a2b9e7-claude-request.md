# Claude Code Class-A delta review request — DDL 103 validation-hold uniqueness

Status: **NOT SENT — exact five-file Anthropic transfer approval required**

Artifact commit: `9a2b9e7fe73cdc75e1c7f5564bd86c65baa17637`

## Exact external payload

Read exactly these five files and no others:

1. `sql/ddl/103_v3_monthend_onetime_immutable_snapshot.sql`
   SHA-256 `7b744fb59aa4d5f9fe01998be138961ecfe748b34f8c0b58b52728b53039f2cd`
2. `scripts/check_v3_monthend_onetime_snapshot.py`
   SHA-256 `da92391cb075738c35d6fbab4c96b0183397ee03e4f8e53cada48c5b06a526e4`
3. `docs/reviews/2026-08-27-59a4521-claude.md`
4. `docs/AGENT_RULES.md`
5. `docs/AGENT_REVIEW_PROTOCOL.md`

## Delta and evidence

The only executable-source change after reviewed commit `59a4521` is an assertion immediately
after `_validation_hold` is built and before it joins `_hold`. It requires exactly one row per
`(order_item, period, invoice_no)`. The checker now requires that assertion text.

- offline checker: `V3_MONTHEND_ONETIME_STATIC=PASS`;
- exact export columns: `V3_MONTHEND_ONETIME_EXPORT_COLUMNS=56`;
- Python compilation: PASS;
- `git diff --check`: PASS;
- authenticated BigQuery dry-run: **NOT RUN** because the workspace approval service rejected the
  request for exhausted credits before command execution;
- no production redeployment, procedure CALL, snapshot, export, GCS, Workflow, Scheduler, SAP, or
  ACK action occurred.

## Requested review

### Standards / safety

1. Confirm the assertion executes before `_validation_hold` can fan out `_hold`.
2. Confirm SQL NULL grouping does not create a silent bypass and duplicates with a NULL invoice
   still fail as one grouped key.
3. Confirm the delta changes no readiness, payload, hold classification, or 56-column behavior.
4. Confirm the checker would fail if the assertion were removed.

### Spec

1. Determine whether the delta fully closes the prior review's validation-hold join uniqueness
   note.
2. Return `PASS`, `PASS WITH NOTES`, or `BLOCK` for exact commit `9a2b9e7`.
3. State explicitly that source PASS does not authorize replacing the live procedure or making the
   first snapshot CALL; authenticated dry-run and separate deploy/CALL approvals remain required.

Read-only review only. Do not mutate files, run commands, query BigQuery, access GCS, invoke a
Workflow, or change production state.

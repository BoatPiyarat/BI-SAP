# Review — RQ-20260805-1939-post-import-unit1-dispatcher

Reviewer: Claude Code
Artifact: commit `ec64deb`; `infra/post_import_dispatcher/` and post-import deltas in
`infra/v3_nightly_orchestrator.workflows.yaml`.
Verdict: **PASS**

## Checked against the request's own checklist

- **Pub/Sub envelope/event validation**: `decode_event` requires a dict with a `message` dict and
  base64+JSON-decodes `message.data`, raising `ValueError` (→ 400) on any shape mismatch.
  `validate_event` then checks every field's exact shape: `log_id` decimal digits, `export_run_id`
  against a bounded shape regex, `sap_file_name` a safe `.csv` basename, `import_status` in the
  same two-value admitted set as DDL 071/072, and `email_date` ISO-8601 with a required timezone.
- **Token determinism**: `claim_token` computes `SHA256(log_id\0export_run_id\0sap_file_name)`
  truncated to 32 hex characters — deterministic (same triple → same token every time) and matches
  DDL 072's `^[a-f0-9]{32}$` format requirement exactly (a truncated SHA-256 hex digest is always
  lowercase hex).
- **Admitted status handling**: `_TERMINAL_IMPORT_STATUSES = {"success", "success with error"}` is
  the same two-value set DDL 071's own `ASSERT` enforces; `import_status` is lowercased before the
  membership check.
- **Claim/retry and duplicate no-op**: if `claim()` returns `STARTED` with a non-empty execution
  name, `dispatch()` returns `204` immediately without calling Workflows again — a duplicate
  delivery of an already-fully-dispatched event is a clean no-op. Traced that `claim()` can only
  ever return `CLAIMED` or `STARTED` without raising (any other outcome means the underlying SQL
  `ASSERT` already threw), so the `state["status"] != "CLAIMED"` fallback check is a correct,
  if currently-unreachable, defensive guard rather than a gap.
- **Definite-vs-ambiguous execution-create failure handling — the subtle part, traced carefully**:
  only `BadRequest`/`Forbidden`/`NotFound` (persistent, retry-without-a-fix-won't-help errors) call
  `release()` before re-raising, returning the claim to `PENDING` (or terminalizing it if attempts
  are exhausted). Any *other* exception (timeouts, transient 5xx) is **not** released — the claim
  stays `CLAIMED`, and Pub/Sub's natural redelivery will retry with the *same* deterministic token,
  which is safe specifically because DDL 072's bind-race handling (reviewed under RQ-1928) lets a
  second, genuinely-successful create attempt win the bind while an earlier ambiguous attempt's
  orphaned execution loses and self-exits. Releasing on an ambiguous failure would have been the
  wrong choice here — it could let the claim reopen while an unconfirmed execution from the
  "failed" attempt is still silently running.
- **IAM/configuration boundary**: `configured()` fails closed on any missing required env var.
  README documents a dedicated service account scoped to BigQuery job creation/read plus
  `workflows.executions.create` on the *one* target workflow — not a broad grant — plus a private
  Cloud Run service behind an authenticated Pub/Sub push subscription with a dead-letter topic and
  bounded delivery-attempt policy recommended before deploy.
- **Server-assigned-name self-bind (verified in the workflow YAML, not the dispatcher)**: the
  dispatcher itself never calls `sp_bind_v3_post_import_execution` — by design, since the Workflows
  Executions API assigns the execution name server-side, only the *running execution* can know its
  own name. The YAML delta's `workflow_execution_name` is reconstructed from
  `sys.get_env(GOOGLE_CLOUD_PROJECT_ID/LOCATION/WORKFLOW_ID/WORKFLOW_EXECUTION_ID)` and bound via
  `bind_post_import` as the very first step after the initial variable assignment — strictly before
  `log_start` or any extract/load/mirror action.
- **Duplicate-loser exit — traced end to end**: `exit_duplicate_post_import_execution` compares the
  bind's returned winning name against the execution's own reconstructed name and `return`s
  `DUPLICATE_NOOP:<name>` if they differ, ending the workflow cleanly with no further side effects.
  Only the winner falls through to `log_start` and Unit 1.
- **Unit-1-only stop and success completion**: `stop_after_post_import_unit1` (added by this same
  commit) gates on `post_import_mode`, calls `complete_post_import`, and `return`s the run_id —
  exiting before the file's later Units 2–5 chaining logic is ever reached in post-import mode.
- **No service, workflow, topic, subscription, IAM, trigger, execution, GCS write, delivery, ACK,
  or SAP action is requested**: this commit adds only source files (`main.py`, `Dockerfile`,
  `README.md`, `requirements.txt`) plus a workflow YAML source delta — nothing is deployed,
  triggered, or executed by this review. A stray local `__pycache__/main.cpython-312.pyc` in the
  working tree is untracked (confirmed via `git ls-files`), not part of the commit.
- **Evidence independently re-verified**: `python -m py_compile infra/post_import_dispatcher/main.py`
  passes; `git diff --check ec64deb^ ec64deb` passes (no trailing whitespace). Cross-checked the
  workflow YAML's positional field reads against DDL 072's actual `SELECT` column order —
  `bind_post_import` reads `rows[0].f[1..3]` for `execution_name/export_run_id/sap_file_name`,
  matching `sp_bind_v3_post_import_execution`'s `SELECT request_status, workflow_execution_name,
  export_run_id, sap_file_name` exactly by position.

## Verdict

PASS. Event validation, deterministic claim tokens, the definite-vs-ambiguous failure split, the
server-assigned self-bind ordering, and the duplicate-loser exit are all implemented and wired
together correctly and consistently with DDL 072's own concurrency guarantees. No infrastructure,
IAM, trigger, execution, or SAP action is requested or occurred in this review.

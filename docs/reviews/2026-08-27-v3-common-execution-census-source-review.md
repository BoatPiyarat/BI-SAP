# Review — common Workflow execution census source

Date: 2026-08-27

Fixed point: `29996af`

Scope:

- `scripts/build_v3_common_execution_census.ps1`
- `scripts/check_v3_common_execution_census.py`
- the census reference in `docs/design/V3_PRODUCTION_CUTOVER_AND_SPLIT_ACTIVATION.md`

Independent review status: unavailable because the review workers exhausted workspace credits.
This record is local source validation, not an independent Class-A PASS.

## Contract and safety

The generator is read-only. It describes the exact production Workflow and issues separate bounded
execution-list calls for `ACTIVE` and `QUEUED`; it contains no deploy, execute, cancel, Scheduler,
storage, or BigQuery command. It requires exact revision, ACTIVE Workflow state, approved service
account, reviewed source identity, literal delivery false, and zero ACTIVE-or-QUEUED executions.
Failure returns a nonzero exit code.

Its output supplies the exact DDL 102 execution-census fields:

- `checked_at`;
- `workflow_revision`;
- `workflow_state`;
- `delivery_enabled`;
- `source_identity_passed`;
- `active_execution_count`.

## Verification

- `scripts/check_v3_common_execution_census.py`:
  `V3_COMMON_EXECUTION_CENSUS_STATIC=PASS`.
- Windows PowerShell AST parser: `V3_COMMON_EXECUTION_CENSUS_PARSE=PASS`.
- Read-only live run at `2026-08-27T12:26:58.7885286+00:00` returned PASS for Workflow revision
  `000011-291`, ACTIVE state, approved Compute service account, delivery false, source identity
  PASS, zero ACTIVE executions, and zero QUEUED executions. The two source mismatches were the
  already-known comment-only em-dash-to-question-mark serialization at candidate lines 1 and 371.

The live result is validation evidence for the generator only. It is not registered cutover
evidence and must not be reused: DDL 102 requires the census to be no more than five minutes old at
registration and claim time.

## Verdict

**BLOCK pending independent Class-A review together with DDL 102.** The source is safe to commit,
but must not be treated as an independent PASS or as authority to deploy DDL 102 or mutate either
Scheduler.

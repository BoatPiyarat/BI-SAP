# Class-A review request — V3 common Scheduler cutover control

Status: **NOT SENT / BLOCKED**. The 2026-08-27 Claude Code invocation was rejected by the execution
safety reviewer because the named internal deployment-control source would be transmitted to an
external destination. No source was sent and no independent verdict exists.

Review exact source checkpoints `e431337` and `56f168b`.

Read `docs/AGENT_RULES.md` first. Review only these named artifacts; ignore unrelated working-tree
changes:

- `sql/ddl/102_v3_common_scheduler_cutover_control.sql`
- `sql/operator/20260827_v3_common_scheduler_cutover_manual_fallback.sql`
- `scripts/check_v3_common_cutover_control.py`
- `scripts/build_v3_common_execution_census.ps1`
- `scripts/check_v3_common_execution_census.py`
- `docs/design/V3_PRODUCTION_CUTOVER_AND_SPLIT_ACTIVATION.md`
- `docs/reviews/2026-08-27-v3-common-cutover-control-source-review.md`
- `docs/reviews/2026-08-27-v3-common-execution-census-source-review.md`

This is an independent source-only Class-A review. Do not edit files, deploy, call a procedure,
write GCS, query BigQuery, run a Workflow, or mutate Scheduler/IAM/production.

Review both axes:

1. Standards/Safety: BigQuery Standard SQL validity, V3-only DDL scope, transaction/concurrency
   behavior, immutable evidence binding, freshness, exact Scheduler configuration/non-overlap,
   safe ABORTED/ROLLED_BACK transitions, and read-only fail-closed PowerShell behavior.
2. Spec: whether the package truthfully supports one common Tier-1 preparation cutover while
   leaving per-flow release separate and blocked unless independently eligible.

Return exactly one verdict, `PASS` or `BLOCK`, followed by numbered load-bearing findings and file/
line evidence. A source PASS does not authorize deployment or Scheduler mutation.

# Claude Code Class-A request — fresh V3 Units 1–5 pilot operator

Review commits `11b89d2` + `9591052` + `e11a9cd` read-only. Read exactly the
following 13 files and no others:

1. `scripts/run_v3_fresh_units1_5_delivery_disabled.ps1`
2. `scripts/v3_fresh_units1_5_delivery_disabled.flags.yaml`
3. `scripts/check_v3_fresh_units1_5_operator.py`
4. `sql/operator/20260827_preflight_fresh_v3_units1_5_pilot_v1.sql`
5. `sql/operator/20260827_report_fresh_v3_units1_5_pilot_v1.sql`
6. `scripts/build_v3_common_execution_census.ps1`
7. `infra/v3_nightly_orchestrator.workflows.yaml`
8. `sql/ddl/060_v3_daily_newpayment_archive.sql`
9. `sql/ddl/061_v3_units2_5_nightly_wrapper.sql`
10. `sql/ddl/063_v3_unit2_population_magnitude_gate.sql`
11. `docs/reviews/2026-08-27-unit2-pilot-bootstrap-deploy-evidence-codex.md`
12. `docs/AGENT_REVIEW_PROTOCOL.md`
13. `docs/design/SAP_INTERFACE_PRE_EXPORT_GATE.md`

## Evidence supplied

- `python scripts/check_v3_fresh_units1_5_operator.py`: PASS.
- Python compilation and `git diff --check`: PASS.
- Both exact SQL files received authenticated safe-wrapper dry-run PASS at 0 bytes on 2026-08-27;
  neither real query was executed during those dry-runs.
- Latest production metadata inspection showed the recent SAP extract API shape uses
  `status.completionTime`; the latest inspected executions were terminal, not active. This is
  shape evidence only, not authorization to run again.
- A live read-only preflight rehearsal found that `gcloud storage ls` returns exit 1 for a clean
  empty prefix. Its first correction used a client filter, which emitted a missing-filter-key
  warning on an empty result and was rejected before production use. The final operator calls
  `gcloud storage objects list gs://rcb-bronze-zone/SAP/production_database/** --limit=1`; the
  exact clean live prefix returned `[]` with exit 0 and no filter warning. Treat both as self-caught
  defects and verify the final replacement remains fail-closed on API errors and nonempty results.
- The final committed runner then completed its explicit `-PreflightOnly` path at
  `2026-08-27T15:16:17Z`: workflow/source/concurrency and Scheduler/extract/bronze gates passed;
  safe-wrapper BigQuery job `bqjob_r41f591606ed2d6d0_000001a043cb1348_1` passed every exact pilot
  assertion; output ended `FRESH_UNITS1_5_PREFLIGHT=PASS`, revision `000011-291`, and
  `PREFLIGHT_EXECUTION_CREATED=false`. No Workflow execution was created.

## Required verdict

Return `PASS`, `PASS WITH NOTES`, or `BLOCK`. Answer the review protocol checklist 1–12 explicitly
and include the anti-rubber-stamp risk statement. Focus especially on:

- whether the runner truly gates exact revision `000011-291`, source identity, delivery false,
  workflow concurrency, active SAP extraction, bronze ownership, both Scheduler prestates, and the
  legacy 20:30 overlap window before execution;
- whether the flags can invoke only the normal delivery-disabled path and cannot queue silently;
- whether the exact Unit 2 pilot configuration/bootstrap gate is fail-closed and protected against
  expiry during the run;
- whether the disclosed mutation boundary is honest: SAP read, bronze/load, V3 table writes, and
  possible restricted `rcb-bronze-zone` archive, but no promoter or `gs://interface-file/**` write;
- whether a threshold breach remains a hold and cannot be relabelled PASS;
- whether terminal execution identity and post-run evidence are strong enough for a separately
  approved one-time production execution.

Do not edit any file, run any query, execute the workflow, invoke Cloud Run, mutate Scheduler, read
GCS, deploy, or write a review file. Return the review text only to Codex.

# Finding — daily completeness human report is not wired

Status: **CONFIRMED FROM CANONICAL INVENTORY AND REVIEWED SOURCE; NO LIVE RECHECK IN THIS INCREMENT**

## Confirmed boundary

- `sql/ddl/067_v3_daily_completeness_snapshot.sql` is Class-A reviewed source for immutable
  run/metric/evidence snapshots, but `docs/AS_BUILT_V3.md` does not list those tables or its
  procedure as live.
- `infra/v3_nightly_orchestrator.workflows.yaml` and
  `sql/ddl/061_v3_units2_5_nightly_wrapper.sql` contain zero references to
  `sp_build_v3_daily_completeness_snapshot`.
- `workflows/v3_daily_completeness_report.gs` passed its base review and the batch-isolation note
  was resolved by reviewed commit `d85aa20`.
- `workflows/V3_DAILY_COMPLETENESS_REPORT_DEPLOYMENT.md` still labels the dispatcher source-only:
  no Apps Script deployment, properties, trigger, email, or BigQuery mutation is authorized or
  evidenced.
- A primary human recipient and a distinct independent fallback recipient remain required. The
  transfer-config owner mailbox alone does not prove either channel reaches Boat.

Therefore the goal condition “every hold/error appears in the human report” and the five-day
acceptance requirement are not operational. The workflow can persist other pipeline evidence, but
it neither creates this immutable completeness snapshot nor dispatches its human report.

## Required ordering

1. Deploy reviewed DDL 067 definitions without calling the snapshot procedure.
2. Add the snapshot call to the workflow only after the zero-file or exact delivered-manifest
   outcome is final. A nonzero archive without its exact manifest must fail the DDL 067 gate; do
   not snapshot before promotion/delivery persistence.
3. Record the snapshot job/procedure outcome in the same pipeline run and route any failure through
   the workflow's existing persist→alert→raise path.
4. Obtain and prove distinct primary/fallback recipients.
5. Deploy the reviewed completeness Apps Script in an owner-controlled project, configure only
   the documented properties/scopes, and install a reviewed bounded trigger.
6. Rehearse healthy-zero, delivered-file, primary success, primary failure/fallback success, both
   channels failed, multiple pending runs, duplicate/non-pending snapshot, and no-PII body.
7. Retain immutable BigQuery rows, trigger execution, and human receipt timestamps.

The completeness dispatcher and the SAP-result mailbox ingestor may share an Apps Script project
only if the owner intentionally deploys both reviewed sources and the union of reviewed scopes/
properties. A package containing only `sap_result_ingestion.gs` does not deploy the completeness
dispatcher.

No DDL, snapshot CALL, Apps Script project, property, OAuth grant, trigger, email, BigQuery row,
workflow, scheduler, GCS object, or SAP state changed in this finding.

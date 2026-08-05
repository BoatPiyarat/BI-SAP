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
2. Split snapshot timing by outcome:
   - healthy zero: the outbound workflow may snapshot after Units 2–5 completes with zero export
     runs/manifests;
   - nonzero export: do **not** snapshot immediately after delivery. DDL 067's immutable
     `SAP_RESULT` metrics would permanently capture `PENDING_ACK`. Defer until DDL 073 finishes
     row reconciliation with `pending_rows=0` and the manifest is terminal
     `ACKNOWLEDGED|PARTIAL_REJECT|REJECTED`.
3. Bind the post-import child back to exactly one original outbound `pipeline_run_id`. The current
   outbox/manifest carries `export_run_id`, not that original pipeline ID; derive it with exact
   export/payload identity conservation or persist it explicitly. Never use the child Unit-1
   pipeline ID as DDL 067's argument.
4. Strengthen DDL 067's nonzero gate so a merely `DELIVERED`/`PICKED_UP` manifest cannot produce a
   final immutable completeness snapshot. A `HUMAN_ACTION` residual remains a failed day and must
   alert; it cannot be labelled five-day acceptance.
5. Record the snapshot job/procedure outcome and route any failure through the workflow's existing
   persist→alert→raise path.
6. Obtain and prove distinct primary/fallback recipients.
7. Deploy the reviewed completeness Apps Script in an owner-controlled project, configure only
   the documented properties/scopes, and install a reviewed bounded trigger.
8. Rehearse healthy-zero, final ACK, partial/full reject, residual HUMAN_ACTION refusal, primary
   success, primary failure/fallback success, both channels failed, multiple pending runs,
   duplicate/non-pending snapshot, and no-PII body.
9. Retain immutable BigQuery rows, trigger execution, and human receipt timestamps.

The completeness dispatcher and the SAP-result mailbox ingestor may share an Apps Script project
only if the owner intentionally deploys both reviewed sources and the union of reviewed scopes/
properties. A package containing only `sap_result_ingestion.gs` does not deploy the completeness
dispatcher.

No DDL, snapshot CALL, Apps Script project, property, OAuth grant, trigger, email, BigQuery row,
workflow, scheduler, GCS object, or SAP state changed in this finding.

# DDL 103 Scenario 1 immutable month-end definition deployment evidence

Date: 2026-08-27 21:03 ICT

Reviewed source: commit `59a4521`,
`sql/ddl/103_v3_monthend_onetime_immutable_snapshot.sql`

Source SHA-256:
`72e18119792fd47e0ebe18bc118d710f7f77a34652c700b7835ac3440e9cc52c`

Independent review: **PASS WITH NOTES** in
`docs/reviews/2026-08-27-59a4521-claude.md`. The note requires a second reviewer pass before the
first live `CALL sp_build_v3_monthend_onetime_snapshot`; it does not block installing new inert
definitions. No procedure was called in this deployment.

Approval basis: Boat's standing instruction that the next independently passed scenario may be
deployed as a shorter production slice. These are new V3-owned objects, not replacements of
existing consumer objects.

Deployment job:
`pacific-plating-282708:asia-southeast1.codex_v3_ddl103_20260827_205449`

- mandatory safe-wrapper dry-run: PASS, 0 bytes;
- job state / statement: `DONE` / `SCRIPT`;
- `errorResult`: absent;
- processed bytes: 0;
- created: epoch milliseconds `1787838917681`;
- started: epoch milliseconds `1787838917732`;
- ended: epoch milliseconds `1787838921515`.

Prestate: targeted `bq show` returned not found for all five exact objects.

Created only in `pacific-plating-282708.sap_integration_v3`:

- `v3_monthend_onetime_payload`: zero rows, 60 columns, partitioned on `built_at`, clustered by
  `snapshot_run_id,OrderItem`;
- `v3_monthend_onetime_identity`: zero rows, 13 columns, partitioned on `built_at`, clustered by
  `snapshot_run_id,order_item`;
- `v3_monthend_onetime_hold`: zero rows, 14 columns, partitioned on `detected_at`, clustered by
  `snapshot_run_id,hold_code,order_item`;
- `v3_monthend_onetime_manifest`: zero rows, 12 columns, clustered by
  `snapshot_run_id,pipeline_run_id`;
- `sp_build_v3_monthend_onetime_snapshot`: SQL procedure with exact five-argument signature
  `STRING, STRING, DATE, DATE, DATE`.

Poststate is inert: every table remains empty. No snapshot build, export, GCS write, interface row,
Workflow execution, Scheduler mutation, SAP pickup/import, or ACK action occurred. The first live
snapshot call remains blocked on the review note's independent second pass, exact approved Unit 2
thresholds/bootstrap, and a fresh Scenario 1 build bound to the current open month.

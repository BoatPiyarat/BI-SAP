# DDL 102 common Scheduler cutover-control deployment evidence

Deployed source: commit `e431337`, `sql/ddl/102_v3_common_scheduler_cutover_control.sql`

Independent review: **PASS WITH NOTES**, `docs/reviews/2026-08-27-e431337-claude.md`. The note asks
for a second review before the first real cutover `CALL`; it does not block inert definition
installation. No procedure was called in this deployment.

Approval basis: Boat's standing instruction to deploy the next artifact when review passes, plus
Boat's `Approved` message on 2026-08-27 immediately before installation.

Deployment job: `pacific-plating-282708:asia-southeast1.codex_v3_ddl102_20260827_2041`

- mandatory safe-wrapper dry-run: PASS, 0 bytes;
- job state: `DONE`;
- `errorResult`: absent;
- statement type: `SCRIPT`;
- reported processed bytes: 8;
- started: epoch milliseconds `1787838113126`;
- ended: epoch milliseconds `1787838120991`.

Created only in `pacific-plating-282708.sap_integration_v3`:

- tables `v3_common_cutover_approval`, `v3_common_scheduler_cutover_ledger`,
  `v3_common_cutover_runtime_evidence`, and `v3_common_cutover_mutex`;
- procedures `sp_register_v3_common_cutover_runtime_evidence`,
  `sp_register_v3_common_cutover_approval`, `sp_claim_v3_common_scheduler_cutover`,
  `sp_finalize_v3_common_scheduler_cutover`, and `sp_close_v3_common_scheduler_cutover`;
- view `vw_v3_common_scheduler_cutover_control`.

Post-deploy inertness proof at 2026-08-27 20:43 ICT:

- approval table: zero rows;
- cutover ledger: zero rows;
- runtime-evidence table: zero rows;
- mutex: exactly the seeded `COMMON`, `lock_version=0` row;
- legacy `sap-extract-schedule`: `ENABLED`, `30 20 * * *`, `Asia/Bangkok`;
- `v3-nightly-orchestrator`: `PAUSED`, `30 20 * * *`, `Asia/Bangkok`.

Therefore this deployment installed rollback/cutover evidence definitions but did not claim or
activate a cutover, execute a Workflow, change either Scheduler, write GCS, create interface rows,
or touch SAP. First `CALL` remains blocked by exact numeric Unit 2 magnitude thresholds, fresh
non-bootstrap PASS evidence, exact cutover approval, and the review note's second-pass requirement.

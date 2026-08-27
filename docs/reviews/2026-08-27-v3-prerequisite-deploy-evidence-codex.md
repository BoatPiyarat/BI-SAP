# Deployment evidence — V3 bootstrap and workflow SQL prerequisites

Recorder: Codex (single deployer)
Date: 2026-08-27
Scope: DDL 099, DDL 067, and DDL 070 only
Verdict requested from Claude: deployment-evidence PASS/BLOCK

## Authorization and review provenance

- Boat's standing instruction allows the next production deployment when its Class-A review
  passes; Scheduler activation remains a separate approval.
- DDL 099 source verdict: PASS,
  `docs/reviews/2026-08-27-46bb3b9-claude.md`.
- Full workflow replacement verdict: PASS WITH NOTES,
  `docs/reviews/2026-08-27-8a420d7-full-delta-claude.md`; it requires DDL 067, current DDL 062,
  DDL 070, and the private promoter before workflow replacement.
- Live precheck found DDL 062 already present with the exact current 13-parameter signature;
  DDL 067 and `sap_delivery_manifest_v3.production_file_name` were absent.

## Production jobs

1. DDL 099 deployed only
   `sp_bootstrap_v3_unit2_magnitude`:
   `bqjob_r7c5302ba320cb0c8_000001a041055acc_1`, DONE, 0 bytes processed/billed.
   BigQuery Job API `creationTime=1787797265930`, `endTime=1787797266625`, principal
   `user:data@rabbit.co.th`.
2. DDL 067 deployed the three empty daily-completeness evidence tables and
   `sp_build_v3_daily_completeness_snapshot`:
   `bqjob_r55a7be3b2b248770_000001a04107efd3_1`, DONE.
3. DDL 070 added only the missing nullable `production_file_name` column; both existing tables and
   the already-present `event_identity_count` column were skipped:
   `bqjob_r57665e184876c0a5_000001a041087c78_1`, DONE.

No bootstrap or completeness procedure was called. No magnitude configuration, workflow,
Scheduler, Cloud Run service, GCS object, interface row, SAP row, pickup, import, or ACK state was
created by these deployments.

## Post-deploy proof

Authenticated read-only verification returned:

- `sp_bootstrap_v3_unit2_magnitude`: exactly 1 routine; live definition SHA-256
  `897ac6ce5ba99e60d5bf7eb2d0ca09cddde60f721c6c7943442862a83d3404b3`.
- `sp_build_v3_daily_completeness_snapshot`: exactly 1 routine; live definition SHA-256
  `e169bfd361d8c80ed8f90cfb92111f745791340edacbb52d975667337311fc1a`.
- `sp_mark_v3_exact_delivery`: exactly 1 routine, 13 parameters, zero name/order differences;
  live definition SHA-256
  `2177d29f14be8966b88ac738dd74383eb000e1b1a13fdcbd9ec2f78b858a8ce7`.
- `production_file_name` column count: 1.
- active magnitude configs: 0; bootstrap runs: 0.
- completeness run/metric/evidence rows: 0/0/0.

Queries:

- `sql/adhoc/20260827_verify_ddl099_deploy.sql`
- `sql/adhoc/20260827_verify_workflow_live_dependencies.sql`
- `sql/adhoc/20260827_verify_v3_prerequisite_deploy_no_runtime.sql`

## Remaining workflow blockers

The authenticated repository checker at `2026-08-27T02:25:17.8741884Z` still found:

- private `sap-delivery-promoter` absent;
- canonical PAUSED `v3-nightly-orchestrator` Scheduler absent;
- live workflow still old revision `000009-e96`, therefore lacking the reviewed two-name markers.

This evidence does not authorize or claim workflow, promoter, IAM, or Scheduler deployment.

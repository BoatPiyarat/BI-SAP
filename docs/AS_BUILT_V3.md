# AS-BUILT — sap_integration_v3

Live inventory of everything that actually exists in `sap_integration_v3` as of 2026-08-05,
cross-referenced to the `sql/ddl/` file that creates it, whether it's actually scheduled, and
whether it's documented anywhere. Compiled from `INFORMATION_SCHEMA.TABLES`/`ROUTINES` and
`bq ls --transfer_config` — not from memory of what was supposed to get built. Per
`TASK_V3_GAP_CLOSURE_v2.md` PHASE A housekeeping.

**Read this instead of trusting any older design doc's component-inventory table for "what's
live today"** — those (`SAP_PIPELINE_E2E_DESIGN_v3.md` §3 etc.) describe intent at design time;
this reflects `bq` output taken today.

## The 2 real BigQuery Data Transfer Service schedules

| Display name | Calls | Schedule | Failure email |
|---|---|---|---|
| `sap_state_and_recon_refresh` | `sp_nightly_state_and_recon_refresh()` | daily 21:00 (see transfer config; this is the only nightly entry point — everything below it runs as one chain) | ✅ enabled |
| `sap_dead_mans_switch` | `sp_check_dead_mans_switch()` | daily 22:00 ICT (15:00 UTC) | ✅ enabled |

No other `sap_integration_v3` object has its own independent schedule — everything else runs
either inside the one nightly chain above, on-demand (`ADHOC:` scope), or not at all yet.

## Tables (BASE TABLE)

| Object | Built by | In nightly chain? | Documented |
|---|---|---|---|
| `pipeline_run_log` | `001_create_sap_integration_v3.sql` | written by every `sp_refresh_*`/`sp_run_*` | README, all ddl headers |
| `stg_order_dim` | `011_stg_order_dim.sql` | ✅ (`sp_refresh_stg_order_dim`) | README, CHANGELOG 07-25 |
| `stg_payment_events` | `013_stg_payment_events.sql` | ✅ (`sp_refresh_stg_payment_events`) | README, CHANGELOG 07-25 |
| `stg_schedule` | `012_stg_schedule.sql` | ✅ (`sp_refresh_stg_schedule`) | README, CHANGELOG 07-25/07-26 (Credit-Shell fix) |
| `sap_mirror_doc` | `024_sap_mirror_doc.sql` | ✅ since `026` (`sp_refresh_sap_mirror_doc`) | README, FINDINGS_SAP_MIRROR, CHANGELOG 07-26/07-27 |
| `sap_mirror_state` | `025_sap_mirror_state.sql` | ✅ since `026` (`sp_refresh_sap_mirror_state`) | README, FINDINGS_SAP_MIRROR, CHANGELOG 07-26/07-27 |
| `recon_careos_charges` | `005_recon_all_charges.sql` | ✅ (`sp_recon_all_charges`) | README, CHANGELOG 07-25 |
| `expected_state` | `016_expected_state.sql` | ✅ (`sp_refresh_expected_state`) | README, CHANGELOG 07-25 |
| `sap_validation_error` | `017_sap_validation_error.sql` | ✅ (`sp_run_validation`) | README, CHANGELOG 07-25/07-26 |
| `delta_export` | `018_delta_export.sql` | ✅ (`sp_refresh_delta_export`) | README, CHANGELOG 07-25/07-26 |
| `sap_import_result_header_v3` | `064_sap_result_ingestion_contract.sql` | ❌ runtime not deployed | CHANGELOG 08-05 |
| `sap_import_error_detail_v3` | `064_sap_result_ingestion_contract.sql` | ❌ runtime not deployed | CHANGELOG 08-05 |
| `sap_file_pickup_v3` | `064_sap_result_ingestion_contract.sql` | ❌ runtime not deployed | CHANGELOG 08-05 |
| `sap_result_ingestion_heartbeat_v3` | `070_sap_result_ingestion_heartbeat.sql` | ❌ runtime not deployed | CHANGELOG 08-05 |
| `sap_delivery_manifest_v3` | `070_sap_result_ingestion_heartbeat.sql` | written by reviewed DDL 062 after exact promotion | CHANGELOG 08-05 |
| `v3_post_import_refresh_outbox` | `071_v3_post_import_refresh_outbox.sql` | ❌ publisher/dispatcher not deployed | CHANGELOG 08-05 |
| `v3_post_import_row_reconciliation` | `073_v3_post_import_row_reconciliation.sql` | ✅ deployed; written only by post-import child execution (runtime not activated) | CHANGELOG 08-05 |
| `manual_close_20260726_motor_newpayment_gap` | `021_backfill_motor_newpayment_gap_20260726.sql` | ❌ one-off audit table | CHANGELOG 07-26 |
| `manual_close_20260726_rcl_creditshell` | `022_backfill_rcl_creditshell_20260726.sql` | ❌ one-off audit table | CHANGELOG 07-26 |
| `manual_close_20260726_rcb_creditshell` | `023_backfill_rcb_creditshell_20260726.sql` | ❌ one-off audit table | CHANGELOG 07-26 |
| `_backfill_rcl_motor_newpayment_20260725` | `009`/CHANGELOG 07-25 (ad-hoc, not a numbered ddl CREATE) | ❌ one-off audit table | CHANGELOG 07-25 only |
| `_backfill_rcl_motor_20260725b` | `010_rcl_backfill_full_period_chunked.sql` | ❌ one-off audit table | CHANGELOG 07-25 |
| `_backfill_rcl_nonmotor_newpayment_20260725` | ad-hoc (same batch as above) | ❌ one-off audit table | CHANGELOG 07-25 only |
| `_backfill_rcl_nonmotor_20260725b` | `010_rcl_backfill_full_period_chunked.sql` | ❌ one-off audit table | CHANGELOG 07-25 |

**Housekeeping gap, not urgent**: the 7 one-off `_backfill_*`/`manual_close_*` audit tables are
intentionally-kept evidence trails (per each backfill's own changelog entry), not scheduled
objects — fine to leave, but worth a retention decision at some point (they'll never be cleaned
up automatically). Noted, not acted on here.

## Views

| Object | Built by | Scheduled? | Documented |
|---|---|---|---|
| `stg_sap_state` | `026_collapse_stg_sap_state_to_view.sql` (was a table via `002`, retired 07-27) | N/A — always fresh, derives from `sap_mirror_state` | README, CHANGELOG 07-27 |
| `SAP_LIVE_FULL_ALL_BU` | `007_sap_live_full_all_bu.sql` | ❌ not consumed anywhere yet (future-proofing only; 0 B2B rows today) | CHANGELOG 07-25 |
| `vw_dead_mans_switch` | `004_dead_mans_switch.sql` | read by `sp_check_dead_mans_switch` (scheduled) | README, CHANGELOG 07-24 |
| `vw_dash_completeness` | `006_dashboard_views.sql` | ❌ Looker Studio reads live, no BQ schedule needed | CHANGELOG 07-25 |
| `vw_dash_completeness_summary` | `006_dashboard_views.sql` | ❌ same | CHANGELOG 07-25 |
| `vw_dash_export_pipeline_health` | `006_dashboard_views.sql` | ❌ same | CHANGELOG 07-25 |
| `vw_dash_freshness` | `006_dashboard_views.sql` | ❌ same | CHANGELOG 07-25, **but see gap below** |

**Source-ready, not deployed (2026-08-04)**: `SAP_DASHBOARD_DESIGN_v1.md` Page 4 was corrected 2026-07-27 to
add an "extract-scheduler health" widget (the `sap-extract-schedule` 401 failure would've been
invisible on the old design). Source DDL 065 now defines
`vw_dash_extract_scheduler_health` from durable V3 workflow evidence. Because BigQuery cannot
read Cloud Scheduler/Logging directly and `sap_extract_control` is confirmed empty/dead, it keeps
the trigger itself `UNVERIFIED_TRIGGER` instead of letting a manual execution masquerade as
scheduler proof. Deployment remains a separate reviewed gate.

## Routines (procedures/functions)

| Object | Built by | Scheduled? | Documented |
|---|---|---|---|
| `sp_nightly_state_and_recon_refresh` | `008` → extended by `014`, `020`, **`026`** (current body) | ✅ `sap_state_and_recon_refresh`, 21:00 daily | README, CHANGELOG (every extension logged) |
| `sp_refresh_stg_order_dim` | `011` | ✅ inside nightly chain | README, CHANGELOG 07-25 |
| `sp_refresh_stg_payment_events` | `013` | ✅ inside nightly chain | README, CHANGELOG 07-25 |
| `sp_refresh_stg_schedule` | `012` | ✅ inside nightly chain | README, CHANGELOG 07-25/07-26 |
| `sp_refresh_sap_mirror_doc` | `024`, fixed `026`-adjacent (see CHANGELOG 07-27) | ✅ inside nightly chain since `026` | README, FINDINGS, CHANGELOG 07-26/07-27 |
| `sp_refresh_sap_mirror_state` | `025`, fixed 07-27 | ✅ inside nightly chain since `026` | README, FINDINGS, CHANGELOG 07-26/07-27 |
| `sp_refresh_sap_state` | `002` | ❌ **retired 07-27** — calling it now would fail (`CREATE OR REPLACE TABLE` against what is now a view) | README (marked retired), CHANGELOG 07-27 |
| `sp_recon_all_charges` | `005` | ✅ inside nightly chain | README, CHANGELOG 07-25 |
| `sp_refresh_expected_state` | `016` | ✅ inside nightly chain | README, CHANGELOG 07-25 |
| `sp_run_validation` | `017` | ✅ inside nightly chain | README, CHANGELOG 07-25/07-26 |
| `sp_enqueue_v3_post_import_refresh` | `071` | ❌ feature-gated runtime not deployed | CHANGELOG 08-05 |
| `sp_claim_v3_post_import_refresh` | `072` | ✅ deployed; dispatcher runtime absent | CHANGELOG 08-05 |
| `sp_bind_v3_post_import_execution` | `072` | ✅ deployed; dispatcher runtime absent | CHANGELOG 08-05 |
| `sp_release_v3_post_import_claim` | `072` | ✅ deployed; dispatcher/watchdog runtimes absent | CHANGELOG 08-05 |
| `sp_complete_v3_post_import_refresh` | `072` | ✅ deployed; dispatcher/watchdog runtimes absent | CHANGELOG 08-05 |
| `sp_reconcile_v3_post_import_rows` | `073` | ✅ deployed; post-import runtime not activated | CHANGELOG 08-05 |
| `sp_refresh_delta_export` | `018` | ✅ inside nightly chain | README, CHANGELOG 07-25/07-26 |
| `sp_check_dead_mans_switch` | `004` | ✅ `sap_dead_mans_switch`, 22:00 ICT daily | README, CHANGELOG 07-24 |
| `sp_backfill_rcl_newpayment_chunked` | `010` | ❌ callable on-demand only, one-off tool | README, CHANGELOG 07-25 |
| `fn_invoice_no` | `015` | N/A (UDF) — confirmed actually called from `016_expected_state.sql` (both the ONETIME and RCL branches) | README, CHANGELOG 07-25 |

## Summary

- Everything with a nightly-relevant role is wired into the **one** schedule
  (`sap_state_and_recon_refresh`, 21:00 daily) — no orphaned "built but never scheduled" objects
  remain in the core pipeline as of this inventory (the `stg_sap_state` collapse today closed the
  last one: `sp_refresh_sap_state` used to be the nightly-scheduled writer, now retired in favor of
  `sap_mirror_doc`/`sap_mirror_state`).
- Extract-scheduler-health widget source is ready in DDL 065; deployment and durable scheduler
  trigger provenance remain open.
- `v3-nightly-orchestrator` revision `000008-4e4` is ACTIVE with the reviewed post-import
  self-bind/reconciliation path and `delivery_enabled: false`. It has no Scheduler target; the
  private dispatcher revision `sap-post-import-dispatcher-00001-qd4`, unscheduled watchdog job,
  input/DLQ topics, and DLQ evidence subscription now exist but are inert pending IAM and
  rehearsal. No push subscription, watchdog scheduler, or Gmail publisher setting exists.
- 7 one-off audit tables from prior backfills are intentionally unscheduled and undocumented beyond
  their originating changelog entry — acceptable, flagged for an eventual retention decision only.
- V3 still writes **no interface file** — every object above feeds `expected_state`/`delta_export`
  (diagnostics), not `gs://interface-file/`. That's PHASE B/C/D, not yet done.

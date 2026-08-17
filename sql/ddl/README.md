# sql/ddl

New objects for `sap_integration_v3` (dataset, tables, stored procedures) introduced by
the v3 redesign. Distinct from `sql/production` (the *existing* per-flow queries being
migrated) and `sql/adhoc` (one-off urgent-session scripts).

> ⚠️ **Corrected 2026-07-27**: this table only listed the first 3 files and described 002/003
> against `raw_sap_live`, which never existed (see `docs/knowledge/10_SAP_CONTEXT.md`
> §ARCHITECTURE). All of `sap_integration_v3` is built from `sap_integration_v2.SAP_LIVE_FULL`.
> Full up-to-date file list below; see `docs/knowledge/30_SAP_CHANGELOG.md` for build history.

Numbered so they can be applied in order the first time the dataset is stood up. Live status
of each is whatever's currently deployed in BigQuery — check `pipeline_run_log` / the changelog,
not this table, for day-to-day freshness.

| File | Purpose |
|---|---|
| 001_create_sap_integration_v3.sql | Dataset + `pipeline_run_log` control table |
| 002_sp_refresh_sap_state.sql | **Retired 2026-07-27** — built `stg_sap_state` as its own table from `SAP_LIVE_FULL`; superseded by 026 (`stg_sap_state` is now a view over `sap_mirror_state`). No longer called by the nightly chain; kept for history/the `DocEntry DESC` tiebreak fix reference |
| 003_PROPOSED_repoint_sap_live_full.sql | **Retired 2026-07-24** — original plan (repoint `SAP_LIVE_FULL` to `raw_sap_live`) moot since that table never existed; kept for history only, do not run |
| 004_dead_mans_switch.sql | Freshness check on `SAP_LIVE.BatchRunDate` + scheduled-query alert |
| 005_recon_all_charges.sql | 3-bucket CareOS↔SAP charge reconciliation |
| 006_dashboard_views.sql | 4 Looker Studio views (`vw_dash_*`) |
| 007_sap_live_full_all_bu.sql | `SAP_LIVE_FULL_ALL_BU` — same as `SAP_LIVE_FULL` minus the B2B filter (future-proofing; 0 B2B rows currently) |
| 008_schedule_state_recon_refresh.sql | Nightly scheduled query wiring `sp_refresh_sap_state` + recon |
| 009_fix_rcl_newpayment_date_override.sql | PaymentDate-in-locked-period fix for RCL newpayment views |
| 010_rcl_backfill_full_period_chunked.sql | `sp_backfill_rcl_newpayment_chunked` — full-period-per-order backfill, chunked export |
| 011_stg_order_dim.sql | P1 staging: materialized order-dimension JSON parse |
| 012_stg_schedule.sql | P1 staging: 1 row/(order_item, period) spine |
| 013_stg_payment_events.sql | P1 staging: charge-driven population source |
| 014_extend_nightly_refresh_with_p1_staging.sql | Wires P1 staging into the nightly refresh chain |
| 015_fn_invoice_no.sql | `fn_invoice_no` UDF — single InvoiceNo standard (raw `third_party_id`, rank-prefixed only for additional payments) |
| 016_expected_state.sql | P2 L3 engine: joins P1 staging into "what SAP should show" |
| 017_sap_validation_error.sql | Blocking validation checks (PK_DUP, SCHEDULE_GAP, MASTER_INSURER_UNKNOWN, MASTER_PAYMENTDATE_LOCKED) |
| 018_delta_export.sql | P3: diffs `expected_state` vs `stg_sap_state` at (order_item, period) grain |
| 019_fix_column_reordering_bug.sql | Fixes the `SELECT * EXCEPT(col), expr AS col` column-reordering bug (use `* REPLACE` instead) |
| 020_extend_nightly_refresh_with_p2_p3.sql | Wires P2/P3 (expected_state, validation, delta_export) into the nightly chain |
| 021_backfill_motor_newpayment_gap_20260726.sql | One-off: 279-row confirmed Motor newpayment gap backfill |
| 022_backfill_rcl_creditshell_20260726.sql | One-off: 37-row RCL Credit-Shell gap backfill |
| 023_backfill_rcb_creditshell_20260726.sql | One-off: 41-row RCB Credit-Shell gap backfill |
| 024_sap_mirror_doc.sql | Doc-grain SAP mirror, one row per `DocEntry`. **RULE-03 2026-07-31:** appends native `UpdateDate`/`UpdateTime` after `BatchRunDate` in all four branches and deduplicates by recency, then `DocEntry` |
| 025_sap_mirror_state.sql | State-grain SAP mirror, one row per (OrderItem, Period). Preserves status/InvoiceNo priority, resolves remaining ties by `UpdateDate`/`UpdateTime`, and tags multi-doc picks `MULTI_DOC_RESOLVED_BY_RECENCY` while retaining `docs_considered` |
| 026_collapse_stg_sap_state_to_view.sql | Collapses `stg_sap_state` (was its own table, 002) into a view over `sap_mirror_state` — one picking rule instead of two; repoints the nightly chain to refresh `sap_mirror_doc`/`sap_mirror_state` instead of calling the now-retired `sp_refresh_sap_state` |
| 034_expected_state_exclusion_rules.sql | **Superseded by 037; kept for history only.** Earlier E1/E2/E3 definition of `sp_refresh_expected_state`; do not apply after 037 |
| 037_fix_expected_invoice_no_null_unsafe.sql | **Live source definition of `sp_refresh_expected_state`; source-only changes pending Class A review.** Includes NULL-safe InvoiceNo, RULE-01/02/08, and the 2026-08-01 E1-E3 tier/exclusion rules. Final E1 supersedes the former RULE-09 old-year rescue |
| 043_sap_mirror_doc_merge_incremental.sql | **Source only / not deployed.** Incremental replacement proposal for 024. Commit `6ef690b` fixes the CALL-time DATE/TIMESTAMP mismatch and invalid watermark aggregation; meaningful MERGE/CALL validation waits for reviewed 024 and a new Class A PASS |
| 044_sap_period_lock_and_payment_date_clamp.sql | Creates the RULE-01/02 period-lock control; apply before the current 037 expected-state procedure that clamps PaymentDate and emits `payment_date_clamped` |
| 045_sap_import_result_schema_v2.sql | **Source only / not deployed.** Creates non-destructive partitioned shadow `sap_import_result_v2`; parser K1/K2/K3 and separate swap gate required |
| 046_exclusion_format_morning_report.sql | **Source only / Class A.** Separates E1-E3 exclusions, F1-F3 validation signals, insurer-code list, and real backlog in the morning report |
| 048_july_export_shadow_and_archive.sql | **Source only / Class A.** Fail-closed July raw-PaymentDate 56-column shadow plus row-level archive schema; no GCS write |
| 049_export_july_payment_to_gcs.sql | **Source only / Class A.** July-only explicit 56-column export to restricted archive; UAT2 + exact-byte production promotion are separate mandatory stages |
| 050_v3_onetime_payload_source.sql | V3-owned ONETIME 56-column payload source captured from the verified live contract; not a daily release gate by itself |
| 051_v3_unit2_shadow_classifier.sql | Unit 2 event/schedule classifier with independent conservation and terminal SAP-state holds |
| 052_v3_unit3_closed_mapping_registries.sql | **Source only / Class A.** Effective-dated InsuranceGroup/payment registries and fail-closed Unit 3 mapping holds; no seed values included |
| 054_v3_automation_release_gate.sql | **Source only / Class A.** Durable fail-closed gate between Units 1–4 and Unit 5; UNKNOWN/mapping holds are skipped only with exact quarantine coverage, while missing evaluation/open-period defects block release |
| 055_v3_notification_quarantine.sql | **Source only / Class A.** Quarantines UNKNOWN/mapping-held rows and materializes notification detail with order_item before Unit 5 |
| 056_seed_nonmotor_insurance_group_exact_matches.sql | **Source only / Class A config mutation.** Effective 2026-08-01 exact Health/Life NonMotor mappings for RCB/RCL; all other live categories remain held |
| 057_seed_payment_mappings_v2_success.sql | V2/SAP-success non-credit PaymentMethod/PaymentChannel mappings; credit-shell remains held |
| 058_v3_unit5_newpayment_shadow.sql | **Source only / Class A.** Exact-event 56-column NEWPAYMENT shadow; CREATE remains held on source gaps; no GCS write |
| 059_v3_unit5_balance_hold.sql | Unit 5 item-level balance quarantine and delivery-ready conservation |
| 060_v3_daily_newpayment_archive.sql | Immutable daily NEWPAYMENT archive exporter |
| 061_v3_units2_5_nightly_wrapper.sql | Ordered Units 2–5 wrapper; now invokes the magnitude gate before Unit 3 |
| 062_v3_mark_exact_delivery.sql | Exact-generation delivery ledger gate |
| 063_v3_unit2_population_magnitude_gate.sql | **Source only / Class A.** Approved-config prior-run distribution gate; no threshold seed |
| 064_sap_result_ingestion_contract.sql | **Source only / Class A.** Non-destructive attachment-first SAP result header, detail, and pickup evidence contract |
| 065_vw_dash_extract_scheduler_health.sql | **Source only / Class A.** Fail-closed orchestrator execution-health widget; scheduler trigger provenance remains explicit/unverified |
| 066_interface_status_history_increase_alert.sql | **Source only / Class A.** Immutable daily status snapshots and approved-config day-over-day increase alert; no threshold seed |
| 067_v3_daily_completeness_snapshot.sql | **Source only / Class A.** Immutable normalized Unit 6 run/metric/evidence snapshot; human alert delivery remains independently pending |
| 068_validation_regression_history_alert.sql | **Source only / Class A.** Per-check immutable history and approved day-over-day regression thresholds; replaces obsolete total-count heuristic |
| 069_v3_manual_newpayment_archive.sql | **Source only / Class A.** Explicit-scope, archive-only `sp_manual_export` for proven RCB_MOTOR NEWPAYMENT; persists requester/scope audit, while unsupported contracts and replays fail closed |
| 077_mo_rcl_recovery_request.sql | **Source only / Class A.** Immutable Mo-list request seeding and one-decision-per-pair RCL mapping classification; no payload or GCS write |
| 053_v3_unit4_period_state_machine.sql | Explicit OPEN/CLOSED/PLANNED monthly state, atomic close/open, and legacy period-lock compatibility |
| 047_repoint_nightly_mirror_to_incremental.sql | **Source only / Class A.** Chain 3 cutover definition: changes the nightly mirror call from full 024 to incremental 043 without altering downstream order; includes an exact 024-call rollback definition |

Every file is a full runnable script (per AGENTS.md: no diffs-as-answer). Apply with:
```
bq query --use_legacy_sql=false < sql/ddl/00X_name.sql
```

## Creating a new table

Copy `_TEMPLATE_new_table.sql` (2026-07-30 convention). In short: any new `diag_*`/scratch
table must set `OPTIONS(expiration_timestamp = TIMESTAMP_ADD(CURRENT_TIMESTAMP(), INTERVAL 30
DAY))` in its `CREATE TABLE`, no exceptions. This does **not** apply retroactively — the 7
pre-existing `_backfill_*`/`manual_close_*` tables are explicitly out of scope, waiting on a
separate retention decision; do not set expiration on them. Always dry-run first
(`scripts/bq_safe_query.sh`, per `docs/COST_CONTROL.md` §3.1).

# sql/ddl

New objects for `sap_integration_v3` (dataset, tables, stored procedures) introduced by
the v3 redesign. Distinct from `sql/production` (the *existing* per-flow queries being
migrated) and `sql/adhoc` (one-off urgent-session scripts).

Numbered so they can be applied in order the first time the dataset is stood up:

| File | Purpose | Status |
|---|---|---|
| 001_create_sap_integration_v3.sql | Dataset + `pipeline_run_log` control table | Ready to run |
| 002_sp_refresh_sap_state.sql | `stg_sap_state` from `raw_sap_live` (P0) | Ready to run, pending schema check (see file header) |
| 003_PROPOSED_repoint_sap_live_full.sql | Repoint `SAP_LIVE_FULL` to `raw_sap_live` | **DO NOT RUN** — proposal only, needs approval (see file header) |

Every file is a full runnable script (per AGENTS.md: no diffs-as-answer). Apply with:
```
bq query --use_legacy_sql=false < sql/ddl/00X_name.sql
```

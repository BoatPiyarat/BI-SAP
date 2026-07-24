-- 001_create_sap_integration_v3.sql
-- Creates the sap_integration_v3 dataset and the pipeline_run_log control table
-- referenced by every sp_refresh_*/sp_validate/sp_export_delta procedure.
-- Design ref: SAP_DATA_PREP_DESIGN_v3.md §1, SAP_RUNBOOK_v3.md §1
-- Safe to re-run: CREATE ... IF NOT EXISTS throughout.

CREATE SCHEMA IF NOT EXISTS `pacific-plating-282708.sap_integration_v3`
OPTIONS (
  location = 'asia-southeast1',
  description = 'SAP <-> CareOS interface pipeline v3 (56-column redesign). See docs/design/SAP_INTERFACE_REDESIGN_V3.md.'
);

CREATE TABLE IF NOT EXISTS `pacific-plating-282708.sap_integration_v3.pipeline_run_log` (
  run_id          STRING NOT NULL,
  run_type        STRING NOT NULL,   -- NIGHTLY | ADHOC
  step            STRING NOT NULL,   -- extract | sap_state | recon | order_dim | payment_events | schedule | engine | validate | export
  scope           STRING,            -- 'FULL' or 'ADHOC:<order_ids>'
  rows_in         INT64,
  rows_out        INT64,
  started_at      TIMESTAMP NOT NULL,
  ended_at        TIMESTAMP,
  status          STRING NOT NULL,   -- SUCCESS | FAILED
  error_message   STRING
)
PARTITION BY DATE(started_at)
CLUSTER BY run_id, step;

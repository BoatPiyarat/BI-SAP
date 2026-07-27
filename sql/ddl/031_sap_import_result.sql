-- 031_sap_import_result.sql
-- TASK_V3_GAP_CLOSURE_v2.md A3. Confirmed from project history (30_SAP_CHANGELOG.md 2026-07-25/26
-- entries): SAP import result logs are NOT machine-delivered anywhere in this project - every
-- prior import-error diagnosis (column-reordering incident, PolicyStatus duplicate, InsurerCode
-- not found, etc.) started from Boat manually pasting/sharing log text from Aware. Per A3's own
-- conditional ("if the log isn't sent automatically, write the manual step into the runbook and
-- say so") - this is exactly that case. No automatic ingestion pipeline exists or is being built;
-- this is a landing table + a documented manual load step.

CREATE TABLE IF NOT EXISTS `pacific-plating-282708.sap_integration_v3.sap_import_result` (
  batch_label STRING,       -- free text, e.g. the source filename or "20260725_nonmotor"
  file_name STRING,         -- the interface file this error was reported against, if known
  order_item STRING,        -- parsed from the error text where possible; NULL if not identifiable
  error_type STRING,        -- e.g. 'PolicyStatus duplicated', 'InsurerCode not found', 'Period sequence invalid'
  message STRING,           -- the raw error line/message
  reported_at TIMESTAMP,    -- when Aware/SAP reported this (if known from the log; else NULL)
  ingested_at TIMESTAMP     -- when this row was loaded into BigQuery
);

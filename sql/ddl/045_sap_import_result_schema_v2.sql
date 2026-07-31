-- SOURCE ONLY — DO NOT APPLY without Boat approval and parser K1/K2/K3 gate.
-- Live table had 0 rows on 2026-07-31. BigQuery cannot replace it with a different partition spec.
-- This script creates a non-destructive shadow table. Swap/drop/rename is a separate reviewed gate.
-- BigQuery may retain the raw SAP error message for restricted diagnosis. Never copy or quote
-- message_raw into repository files, documentation, review artifacts, logs, or chat.
-- No expiration: this is durable audit evidence, not a scratch/diag table. Retention needs review.

CREATE TABLE IF NOT EXISTS `pacific-plating-282708.sap_integration_v3.sap_import_result_v2` (
  log_id STRING NOT NULL,
  file_name STRING,
  import_type STRING,
  status STRING,
  order_item STRING,
  period INT64,
  error_type STRING,
  error_code STRING,
  row_number INT64,
  rows_total INT64,
  rows_failed INT64,
  imported_at TIMESTAMP NOT NULL,
  source STRING NOT NULL,
  message_raw STRING OPTIONS(description = 'Restricted BigQuery-only raw SAP error text; may contain PII'),
  error_template STRING OPTIONS(description = 'Sanitized error template safe for reports and documentation')
)
PARTITION BY DATE(imported_at)
CLUSTER BY log_id, order_item, error_type
OPTIONS (description = 'Restricted SAP import-result audit; message_raw stays in BigQuery, while error_template is sanitized for reporting');

-- SOURCE ONLY — DO NOT APPLY without Boat approval and parser K1/K2/K3 gate.
-- Live table had 0 rows on 2026-07-31. BigQuery cannot replace it with a different partition spec.
-- This script creates a non-destructive shadow table. Swap/drop/rename is a separate reviewed gate.
-- Never store raw email body/header/attachment or raw error text here.
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
  error_message_template STRING
)
PARTITION BY DATE(imported_at)
CLUSTER BY log_id, order_item, error_type
OPTIONS (description = 'Sanitized SAP import-result audit; no raw email/header/attachment/PII');

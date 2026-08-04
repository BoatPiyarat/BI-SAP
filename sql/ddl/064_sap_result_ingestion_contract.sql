-- SOURCE ONLY / Class A.
-- Non-destructive storage contract for bounded, attachment-first SAP result ingestion.
-- These tables do not replace the legacy sap_import_result table. A parser rehearsal,
-- migration/swap plan, review PASS, and separate deploy approval remain required.
-- Raw SAP messages stay in restricted BigQuery columns and must not be copied into docs or chat.

CREATE TABLE IF NOT EXISTS
  `pacific-plating-282708.sap_integration_v3.sap_import_result_header_v3` (
    log_id STRING NOT NULL,
    file_name STRING NOT NULL,
    status STRING NOT NULL,
    import_type STRING,
    company_db STRING NOT NULL,
    email_date TIMESTAMP NOT NULL,
    gmail_message_id STRING NOT NULL,
    txt_gcs_uri STRING NOT NULL,
    xlsx_gcs_uri STRING,
    je_reference STRING,
    reconciliation_reference STRING,
    attachment_parse_status STRING NOT NULL,
    ingested_at TIMESTAMP NOT NULL
  )
PARTITION BY DATE(email_date)
CLUSTER BY log_id, file_name, company_db
OPTIONS (
  description = 'Restricted immutable SAP import-result headers; logical key log_id'
);

CREATE TABLE IF NOT EXISTS
  `pacific-plating-282708.sap_integration_v3.sap_import_error_detail_v3` (
    log_id STRING NOT NULL,
    detail_seq INT64 NOT NULL,
    error_class STRING NOT NULL,
    error_template STRING,
    error_message_raw STRING
      OPTIONS(description = 'Restricted BigQuery-only raw SAP error text; may contain PII'),
    row_ref STRING,
    order_item STRING,
    period INT64,
    parsed_at TIMESTAMP NOT NULL
  )
PARTITION BY DATE(parsed_at)
CLUSTER BY log_id, error_class, order_item
OPTIONS (
  description = 'Restricted SAP attachment details; logical key (log_id, detail_seq)'
);

CREATE TABLE IF NOT EXISTS
  `pacific-plating-282708.sap_integration_v3.sap_file_pickup_v3` (
    pickup_key STRING NOT NULL,
    gmail_message_id STRING NOT NULL,
    file_name STRING NOT NULL,
    company_db STRING NOT NULL,
    email_date TIMESTAMP NOT NULL,
    pickup_status STRING NOT NULL,
    ingested_at TIMESTAMP NOT NULL
  )
PARTITION BY DATE(email_date)
CLUSTER BY pickup_key, file_name, company_db
OPTIONS (
  description = 'DOWNLOAD_GCS_FILE evidence only; never interpreted as SAP import success'
);

-- BigQuery does not enforce primary keys. The ingestion writer must MERGE header rows by log_id,
-- detail rows by (log_id, detail_seq), and pickup rows by pickup_key. Before any downstream ACK
-- consumer is deployed, its release gate must assert all three logical-key duplicate counts are 0.
-- A header status is terminal only when company_db='RCB_LIVE_DB', attachment_parse_status='PARSED',
-- the TXT URI is present, and the exact file_name matches one current delivery manifest.

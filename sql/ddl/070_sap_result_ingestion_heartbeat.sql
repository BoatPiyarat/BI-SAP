-- SOURCE ONLY / Class A.
-- Durable heartbeat for the separately deployed Apps Script SAP-result ingestor.
-- No schedule, Gmail access, GCS write, or BigQuery mutation occurs by adding this source file.

CREATE TABLE IF NOT EXISTS
  `pacific-plating-282708.sap_integration_v3.sap_result_ingestion_heartbeat_v3` (
    ingestor_name STRING NOT NULL,
    last_success_at TIMESTAMP NOT NULL,
    last_poll_started_at TIMESTAMP NOT NULL,
    last_poll_outcome STRING NOT NULL,
    last_message_count INT64 NOT NULL,
    last_error_template STRING,
    recorded_at TIMESTAMP NOT NULL
  )
PARTITION BY DATE(recorded_at)
CLUSTER BY ingestor_name
OPTIONS (
  description = 'Immutable-latest-upsert heartbeat for the SAP-result Gmail ingestor; a missing or stale heartbeat is an alert condition.'
);

CREATE TABLE IF NOT EXISTS
  `pacific-plating-282708.sap_integration_v3.sap_delivery_manifest_v3` (
    export_run_id STRING NOT NULL,
    production_uri STRING NOT NULL,
    production_generation STRING NOT NULL,
    sap_file_name STRING NOT NULL,
    file_sha256 STRING NOT NULL,
    data_row_count INT64 NOT NULL,
    delivery_status STRING NOT NULL,
    recorded_at TIMESTAMP NOT NULL,
    production_file_name STRING NOT NULL
  )
PARTITION BY DATE(recorded_at)
CLUSTER BY sap_file_name, export_run_id
OPTIONS (
  description = 'Two-name delivery identity: production_file_name is the exact GCS basename; sap_file_name is the exact SAP-reported result name.'
);

ALTER TABLE `pacific-plating-282708.sap_integration_v3.sap_delivery_manifest_v3`
ADD COLUMN IF NOT EXISTS production_file_name STRING;

-- Deployment gate: the runtime writer must MERGE exactly one logical row per ingestor_name and
-- the independent monitor must alert before a 60-minute successful-poll gap. The promotion writer
-- must MERGE one active delivery-manifest row with the exact SAP-facing filename, generation, and
-- hash; it must persist both the exact production basename and SAP-reported result name. A
-- ScriptProperties timestamp is not
-- sufficient evidence because it is not independently observable.

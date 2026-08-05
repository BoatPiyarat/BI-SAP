-- Class A / source only. Durable, idempotent handoff from a persisted SAP LIVE import result
-- to a later Unit-1-only post-import refresh dispatcher. This file creates no trigger or workflow.
-- Depends on 064_sap_result_ingestion_contract.sql and 070_sap_result_ingestion_heartbeat.sql.

CREATE TABLE IF NOT EXISTS `pacific-plating-282708.sap_integration_v3.v3_post_import_refresh_outbox` (
  log_id STRING NOT NULL,
  export_run_id STRING NOT NULL,
  sap_file_name STRING NOT NULL,
  import_status STRING NOT NULL,
  email_date TIMESTAMP NOT NULL,
  request_status STRING NOT NULL,
  workflow_execution_name STRING,
  claimed_at TIMESTAMP,
  completed_at TIMESTAMP,
  attempt_count INT64 NOT NULL,
  last_error_template STRING,
  requested_at TIMESTAMP NOT NULL
)
PARTITION BY DATE(requested_at)
CLUSTER BY log_id, export_run_id, request_status
OPTIONS (description = 'Idempotent post-import Unit-1 refresh requests; logical key log_id bound to one delivery manifest.');

CREATE OR REPLACE PROCEDURE `pacific-plating-282708.sap_integration_v3.sp_enqueue_v3_post_import_refresh`(
  p_log_id STRING,
  p_export_run_id STRING,
  p_sap_file_name STRING,
  p_import_status STRING,
  p_email_date TIMESTAMP
)
BEGIN
  ASSERT NULLIF(TRIM(p_log_id), '') IS NOT NULL AS 'log_id is required';
  ASSERT NULLIF(TRIM(p_export_run_id), '') IS NOT NULL AS 'export_run_id is required';
  ASSERT NULLIF(TRIM(p_sap_file_name), '') IS NOT NULL AS 'sap_file_name is required';
  ASSERT p_email_date IS NOT NULL AS 'email_date is required';
  ASSERT LOWER(TRIM(p_import_status)) IN ('success', 'success with error')
    AS 'only evidenced terminal SAP import statuses may enqueue a post-import refresh';
  ASSERT (SELECT COUNT(*)
    FROM `pacific-plating-282708.sap_integration_v3.sap_delivery_manifest_v3`
    WHERE export_run_id=p_export_run_id AND sap_file_name=p_sap_file_name AND delivery_status='DELIVERED')=1
    AS 'refresh request must bind one exact delivered SAP manifest';
  ASSERT (SELECT COUNT(*)
    FROM `pacific-plating-282708.sap_integration_v3.sap_import_result_header_v3`
    WHERE log_id=p_log_id AND file_name=p_sap_file_name AND company_db='RCB_LIVE_DB'
      AND attachment_parse_status='PARSED' AND LOWER(TRIM(status))=LOWER(TRIM(p_import_status)))=1
    AS 'refresh request requires one persisted parsed LIVE SAP result header';
  ASSERT (SELECT COUNT(*)
    FROM `pacific-plating-282708.sap_integration_v3.v3_post_import_refresh_outbox`
    WHERE log_id=p_log_id AND (export_run_id!=p_export_run_id OR sap_file_name!=p_sap_file_name))=0
    AS 'log_id is already bound to a different delivery manifest';

  BEGIN TRANSACTION;
  MERGE `pacific-plating-282708.sap_integration_v3.v3_post_import_refresh_outbox` t
  USING (SELECT p_log_id log_id) s ON t.log_id=s.log_id
  WHEN NOT MATCHED THEN INSERT
    (log_id,export_run_id,sap_file_name,import_status,email_date,request_status,workflow_execution_name,
     claimed_at,completed_at,attempt_count,last_error_template,requested_at)
  VALUES
    (p_log_id,p_export_run_id,p_sap_file_name,LOWER(TRIM(p_import_status)),p_email_date,'PENDING',NULL,
     NULL,NULL,0,NULL,CURRENT_TIMESTAMP());
  ASSERT @@row_count IN (0,1) AS 'outbox enqueue affected an unexpected number of rows';
  COMMIT TRANSACTION;
END;

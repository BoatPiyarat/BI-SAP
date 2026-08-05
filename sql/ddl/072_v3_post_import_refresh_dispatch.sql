-- Class A / source only. Atomic dispatcher state transitions for DDL 071's durable outbox.
-- This file does not create a Pub/Sub topic, start a workflow, refresh SAP, or change ACK state.

CREATE OR REPLACE PROCEDURE `pacific-plating-282708.sap_integration_v3.sp_claim_v3_post_import_refresh`(
  p_log_id STRING,
  p_export_run_id STRING,
  p_sap_file_name STRING,
  p_workflow_execution_name STRING
)
BEGIN
  ASSERT NULLIF(TRIM(p_log_id),'') IS NOT NULL AS 'log_id is required';
  ASSERT NULLIF(TRIM(p_export_run_id),'') IS NOT NULL AS 'export_run_id is required';
  ASSERT NULLIF(TRIM(p_sap_file_name),'') IS NOT NULL AS 'sap_file_name is required';
  ASSERT REGEXP_CONTAINS(p_workflow_execution_name,
    r'^projects/[a-z][a-z0-9-]{4,28}[a-z0-9]/locations/[a-z0-9-]+/workflows/[A-Za-z0-9_-]+/executions/[A-Za-z0-9_-]+$')
    AS 'workflow_execution_name must be a complete Workflows execution resource name';
  ASSERT (SELECT COUNT(*)
    FROM `pacific-plating-282708.sap_integration_v3.v3_post_import_refresh_outbox`
    WHERE log_id=p_log_id AND export_run_id=p_export_run_id AND sap_file_name=p_sap_file_name)=1
    AS 'claim must bind exactly one outbox row';
  ASSERT (SELECT COUNT(*)
    FROM `pacific-plating-282708.sap_integration_v3.v3_post_import_refresh_outbox`
    WHERE workflow_execution_name=p_workflow_execution_name AND log_id!=p_log_id)=0
    AS 'workflow execution name is already bound to another LogID';

  BEGIN TRANSACTION;
  UPDATE `pacific-plating-282708.sap_integration_v3.v3_post_import_refresh_outbox`
  SET request_status='STARTED',workflow_execution_name=p_workflow_execution_name,
      claimed_at=CURRENT_TIMESTAMP(),attempt_count=attempt_count+1,last_error_template=NULL
  WHERE log_id=p_log_id AND export_run_id=p_export_run_id AND sap_file_name=p_sap_file_name
    AND request_status='PENDING' AND attempt_count<3;
  ASSERT @@row_count IN (0,1) AS 'claim affected an unexpected number of rows';
  ASSERT (SELECT COUNT(*)
    FROM `pacific-plating-282708.sap_integration_v3.v3_post_import_refresh_outbox`
    WHERE log_id=p_log_id AND export_run_id=p_export_run_id AND sap_file_name=p_sap_file_name
      AND request_status='STARTED' AND workflow_execution_name=p_workflow_execution_name)=1
    AS 'claim lost or conflicts with an existing execution';
  COMMIT TRANSACTION;
END;

CREATE OR REPLACE PROCEDURE `pacific-plating-282708.sap_integration_v3.sp_complete_v3_post_import_refresh`(
  p_log_id STRING,
  p_workflow_execution_name STRING,
  p_terminal_status STRING,
  p_error_template STRING
)
BEGIN
  ASSERT p_terminal_status IN ('SUCCEEDED','TIMEOUT','HUMAN_ACTION')
    AS 'terminal status must be SUCCEEDED, TIMEOUT, or HUMAN_ACTION';
  ASSERT p_terminal_status='SUCCEEDED' AND p_error_template IS NULL
      OR p_terminal_status!='SUCCEEDED' AND NULLIF(TRIM(p_error_template),'') IS NOT NULL
    AS 'success must not carry an error; failure must carry a sanitized template';
  ASSERT p_error_template IS NULL OR LENGTH(p_error_template)<=300
    AS 'error template exceeds the sanitized 300-character limit';

  BEGIN TRANSACTION;
  UPDATE `pacific-plating-282708.sap_integration_v3.v3_post_import_refresh_outbox`
  SET request_status=p_terminal_status,completed_at=CURRENT_TIMESTAMP(),
      last_error_template=p_error_template
  WHERE log_id=p_log_id AND workflow_execution_name=p_workflow_execution_name
    AND request_status='STARTED';
  ASSERT @@row_count=1 AS 'completion requires one matching STARTED outbox row';
  COMMIT TRANSACTION;
END;

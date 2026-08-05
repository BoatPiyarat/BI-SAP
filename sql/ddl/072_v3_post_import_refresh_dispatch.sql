-- Class A / source only. Atomic dispatcher state transitions for DDL 071's durable outbox.
-- This file does not create a Pub/Sub topic, start a workflow, refresh SAP, or change ACK state.

ALTER TABLE `pacific-plating-282708.sap_integration_v3.v3_post_import_refresh_outbox`
ADD COLUMN IF NOT EXISTS claim_token STRING;

CREATE OR REPLACE PROCEDURE `pacific-plating-282708.sap_integration_v3.sp_claim_v3_post_import_refresh`(
  p_log_id STRING,
  p_export_run_id STRING,
  p_sap_file_name STRING,
  p_claim_token STRING
)
BEGIN
  ASSERT NULLIF(TRIM(p_log_id),'') IS NOT NULL AS 'log_id is required';
  ASSERT NULLIF(TRIM(p_export_run_id),'') IS NOT NULL AS 'export_run_id is required';
  ASSERT NULLIF(TRIM(p_sap_file_name),'') IS NOT NULL AS 'sap_file_name is required';
  ASSERT REGEXP_CONTAINS(p_claim_token,r'^[a-f0-9]{32}$')
    AS 'claim_token must be a deterministic 32-character lowercase hex value';
  ASSERT (SELECT COUNT(*)
    FROM `pacific-plating-282708.sap_integration_v3.v3_post_import_refresh_outbox`
    WHERE log_id=p_log_id AND export_run_id=p_export_run_id AND sap_file_name=p_sap_file_name)=1
    AS 'claim must bind exactly one outbox row';
  ASSERT (SELECT COUNT(*)
    FROM `pacific-plating-282708.sap_integration_v3.v3_post_import_refresh_outbox`
    WHERE claim_token=p_claim_token AND log_id!=p_log_id)=0
    AS 'claim token is already bound to another LogID';

  BEGIN TRANSACTION;
  UPDATE `pacific-plating-282708.sap_integration_v3.v3_post_import_refresh_outbox`
  SET request_status='CLAIMED',claim_token=p_claim_token,claimed_at=CURRENT_TIMESTAMP(),
      attempt_count=attempt_count+1,last_error_template=NULL
  WHERE log_id=p_log_id AND export_run_id=p_export_run_id AND sap_file_name=p_sap_file_name
    AND request_status='PENDING' AND attempt_count<3;
  ASSERT @@row_count IN (0,1) AS 'claim affected an unexpected number of rows';
  ASSERT (SELECT COUNT(*)
    FROM `pacific-plating-282708.sap_integration_v3.v3_post_import_refresh_outbox`
    WHERE log_id=p_log_id AND export_run_id=p_export_run_id AND sap_file_name=p_sap_file_name
      AND claim_token=p_claim_token AND request_status IN ('CLAIMED','STARTED'))=1
    AS 'claim lost or conflicts with an existing claim';
  COMMIT TRANSACTION;
  SELECT request_status,workflow_execution_name,attempt_count
  FROM `pacific-plating-282708.sap_integration_v3.v3_post_import_refresh_outbox`
  WHERE log_id=p_log_id AND claim_token=p_claim_token;
END;

CREATE OR REPLACE PROCEDURE `pacific-plating-282708.sap_integration_v3.sp_bind_v3_post_import_execution`(
  p_log_id STRING,
  p_claim_token STRING,
  p_workflow_execution_name STRING
)
BEGIN
  ASSERT (SELECT COUNT(*)
    FROM `pacific-plating-282708.sap_integration_v3.v3_post_import_refresh_outbox`
    WHERE log_id=p_log_id AND claim_token=p_claim_token)=1
    AS 'execution bind must reference exactly one claimed LogID/token';
  ASSERT REGEXP_CONTAINS(p_workflow_execution_name,
    r'^projects/[a-z][a-z0-9-]{4,28}[a-z0-9]/locations/[a-z0-9-]+/workflows/[A-Za-z0-9_-]+/executions/[A-Za-z0-9_-]+$')
    AS 'workflow_execution_name must be a complete Workflows execution resource name';
  ASSERT (SELECT COUNT(*)
    FROM `pacific-plating-282708.sap_integration_v3.v3_post_import_refresh_outbox`
    WHERE workflow_execution_name=p_workflow_execution_name AND log_id!=p_log_id)=0
    AS 'workflow execution name is already bound to another LogID';

  BEGIN TRANSACTION;
  UPDATE `pacific-plating-282708.sap_integration_v3.v3_post_import_refresh_outbox`
  SET request_status='STARTED',workflow_execution_name=p_workflow_execution_name
  WHERE log_id=p_log_id AND claim_token=p_claim_token AND request_status='CLAIMED';
  ASSERT @@row_count IN (0,1) AS 'execution bind affected an unexpected number of rows';
  COMMIT TRANSACTION;
  SELECT request_status,workflow_execution_name
  FROM `pacific-plating-282708.sap_integration_v3.v3_post_import_refresh_outbox`
  WHERE log_id=p_log_id AND claim_token=p_claim_token;
END;

CREATE OR REPLACE PROCEDURE `pacific-plating-282708.sap_integration_v3.sp_release_v3_post_import_claim`(
  p_log_id STRING,
  p_claim_token STRING,
  p_error_template STRING
)
BEGIN
  ASSERT NULLIF(TRIM(p_error_template),'') IS NOT NULL AND LENGTH(p_error_template)<=300
    AS 'a sanitized error template of at most 300 characters is required';
  BEGIN TRANSACTION;
  UPDATE `pacific-plating-282708.sap_integration_v3.v3_post_import_refresh_outbox`
  SET request_status=IF(attempt_count<3,'PENDING','HUMAN_ACTION'),
      completed_at=IF(attempt_count<3,NULL,CURRENT_TIMESTAMP()),
      last_error_template=p_error_template,claim_token=IF(attempt_count<3,NULL,claim_token),
      claimed_at=IF(attempt_count<3,NULL,claimed_at)
  WHERE log_id=p_log_id AND claim_token=p_claim_token AND request_status='CLAIMED';
  ASSERT @@row_count=1 AS 'claim release requires one matching CLAIMED row';
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
  ASSERT (p_terminal_status='SUCCEEDED' AND p_error_template IS NULL)
      OR (p_terminal_status!='SUCCEEDED' AND NULLIF(TRIM(p_error_template),'') IS NOT NULL)
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

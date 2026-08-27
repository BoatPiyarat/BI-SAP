-- SOURCE ONLY / Class A / NOT DEPLOYED.
-- Durable evidence control for the one common V3 preparation Scheduler cutover.
-- This SQL cannot call Cloud Scheduler, Workflows, GCS, SAP, or the delivery promoter.

CREATE TABLE IF NOT EXISTS
  `pacific-plating-282708.sap_integration_v3.v3_common_cutover_approval` (
    approval_id STRING NOT NULL,
    approval_reference STRING NOT NULL,
    approved_by STRING NOT NULL,
    approved_at TIMESTAMP NOT NULL,
    expires_at TIMESTAMP NOT NULL,
    approved_commit STRING NOT NULL,
    workflow_revision STRING NOT NULL,
    permission_rehearsal_execution_id STRING NOT NULL,
    legacy_scheduler_name STRING NOT NULL,
    v3_scheduler_name STRING NOT NULL,
    desired_schedule STRING NOT NULL,
    desired_time_zone STRING NOT NULL,
    manual_fallback STRING NOT NULL,
    recorded_at TIMESTAMP NOT NULL
  )
CLUSTER BY approval_id;

CREATE TABLE IF NOT EXISTS
  `pacific-plating-282708.sap_integration_v3.v3_common_scheduler_cutover_ledger` (
    cutover_id STRING NOT NULL,
    approval_id STRING NOT NULL,
    workflow_revision STRING NOT NULL,
    pre_inventory_evidence_id STRING NOT NULL,
    pre_inventory JSON NOT NULL,
    legacy_prestate JSON NOT NULL,
    v3_prestate JSON NOT NULL,
    legacy_config_hash STRING NOT NULL,
    v3_config_hash STRING NOT NULL,
    permission_rehearsal_evidence_id STRING NOT NULL,
    permission_rehearsal_evidence JSON NOT NULL,
    execution_census_evidence_id STRING NOT NULL,
    execution_census_evidence JSON NOT NULL,
    cutover_state STRING NOT NULL,
    post_inventory_evidence_id STRING,
    post_inventory JSON,
    legacy_poststate JSON,
    v3_poststate JSON,
    close_reason STRING,
    claimed_by STRING NOT NULL,
    claimed_at TIMESTAMP NOT NULL,
    completed_by STRING,
    completed_at TIMESTAMP,
    verification_reference STRING NOT NULL
  )
CLUSTER BY cutover_state,cutover_id
OPTIONS(enable_change_history=TRUE);

CREATE TABLE IF NOT EXISTS
  `pacific-plating-282708.sap_integration_v3.v3_common_cutover_runtime_evidence` (
    evidence_id STRING NOT NULL,
    evidence_type STRING NOT NULL,
    evidence JSON NOT NULL,
    evidence_sha256 STRING NOT NULL,
    registered_by STRING NOT NULL,
    registered_at TIMESTAMP NOT NULL,
    verification_reference STRING NOT NULL
  )
CLUSTER BY evidence_type,evidence_id
OPTIONS(enable_change_history=TRUE);

CREATE TABLE IF NOT EXISTS
  `pacific-plating-282708.sap_integration_v3.v3_common_cutover_mutex` (
    lock_key STRING NOT NULL,
    lock_version INT64 NOT NULL,
    updated_at TIMESTAMP NOT NULL
  );

MERGE `pacific-plating-282708.sap_integration_v3.v3_common_cutover_mutex` t
USING (SELECT 'COMMON' AS lock_key) s
ON t.lock_key=s.lock_key
WHEN NOT MATCHED THEN
  INSERT(lock_key,lock_version,updated_at) VALUES('COMMON',0,CURRENT_TIMESTAMP());

ASSERT (SELECT COUNT(*)
  FROM `pacific-plating-282708.sap_integration_v3.v3_common_cutover_mutex`
  WHERE lock_key='COMMON')=1
  AS 'Common cutover mutex must contain exactly one singleton row';

CREATE OR REPLACE PROCEDURE
  `pacific-plating-282708.sap_integration_v3.sp_register_v3_common_cutover_runtime_evidence`(
    p_evidence_id STRING,p_evidence_type STRING,p_evidence JSON,
    p_registered_by STRING,p_verification_reference STRING)
BEGIN
  DECLARE v_now TIMESTAMP DEFAULT CURRENT_TIMESTAMP();

  ASSERT NULLIF(TRIM(p_evidence_id),'') IS NOT NULL
    AND p_evidence_type IN ('PERMISSION_REHEARSAL','EXECUTION_CENSUS')
    AND NULLIF(TRIM(p_registered_by),'') IS NOT NULL
    AND NULLIF(TRIM(p_verification_reference),'') IS NOT NULL
    AS 'Runtime evidence requires exact ID, type, operator, and verification reference';
  IF p_evidence_type='PERMISSION_REHEARSAL' THEN
    ASSERT STARTS_WITH(JSON_VALUE(p_evidence,'$.execution'),
        'projects/919786098205/locations/asia-southeast1/workflows/'
        ||'v3-nightly-orchestrator/executions/')
      AND NULLIF(JSON_VALUE(p_evidence,'$.workflow_revision'),'') IS NOT NULL
      AND JSON_VALUE(p_evidence,'$.execution_state')='SUCCEEDED'
      AND JSON_VALUE(p_evidence,'$.result.permission_rehearsal')
        ='PROMOTER_AUTH_REACHED_VALIDATOR'
      AND SAFE_CAST(JSON_VALUE(p_evidence,'$.result.http_code') AS INT64)=400
      AND JSON_VALUE(p_evidence,'$.result.production_write_expected')='false'
      AND JSON_VALUE(p_evidence,'$.verification_passed')='true'
      AND SAFE_CAST(JSON_VALUE(p_evidence,'$.promoter_http_400_count') AS INT64)=1
      AND SAFE_CAST(JSON_VALUE(p_evidence,'$.gcs_mutation_count') AS INT64)=0
      AND SAFE_CAST(JSON_VALUE(p_evidence,'$.bigquery_audit_event_count') AS INT64)=0
      AND SAFE_CAST(JSON_VALUE(p_evidence,'$.extract_execution_count') AS INT64)=0
      AND JSON_VALUE(p_evidence,'$.window_covers_execution')='true'
      AND JSON_VALUE(p_evidence,'$.candidate_caps_clear')='true'
      AND TIMESTAMP(JSON_VALUE(p_evidence,'$.checked_at'))
        BETWEEN TIMESTAMP_SUB(v_now,INTERVAL 7 DAY) AND v_now
      AS 'Permission rehearsal evidence is incomplete or not a bounded no-write PASS';
  ELSE
    ASSERT NULLIF(JSON_VALUE(p_evidence,'$.workflow_revision'),'') IS NOT NULL
      AND JSON_VALUE(p_evidence,'$.workflow_state')='ACTIVE'
      AND JSON_VALUE(p_evidence,'$.delivery_enabled')='false'
      AND JSON_VALUE(p_evidence,'$.source_identity_passed')='true'
      AND SAFE_CAST(JSON_VALUE(p_evidence,'$.active_execution_count') AS INT64)=0
      AND TIMESTAMP(JSON_VALUE(p_evidence,'$.checked_at'))
        BETWEEN TIMESTAMP_SUB(v_now,INTERVAL 5 MINUTE) AND v_now
      AS 'Execution census is not a fresh delivery-disabled zero-active proof';
  END IF;
  ASSERT (SELECT COUNT(*)
    FROM `pacific-plating-282708.sap_integration_v3.v3_common_cutover_runtime_evidence`
    WHERE evidence_id=p_evidence_id)=0
    AS 'Runtime evidence ID already exists';

  INSERT INTO `pacific-plating-282708.sap_integration_v3.v3_common_cutover_runtime_evidence`
  VALUES(p_evidence_id,p_evidence_type,p_evidence,
    TO_HEX(SHA256(TO_JSON_STRING(p_evidence))),p_registered_by,v_now,
    p_verification_reference);
  ASSERT @@row_count=1 AS 'Runtime evidence insert failed';
END;

CREATE OR REPLACE PROCEDURE
  `pacific-plating-282708.sap_integration_v3.sp_register_v3_common_cutover_approval`(
    p_approval_id STRING,p_approval_reference STRING,p_approved_by STRING,
    p_approved_at TIMESTAMP,p_expires_at TIMESTAMP,p_approved_commit STRING,
    p_workflow_revision STRING,p_permission_rehearsal_execution_id STRING,
    p_legacy_scheduler_name STRING,p_v3_scheduler_name STRING,
    p_desired_schedule STRING,p_desired_time_zone STRING,p_manual_fallback STRING)
BEGIN
  DECLARE v_legacy_name STRING DEFAULT
    'projects/pacific-plating-282708/locations/asia-southeast1/jobs/sap-extract-schedule';
  DECLARE v_v3_name STRING DEFAULT
    'projects/pacific-plating-282708/locations/asia-southeast1/jobs/v3-nightly-orchestrator';

  ASSERT NULLIF(TRIM(p_approval_id),'') IS NOT NULL
    AND NULLIF(TRIM(p_approval_reference),'') IS NOT NULL
    AND NULLIF(TRIM(p_approved_by),'') IS NOT NULL
    AND NULLIF(TRIM(p_workflow_revision),'') IS NOT NULL
    AND NULLIF(TRIM(p_permission_rehearsal_execution_id),'') IS NOT NULL
    AS 'Common cutover approval requires exact identity and provenance';
  ASSERT STARTS_WITH(p_permission_rehearsal_execution_id,
      'projects/919786098205/locations/asia-southeast1/workflows/'
      ||'v3-nightly-orchestrator/executions/')
    AS 'Approval must bind the full immutable rehearsal execution resource';
  ASSERT p_approved_at<=CURRENT_TIMESTAMP() AND p_expires_at>CURRENT_TIMESTAMP()
    AS 'Common cutover approval must be current and unexpired';
  ASSERT REGEXP_CONTAINS(p_approved_commit,r'^[0-9a-f]{7,40}$')
    AS 'approved_commit must be an exact Git commit';
  ASSERT p_legacy_scheduler_name=v_legacy_name AND p_v3_scheduler_name=v_v3_name
    AND p_legacy_scheduler_name!=p_v3_scheduler_name
    AS 'Approval must name the exact distinct legacy and V3 Scheduler resources';
  ASSERT p_desired_schedule='30 20 * * *' AND p_desired_time_zone='Asia/Bangkok'
    AS 'Common V3 preparation must retain the approved 20:30 ICT anchor';
  ASSERT STARTS_WITH(p_manual_fallback,'sql/operator/')
    AS 'Approval requires a reviewed human fallback artifact';
  ASSERT (SELECT COUNT(*)
    FROM `pacific-plating-282708.sap_integration_v3.v3_common_cutover_approval`
    WHERE approval_id=p_approval_id)=0
    AS 'Common cutover approval ID already exists';

  INSERT INTO `pacific-plating-282708.sap_integration_v3.v3_common_cutover_approval`
  VALUES(p_approval_id,p_approval_reference,p_approved_by,p_approved_at,p_expires_at,
    p_approved_commit,p_workflow_revision,p_permission_rehearsal_execution_id,
    p_legacy_scheduler_name,p_v3_scheduler_name,
    p_desired_schedule,p_desired_time_zone,p_manual_fallback,CURRENT_TIMESTAMP());
  ASSERT @@row_count=1 AS 'Common cutover approval insert failed';
END;

CREATE OR REPLACE PROCEDURE
  `pacific-plating-282708.sap_integration_v3.sp_claim_v3_common_scheduler_cutover`(
    p_cutover_id STRING,p_approval_id STRING,p_workflow_revision STRING,
    p_pre_inventory_evidence_id STRING,p_pre_inventory JSON,
    p_legacy_prestate JSON,p_v3_prestate JSON,
    p_permission_rehearsal_evidence_id STRING,p_permission_rehearsal_evidence JSON,
    p_execution_census_evidence_id STRING,p_execution_census_evidence JSON,
    p_claimed_by STRING,p_verification_reference STRING)
BEGIN
  DECLARE v_now TIMESTAMP DEFAULT CURRENT_TIMESTAMP();
  DECLARE v_legacy_name STRING DEFAULT
    'projects/pacific-plating-282708/locations/asia-southeast1/jobs/sap-extract-schedule';
  DECLARE v_v3_name STRING DEFAULT
    'projects/pacific-plating-282708/locations/asia-southeast1/jobs/v3-nightly-orchestrator';

  ASSERT NULLIF(TRIM(p_cutover_id),'') IS NOT NULL
    AND NULLIF(TRIM(p_claimed_by),'') IS NOT NULL
    AND NULLIF(TRIM(p_verification_reference),'') IS NOT NULL
    AS 'Common cutover claim requires identity, operator, and verification reference';
  ASSERT (SELECT COUNT(*)
    FROM `pacific-plating-282708.sap_integration_v3.v3_common_cutover_approval`
    WHERE approval_id=p_approval_id AND workflow_revision=p_workflow_revision
      AND legacy_scheduler_name=v_legacy_name AND v3_scheduler_name=v_v3_name
      AND expires_at>v_now)=1
    AS 'Common cutover lacks exact unexpired approval';
  ASSERT (SELECT COUNT(*)
    FROM `pacific-plating-282708.sap_integration_v3.v3_scheduler_inventory_evidence`
    WHERE evidence_id=p_pre_inventory_evidence_id
      AND evidence_sha256=TO_HEX(SHA256(TO_JSON_STRING(p_pre_inventory)))
      AND TO_JSON_STRING(scheduler_inventory_evidence)=TO_JSON_STRING(p_pre_inventory))=1
    AS 'Claim requires exact immutable registered pre-cutover inventory';
  ASSERT JSON_VALUE(p_pre_inventory,'$.generator')
      ='scripts/build_v3_scheduler_inventory.py:v1'
    AND JSON_VALUE(p_pre_inventory,'$.paginationComplete')='true'
    AND JSON_VALUE(p_pre_inventory,'$.project')='pacific-plating-282708'
    AND JSON_VALUE(p_pre_inventory,'$.region')='asia-southeast1'
    AND TIMESTAMP(JSON_VALUE(p_pre_inventory,'$.checkedAt'))
      BETWEEN TIMESTAMP_SUB(v_now,INTERVAL 15 MINUTE) AND v_now
    AND SAFE_CAST(JSON_VALUE(p_pre_inventory,'$.horizonMinuteCount') AS INT64)>=10080
    AS 'Claim requires a fresh complete production Scheduler inventory';
  ASSERT (SELECT COUNTIF(JSON_VALUE(j,'$.name')=v_legacy_name
      AND JSON_VALUE(j,'$.state')='ENABLED'
      AND JSON_VALUE(j,'$.schedule')='30 20 * * *'
      AND JSON_VALUE(j,'$.timeZone')='Asia/Bangkok')
    FROM UNNEST(JSON_QUERY_ARRAY(p_pre_inventory,'$.jobs')) j)=1
    AND (SELECT COUNTIF(JSON_VALUE(j,'$.name')=v_v3_name
      AND JSON_VALUE(j,'$.state')='PAUSED'
      AND JSON_VALUE(j,'$.schedule')='30 20 * * *'
      AND JSON_VALUE(j,'$.timeZone')='Asia/Bangkok')
    FROM UNNEST(JSON_QUERY_ARRAY(p_pre_inventory,'$.jobs')) j)=1
    AS 'Pre-cutover inventory must show legacy ENABLED and V3 PAUSED';
  ASSERT JSON_VALUE(p_legacy_prestate,'$.name')=v_legacy_name
    AND JSON_VALUE(p_legacy_prestate,'$.state')='ENABLED'
    AND JSON_VALUE(p_legacy_prestate,'$.schedule')='30 20 * * *'
    AND JSON_VALUE(p_legacy_prestate,'$.timeZone')='Asia/Bangkok'
    AND JSON_VALUE(p_v3_prestate,'$.name')=v_v3_name
    AND JSON_VALUE(p_v3_prestate,'$.state')='PAUSED'
    AND JSON_VALUE(p_v3_prestate,'$.schedule')='30 20 * * *'
    AND JSON_VALUE(p_v3_prestate,'$.timeZone')='Asia/Bangkok'
    AS 'Exact Scheduler prestates do not match the approved safe boundary';
  ASSERT (SELECT TO_HEX(SHA256(TO_JSON_STRING(STRUCT(
      JSON_VALUE(j,'$.name') AS resource_name,JSON_VALUE(j,'$.schedule') AS schedule,
      JSON_VALUE(j,'$.timeZone') AS time_zone,
      JSON_VALUE(j,'$.attemptDeadline') AS attempt_deadline,
      JSON_QUERY(j,'$.retryConfig') AS retry_config,
      JSON_QUERY(j,'$.httpTarget') AS http_target))))
    FROM UNNEST(JSON_QUERY_ARRAY(p_pre_inventory,'$.jobs')) j
    WHERE JSON_VALUE(j,'$.name')=v_legacy_name)=TO_HEX(SHA256(TO_JSON_STRING(STRUCT(
      JSON_VALUE(p_legacy_prestate,'$.name') AS resource_name,
      JSON_VALUE(p_legacy_prestate,'$.schedule') AS schedule,
      JSON_VALUE(p_legacy_prestate,'$.timeZone') AS time_zone,
      JSON_VALUE(p_legacy_prestate,'$.attemptDeadline') AS attempt_deadline,
      JSON_QUERY(p_legacy_prestate,'$.retryConfig') AS retry_config,
      JSON_QUERY(p_legacy_prestate,'$.httpTarget') AS http_target))))
    AND (SELECT TO_HEX(SHA256(TO_JSON_STRING(STRUCT(
      JSON_VALUE(j,'$.name') AS resource_name,JSON_VALUE(j,'$.schedule') AS schedule,
      JSON_VALUE(j,'$.timeZone') AS time_zone,
      JSON_VALUE(j,'$.attemptDeadline') AS attempt_deadline,
      JSON_QUERY(j,'$.retryConfig') AS retry_config,
      JSON_QUERY(j,'$.httpTarget') AS http_target))))
    FROM UNNEST(JSON_QUERY_ARRAY(p_pre_inventory,'$.jobs')) j
    WHERE JSON_VALUE(j,'$.name')=v_v3_name)=TO_HEX(SHA256(TO_JSON_STRING(STRUCT(
      JSON_VALUE(p_v3_prestate,'$.name') AS resource_name,
      JSON_VALUE(p_v3_prestate,'$.schedule') AS schedule,
      JSON_VALUE(p_v3_prestate,'$.timeZone') AS time_zone,
      JSON_VALUE(p_v3_prestate,'$.attemptDeadline') AS attempt_deadline,
      JSON_QUERY(p_v3_prestate,'$.retryConfig') AS retry_config,
      JSON_QUERY(p_v3_prestate,'$.httpTarget') AS http_target))))
    AS 'Scheduler prestates do not match the registered inventory configurations';
  ASSERT (SELECT COUNT(*)
    FROM `pacific-plating-282708.sap_integration_v3.v3_unit2_magnitude_config`
    WHERE effective_start<=v_now AND (effective_end IS NULL OR effective_end>v_now))=1
    AS 'Common cutover requires exactly one active Unit 2 magnitude configuration';
  ASSERT (SELECT COUNT(*) FROM (
    SELECT m.pipeline_run_id
    FROM `pacific-plating-282708.sap_integration_v3.v3_unit2_magnitude_run` m
    JOIN `pacific-plating-282708.sap_integration_v3.v3_unit2_magnitude_config` c
      USING(config_id)
    JOIN `pacific-plating-282708.sap_integration_v3.pipeline_run_log` l
      ON l.run_id=m.pipeline_run_id AND l.step='UNITS_2_5_ARCHIVE' AND l.status='SUCCESS'
    WHERE c.effective_start<=v_now AND (c.effective_end IS NULL OR c.effective_end>v_now)
      AND m.status='PASS' AND m.pipeline_run_id!=m.baseline_run_id
      AND m.evaluated_at>=c.created_at
    GROUP BY m.pipeline_run_id))>0
    AS 'Common cutover requires a fresh non-bootstrap Unit 2 magnitude PASS';
  ASSERT JSON_VALUE(p_permission_rehearsal_evidence,'$.execution')=(SELECT
      permission_rehearsal_execution_id
    FROM `pacific-plating-282708.sap_integration_v3.v3_common_cutover_approval`
    WHERE approval_id=p_approval_id)
    AND JSON_VALUE(p_permission_rehearsal_evidence,'$.workflow_revision')=p_workflow_revision
    AND JSON_VALUE(p_permission_rehearsal_evidence,'$.execution_state')='SUCCEEDED'
    AND JSON_VALUE(p_permission_rehearsal_evidence,'$.result.permission_rehearsal')
      ='PROMOTER_AUTH_REACHED_VALIDATOR'
    AND SAFE_CAST(JSON_VALUE(p_permission_rehearsal_evidence,'$.result.http_code') AS INT64)=400
    AND JSON_VALUE(p_permission_rehearsal_evidence,'$.result.production_write_expected')='false'
    AND JSON_VALUE(p_permission_rehearsal_evidence,'$.verification_passed')='true'
    AS 'Common cutover requires exact PASSed no-write promoter rehearsal evidence';
  ASSERT (SELECT COUNT(*)
    FROM `pacific-plating-282708.sap_integration_v3.v3_common_cutover_runtime_evidence`
    WHERE evidence_id=p_permission_rehearsal_evidence_id
      AND evidence_type='PERMISSION_REHEARSAL'
      AND evidence_sha256=TO_HEX(SHA256(TO_JSON_STRING(p_permission_rehearsal_evidence)))
      AND TO_JSON_STRING(evidence)=TO_JSON_STRING(p_permission_rehearsal_evidence))=1
    AS 'Permission rehearsal evidence is not immutably registered';
  ASSERT JSON_VALUE(p_execution_census_evidence,'$.workflow_revision')=p_workflow_revision
    AND SAFE_CAST(JSON_VALUE(p_execution_census_evidence,'$.active_execution_count') AS INT64)=0
    AND TIMESTAMP(JSON_VALUE(p_execution_census_evidence,'$.checked_at'))
      BETWEEN TIMESTAMP_SUB(v_now,INTERVAL 5 MINUTE) AND v_now
    AS 'Common cutover requires a fresh zero-active-execution census';
  ASSERT (SELECT COUNT(*)
    FROM `pacific-plating-282708.sap_integration_v3.v3_common_cutover_runtime_evidence`
    WHERE evidence_id=p_execution_census_evidence_id
      AND evidence_type='EXECUTION_CENSUS'
      AND evidence_sha256=TO_HEX(SHA256(TO_JSON_STRING(p_execution_census_evidence)))
      AND TO_JSON_STRING(evidence)=TO_JSON_STRING(p_execution_census_evidence))=1
    AS 'Execution census evidence is not immutably registered';
  ASSERT (SELECT COUNT(*)
    FROM `pacific-plating-282708.sap_integration_v3.v3_common_scheduler_cutover_ledger`
    WHERE cutover_id=p_cutover_id OR cutover_state IN ('CLAIMED','ACTIVATED'))=0
    AS 'Cutover ID exists or another common cutover is live';

  BEGIN TRANSACTION;
  UPDATE `pacific-plating-282708.sap_integration_v3.v3_common_cutover_mutex`
  SET lock_version=lock_version+1,updated_at=v_now
  WHERE lock_key='COMMON';
  ASSERT @@row_count=1 AS 'Common cutover mutex acquisition failed';
  ASSERT (SELECT COUNT(*)
    FROM `pacific-plating-282708.sap_integration_v3.v3_common_scheduler_cutover_ledger`
    WHERE cutover_id=p_cutover_id OR cutover_state IN ('CLAIMED','ACTIVATED'))=0
    AS 'Concurrent cutover ID exists or another common cutover is live';
  INSERT INTO `pacific-plating-282708.sap_integration_v3.v3_common_scheduler_cutover_ledger`
    (cutover_id,approval_id,workflow_revision,pre_inventory_evidence_id,pre_inventory,
      legacy_prestate,v3_prestate,legacy_config_hash,v3_config_hash,
      permission_rehearsal_evidence_id,permission_rehearsal_evidence,
      execution_census_evidence_id,execution_census_evidence,
      cutover_state,post_inventory_evidence_id,post_inventory,legacy_poststate,v3_poststate,
      close_reason,claimed_by,claimed_at,completed_by,completed_at,verification_reference)
  VALUES(p_cutover_id,p_approval_id,p_workflow_revision,p_pre_inventory_evidence_id,
    p_pre_inventory,p_legacy_prestate,p_v3_prestate,
    TO_HEX(SHA256(TO_JSON_STRING(STRUCT(
      JSON_VALUE(p_legacy_prestate,'$.name') AS resource_name,
      JSON_VALUE(p_legacy_prestate,'$.schedule') AS schedule,
      JSON_VALUE(p_legacy_prestate,'$.timeZone') AS time_zone,
      JSON_VALUE(p_legacy_prestate,'$.attemptDeadline') AS attempt_deadline,
      JSON_QUERY(p_legacy_prestate,'$.retryConfig') AS retry_config,
      JSON_QUERY(p_legacy_prestate,'$.httpTarget') AS http_target)))),
    TO_HEX(SHA256(TO_JSON_STRING(STRUCT(
      JSON_VALUE(p_v3_prestate,'$.name') AS resource_name,
      JSON_VALUE(p_v3_prestate,'$.schedule') AS schedule,
      JSON_VALUE(p_v3_prestate,'$.timeZone') AS time_zone,
      JSON_VALUE(p_v3_prestate,'$.attemptDeadline') AS attempt_deadline,
      JSON_QUERY(p_v3_prestate,'$.retryConfig') AS retry_config,
      JSON_QUERY(p_v3_prestate,'$.httpTarget') AS http_target)))),
    p_permission_rehearsal_evidence_id,p_permission_rehearsal_evidence,
    p_execution_census_evidence_id,p_execution_census_evidence,
    'CLAIMED',NULL,NULL,NULL,NULL,NULL,p_claimed_by,v_now,
    NULL,NULL,p_verification_reference);
  ASSERT @@row_count=1 AS 'Common cutover claim insert failed';
  COMMIT TRANSACTION;
END;

CREATE OR REPLACE PROCEDURE
  `pacific-plating-282708.sap_integration_v3.sp_finalize_v3_common_scheduler_cutover`(
    p_cutover_id STRING,p_post_inventory_evidence_id STRING,p_post_inventory JSON,
    p_legacy_poststate JSON,p_v3_poststate JSON,
    p_completed_by STRING,p_verification_reference STRING)
BEGIN
  DECLARE v_now TIMESTAMP DEFAULT CURRENT_TIMESTAMP();
  DECLARE v_legacy_name STRING DEFAULT
    'projects/pacific-plating-282708/locations/asia-southeast1/jobs/sap-extract-schedule';
  DECLARE v_v3_name STRING DEFAULT
    'projects/pacific-plating-282708/locations/asia-southeast1/jobs/v3-nightly-orchestrator';

  ASSERT (SELECT COUNT(*)
    FROM `pacific-plating-282708.sap_integration_v3.v3_common_scheduler_cutover_ledger`
    WHERE cutover_id=p_cutover_id AND cutover_state='CLAIMED')=1
    AS 'Finalization requires exactly one CLAIMED common cutover';
  ASSERT (SELECT COUNT(*)
    FROM `pacific-plating-282708.sap_integration_v3.v3_scheduler_inventory_evidence`
    WHERE evidence_id=p_post_inventory_evidence_id
      AND evidence_sha256=TO_HEX(SHA256(TO_JSON_STRING(p_post_inventory)))
      AND TO_JSON_STRING(scheduler_inventory_evidence)=TO_JSON_STRING(p_post_inventory))=1
    AS 'Finalization requires exact immutable registered post-cutover inventory';
  ASSERT JSON_VALUE(p_post_inventory,'$.paginationComplete')='true'
    AND JSON_VALUE(p_post_inventory,'$.generator')='scripts/build_v3_scheduler_inventory.py:v1'
    AND TIMESTAMP(JSON_VALUE(p_post_inventory,'$.checkedAt'))
      BETWEEN TIMESTAMP_SUB(v_now,INTERVAL 15 MINUTE) AND v_now
    AND SAFE_CAST(JSON_VALUE(p_post_inventory,'$.horizonMinuteCount') AS INT64)>=10080
    AS 'Finalization requires a fresh complete Scheduler inventory';
  ASSERT JSON_VALUE(p_legacy_poststate,'$.name')=v_legacy_name
    AND JSON_VALUE(p_legacy_poststate,'$.state')='PAUSED'
    AND JSON_VALUE(p_v3_poststate,'$.name')=v_v3_name
    AND JSON_VALUE(p_v3_poststate,'$.state')='ENABLED'
    AND JSON_VALUE(p_v3_poststate,'$.schedule')='30 20 * * *'
    AND JSON_VALUE(p_v3_poststate,'$.timeZone')='Asia/Bangkok'
    AS 'Poststate must show legacy PAUSED and exact V3 ENABLED';
  ASSERT TO_HEX(SHA256(TO_JSON_STRING(STRUCT(
      JSON_VALUE(p_legacy_poststate,'$.name') AS resource_name,
      JSON_VALUE(p_legacy_poststate,'$.schedule') AS schedule,
      JSON_VALUE(p_legacy_poststate,'$.timeZone') AS time_zone,
      JSON_VALUE(p_legacy_poststate,'$.attemptDeadline') AS attempt_deadline,
      JSON_QUERY(p_legacy_poststate,'$.retryConfig') AS retry_config,
      JSON_QUERY(p_legacy_poststate,'$.httpTarget') AS http_target))))=(SELECT legacy_config_hash
    FROM `pacific-plating-282708.sap_integration_v3.v3_common_scheduler_cutover_ledger`
    WHERE cutover_id=p_cutover_id)
    AND TO_HEX(SHA256(TO_JSON_STRING(STRUCT(
      JSON_VALUE(p_v3_poststate,'$.name') AS resource_name,
      JSON_VALUE(p_v3_poststate,'$.schedule') AS schedule,
      JSON_VALUE(p_v3_poststate,'$.timeZone') AS time_zone,
      JSON_VALUE(p_v3_poststate,'$.attemptDeadline') AS attempt_deadline,
      JSON_QUERY(p_v3_poststate,'$.retryConfig') AS retry_config,
      JSON_QUERY(p_v3_poststate,'$.httpTarget') AS http_target))))=(SELECT v3_config_hash
    FROM `pacific-plating-282708.sap_integration_v3.v3_common_scheduler_cutover_ledger`
    WHERE cutover_id=p_cutover_id)
    AS 'Scheduler configuration changed during cutover';
  ASSERT (SELECT TO_HEX(SHA256(TO_JSON_STRING(STRUCT(
      JSON_VALUE(j,'$.name') AS resource_name,JSON_VALUE(j,'$.schedule') AS schedule,
      JSON_VALUE(j,'$.timeZone') AS time_zone,
      JSON_VALUE(j,'$.attemptDeadline') AS attempt_deadline,
      JSON_QUERY(j,'$.retryConfig') AS retry_config,
      JSON_QUERY(j,'$.httpTarget') AS http_target))))
    FROM UNNEST(JSON_QUERY_ARRAY(p_post_inventory,'$.jobs')) j
    WHERE JSON_VALUE(j,'$.name')=v_legacy_name)=(SELECT legacy_config_hash
      FROM `pacific-plating-282708.sap_integration_v3.v3_common_scheduler_cutover_ledger`
      WHERE cutover_id=p_cutover_id)
    AND (SELECT TO_HEX(SHA256(TO_JSON_STRING(STRUCT(
      JSON_VALUE(j,'$.name') AS resource_name,JSON_VALUE(j,'$.schedule') AS schedule,
      JSON_VALUE(j,'$.timeZone') AS time_zone,
      JSON_VALUE(j,'$.attemptDeadline') AS attempt_deadline,
      JSON_QUERY(j,'$.retryConfig') AS retry_config,
      JSON_QUERY(j,'$.httpTarget') AS http_target))))
    FROM UNNEST(JSON_QUERY_ARRAY(p_post_inventory,'$.jobs')) j
    WHERE JSON_VALUE(j,'$.name')=v_v3_name)=(SELECT v3_config_hash
      FROM `pacific-plating-282708.sap_integration_v3.v3_common_scheduler_cutover_ledger`
      WHERE cutover_id=p_cutover_id)
    AS 'Registered post-inventory configurations differ from exact prestates';
  ASSERT (SELECT COUNTIF(JSON_VALUE(j,'$.name')=v_legacy_name
      AND JSON_VALUE(j,'$.state')='PAUSED'
      AND JSON_VALUE(j,'$.schedule')='30 20 * * *'
      AND JSON_VALUE(j,'$.timeZone')='Asia/Bangkok')
    FROM UNNEST(JSON_QUERY_ARRAY(p_post_inventory,'$.jobs')) j)=1
    AND (SELECT COUNTIF(JSON_VALUE(j,'$.name')=v_v3_name
      AND JSON_VALUE(j,'$.state')='ENABLED'
      AND JSON_VALUE(j,'$.schedule')='30 20 * * *'
      AND JSON_VALUE(j,'$.timeZone')='Asia/Bangkok')
    FROM UNNEST(JSON_QUERY_ARRAY(p_post_inventory,'$.jobs')) j)=1
    AS 'Post-cutover inventory does not match exact enabled/paused states';
  ASSERT (WITH jobs AS (
      SELECT j FROM UNNEST(JSON_QUERY_ARRAY(p_post_inventory,'$.jobs')) j),
    v3_windows AS (
      SELECT TIMESTAMP(JSON_VALUE(w,'$.start')) start_at,
        TIMESTAMP(JSON_VALUE(w,'$.end')) end_at
      FROM jobs,UNNEST(JSON_QUERY_ARRAY(j,'$.windows')) w
      WHERE JSON_VALUE(j,'$.name')=v_v3_name),
    other_windows AS (
      SELECT JSON_VALUE(j,'$.name') name,
        TIMESTAMP(JSON_VALUE(w,'$.start')) start_at,
        TIMESTAMP(JSON_VALUE(w,'$.end')) end_at
      FROM jobs,UNNEST(JSON_QUERY_ARRAY(j,'$.windows')) w
      WHERE JSON_VALUE(j,'$.name')!=v_v3_name)
    SELECT COUNT(*) FROM v3_windows v JOIN other_windows o
      ON v.start_at<o.end_at AND o.start_at<v.end_at)=0
    AS 'Fresh complete inventory does not prove zero Scheduler overlap';
  ASSERT NULLIF(TRIM(p_completed_by),'') IS NOT NULL
    AND NULLIF(TRIM(p_verification_reference),'') IS NOT NULL
    AS 'Finalization requires operator and verification reference';

  UPDATE `pacific-plating-282708.sap_integration_v3.v3_common_scheduler_cutover_ledger`
  SET cutover_state='ACTIVATED',post_inventory_evidence_id=p_post_inventory_evidence_id,
    post_inventory=p_post_inventory,legacy_poststate=p_legacy_poststate,
    v3_poststate=p_v3_poststate,completed_by=p_completed_by,completed_at=v_now,
    verification_reference=p_verification_reference
  WHERE cutover_id=p_cutover_id AND cutover_state='CLAIMED';
  ASSERT @@row_count=1 AS 'Common cutover finalization failed';
END;

CREATE OR REPLACE PROCEDURE
  `pacific-plating-282708.sap_integration_v3.sp_close_v3_common_scheduler_cutover`(
    p_cutover_id STRING,p_terminal_state STRING,p_post_inventory_evidence_id STRING,
    p_post_inventory JSON,p_legacy_poststate JSON,p_v3_poststate JSON,p_close_reason STRING,
    p_completed_by STRING,p_verification_reference STRING)
BEGIN
  DECLARE v_now TIMESTAMP DEFAULT CURRENT_TIMESTAMP();
  DECLARE v_expected_prior_state STRING;
  DECLARE v_legacy_name STRING DEFAULT
    'projects/pacific-plating-282708/locations/asia-southeast1/jobs/sap-extract-schedule';
  DECLARE v_v3_name STRING DEFAULT
    'projects/pacific-plating-282708/locations/asia-southeast1/jobs/v3-nightly-orchestrator';

  ASSERT p_terminal_state IN ('ABORTED','ROLLED_BACK')
    AS 'Close state must be ABORTED or ROLLED_BACK';
  SET v_expected_prior_state=IF(p_terminal_state='ABORTED','CLAIMED','ACTIVATED');
  ASSERT (SELECT COUNT(*)
    FROM `pacific-plating-282708.sap_integration_v3.v3_common_scheduler_cutover_ledger`
    WHERE cutover_id=p_cutover_id AND cutover_state=v_expected_prior_state)=1
    AS 'Close transition does not match current common cutover state';
  ASSERT NULLIF(TRIM(p_close_reason),'') IS NOT NULL
    AND NULLIF(TRIM(p_completed_by),'') IS NOT NULL
    AND NULLIF(TRIM(p_verification_reference),'') IS NOT NULL
    AS 'Close transition requires reason, operator, and verification reference';
  ASSERT (SELECT COUNT(*)
    FROM `pacific-plating-282708.sap_integration_v3.v3_scheduler_inventory_evidence`
    WHERE evidence_id=p_post_inventory_evidence_id
      AND evidence_sha256=TO_HEX(SHA256(TO_JSON_STRING(p_post_inventory)))
      AND TO_JSON_STRING(scheduler_inventory_evidence)=TO_JSON_STRING(p_post_inventory))=1
    AS 'Close transition requires exact immutable registered inventory';
  ASSERT JSON_VALUE(p_post_inventory,'$.paginationComplete')='true'
    AND JSON_VALUE(p_post_inventory,'$.generator')='scripts/build_v3_scheduler_inventory.py:v1'
    AND TIMESTAMP(JSON_VALUE(p_post_inventory,'$.checkedAt'))
      BETWEEN TIMESTAMP_SUB(v_now,INTERVAL 15 MINUTE) AND v_now
    AS 'Close transition requires fresh complete Scheduler inventory';
  ASSERT JSON_VALUE(p_legacy_poststate,'$.name')=v_legacy_name
    AND JSON_VALUE(p_legacy_poststate,'$.state')='ENABLED'
    AND JSON_VALUE(p_legacy_poststate,'$.schedule')='30 20 * * *'
    AND JSON_VALUE(p_legacy_poststate,'$.timeZone')='Asia/Bangkok'
    AND JSON_VALUE(p_v3_poststate,'$.name')=v_v3_name
    AND JSON_VALUE(p_v3_poststate,'$.state')='PAUSED'
    AND JSON_VALUE(p_v3_poststate,'$.schedule')='30 20 * * *'
    AND JSON_VALUE(p_v3_poststate,'$.timeZone')='Asia/Bangkok'
    AS 'Close transition must prove exact legacy ENABLED / V3 PAUSED restoration';
  ASSERT TO_HEX(SHA256(TO_JSON_STRING(STRUCT(
      JSON_VALUE(p_legacy_poststate,'$.name') AS resource_name,
      JSON_VALUE(p_legacy_poststate,'$.schedule') AS schedule,
      JSON_VALUE(p_legacy_poststate,'$.timeZone') AS time_zone,
      JSON_VALUE(p_legacy_poststate,'$.attemptDeadline') AS attempt_deadline,
      JSON_QUERY(p_legacy_poststate,'$.retryConfig') AS retry_config,
      JSON_QUERY(p_legacy_poststate,'$.httpTarget') AS http_target))))=(SELECT legacy_config_hash
    FROM `pacific-plating-282708.sap_integration_v3.v3_common_scheduler_cutover_ledger`
    WHERE cutover_id=p_cutover_id)
    AND TO_HEX(SHA256(TO_JSON_STRING(STRUCT(
      JSON_VALUE(p_v3_poststate,'$.name') AS resource_name,
      JSON_VALUE(p_v3_poststate,'$.schedule') AS schedule,
      JSON_VALUE(p_v3_poststate,'$.timeZone') AS time_zone,
      JSON_VALUE(p_v3_poststate,'$.attemptDeadline') AS attempt_deadline,
      JSON_QUERY(p_v3_poststate,'$.retryConfig') AS retry_config,
      JSON_QUERY(p_v3_poststate,'$.httpTarget') AS http_target))))=(SELECT v3_config_hash
    FROM `pacific-plating-282708.sap_integration_v3.v3_common_scheduler_cutover_ledger`
    WHERE cutover_id=p_cutover_id)
    AS 'Close transition did not restore exact Scheduler configurations';
  ASSERT (SELECT TO_HEX(SHA256(TO_JSON_STRING(STRUCT(
      JSON_VALUE(j,'$.name') AS resource_name,JSON_VALUE(j,'$.schedule') AS schedule,
      JSON_VALUE(j,'$.timeZone') AS time_zone,
      JSON_VALUE(j,'$.attemptDeadline') AS attempt_deadline,
      JSON_QUERY(j,'$.retryConfig') AS retry_config,
      JSON_QUERY(j,'$.httpTarget') AS http_target))))
    FROM UNNEST(JSON_QUERY_ARRAY(p_post_inventory,'$.jobs')) j
    WHERE JSON_VALUE(j,'$.name')=v_legacy_name)=(SELECT legacy_config_hash
      FROM `pacific-plating-282708.sap_integration_v3.v3_common_scheduler_cutover_ledger`
      WHERE cutover_id=p_cutover_id)
    AND (SELECT TO_HEX(SHA256(TO_JSON_STRING(STRUCT(
      JSON_VALUE(j,'$.name') AS resource_name,JSON_VALUE(j,'$.schedule') AS schedule,
      JSON_VALUE(j,'$.timeZone') AS time_zone,
      JSON_VALUE(j,'$.attemptDeadline') AS attempt_deadline,
      JSON_QUERY(j,'$.retryConfig') AS retry_config,
      JSON_QUERY(j,'$.httpTarget') AS http_target))))
    FROM UNNEST(JSON_QUERY_ARRAY(p_post_inventory,'$.jobs')) j
    WHERE JSON_VALUE(j,'$.name')=v_v3_name)=(SELECT v3_config_hash
      FROM `pacific-plating-282708.sap_integration_v3.v3_common_scheduler_cutover_ledger`
      WHERE cutover_id=p_cutover_id)
    AS 'Registered close inventory differs from restored exact configurations';
  ASSERT (SELECT COUNTIF(JSON_VALUE(j,'$.name')=v_legacy_name
      AND JSON_VALUE(j,'$.state')='ENABLED'
      AND JSON_VALUE(j,'$.schedule')='30 20 * * *'
      AND JSON_VALUE(j,'$.timeZone')='Asia/Bangkok')
    FROM UNNEST(JSON_QUERY_ARRAY(p_post_inventory,'$.jobs')) j)=1
    AND (SELECT COUNTIF(JSON_VALUE(j,'$.name')=v_v3_name
      AND JSON_VALUE(j,'$.state')='PAUSED'
      AND JSON_VALUE(j,'$.schedule')='30 20 * * *'
      AND JSON_VALUE(j,'$.timeZone')='Asia/Bangkok')
    FROM UNNEST(JSON_QUERY_ARRAY(p_post_inventory,'$.jobs')) j)=1
    AS 'Close inventory does not match restored safe state';
  ASSERT (WITH jobs AS (
      SELECT j FROM UNNEST(JSON_QUERY_ARRAY(p_post_inventory,'$.jobs')) j),
    legacy_windows AS (
      SELECT TIMESTAMP(JSON_VALUE(w,'$.start')) start_at,
        TIMESTAMP(JSON_VALUE(w,'$.end')) end_at
      FROM jobs,UNNEST(JSON_QUERY_ARRAY(j,'$.windows')) w
      WHERE JSON_VALUE(j,'$.name')=v_legacy_name),
    other_windows AS (
      SELECT JSON_VALUE(j,'$.name') name,
        TIMESTAMP(JSON_VALUE(w,'$.start')) start_at,
        TIMESTAMP(JSON_VALUE(w,'$.end')) end_at
      FROM jobs,UNNEST(JSON_QUERY_ARRAY(j,'$.windows')) w
      WHERE JSON_VALUE(j,'$.name')!=v_legacy_name)
    SELECT COUNT(*) FROM legacy_windows l JOIN other_windows o
      ON l.start_at<o.end_at AND o.start_at<l.end_at)=0
    AS 'Restored inventory does not prove zero Scheduler overlap';

  UPDATE `pacific-plating-282708.sap_integration_v3.v3_common_scheduler_cutover_ledger`
  SET cutover_state=p_terminal_state,post_inventory_evidence_id=p_post_inventory_evidence_id,
    post_inventory=p_post_inventory,legacy_poststate=p_legacy_poststate,
    v3_poststate=p_v3_poststate,close_reason=p_close_reason,completed_by=p_completed_by,
    completed_at=v_now,verification_reference=p_verification_reference
  WHERE cutover_id=p_cutover_id AND cutover_state=v_expected_prior_state;
  ASSERT @@row_count=1 AS 'Common cutover close transition failed';
END;

CREATE OR REPLACE VIEW
  `pacific-plating-282708.sap_integration_v3.vw_v3_common_scheduler_cutover_control` AS
SELECT
  a.approval_id,a.approval_reference,a.approved_by,a.approved_at,a.expires_at,
  a.approved_commit,a.workflow_revision,a.legacy_scheduler_name,a.v3_scheduler_name,
  a.desired_schedule,a.desired_time_zone,a.manual_fallback,
  l.cutover_id,l.cutover_state,l.claimed_by,l.claimed_at,l.completed_by,l.completed_at,
  l.close_reason,l.verification_reference,
  CASE
    WHEN a.expires_at<=CURRENT_TIMESTAMP() AND l.cutover_id IS NULL THEN 'BLOCKED_APPROVAL_EXPIRED'
    WHEN l.cutover_id IS NULL THEN 'READY_FOR_PRESTATE_CLAIM'
    WHEN l.cutover_state='CLAIMED' THEN 'EXTERNAL_CUTOVER_IN_PROGRESS'
    WHEN l.cutover_state='ACTIVATED' THEN 'COMMON_PREPARATION_ACTIVE'
    WHEN l.cutover_state='ABORTED' THEN 'SAFE_ABORT_RECORDED'
    WHEN l.cutover_state='ROLLED_BACK' THEN 'SAFE_ROLLBACK_RECORDED'
    ELSE 'BLOCKED_UNKNOWN_STATE'
  END AS control_state
FROM `pacific-plating-282708.sap_integration_v3.v3_common_cutover_approval` a
LEFT JOIN `pacific-plating-282708.sap_integration_v3.v3_common_scheduler_cutover_ledger` l
  USING(approval_id);

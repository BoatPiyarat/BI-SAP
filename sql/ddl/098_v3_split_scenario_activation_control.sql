-- SOURCE ONLY / Class A.
-- Durable split-scenario activation and rollback control plane. This DDL never calls Cloud
-- Scheduler and never delivers an interface file. External activation remains a separate action.

CREATE TABLE IF NOT EXISTS
  `pacific-plating-282708.sap_integration_v3.v3_scenario_activation_approval` (
    flow_key STRING NOT NULL,
    evidence_run_id STRING NOT NULL,
    approval_id STRING NOT NULL,
    approval_reference STRING NOT NULL,
    approved_by STRING NOT NULL,
    approved_at TIMESTAMP NOT NULL,
    expires_at TIMESTAMP NOT NULL,
    approved_commit STRING NOT NULL,
    scheduler_job_name STRING NOT NULL,
    desired_schedule STRING NOT NULL,
    desired_time_zone STRING NOT NULL,
    manual_fallback STRING NOT NULL,
    recorded_at TIMESTAMP NOT NULL
  )
CLUSTER BY flow_key,evidence_run_id;

CREATE TABLE IF NOT EXISTS
  `pacific-plating-282708.sap_integration_v3.v3_scenario_scheduler_prestate` (
    activation_id STRING NOT NULL,
    flow_key STRING NOT NULL,
    evidence_run_id STRING NOT NULL,
    scheduler_job_name STRING NOT NULL,
    scheduler_resource_json JSON NOT NULL,
    scheduler_inventory_evidence JSON NOT NULL,
    scheduler_restore_hash STRING NOT NULL,
    scheduler_state STRING NOT NULL,
    schedule STRING NOT NULL,
    time_zone STRING NOT NULL,
    workflow_revision STRING NOT NULL,
    captured_by STRING NOT NULL,
    captured_at TIMESTAMP NOT NULL
  )
CLUSTER BY activation_id,flow_key;

CREATE TABLE IF NOT EXISTS
  `pacific-plating-282708.sap_integration_v3.v3_scenario_activation_ledger` (
    activation_id STRING NOT NULL,
    flow_key STRING NOT NULL,
    evidence_run_id STRING NOT NULL,
    approval_id STRING NOT NULL,
    scheduler_job_name STRING NOT NULL,
    activated_schedule STRING NOT NULL,
    activated_time_zone STRING NOT NULL,
    workflow_revision STRING NOT NULL,
    activation_state STRING NOT NULL,
    scheduler_poststate_json JSON,
    non_overlap_evidence JSON,
    activated_by STRING NOT NULL,
    activated_at TIMESTAMP NOT NULL,
    verification_reference STRING NOT NULL
  )
CLUSTER BY activation_id,flow_key;

CREATE TABLE IF NOT EXISTS
  `pacific-plating-282708.sap_integration_v3.v3_scenario_rollback_ledger` (
    rollback_id STRING NOT NULL,
    activation_id STRING NOT NULL,
    flow_key STRING NOT NULL,
    scheduler_job_name STRING NOT NULL,
    restored_scheduler_state STRING NOT NULL,
    restored_schedule STRING NOT NULL,
    restored_time_zone STRING NOT NULL,
    restored_workflow_revision STRING NOT NULL,
    rolled_back_by STRING NOT NULL,
    rolled_back_at TIMESTAMP NOT NULL,
    verification_reference STRING NOT NULL
  )
CLUSTER BY rollback_id,activation_id;

CREATE OR REPLACE PROCEDURE
  `pacific-plating-282708.sap_integration_v3.sp_register_v3_scenario_activation_approval`(
    p_flow_key STRING,p_evidence_run_id STRING,p_approval_id STRING,
    p_approval_reference STRING,p_approved_by STRING,p_approved_at TIMESTAMP,
    p_expires_at TIMESTAMP,p_approved_commit STRING,p_scheduler_job_name STRING,
    p_desired_schedule STRING,p_desired_time_zone STRING,p_manual_fallback STRING)
BEGIN
  ASSERT NULLIF(TRIM(p_flow_key),'') IS NOT NULL
    AND NULLIF(TRIM(p_evidence_run_id),'') IS NOT NULL
    AND NULLIF(TRIM(p_approval_id),'') IS NOT NULL
    AND NULLIF(TRIM(p_approval_reference),'') IS NOT NULL
    AND NULLIF(TRIM(p_approved_by),'') IS NOT NULL
    AS 'Scenario activation requires exact flow/run/approval provenance';
  ASSERT p_approved_at<=CURRENT_TIMESTAMP() AND p_expires_at>CURRENT_TIMESTAMP()
    AS 'Scenario activation approval must be current and unexpired';
  ASSERT REGEXP_CONTAINS(p_approved_commit,r'^[0-9a-f]{7,40}$')
    AS 'approved_commit must be an exact Git commit';
  ASSERT STARTS_WITH(p_scheduler_job_name,
      'projects/pacific-plating-282708/locations/asia-southeast1/jobs/')
    AS 'scheduler job must be an exact production regional resource';
  ASSERT REGEXP_CONTAINS(p_desired_schedule,
      r'^\S+\s+\S+\s+\S+\s+\S+\s+\S+$')
    AS 'desired schedule must contain five cron fields';
  ASSERT p_desired_time_zone='Asia/Bangkok'
    AS 'V3 scenario schedules must use Asia/Bangkok explicitly';
  ASSERT STARTS_WITH(p_manual_fallback,'sql/operator/')
    AS 'manual fallback must be a reviewed operator artifact';
  ASSERT (SELECT COUNT(*)
    FROM `pacific-plating-282708.sap_integration_v3.vw_v3_business_flow_activation_readiness`
    WHERE flow_key=p_flow_key AND evidence_run_id=p_evidence_run_id
      AND release_ready_count>0 AND interface_row_count=0
      AND release_gate_state='READY_FOR_SCHEDULE_REVIEW'
      AND schedule_action='SCHEDULE_REVIEW_REQUIRED'
      AND blocker_code='NONE')=1
    AS 'exact flow/run is not eligible for activation approval';
  BEGIN TRANSACTION;
  MERGE `pacific-plating-282708.sap_integration_v3.v3_scenario_activation_approval` t
  USING (SELECT p_flow_key flow_key,p_evidence_run_id evidence_run_id,
    p_approval_id approval_id,p_approval_reference approval_reference,
    p_approved_by approved_by,p_approved_at approved_at,p_expires_at expires_at,
    p_approved_commit approved_commit,p_scheduler_job_name scheduler_job_name,
    p_desired_schedule desired_schedule,p_desired_time_zone desired_time_zone,
    p_manual_fallback manual_fallback,CURRENT_TIMESTAMP() recorded_at) s
  ON (t.flow_key=s.flow_key AND t.evidence_run_id=s.evidence_run_id)
    OR t.approval_id=s.approval_id
    OR (t.scheduler_job_name=s.scheduler_job_name AND t.flow_key!=s.flow_key)
  WHEN NOT MATCHED THEN INSERT ROW;
  ASSERT @@row_count=1
    AS 'flow/run or approval already exists, or scheduler is bound to another flow';
  COMMIT TRANSACTION;
END;

CREATE OR REPLACE PROCEDURE
  `pacific-plating-282708.sap_integration_v3.sp_finalize_v3_scenario_activation`(
    p_activation_id STRING,p_scheduler_poststate_json JSON,p_non_overlap_evidence JSON,
    p_verified_by STRING,p_verification_reference STRING)
BEGIN
  ASSERT (SELECT COUNT(*)
    FROM `pacific-plating-282708.sap_integration_v3.v3_scenario_activation_ledger`
    WHERE activation_id=p_activation_id AND activation_state='PRESTATE_CAPTURED')=1
    AS 'Activation must have exactly one captured prestate';
  ASSERT JSON_VALUE(p_scheduler_poststate_json,'$.name')=(SELECT scheduler_job_name
    FROM `pacific-plating-282708.sap_integration_v3.v3_scenario_activation_ledger`
    WHERE activation_id=p_activation_id)
    AND JSON_VALUE(p_scheduler_poststate_json,'$.state')='ENABLED'
    AND JSON_VALUE(p_scheduler_poststate_json,'$.schedule')=(SELECT activated_schedule
      FROM `pacific-plating-282708.sap_integration_v3.v3_scenario_activation_ledger`
      WHERE activation_id=p_activation_id)
    AND JSON_VALUE(p_scheduler_poststate_json,'$.timeZone')=(SELECT activated_time_zone
      FROM `pacific-plating-282708.sap_integration_v3.v3_scenario_activation_ledger`
      WHERE activation_id=p_activation_id)
    AS 'Exact scheduler poststate does not match approved enabled state';
  ASSERT JSON_VALUE(p_non_overlap_evidence,'$.project')='pacific-plating-282708'
    AND JSON_VALUE(p_non_overlap_evidence,'$.region')='asia-southeast1'
    AND TIMESTAMP(JSON_VALUE(p_non_overlap_evidence,'$.checkedAt'))
      BETWEEN TIMESTAMP_SUB(CURRENT_TIMESTAMP(),INTERVAL 15 MINUTE) AND CURRENT_TIMESTAMP()
    AND TIMESTAMP(JSON_VALUE(p_non_overlap_evidence,'$.horizonStart'))
      <=CURRENT_TIMESTAMP()
    AND TIMESTAMP(JSON_VALUE(p_non_overlap_evidence,'$.horizonEnd'))
      >=TIMESTAMP_ADD(CURRENT_TIMESTAMP(),INTERVAL 7 DAY)
    AND SAFE_CAST(JSON_VALUE(p_non_overlap_evidence,'$.jobCount') AS INT64)
      =ARRAY_LENGTH(JSON_QUERY_ARRAY(p_non_overlap_evidence,'$.jobs'))
    AND SAFE_CAST(JSON_VALUE(p_non_overlap_evidence,'$.enabledJobCount') AS INT64)
      =(SELECT COUNTIF(JSON_VALUE(j,'$.state')='ENABLED')
        FROM UNNEST(JSON_QUERY_ARRAY(p_non_overlap_evidence,'$.jobs')) j)
    AND (SELECT COUNTIF(JSON_VALUE(j,'$.name')
        =JSON_VALUE(p_scheduler_poststate_json,'$.name')
        AND JSON_VALUE(j,'$.state')='ENABLED')
      FROM UNNEST(JSON_QUERY_ARRAY(p_non_overlap_evidence,'$.jobs')) j)=1
    AND (SELECT COUNT(*) FROM (
      SELECT JSON_VALUE(j,'$.name') name
      FROM UNNEST(JSON_QUERY_ARRAY(p_non_overlap_evidence,'$.jobs')) j
      GROUP BY name HAVING COUNT(*)>1))=0
    AND (SELECT COUNTIF(JSON_VALUE(j,'$.state')='ENABLED'
        AND (ARRAY_LENGTH(JSON_QUERY_ARRAY(j,'$.windows'))=0
          OR SAFE_CAST(JSON_VALUE(j,'$.windowCount') AS INT64)
            !=ARRAY_LENGTH(JSON_QUERY_ARRAY(j,'$.windows'))))
      FROM UNNEST(JSON_QUERY_ARRAY(p_non_overlap_evidence,'$.jobs')) j)=0
    AND (WITH jobs AS (
      SELECT j FROM UNNEST(JSON_QUERY_ARRAY(p_non_overlap_evidence,'$.jobs')) j
      WHERE JSON_VALUE(j,'$.state')='ENABLED'),
    activated_windows AS (
      SELECT TIMESTAMP(JSON_VALUE(w,'$.start')) start_at,
        TIMESTAMP(JSON_VALUE(w,'$.end')) end_at
      FROM jobs,UNNEST(JSON_QUERY_ARRAY(j,'$.windows')) w
      WHERE JSON_VALUE(j,'$.name')=JSON_VALUE(p_scheduler_poststate_json,'$.name')),
    other_windows AS (
      SELECT JSON_VALUE(j,'$.name') name,
        TIMESTAMP(JSON_VALUE(w,'$.start')) start_at,
        TIMESTAMP(JSON_VALUE(w,'$.end')) end_at
      FROM jobs,UNNEST(JSON_QUERY_ARRAY(j,'$.windows')) w
      WHERE JSON_VALUE(j,'$.name')!=JSON_VALUE(p_scheduler_poststate_json,'$.name'))
    SELECT COUNT(*) FROM activated_windows a JOIN other_windows o
      ON a.start_at<o.end_at AND o.start_at<a.end_at)=0
    AS 'Fresh full scheduler inventory does not prove zero overlap';
  ASSERT NULLIF(TRIM(p_verified_by),'') IS NOT NULL
    AND NULLIF(TRIM(p_verification_reference),'') IS NOT NULL
    AS 'Activation finalization requires verifier and evidence reference';

  UPDATE `pacific-plating-282708.sap_integration_v3.v3_scenario_activation_ledger`
  SET activation_state='ACTIVATED',scheduler_poststate_json=p_scheduler_poststate_json,
    non_overlap_evidence=p_non_overlap_evidence,activated_by=p_verified_by,
    activated_at=CURRENT_TIMESTAMP(),verification_reference=p_verification_reference
  WHERE activation_id=p_activation_id AND activation_state='PRESTATE_CAPTURED';
  ASSERT @@row_count=1 AS 'Activation finalization failed';
END;

CREATE OR REPLACE PROCEDURE
  `pacific-plating-282708.sap_integration_v3.sp_record_v3_scenario_rollback`(
    p_rollback_id STRING,p_activation_id STRING,p_restored_scheduler_json JSON,
    p_restored_workflow_revision STRING,p_rolled_back_by STRING,
    p_verification_reference STRING)
BEGIN
  ASSERT NULLIF(TRIM(p_rollback_id),'') IS NOT NULL
    AND NULLIF(TRIM(p_rolled_back_by),'') IS NOT NULL
    AND NULLIF(TRIM(p_verification_reference),'') IS NOT NULL
    AS 'Rollback requires identity, operator, and verification evidence';
  ASSERT (SELECT COUNT(*)
    FROM `pacific-plating-282708.sap_integration_v3.v3_scenario_activation_ledger`
    WHERE activation_id=p_activation_id AND activation_state='ACTIVATED')=1
    AS 'Rollback requires exactly one activated scenario';
  ASSERT (SELECT COUNT(*)
    FROM `pacific-plating-282708.sap_integration_v3.v3_scenario_scheduler_prestate`
    WHERE activation_id=p_activation_id)=1
    AS 'Rollback requires exactly one durable scheduler prestate';
  ASSERT JSON_VALUE(p_restored_scheduler_json,'$.name')=(SELECT scheduler_job_name
      FROM `pacific-plating-282708.sap_integration_v3.v3_scenario_scheduler_prestate`
      WHERE activation_id=p_activation_id)
    AND JSON_VALUE(p_restored_scheduler_json,'$.state')=(SELECT scheduler_state
      FROM `pacific-plating-282708.sap_integration_v3.v3_scenario_scheduler_prestate`
      WHERE activation_id=p_activation_id)
    AND JSON_VALUE(p_restored_scheduler_json,'$.schedule')=(SELECT schedule
      FROM `pacific-plating-282708.sap_integration_v3.v3_scenario_scheduler_prestate`
      WHERE activation_id=p_activation_id)
    AND JSON_VALUE(p_restored_scheduler_json,'$.timeZone')=(SELECT time_zone
      FROM `pacific-plating-282708.sap_integration_v3.v3_scenario_scheduler_prestate`
      WHERE activation_id=p_activation_id)
    AND p_restored_workflow_revision=(SELECT workflow_revision
      FROM `pacific-plating-282708.sap_integration_v3.v3_scenario_scheduler_prestate`
      WHERE activation_id=p_activation_id)
    AND TO_HEX(SHA256(TO_JSON_STRING(STRUCT(
      JSON_VALUE(p_restored_scheduler_json,'$.name') AS resource_name,
      JSON_VALUE(p_restored_scheduler_json,'$.description') AS description,
      JSON_VALUE(p_restored_scheduler_json,'$.schedule') AS schedule,
      JSON_VALUE(p_restored_scheduler_json,'$.timeZone') AS time_zone,
      JSON_VALUE(p_restored_scheduler_json,'$.state') AS scheduler_state,
      JSON_VALUE(p_restored_scheduler_json,'$.attemptDeadline') AS attempt_deadline,
      JSON_QUERY(p_restored_scheduler_json,'$.retryConfig') AS retry_config,
      JSON_QUERY(p_restored_scheduler_json,'$.httpTarget') AS http_target,
      JSON_QUERY(p_restored_scheduler_json,'$.pubsubTarget') AS pubsub_target,
      JSON_QUERY(p_restored_scheduler_json,'$.appEngineHttpTarget') AS app_engine_target))))
      =(SELECT scheduler_restore_hash
        FROM `pacific-plating-282708.sap_integration_v3.v3_scenario_scheduler_prestate`
        WHERE activation_id=p_activation_id)
    AS 'Rollback poststate does not exactly restore scheduler/workflow prestate';
  ASSERT (SELECT COUNT(*)
    FROM `pacific-plating-282708.sap_integration_v3.v3_scenario_rollback_ledger`
    WHERE rollback_id=p_rollback_id OR activation_id=p_activation_id)=0
    AS 'Rollback ID or activation already recorded';

  BEGIN TRANSACTION;
  INSERT INTO `pacific-plating-282708.sap_integration_v3.v3_scenario_rollback_ledger`
  SELECT p_rollback_id,p_activation_id,p.flow_key,p.scheduler_job_name,
    JSON_VALUE(p_restored_scheduler_json,'$.state'),
    JSON_VALUE(p_restored_scheduler_json,'$.schedule'),
    JSON_VALUE(p_restored_scheduler_json,'$.timeZone'),p_restored_workflow_revision,
    p_rolled_back_by,CURRENT_TIMESTAMP(),p_verification_reference
  FROM `pacific-plating-282708.sap_integration_v3.v3_scenario_scheduler_prestate` p
  WHERE p.activation_id=p_activation_id;
  ASSERT @@row_count=1 AS 'Rollback evidence insert failed';
  UPDATE `pacific-plating-282708.sap_integration_v3.v3_scenario_activation_ledger`
  SET activation_state='ROLLED_BACK',verification_reference=p_verification_reference
  WHERE activation_id=p_activation_id AND activation_state='ACTIVATED';
  ASSERT @@row_count=1 AS 'Activation ledger rollback transition failed';
  COMMIT TRANSACTION;
END;

CREATE OR REPLACE PROCEDURE
  `pacific-plating-282708.sap_integration_v3.sp_claim_v3_scenario_activation`(
    p_activation_id STRING,p_flow_key STRING,p_evidence_run_id STRING,p_approval_id STRING,
    p_scheduler_resource_json JSON,p_scheduler_inventory_evidence JSON,
    p_workflow_revision STRING,p_activated_by STRING,p_verification_reference STRING)
BEGIN
  ASSERT NULLIF(TRIM(p_activation_id),'') IS NOT NULL
    AND NULLIF(TRIM(p_workflow_revision),'') IS NOT NULL
    AND NULLIF(TRIM(p_activated_by),'') IS NOT NULL
    AND NULLIF(TRIM(p_verification_reference),'') IS NOT NULL
    AS 'Activation claim requires identity, revision, operator, and verification';
  ASSERT (SELECT COUNT(*)
    FROM `pacific-plating-282708.sap_integration_v3.v3_scenario_activation_approval`
    WHERE flow_key=p_flow_key AND evidence_run_id=p_evidence_run_id
      AND approval_id=p_approval_id AND expires_at>CURRENT_TIMESTAMP())=1
    AS 'Activation claim lacks exact unexpired approval';
  ASSERT JSON_VALUE(p_scheduler_resource_json,'$.name')=(SELECT scheduler_job_name
    FROM `pacific-plating-282708.sap_integration_v3.v3_scenario_activation_approval`
    WHERE flow_key=p_flow_key AND evidence_run_id=p_evidence_run_id
      AND approval_id=p_approval_id)
    AS 'Scheduler prestate name differs from approved exact resource';
  ASSERT JSON_VALUE(p_scheduler_resource_json,'$.state') IN ('PAUSED','ENABLED','DISABLED')
    AND NULLIF(JSON_VALUE(p_scheduler_resource_json,'$.schedule'),'') IS NOT NULL
    AND NULLIF(JSON_VALUE(p_scheduler_resource_json,'$.timeZone'),'') IS NOT NULL
    AS 'Scheduler prestate is incomplete';
  ASSERT JSON_VALUE(p_scheduler_inventory_evidence,'$.project')='pacific-plating-282708'
    AND JSON_VALUE(p_scheduler_inventory_evidence,'$.region')='asia-southeast1'
    AND TIMESTAMP(JSON_VALUE(p_scheduler_inventory_evidence,'$.checkedAt'))
      BETWEEN TIMESTAMP_SUB(CURRENT_TIMESTAMP(),INTERVAL 15 MINUTE) AND CURRENT_TIMESTAMP()
    AND SAFE_CAST(JSON_VALUE(p_scheduler_inventory_evidence,'$.jobCount') AS INT64)
      =ARRAY_LENGTH(JSON_QUERY_ARRAY(p_scheduler_inventory_evidence,'$.jobs'))
    AND (SELECT COUNTIF(JSON_VALUE(j,'$.name')=JSON_VALUE(
        p_scheduler_resource_json,'$.name'))
      FROM UNNEST(JSON_QUERY_ARRAY(p_scheduler_inventory_evidence,'$.jobs')) j)=1
    AND (SELECT COUNT(*) FROM (
      SELECT JSON_VALUE(j,'$.name') name
      FROM UNNEST(JSON_QUERY_ARRAY(p_scheduler_inventory_evidence,'$.jobs')) j
      GROUP BY name HAVING COUNT(*)>1))=0
    AS 'Fresh complete production-region scheduler inventory is required';

  BEGIN TRANSACTION;
  MERGE `pacific-plating-282708.sap_integration_v3.v3_scenario_activation_ledger` t
  USING (SELECT p_activation_id activation_id,p_flow_key flow_key,
    p_evidence_run_id evidence_run_id,p_approval_id approval_id,
    JSON_VALUE(p_scheduler_resource_json,'$.name') scheduler_job_name) s
  ON t.activation_id=s.activation_id OR ((t.flow_key=s.flow_key
    OR t.scheduler_job_name=s.scheduler_job_name) AND t.activation_state!='ROLLED_BACK')
  WHEN NOT MATCHED THEN INSERT
    (activation_id,flow_key,evidence_run_id,approval_id,scheduler_job_name,
      activated_schedule,activated_time_zone,workflow_revision,activation_state,
      scheduler_poststate_json,non_overlap_evidence,activated_by,activated_at,
      verification_reference)
  VALUES(s.activation_id,s.flow_key,s.evidence_run_id,s.approval_id,s.scheduler_job_name,
    (SELECT desired_schedule FROM
      `pacific-plating-282708.sap_integration_v3.v3_scenario_activation_approval`
      WHERE flow_key=s.flow_key AND evidence_run_id=s.evidence_run_id
        AND approval_id=s.approval_id),
    (SELECT desired_time_zone FROM
      `pacific-plating-282708.sap_integration_v3.v3_scenario_activation_approval`
      WHERE flow_key=s.flow_key AND evidence_run_id=s.evidence_run_id
        AND approval_id=s.approval_id),p_workflow_revision,'PRESTATE_CAPTURED',NULL,NULL,
    p_activated_by,CURRENT_TIMESTAMP(),p_verification_reference);
  ASSERT @@row_count=1
    AS 'Activation ID already exists, or flow/scheduler has a non-rolled-back claim';
  INSERT INTO `pacific-plating-282708.sap_integration_v3.v3_scenario_scheduler_prestate`
  SELECT p_activation_id,p_flow_key,p_evidence_run_id,JSON_VALUE(
    p_scheduler_resource_json,'$.name'),p_scheduler_resource_json,p_scheduler_inventory_evidence,
    TO_HEX(SHA256(TO_JSON_STRING(STRUCT(
      JSON_VALUE(p_scheduler_resource_json,'$.name') AS resource_name,
      JSON_VALUE(p_scheduler_resource_json,'$.description') AS description,
      JSON_VALUE(p_scheduler_resource_json,'$.schedule') AS schedule,
      JSON_VALUE(p_scheduler_resource_json,'$.timeZone') AS time_zone,
      JSON_VALUE(p_scheduler_resource_json,'$.state') AS scheduler_state,
      JSON_VALUE(p_scheduler_resource_json,'$.attemptDeadline') AS attempt_deadline,
      JSON_QUERY(p_scheduler_resource_json,'$.retryConfig') AS retry_config,
      JSON_QUERY(p_scheduler_resource_json,'$.httpTarget') AS http_target,
      JSON_QUERY(p_scheduler_resource_json,'$.pubsubTarget') AS pubsub_target,
      JSON_QUERY(p_scheduler_resource_json,'$.appEngineHttpTarget') AS app_engine_target)))),
    JSON_VALUE(p_scheduler_resource_json,'$.state'),
    JSON_VALUE(p_scheduler_resource_json,'$.schedule'),
    JSON_VALUE(p_scheduler_resource_json,'$.timeZone'),p_workflow_revision,
    p_activated_by,CURRENT_TIMESTAMP();
  ASSERT @@row_count=1 AS 'Scheduler prestate capture failed';
  COMMIT TRANSACTION;
END;

CREATE OR REPLACE VIEW
  `pacific-plating-282708.sap_integration_v3.vw_v3_split_activation_control` AS
SELECT r.*,a.approval_id,a.approved_commit,a.scheduler_job_name,a.desired_schedule,
  a.desired_time_zone,a.expires_at,
  IF(a.approval_id IS NULL,'BLOCKED_NO_ACTIVATION_APPROVAL',
    IF(a.expires_at<=CURRENT_TIMESTAMP(),'BLOCKED_APPROVAL_EXPIRED',
      IF(l.activation_id IS NULL,'READY_TO_CAPTURE_PRESTATE',l.activation_state)))
    AS activation_control_state,
  a.manual_fallback
FROM `pacific-plating-282708.sap_integration_v3.vw_v3_business_flow_activation_readiness` r
LEFT JOIN `pacific-plating-282708.sap_integration_v3.v3_scenario_activation_approval` a
  ON a.flow_key=r.flow_key AND a.evidence_run_id=r.evidence_run_id
LEFT JOIN `pacific-plating-282708.sap_integration_v3.v3_scenario_activation_ledger` l
  ON l.flow_key=a.flow_key AND l.evidence_run_id=a.evidence_run_id
  AND l.approval_id=a.approval_id;

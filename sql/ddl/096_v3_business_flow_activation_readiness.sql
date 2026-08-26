-- Class A / read-only production control plane for the nine named business populations.
-- Only Scenarios 1-3 have authoritative numbers. Remaining flows deliberately keep number NULL.
-- These views never activate a scheduler; they state whether activation review is permissible.

CREATE TABLE IF NOT EXISTS
  `pacific-plating-282708.sap_integration_v3.v3_onetime_create_activation_summary` (
    pipeline_run_id STRING NOT NULL,
    build_job_id STRING NOT NULL,
    build_completed_at TIMESTAMP NOT NULL,
    held_count INT64 NOT NULL,
    ready_count INT64 NOT NULL,
    evidence_at TIMESTAMP NOT NULL
  )
CLUSTER BY pipeline_run_id;

CREATE OR REPLACE PROCEDURE
  `pacific-plating-282708.sap_integration_v3.sp_snapshot_v3_onetime_create_activation`(
    p_pipeline_run_id STRING
  )
BEGIN
  ASSERT NULLIF(TRIM(p_pipeline_run_id), '') IS NOT NULL AS 'pipeline_run_id is required';

  CREATE TEMP TABLE _build_proof AS
  SELECT build_job_id, completed_at AS build_completed_at, held_count, ready_count
  FROM `pacific-plating-282708.sap_integration_v3.v3_onetime_create_build_manifest`
  WHERE pipeline_run_id = p_pipeline_run_id
    AND build_contract = 'DDL085_MANIFEST_V2';

  ASSERT (SELECT COUNT(*) FROM _build_proof) = 1
    AS 'Scenario 1 snapshot requires exactly one atomic DDL085 build manifest';

  CREATE TEMP TABLE _summary AS
  SELECT p_pipeline_run_id AS pipeline_run_id,
    (SELECT build_job_id FROM _build_proof) AS build_job_id,
    (SELECT build_completed_at FROM _build_proof) AS build_completed_at,
    (SELECT held_count FROM _build_proof) AS held_count,
    (SELECT ready_count FROM _build_proof) AS ready_count,
    CURRENT_TIMESTAMP() AS evidence_at;

  BEGIN TRANSACTION;
  MERGE `pacific-plating-282708.sap_integration_v3.v3_onetime_create_activation_summary` AS target
  USING _summary AS source
  ON target.pipeline_run_id = source.pipeline_run_id
    OR target.build_job_id = source.build_job_id
  WHEN NOT MATCHED THEN
    INSERT ROW;
  ASSERT @@row_count = 1
    AS 'pipeline_run_id or build_job_id already snapshotted';
  COMMIT TRANSACTION;
END;

CREATE OR REPLACE VIEW
  `pacific-plating-282708.sap_integration_v3.vw_v3_business_flow_activation_readiness` AS
WITH
onetime AS (
  SELECT pipeline_run_id AS evidence_run_id, held_count + ready_count AS prepared_count,
    ready_count AS release_ready_count, evidence_at
  FROM `pacific-plating-282708.sap_integration_v3.v3_onetime_create_activation_summary`
  QUALIFY ROW_NUMBER() OVER (ORDER BY evidence_at DESC, pipeline_run_id DESC) = 1
),
rcl_first AS (
  SELECT * FROM `pacific-plating-282708.sap_integration_v3.v3_rcl_first_create_gate_summary`
  QUALIFY ROW_NUMBER() OVER (ORDER BY built_at DESC, pipeline_run_id DESC) = 1
),
rcl_later AS (
  SELECT * FROM `pacific-plating-282708.sap_integration_v3.v3_rcl_later_newpayment_summary`
  QUALIFY ROW_NUMBER() OVER (ORDER BY built_at DESC, pipeline_run_id DESC) = 1
),
edc AS (
  SELECT * FROM `pacific-plating-282708.sap_integration_v3.v3_edc_onetime_event_summary`
  QUALIFY ROW_NUMBER() OVER (ORDER BY built_at DESC, pipeline_run_id DESC) = 1
),
cmi AS (
  SELECT * FROM `pacific-plating-282708.sap_integration_v3.v3_rcl_cmi_event_summary`
  QUALIFY ROW_NUMBER() OVER (ORDER BY built_at DESC, pipeline_run_id DESC) = 1
),
plain_cancel AS (
  SELECT * FROM `pacific-plating-282708.sap_integration_v3.v3_plain_cancel_payload_summary`
  QUALIFY ROW_NUMBER() OVER (ORDER BY built_at DESC, ownership_run_id DESC) = 1
),
change_cancel AS (
  SELECT * FROM `pacific-plating-282708.sap_integration_v3.v3_change_order_cancel_payload_summary`
  QUALIFY ROW_NUMBER() OVER (ORDER BY built_at DESC, ownership_run_id DESC) = 1
),
creditshell AS (
  SELECT * FROM `pacific-plating-282708.sap_integration_v3.v3_creditshell_dependency_summary`
  QUALIFY ROW_NUMBER() OVER (ORDER BY built_at DESC, run_id DESC) = 1
),
adjustment AS (
  SELECT * FROM `pacific-plating-282708.sap_integration_v3.v3_payment_adjustment_intent_summary`
  QUALIFY ROW_NUMBER() OVER (ORDER BY built_at DESC, pipeline_run_id DESC) = 1
),
catalog AS (
  SELECT * FROM UNNEST([
    STRUCT('ORDINARY_ONETIME_CREATE' AS flow_key, 1 AS authoritative_scenario_number,
      'sql/operator/20260826_export_v3_onetime_create_manual.sql' AS human_fallback),
    STRUCT('RCL_FIRST_PERIOD_CREATE', 2,
      'sql/operator/20260826_report_v3_rcl_first_create_holds.sql'),
    STRUCT('RCL_LATER_PERIOD_NEWPAYMENT', 3,
      'sql/operator/20260825_export_fresh_v3_newpayment_interface.sql'),
    STRUCT('EDC_ONETIME', CAST(NULL AS INT64),
      'sql/operator/20260826_report_v3_edc_onetime_holds.sql'),
    STRUCT('RCL_CMI', CAST(NULL AS INT64),
      'sql/operator/20260826_report_v3_rcl_cmi_holds.sql'),
    STRUCT('PLAIN_CANCEL', CAST(NULL AS INT64),
      'sql/operator/20260826_report_v3_plain_cancel_payload_holds.sql'),
    STRUCT('CHANGE_ORDER_CANCEL', CAST(NULL AS INT64),
      'sql/operator/20260826_report_v3_change_order_cancel_payload_holds.sql'),
    STRUCT('CREDITSHELL_REPLACEMENT', CAST(NULL AS INT64),
      'sql/operator/20260826_report_v3_creditshell_dependency_holds.sql'),
    STRUCT('PAYMENT_ADJUSTMENT_INTENT', CAST(NULL AS INT64),
      'sql/operator/20260826_report_v3_payment_adjustment_intent_holds.sql')
  ])
),
matrix AS (
  SELECT 'ORDINARY_ONETIME_CREATE' AS flow_key, 1 AS authoritative_scenario_number,
    evidence_run_id, evidence_at, prepared_count, release_ready_count, 0 AS interface_row_count,
    IF(release_ready_count > 0, 'READY_FOR_SCHEDULE_REVIEW', 'BLOCKED_ZERO_READY') AS release_gate_state,
    IF(release_ready_count > 0, 'SCHEDULE_REVIEW_REQUIRED', 'DO_NOT_ACTIVATE') AS schedule_action,
    IF(release_ready_count > 0, 'NONE', 'SCENARIO1_NO_RELEASE_READY_ROWS') AS blocker_code,
    'sql/operator/20260826_export_v3_onetime_create_manual.sql' AS human_fallback
  FROM onetime
  UNION ALL
  SELECT 'RCL_FIRST_PERIOD_CREATE', 2, pipeline_run_id, built_at, canonical_identity_rows,
    ready_identity_rows, 0, gate_status, 'DO_NOT_ACTIVATE',
    'RCL_CREATE_INVOICE_MAPPING_REQUIRED',
    'sql/operator/20260826_report_v3_rcl_first_create_holds.sql' FROM rcl_first
  UNION ALL
  SELECT 'RCL_LATER_PERIOD_NEWPAYMENT', 3, pipeline_run_id, built_at, canonical_identity_rows,
    released_identity_rows, 0,
    IF(released_identity_rows > 0, 'READY_FOR_SCHEDULE_REVIEW', 'BLOCKED_ZERO_READY'),
    IF(released_identity_rows > 0, 'SCHEDULE_REVIEW_REQUIRED', 'DO_NOT_ACTIVATE'),
    IF(released_identity_rows > 0, 'NONE', 'SCENARIO3_NO_RELEASE_READY_ROWS'),
    'sql/operator/20260825_export_fresh_v3_newpayment_interface.sql' FROM rcl_later
  UNION ALL
  SELECT 'EDC_ONETIME', NULL, pipeline_run_id, built_at, event_count,
    0, interface_row_count, gate_status, 'DO_NOT_ACTIVATE',
    'EDC_RELEASE_APPROVAL_OR_BANK_MAPPING_REQUIRED',
    'sql/operator/20260826_report_v3_edc_onetime_holds.sql' FROM edc
  UNION ALL
  SELECT 'RCL_CMI', NULL, pipeline_run_id, built_at, event_count,
    0, interface_row_count, gate_status, 'DO_NOT_ACTIVATE',
    'CMI_PAYMENT_MAPPING_APPROVAL_REQUIRED',
    'sql/operator/20260826_report_v3_rcl_cmi_holds.sql' FROM cmi
  UNION ALL
  SELECT 'PLAIN_CANCEL', NULL, ownership_run_id, built_at, input_item_count,
    0, interface_row_count, gate_status, 'DO_NOT_ACTIVATE',
    'FA_BATCH_APPROVAL_REQUIRED',
    'sql/operator/20260826_report_v3_plain_cancel_payload_holds.sql' FROM plain_cancel
  UNION ALL
  SELECT 'CHANGE_ORDER_CANCEL', NULL, ownership_run_id, built_at, input_item_count,
    0, interface_row_count, gate_status, 'DO_NOT_ACTIVATE',
    'AWARE_FA_APPROVAL_REQUIRED',
    'sql/operator/20260826_report_v3_change_order_cancel_payload_holds.sql' FROM change_cancel
  UNION ALL
  SELECT 'CREDITSHELL_REPLACEMENT', NULL, run_id, built_at, router_item_count,
    0, interface_row_count, gate_status, 'DO_NOT_ACTIVATE',
    'ITEM_MAP_CANCEL_ACK_AND_LITERAL_APPROVAL_REQUIRED',
    'sql/operator/20260826_report_v3_creditshell_dependency_holds.sql' FROM creditshell
  UNION ALL
  SELECT 'PAYMENT_ADJUSTMENT_INTENT', NULL, pipeline_run_id, built_at, candidate_payload_count,
    0, interface_row_count, gate_status, 'DO_NOT_ACTIVATE',
    'DURABLE_INTENT_AND_RELEASE_APPROVAL_REQUIRED',
    'sql/operator/20260826_report_v3_payment_adjustment_intent_holds.sql' FROM adjustment
)
SELECT
  catalog.flow_key,
  catalog.authoritative_scenario_number,
  matrix.evidence_run_id,
  matrix.evidence_at,
  IFNULL(matrix.prepared_count, 0) AS prepared_count,
  IFNULL(matrix.release_ready_count, 0) AS release_ready_count,
  IFNULL(matrix.interface_row_count, 0) AS interface_row_count,
  COALESCE(matrix.release_gate_state, 'BLOCKED_MISSING_EVIDENCE') AS release_gate_state,
  COALESCE(matrix.schedule_action, 'DO_NOT_ACTIVATE') AS schedule_action,
  COALESCE(matrix.blocker_code, 'MISSING_DURABLE_EVIDENCE') AS blocker_code,
  catalog.human_fallback
FROM catalog
LEFT JOIN matrix USING (flow_key);

CREATE OR REPLACE VIEW
  `pacific-plating-282708.sap_integration_v3.vw_v3_scheduler_activation_blockers` AS
SELECT *
FROM `pacific-plating-282708.sap_integration_v3.vw_v3_business_flow_activation_readiness`
WHERE schedule_action != 'ACTIVATION_APPROVED'
  OR release_ready_count <= 0
  OR interface_row_count != 0;

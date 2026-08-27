-- Read-only production audit for independently releasing the nine named V3 business flows.
-- This query performs no Scheduler, workflow, GCS, SAP, or BigQuery mutation.
-- A routine being present is not sufficient: payload shape, a release-ready immutable run,
-- zero pre-activation interface rows, exact approval, activation evidence, and rollback proof
-- are reported separately so a single flow can move without weakening any other flow's holds.

WITH flow_catalog AS (
  SELECT * FROM UNNEST([
    STRUCT(
      'ORDINARY_ONETIME_CREATE' AS flow_key,
      1 AS authoritative_scenario_number,
      'sp_build_v3_onetime_create_shadow' AS build_routine,
      'v3_onetime_create_ready' AS payload_object),
    STRUCT(
      'RCL_FIRST_PERIOD_CREATE', 2,
      'sp_build_v3_rcl_first_create_hold_gate', CAST(NULL AS STRING)),
    STRUCT(
      'RCL_LATER_PERIOD_NEWPAYMENT', 3,
      'sp_build_v3_rcl_later_newpayment_split',
      'v3_rcl_later_newpayment_ready'),
    STRUCT(
      'EDC_ONETIME', CAST(NULL AS INT64),
      'sp_build_v3_edc_onetime_holds',
      'vw_v3_edc_onetime_payload_source'),
    STRUCT(
      'RCL_CMI', CAST(NULL AS INT64),
      'sp_build_v3_rcl_cmi_holds',
      'vw_v3_rcl_cmi_payload_source'),
    STRUCT(
      'PLAIN_CANCEL', CAST(NULL AS INT64),
      'sp_build_v3_plain_cancel_payload_holds',
      'vw_v3_plain_cancel_payload_source'),
    STRUCT(
      'CHANGE_ORDER_CANCEL', CAST(NULL AS INT64),
      'sp_build_v3_change_order_cancel_payload_holds',
      'vw_v3_change_order_cancel_payload_source'),
    STRUCT(
      'CREDITSHELL_REPLACEMENT', CAST(NULL AS INT64),
      'sp_build_v3_creditshell_dependency_holds', CAST(NULL AS STRING)),
    STRUCT(
      'PAYMENT_ADJUSTMENT_INTENT', CAST(NULL AS INT64),
      'sp_build_v3_payment_adjustment_intent_holds',
      'vw_v3_payment_adjustment_payload_source')
  ])
),
routine_inventory AS (
  SELECT routine_name, COUNT(*) AS routine_count
  FROM `pacific-plating-282708.sap_integration_v3.INFORMATION_SCHEMA.ROUTINES`
  GROUP BY routine_name
),
canonical_payload AS (
  SELECT
    COUNT(*) AS column_count,
    ARRAY_AGG(column_name ORDER BY ordinal_position) AS ordered_columns
  FROM `pacific-plating-282708.sap_integration_v3.INFORMATION_SCHEMA.COLUMNS`
  WHERE table_name = 'v3_unit5_newpayment_delivery_ready'
),
payload_inventory AS (
  SELECT
    table_name,
    COUNT(*) AS column_count,
    ARRAY_AGG(column_name ORDER BY ordinal_position) AS ordered_columns
  FROM `pacific-plating-282708.sap_integration_v3.INFORMATION_SCHEMA.COLUMNS`
  GROUP BY table_name
),
readiness AS (
  SELECT *
  FROM `pacific-plating-282708.sap_integration_v3.vw_v3_business_flow_activation_readiness`
),
latest_approval AS (
  SELECT *
  FROM `pacific-plating-282708.sap_integration_v3.v3_scenario_activation_approval`
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY flow_key, evidence_run_id
    ORDER BY recorded_at DESC, approval_id DESC) = 1
),
latest_activation AS (
  SELECT *
  FROM `pacific-plating-282708.sap_integration_v3.v3_scenario_activation_ledger`
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY flow_key, evidence_run_id
    ORDER BY activated_at DESC, activation_id DESC) = 1
),
activation_prestate AS (
  SELECT
    activation_id,
    COUNT(*) AS prestate_count,
    COUNTIF(
      NULLIF(scheduler_inventory_evidence_id, '') IS NOT NULL
      AND scheduler_inventory_evidence IS NOT NULL
      AND NULLIF(scheduler_restore_hash, '') IS NOT NULL) AS restorable_prestate_count
  FROM `pacific-plating-282708.sap_integration_v3.v3_scenario_scheduler_prestate`
  GROUP BY activation_id
),
audit AS (
  SELECT
    c.flow_key,
    c.authoritative_scenario_number,
    c.build_routine,
    c.payload_object,
    IF(IFNULL(ri.routine_count, 0) = 1, 'PRESENT', 'BLOCKED_ROUTINE_NOT_PRESENT')
      AS routine_state,
    IF(c.payload_object IS NULL,
      'BLOCKED_NO_RELEASE_PAYLOAD_OBJECT',
      IF(IFNULL(pi.column_count, 0) != 56,
        CONCAT('BLOCKED_PAYLOAD_COLUMN_COUNT_', CAST(IFNULL(pi.column_count, 0) AS STRING)),
        IF(TO_JSON_STRING(pi.ordered_columns) != TO_JSON_STRING(cp.ordered_columns),
          'BLOCKED_PAYLOAD_COLUMN_ORDER', 'PASS_56_COLUMN_CONTRACT')))
      AS payload_contract_state,
    r.evidence_run_id,
    r.evidence_at,
    r.prepared_count,
    r.release_ready_count,
    r.interface_row_count,
    r.release_gate_state,
    r.schedule_action,
    r.blocker_code,
    r.human_fallback,
    a.approval_id,
    a.approved_commit,
    a.scheduler_job_name,
    a.desired_schedule,
    a.desired_time_zone,
    a.expires_at AS approval_expires_at,
    IF(a.approval_id IS NULL, 'BLOCKED_NO_EXACT_APPROVAL',
      IF(a.expires_at <= CURRENT_TIMESTAMP(), 'BLOCKED_APPROVAL_EXPIRED',
        'PASS_EXACT_UNEXPIRED_APPROVAL')) AS approval_state,
    l.activation_id,
    COALESCE(l.activation_state, 'NOT_ACTIVATED') AS activation_state,
    IF(l.activation_id IS NULL, 'NOT_STARTED',
      IF(l.activation_state = 'ACTIVATED' AND l.non_overlap_evidence IS NOT NULL,
        'PASS_ACTIVATED_WITH_NONOVERLAP_EVIDENCE',
        'BLOCKED_ACTIVATION_NOT_FINALIZED')) AS schedule_evidence_state,
    IF(l.activation_id IS NULL, 'NOT_REQUIRED_BEFORE_ACTIVATION',
      IF(IFNULL(p.prestate_count, 0) = 1 AND IFNULL(p.restorable_prestate_count, 0) = 1,
        'PASS_EXACT_RESTORABLE_PRESTATE', 'BLOCKED_NO_EXACT_ROLLBACK_PRESTATE'))
      AS rollback_proof_state,
    -- The current shared delivery/import tables do not carry a universal flow_key +
    -- evidence_run_id binding for all nine flows. Never infer downstream success by filename.
    IF(l.activation_state = 'ACTIVATED',
      'REQUIRES_FLOW_SCOPED_EXPORT_DELIVERY_IMPORT_ACK_PROVENANCE',
      'NOT_STARTED_BEFORE_ACTIVATION') AS downstream_evidence_state
  FROM flow_catalog c
  CROSS JOIN canonical_payload cp
  LEFT JOIN routine_inventory ri ON ri.routine_name = c.build_routine
  LEFT JOIN payload_inventory pi ON pi.table_name = c.payload_object
  LEFT JOIN readiness r USING (flow_key)
  LEFT JOIN latest_approval a
    ON a.flow_key = r.flow_key AND a.evidence_run_id = r.evidence_run_id
  LEFT JOIN latest_activation l
    ON l.flow_key = r.flow_key AND l.evidence_run_id = r.evidence_run_id
  LEFT JOIN activation_prestate p USING (activation_id)
)
SELECT
  *,
  CASE
    WHEN routine_state != 'PRESENT' THEN routine_state
    WHEN payload_contract_state != 'PASS_56_COLUMN_CONTRACT' THEN payload_contract_state
    WHEN evidence_run_id IS NULL THEN 'BLOCKED_MISSING_DURABLE_EVIDENCE'
    WHEN release_ready_count <= 0 THEN blocker_code
    WHEN interface_row_count != 0 THEN 'BLOCKED_NONZERO_PREACTIVATION_INTERFACE_ROWS'
    WHEN release_gate_state != 'READY_FOR_SCHEDULE_REVIEW'
      OR schedule_action != 'SCHEDULE_REVIEW_REQUIRED' THEN 'BLOCKED_RELEASE_GATE'
    WHEN approval_state != 'PASS_EXACT_UNEXPIRED_APPROVAL' THEN approval_state
    WHEN activation_state = 'NOT_ACTIVATED' THEN 'READY_TO_CAPTURE_PRESTATE_AND_ACTIVATE'
    WHEN activation_state != 'ACTIVATED' THEN CONCAT('BLOCKED_', activation_state)
    WHEN schedule_evidence_state != 'PASS_ACTIVATED_WITH_NONOVERLAP_EVIDENCE'
      THEN schedule_evidence_state
    WHEN rollback_proof_state != 'PASS_EXACT_RESTORABLE_PRESTATE' THEN rollback_proof_state
    WHEN downstream_evidence_state != 'PASS_EXACT_EXPORT_DELIVERY_IMPORT_ACK'
      THEN downstream_evidence_state
    ELSE 'PRODUCTION_COMPLETE'
  END AS overall_state
FROM audit
ORDER BY COALESCE(authoritative_scenario_number, 999), flow_key;

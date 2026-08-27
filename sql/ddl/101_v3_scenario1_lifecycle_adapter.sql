-- SOURCE ONLY / Class A.
-- Adapts the already-reviewed Scenario 1 manual-delivery evidence into DDL 100's common
-- export→pickup→import→row-ACK lifecycle. It does not export, write GCS, deliver a file,
-- activate a workflow, or mutate Cloud Scheduler. Deploy DDL 100 first.

CREATE OR REPLACE PROCEDURE
  `pacific-plating-282708.sap_integration_v3.sp_register_v3_scenario1_lifecycle`(
    p_pipeline_run_id STRING,
    p_export_run_id STRING,
    p_registered_by STRING
  )
BEGIN
  DECLARE v_flow_key STRING DEFAULT 'ORDINARY_ONETIME_CREATE';
  DECLARE v_approval_id STRING;
  DECLARE v_identity_rows INT64;
  DECLARE v_payload_set_hash STRING;

  ASSERT NULLIF(TRIM(p_pipeline_run_id), '') IS NOT NULL
    AND NULLIF(TRIM(p_export_run_id), '') IS NOT NULL
    AND NULLIF(TRIM(p_registered_by), '') IS NOT NULL
    AS 'Scenario 1 lifecycle registration requires run, export, and operator identities';
  ASSERT (SELECT COUNT(*)
    FROM `pacific-plating-282708.sap_integration_v3.vw_v3_business_flow_activation_readiness`
    WHERE flow_key = v_flow_key
      AND evidence_run_id = p_pipeline_run_id
      AND release_ready_count > 0
      AND interface_row_count = 0
      AND release_gate_state = 'READY_FOR_SCHEDULE_REVIEW'
      AND schedule_action = 'SCHEDULE_REVIEW_REQUIRED'
      AND blocker_code = 'NONE') = 1
    AS 'Scenario 1 exact run is not release-ready';
  ASSERT (SELECT COUNT(*)
    FROM `pacific-plating-282708.sap_integration_v3.v3_scenario_activation_approval`
    WHERE flow_key = v_flow_key
      AND evidence_run_id = p_pipeline_run_id
      AND expires_at > CURRENT_TIMESTAMP()) = 1
    AS 'Scenario 1 lifecycle registration requires one exact unexpired approval';
  SET v_approval_id = (SELECT approval_id
    FROM `pacific-plating-282708.sap_integration_v3.v3_scenario_activation_approval`
    WHERE flow_key = v_flow_key
      AND evidence_run_id = p_pipeline_run_id
      AND expires_at > CURRENT_TIMESTAMP());

  ASSERT (SELECT COUNT(*)
    FROM `pacific-plating-282708.sap_integration_v3.v3_onetime_manual_delivery_evidence`
    WHERE pipeline_run_id = p_pipeline_run_id
      AND export_run_id = p_export_run_id) = 1
    AS 'Scenario 1 requires one exact manual-delivery evidence row';
  ASSERT (SELECT COUNT(*)
    FROM `pacific-plating-282708.sap_integration_v3.export_file_manifest` f
    JOIN `pacific-plating-282708.sap_integration_v3.v3_onetime_manual_delivery_evidence` e
      ON e.export_run_id = f.export_run_id
      AND e.archive_uri = f.archive_uri
      AND e.production_uri = f.production_uri
      AND e.archive_generation = f.archive_generation
      AND e.production_generation = f.production_generation
      AND e.production_sha256 = f.sha256
      AND e.production_size_bytes = f.size_bytes
      AND e.header_column_count = f.header_column_count
      AND e.data_row_count = f.data_row_count
    WHERE e.pipeline_run_id = p_pipeline_run_id
      AND e.export_run_id = p_export_run_id
      AND f.delivery_status IN ('DELIVERED','PICKED_UP','ACKNOWLEDGED',
        'PARTIAL_REJECT','REJECTED')) = 1
    AS 'Scenario 1 file manifest is not byte-bound to manual-delivery evidence';
  ASSERT (SELECT COUNT(*)
    FROM `pacific-plating-282708.sap_integration_v3.sap_delivery_manifest_v3` d
    JOIN `pacific-plating-282708.sap_integration_v3.v3_onetime_manual_delivery_evidence` e
      ON e.export_run_id = d.export_run_id
      AND e.production_uri = d.production_uri
      AND e.production_generation = d.production_generation
      AND e.production_sha256 = d.file_sha256
      AND e.production_file_name = d.production_file_name
      AND e.sap_result_file_name = d.sap_file_name
      AND e.data_row_count = d.data_row_count
    WHERE e.pipeline_run_id = p_pipeline_run_id
      AND e.export_run_id = p_export_run_id
      AND d.delivery_status IN ('DELIVERED','PICKED_UP','ACKNOWLEDGED',
        'PARTIAL_REJECT','REJECTED')) = 1
    AS 'Scenario 1 SAP manifest is not byte/name-bound to manual-delivery evidence';

  CREATE TEMP TABLE _identity AS
  SELECT order_item, period, charge_id, invoice_no, payload_hash
  FROM `pacific-plating-282708.sap_integration_v3.v3_unit5_payload_identity`
  WHERE pipeline_run_id = p_pipeline_run_id AND file_role = 'CREATE_ONETIME';
  SET v_identity_rows = (SELECT COUNT(*) FROM _identity);
  SET v_payload_set_hash = (SELECT TO_HEX(SHA256(COALESCE(
    STRING_AGG(payload_hash, '' ORDER BY order_item, period, invoice_no, payload_hash),
    '<EMPTY>'))) FROM _identity);

  ASSERT v_identity_rows > 0
    AND v_identity_rows = (SELECT release_ready_count
      FROM `pacific-plating-282708.sap_integration_v3.vw_v3_business_flow_activation_readiness`
      WHERE flow_key = v_flow_key AND evidence_run_id = p_pipeline_run_id)
    AS 'Scenario 1 released identities differ from activation readiness';
  ASSERT (SELECT COUNT(*) FROM (
    SELECT order_item, period, charge_id, invoice_no, COUNT(*) AS row_count
    FROM _identity GROUP BY 1,2,3,4 HAVING row_count != 1)) = 0
    AS 'Scenario 1 released identity is duplicated';
  ASSERT (SELECT COUNT(*)
    FROM `pacific-plating-282708.sap_integration_v3.export_archive` a
    JOIN _identity i
      ON i.order_item = a.order_item AND i.period = a.period
        AND i.charge_id = a.charge_id AND i.payload_hash = a.payload_hash
    WHERE a.export_run_id = p_export_run_id
      AND a.delivery_status IN ('DELIVERED','PICKED_UP','ACKNOWLEDGED')) = v_identity_rows
    AS 'Scenario 1 archive ledger does not conserve exact released identities';
  ASSERT (SELECT COUNT(*)
    FROM `pacific-plating-282708.sap_integration_v3.v3_flow_export_claim`
    WHERE export_run_id = p_export_run_id
      OR (flow_key = v_flow_key AND evidence_run_id = p_pipeline_run_id
        AND claim_state != 'ABANDONED')) = 0
    AS 'Scenario 1 export ID or flow/run lifecycle is already claimed';

  BEGIN TRANSACTION;
  MERGE `pacific-plating-282708.sap_integration_v3.v3_flow_export_claim` t
  USING (SELECT v_flow_key AS flow_key, p_pipeline_run_id AS evidence_run_id,
    v_approval_id AS approval_id, p_export_run_id AS export_run_id,
    'SCENARIO1_MANUAL_DELIVERY_V1' AS export_contract, production_file_name AS file_name,
    archive_uri AS archive_uri_pattern, v_identity_rows AS released_identity_count,
    data_row_count AS payload_row_count, v_payload_set_hash AS payload_set_hash,
    'DELIVERED' AS claim_state, TRIM(p_registered_by) AS requested_by,
    recorded_at AS requested_at, CURRENT_TIMESTAMP() AS completed_at
  FROM `pacific-plating-282708.sap_integration_v3.v3_onetime_manual_delivery_evidence`
  WHERE pipeline_run_id = p_pipeline_run_id AND export_run_id = p_export_run_id) s
  ON t.export_run_id = s.export_run_id
    OR (t.flow_key = s.flow_key AND t.evidence_run_id = s.evidence_run_id
      AND t.claim_state != 'ABANDONED')
  WHEN NOT MATCHED THEN INSERT ROW;
  ASSERT @@row_count = 1 AS 'Scenario 1 lifecycle claim insert failed or raced';
  COMMIT TRANSACTION;
END;

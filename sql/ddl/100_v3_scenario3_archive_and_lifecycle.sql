-- SOURCE ONLY / Class A.
-- Independently archives the reviewed Scenario 3 release and preserves an exact
-- flow/run/export binding through delivery, SAP pickup, import, and row reconciliation.
-- Creating this procedure/view does not CALL it, write GCS, deliver an interface file,
-- activate a workflow, or mutate Cloud Scheduler.

CREATE TABLE IF NOT EXISTS
  `pacific-plating-282708.sap_integration_v3.v3_flow_export_claim` (
    flow_key STRING NOT NULL,
    evidence_run_id STRING NOT NULL,
    approval_id STRING NOT NULL,
    export_run_id STRING NOT NULL,
    export_contract STRING NOT NULL,
    file_name STRING NOT NULL,
    archive_uri_pattern STRING NOT NULL,
    released_identity_count INT64 NOT NULL,
    payload_row_count INT64 NOT NULL,
    payload_set_hash STRING NOT NULL,
    claim_state STRING NOT NULL,
    requested_by STRING NOT NULL,
    requested_at TIMESTAMP NOT NULL,
    completed_at TIMESTAMP
  )
CLUSTER BY flow_key, evidence_run_id, export_run_id
OPTIONS(enable_change_history=TRUE);

CREATE OR REPLACE PROCEDURE
  `pacific-plating-282708.sap_integration_v3.sp_export_v3_scenario3_archive`(
    p_pipeline_run_id STRING,
    p_export_run_id STRING,
    p_requested_by STRING
  )
BEGIN
  DECLARE v_flow_key STRING DEFAULT 'RCL_LATER_PERIOD_NEWPAYMENT';
  DECLARE v_approval_id STRING;
  DECLARE v_file_name STRING;
  DECLARE v_archive_uri STRING;
  DECLARE v_identity_rows INT64;
  DECLARE v_payload_rows INT64;
  DECLARE v_payload_set_hash STRING;

  ASSERT NULLIF(TRIM(p_pipeline_run_id), '') IS NOT NULL
    AS 'Scenario 3 archive requires pipeline_run_id';
  ASSERT REGEXP_CONTAINS(p_export_run_id,
    r'^V3SCENARIO3-[0-9]{8}-[0-9]{6}-[A-Za-z0-9-]{8,}$')
    AS 'Scenario 3 export_run_id must be an explicit reviewed token';
  ASSERT NULLIF(TRIM(p_requested_by), '') IS NOT NULL
    AS 'Scenario 3 archive requires requester identity';
  ASSERT (SELECT COUNT(*)
    FROM `pacific-plating-282708.sap_integration_v3.pipeline_run_log`
    WHERE run_id = p_pipeline_run_id
      AND step = 'UNIT1_COMPLETE'
      AND status = 'SUCCESS') = 1
    AS 'Scenario 3 archive requires exactly one successful Unit 1 row';
  ASSERT (SELECT COUNT(*)
    FROM `pacific-plating-282708.sap_integration_v3.v3_rcl_later_newpayment_summary`
    WHERE pipeline_run_id = p_pipeline_run_id) = 1
    AS 'Scenario 3 archive requires one immutable split summary';
  ASSERT (SELECT COUNT(*)
    FROM `pacific-plating-282708.sap_integration_v3.vw_v3_business_flow_activation_readiness`
    WHERE flow_key = v_flow_key
      AND evidence_run_id = p_pipeline_run_id
      AND release_ready_count > 0
      AND interface_row_count = 0
      AND release_gate_state = 'READY_FOR_SCHEDULE_REVIEW'
      AND schedule_action = 'SCHEDULE_REVIEW_REQUIRED'
      AND blocker_code = 'NONE') = 1
    AS 'Scenario 3 exact run is not release-ready';
  ASSERT (SELECT COUNT(*)
    FROM `pacific-plating-282708.sap_integration_v3.v3_scenario_activation_approval`
    WHERE flow_key = v_flow_key
      AND evidence_run_id = p_pipeline_run_id
      AND expires_at > CURRENT_TIMESTAMP()) = 1
    AS 'Scenario 3 archive requires one exact unexpired activation approval';

  SET v_approval_id = (SELECT approval_id
    FROM `pacific-plating-282708.sap_integration_v3.v3_scenario_activation_approval`
    WHERE flow_key = v_flow_key
      AND evidence_run_id = p_pipeline_run_id
      AND expires_at > CURRENT_TIMESTAMP());
  SET v_file_name = CONCAT('INSURANCE_RCB_06_V3_SCENARIO3_NEWPAYMENT_',
    FORMAT_DATE('%Y%m%d', CURRENT_DATE('Asia/Bangkok')), '_', p_export_run_id);
  SET v_archive_uri = CONCAT(
    'gs://rcb-bronze-zone/sap-interface-archive/scenario3/',
    FORMAT_DATE('%Y/%m/%d', CURRENT_DATE('Asia/Bangkok')), '/',
    p_export_run_id, '/', v_file_name, '_*.csv');

  CREATE TEMP TABLE _identity AS
  SELECT pipeline_run_id, order_item, period, charge_id, invoice_no, payload_hash
  FROM `pacific-plating-282708.sap_integration_v3.v3_unit5_payload_identity`
  WHERE pipeline_run_id = p_pipeline_run_id
    AND file_role = 'NEWPAYMENT_RCL_LATER';

  CREATE TEMP TABLE _snapshot AS
  SELECT pipeline_run_id, order_item, period, invoice_no, payload_hash, payload_json
  FROM `pacific-plating-282708.sap_integration_v3.v3_rcl_later_newpayment_spine_snapshot`
  WHERE pipeline_run_id = p_pipeline_run_id;

  CREATE TEMP TABLE _payload AS
  SELECT *
  FROM `pacific-plating-282708.sap_integration_v3.v3_rcl_later_newpayment_ready`;

  SET v_identity_rows = (SELECT COUNT(*) FROM _identity);
  SET v_payload_rows = (SELECT COUNT(*) FROM _snapshot);
  SET v_payload_set_hash = (SELECT TO_HEX(SHA256(COALESCE(
    STRING_AGG(payload_hash, '' ORDER BY order_item, period, invoice_no, payload_hash),
    '<EMPTY>'))) FROM _snapshot);

  ASSERT v_identity_rows > 0
    AND v_identity_rows = (SELECT released_identity_rows
      FROM `pacific-plating-282708.sap_integration_v3.v3_rcl_later_newpayment_summary`
      WHERE pipeline_run_id = p_pipeline_run_id)
    AS 'Scenario 3 released identity count differs from immutable summary';
  ASSERT v_payload_rows > 0
    AND v_payload_rows = (SELECT released_spine_rows
      FROM `pacific-plating-282708.sap_integration_v3.v3_rcl_later_newpayment_summary`
      WHERE pipeline_run_id = p_pipeline_run_id)
    AS 'Scenario 3 payload rows differ from immutable summary';
  ASSERT (SELECT release_ready_count
    FROM `pacific-plating-282708.sap_integration_v3.vw_v3_business_flow_activation_readiness`
    WHERE flow_key = v_flow_key AND evidence_run_id = p_pipeline_run_id) = v_identity_rows
    AS 'Scenario 3 activation-ready count differs from released identities';
  ASSERT (SELECT COUNT(*) FROM (
    SELECT order_item, period, charge_id, invoice_no, COUNT(*) AS row_count
    FROM _identity GROUP BY 1,2,3,4 HAVING row_count != 1)) = 0
    AS 'Scenario 3 released identity is duplicated';
  ASSERT (SELECT COUNT(*) FROM (
    SELECT order_item, period, invoice_no, COUNT(*) AS row_count
    FROM _snapshot GROUP BY 1,2,3 HAVING row_count != 1)) = 0
    AS 'Scenario 3 immutable payload spine is duplicated';
  ASSERT (SELECT COUNT(*)
    FROM `pacific-plating-282708.sap_integration_v3.INFORMATION_SCHEMA.COLUMNS`
    WHERE table_name = 'v3_rcl_later_newpayment_ready') = 56
    AS 'Scenario 3 ready table must have exactly 56 columns';
  ASSERT (SELECT COUNT(*) FROM (
    SELECT ordinal_position, column_name, data_type
    FROM `pacific-plating-282708.sap_integration_v3.INFORMATION_SCHEMA.COLUMNS`
    WHERE table_name = 'v3_rcl_later_newpayment_ready'
    EXCEPT DISTINCT
    SELECT ordinal_position, column_name, data_type
    FROM `pacific-plating-282708.sap_integration_v3.INFORMATION_SCHEMA.COLUMNS`
    WHERE table_name = 'v3_unit5_newpayment_delivery_ready')) = 0
    AND (SELECT COUNT(*) FROM (
    SELECT ordinal_position, column_name, data_type
    FROM `pacific-plating-282708.sap_integration_v3.INFORMATION_SCHEMA.COLUMNS`
    WHERE table_name = 'v3_unit5_newpayment_delivery_ready'
    EXCEPT DISTINCT
    SELECT ordinal_position, column_name, data_type
    FROM `pacific-plating-282708.sap_integration_v3.INFORMATION_SCHEMA.COLUMNS`
    WHERE table_name = 'v3_rcl_later_newpayment_ready')) = 0
    AS 'Scenario 3 ready schema differs from canonical ordered contract';
  ASSERT (SELECT COUNT(*) FROM _snapshot s FULL OUTER JOIN _payload p
    ON p.OrderItem = s.order_item
      AND SAFE_CAST(p.Period AS INT64) = s.period
      AND p.InvoiceNo IS NOT DISTINCT FROM s.invoice_no
    WHERE s.order_item IS NULL OR p.OrderItem IS NULL
      OR s.payload_hash != TO_HEX(SHA256(TO_JSON_STRING(p)))
      OR s.payload_json != TO_JSON_STRING(p)) = 0
    AS 'Mutable Scenario 3 payload is not an exact immutable-snapshot bijection';
  ASSERT (SELECT COUNT(*) FROM _identity i
    LEFT JOIN _snapshot s
      ON s.order_item = i.order_item AND s.period = i.period
        AND s.invoice_no IS NOT DISTINCT FROM i.invoice_no
        AND s.payload_hash = i.payload_hash
    WHERE s.order_item IS NULL) = 0
    AS 'Scenario 3 released identity lacks its exact immutable target payload';
  ASSERT (SELECT COUNT(*)
    FROM `pacific-plating-282708.sap_integration_v3.v3_flow_export_claim`
    WHERE export_run_id = p_export_run_id
      OR (flow_key = v_flow_key AND evidence_run_id = p_pipeline_run_id
        AND claim_state != 'ABANDONED')) = 0
    AS 'Scenario 3 export ID or flow/run already has an active claim';
  ASSERT (SELECT COUNT(*) FROM _identity i
    JOIN `pacific-plating-282708.sap_integration_v3.export_archive` a
      ON a.order_item = i.order_item AND a.period = i.period
        AND a.charge_id = i.charge_id
    WHERE a.delivery_status IN (
      'PREPARED_ARCHIVE','ARCHIVED_PENDING_OBJECT_METADATA',
      'ARCHIVED_PENDING_DELIVERY','DELIVERED','PICKED_UP','ACKNOWLEDGED')) = 0
    AS 'Scenario 3 released identity already has active archive/delivery evidence';

  BEGIN TRANSACTION;
  INSERT INTO `pacific-plating-282708.sap_integration_v3.v3_flow_export_claim`
    (flow_key, evidence_run_id, approval_id, export_run_id, export_contract, file_name,
      archive_uri_pattern, released_identity_count, payload_row_count, payload_set_hash,
      claim_state, requested_by, requested_at)
  VALUES
    (v_flow_key, p_pipeline_run_id, v_approval_id, p_export_run_id,
      'SCENARIO3_IMMUTABLE_SPINE_V1', v_file_name, v_archive_uri,
      v_identity_rows, v_payload_rows, v_payload_set_hash,
      'PREPARING_ARCHIVE', TRIM(p_requested_by), CURRENT_TIMESTAMP());
  ASSERT @@row_count = 1 AS 'Scenario 3 export claim insert failed';

  INSERT INTO `pacific-plating-282708.sap_integration_v3.export_archive`
    (export_run_id, order_item, period, charge_id, raw_payment_date, file_name,
      gcs_uri, archive_uri, delivery_folder, contract_version, payload_hash,
      payload_json, run_type, delivery_status, exported_at)
  SELECT p_export_run_id, i.order_item, i.period, i.charge_id, DATE(e.charge_time),
    v_file_name, NULL, v_archive_uri, 'RCB_MOTOR', 'SAP_INSURANCE_56_V1',
    i.payload_hash, s.payload_json, 'SCENARIO3_NEWPAYMENT', 'PREPARED_ARCHIVE',
    CURRENT_TIMESTAMP()
  FROM _identity i
  JOIN _snapshot s
    ON s.order_item = i.order_item AND s.period = i.period
      AND s.invoice_no IS NOT DISTINCT FROM i.invoice_no
      AND s.payload_hash = i.payload_hash
  JOIN `pacific-plating-282708.sap_integration_v3.v3_unit2_event_shadow` e
    ON e.pipeline_run_id = i.pipeline_run_id AND e.order_item = i.order_item
      AND e.period = i.period AND e.charge_id = i.charge_id;
  ASSERT @@row_count = v_identity_rows
    AS 'Scenario 3 event-grain archive ledger does not conserve';
  COMMIT TRANSACTION;

  EXECUTE IMMEDIATE FORMAT("""
    EXPORT DATA OPTIONS(uri='%s',format='CSV',overwrite=false,header=true)
    AS SELECT CompanyDB,OrderID,OrderItem,InvoiceNo,OrderDate,InsuredID,Title,FirstName,LastName,
      InsurerCode,InsuranceGroup,InsuranceType,InsuranceProduct,ProductType,PolicyType,Endorse,
      PolicyDate,PolicyNo,EndorsementNo,ChassisNo,LicensePlate,GrossPremium,StampDuty,VAT,
      TotalPremium,WHT,TotalEIR,TotalSBT,ProcessingFee,ProcessingFeeVat,ShippingFee,ShippingFeeVat,
      TotalAmount,Discount,TransactionStatus,SubmissionStatus,ApprovalStatus,PaymentStatus,
      ExpectedReceived,ActualReceived,InterestThisPeriod,PrincipleThisPeriod,InterestEIRThisPeriod,
      PrincipleEIRThisPeriod,PaymentDate,Period,TotalPeriods,PendingPayment,PaymentMethod,
      PaymentChannel,ExpectedDate,RefOrder,RefundAmountBeforeFee,RefundAmountAfterFee,BillingAddress,
      BatchRunDate
    FROM _payload
  """, v_archive_uri);

  BEGIN TRANSACTION;
  UPDATE `pacific-plating-282708.sap_integration_v3.export_archive`
  SET delivery_status = 'ARCHIVED_PENDING_OBJECT_METADATA', exported_at = CURRENT_TIMESTAMP()
  WHERE export_run_id = p_export_run_id AND delivery_status = 'PREPARED_ARCHIVE';
  ASSERT @@row_count = v_identity_rows
    AS 'Scenario 3 archive rows did not finalize after object creation';
  UPDATE `pacific-plating-282708.sap_integration_v3.v3_flow_export_claim`
  SET claim_state = 'ARCHIVED_PENDING_OBJECT_METADATA', completed_at = CURRENT_TIMESTAMP()
  WHERE export_run_id = p_export_run_id AND claim_state = 'PREPARING_ARCHIVE';
  ASSERT @@row_count = 1 AS 'Scenario 3 export claim did not finalize';
  COMMIT TRANSACTION;

  SELECT p_export_run_id AS export_run_id, v_archive_uri AS archive_uri_pattern,
    v_identity_rows AS event_identity_count, v_payload_rows AS payload_row_count,
    v_payload_set_hash AS payload_set_hash,
    'ARCHIVED_PENDING_OBJECT_METADATA' AS claim_state;
END;

CREATE OR REPLACE PROCEDURE
  `pacific-plating-282708.sap_integration_v3.sp_mark_v3_flow_exact_delivery`(
    p_export_run_id STRING,
    p_archive_uri STRING,
    p_archive_generation STRING,
    p_production_uri STRING,
    p_production_generation STRING,
    p_size_bytes INT64,
    p_crc32c STRING,
    p_header_column_count INT64,
    p_data_row_count INT64,
    p_production_file_name STRING,
    p_sap_result_file_name STRING,
    p_file_sha256 STRING
  )
BEGIN
  DECLARE v_identity_rows INT64;
  DECLARE v_payload_rows INT64;
  DECLARE v_archive_uri_pattern STRING;
  DECLARE v_file_prefix STRING;

  ASSERT NULLIF(TRIM(p_export_run_id), '') IS NOT NULL
    AS 'flow delivery requires export_run_id';
  ASSERT (SELECT COUNT(*)
    FROM `pacific-plating-282708.sap_integration_v3.v3_flow_export_claim`
    WHERE export_run_id = p_export_run_id
      AND claim_state = 'ARCHIVED_PENDING_OBJECT_METADATA') = 1
    AS 'flow delivery requires one finalized archive claim';
  SET (v_identity_rows, v_payload_rows, v_archive_uri_pattern, v_file_prefix) = (
    SELECT AS STRUCT released_identity_count, payload_row_count, archive_uri_pattern, file_name
    FROM `pacific-plating-282708.sap_integration_v3.v3_flow_export_claim`
    WHERE export_run_id = p_export_run_id
      AND claim_state = 'ARCHIVED_PENDING_OBJECT_METADATA');

  ASSERT v_identity_rows > 0 AND v_payload_rows >= v_identity_rows
    AS 'flow claim has invalid identity/payload conservation';
  ASSERT STARTS_WITH(p_archive_uri,
    REGEXP_REPLACE(v_archive_uri_pattern, r'[*][.]csv$', ''))
    AS 'archive object URI is outside the exact claimed URI pattern';
  ASSERT STARTS_WITH(p_production_uri, 'gs://interface-file/RCB_MOTOR/')
    AS 'production URI is outside the approved RCB_MOTOR prefix';
  ASSERT REGEXP_CONTAINS(p_archive_generation, r'^[1-9][0-9]*$')
    AND REGEXP_CONTAINS(p_production_generation, r'^[1-9][0-9]*$')
    AS 'exact archive and production generations are required';
  ASSERT p_size_bytes > 0 AND NULLIF(TRIM(p_crc32c), '') IS NOT NULL
    AS 'exact non-empty size and CRC32C evidence is required';
  ASSERT p_header_column_count = 56
    AS 'physical flow CSV must have exactly 56 header columns';
  ASSERT p_data_row_count = v_payload_rows
    AS 'physical data rows differ from the immutable full-spine claim';
  ASSERT REGEXP_CONTAINS(p_file_sha256, r'^[0-9A-Fa-f]{64}$')
    AS 'exact flow delivery SHA-256 is required';
  ASSERT REGEXP_CONTAINS(p_production_file_name,
    CONCAT('^', v_file_prefix, r'_[0-9]+[.]csv$'))
    AS 'production filename is not one exact shard of the claimed export';
  ASSERT REGEXP_EXTRACT(p_archive_uri, r'([^/]+)$') = p_production_file_name
    AND REGEXP_EXTRACT(p_production_uri, r'([^/]+)$') = p_production_file_name
    AS 'archive and production basenames must equal the exact production filename';
  ASSERT p_sap_result_file_name = CONCAT('RCB_MOTOR_', p_production_file_name)
    AS 'SAP result filename must be the approved BU prefix plus production filename';
  ASSERT (SELECT COUNT(*)
    FROM `pacific-plating-282708.sap_integration_v3.export_archive`
    WHERE export_run_id = p_export_run_id
      AND delivery_status = 'ARCHIVED_PENDING_OBJECT_METADATA') = v_identity_rows
    AS 'flow archive ledger differs from claimed released identities';
  ASSERT (SELECT COUNT(*) FROM (
    SELECT order_item, period, charge_id, payload_hash, COUNT(*) AS row_count
    FROM `pacific-plating-282708.sap_integration_v3.export_archive`
    WHERE export_run_id = p_export_run_id
      AND delivery_status = 'ARCHIVED_PENDING_OBJECT_METADATA'
    GROUP BY 1,2,3,4 HAVING row_count != 1)) = 0
    AS 'flow archive contains duplicate event identities';
  ASSERT (SELECT COUNT(*)
    FROM `pacific-plating-282708.sap_integration_v3.export_file_manifest`
    WHERE export_run_id = p_export_run_id OR production_uri = p_production_uri) = 0
    AS 'flow file manifest/export destination already exists';
  ASSERT (SELECT COUNT(*)
    FROM `pacific-plating-282708.sap_integration_v3.sap_delivery_manifest_v3`
    WHERE export_run_id = p_export_run_id
      OR production_file_name = p_production_file_name
      OR sap_file_name = p_sap_result_file_name) = 0
    AS 'flow SAP manifest identity already exists';

  BEGIN TRANSACTION;
  UPDATE `pacific-plating-282708.sap_integration_v3.export_archive`
  SET gcs_uri = p_production_uri,
      object_generation = p_production_generation,
      file_sha256 = LOWER(p_file_sha256),
      delivery_status = 'DELIVERED'
  WHERE export_run_id = p_export_run_id
    AND delivery_status = 'ARCHIVED_PENDING_OBJECT_METADATA';
  ASSERT @@row_count = v_identity_rows
    AS 'not every flow archive identity was marked delivered';

  INSERT INTO `pacific-plating-282708.sap_integration_v3.export_file_manifest`
    (export_run_id, archive_uri, production_uri, archive_generation,
      production_generation, sha256, size_bytes, header_column_count, data_row_count,
      event_identity_count, uat2_status, delivery_status, recorded_at)
  VALUES
    (p_export_run_id, p_archive_uri, p_production_uri, p_archive_generation,
      p_production_generation, LOWER(p_file_sha256), p_size_bytes,
      p_header_column_count, p_data_row_count, v_identity_rows, NULL,
      'DELIVERED', CURRENT_TIMESTAMP());

  INSERT INTO `pacific-plating-282708.sap_integration_v3.sap_delivery_manifest_v3`
    (export_run_id, production_uri, production_generation, sap_file_name,
      file_sha256, data_row_count, event_identity_count, delivery_status,
      recorded_at, production_file_name)
  VALUES
    (p_export_run_id, p_production_uri, p_production_generation,
      p_sap_result_file_name, LOWER(p_file_sha256), p_data_row_count,
      v_identity_rows, 'DELIVERED', CURRENT_TIMESTAMP(), p_production_file_name);

  UPDATE `pacific-plating-282708.sap_integration_v3.v3_flow_export_claim`
  SET claim_state = 'DELIVERED', completed_at = CURRENT_TIMESTAMP()
  WHERE export_run_id = p_export_run_id
    AND claim_state = 'ARCHIVED_PENDING_OBJECT_METADATA';
  ASSERT @@row_count = 1 AS 'flow export claim delivery transition failed';
  COMMIT TRANSACTION;
END;

CREATE OR REPLACE VIEW
  `pacific-plating-282708.sap_integration_v3.vw_v3_flow_export_lifecycle` AS
WITH duplicate_pickup_keys AS (
  SELECT pickup_key
  FROM `pacific-plating-282708.sap_integration_v3.sap_file_pickup_v3`
  GROUP BY pickup_key HAVING COUNT(*) != 1
),
pickup AS (
  SELECT file_name,
    COUNT(*) AS pickup_rows,
    COUNTIF(LOWER(pickup_status) = 'success') AS successful_pickup_rows,
    COUNTIF(pickup_key IN (SELECT pickup_key FROM duplicate_pickup_keys))
      AS duplicate_pickup_key_rows,
    ARRAY_AGG(DISTINCT pickup_status IGNORE NULLS ORDER BY pickup_status) AS pickup_statuses
  FROM `pacific-plating-282708.sap_integration_v3.sap_file_pickup_v3`
  GROUP BY file_name
),
duplicate_log_ids AS (
  SELECT log_id
  FROM `pacific-plating-282708.sap_integration_v3.sap_import_result_header_v3`
  GROUP BY log_id HAVING COUNT(*) != 1
),
import_header AS (
  SELECT file_name,
    COUNT(*) AS import_header_rows,
    COUNTIF(log_id IN (SELECT log_id FROM duplicate_log_ids)) AS duplicate_log_id_rows,
    COUNTIF(company_db = 'RCB_LIVE_DB'
      AND attachment_parse_status = 'PARSED'
      AND NULLIF(txt_gcs_uri, '') IS NOT NULL
      AND LOWER(status) IN ('success', 'success with error')) AS terminal_import_rows,
    ARRAY_AGG(DISTINCT IF(company_db = 'RCB_LIVE_DB'
      AND attachment_parse_status = 'PARSED'
      AND NULLIF(txt_gcs_uri, '') IS NOT NULL
      AND LOWER(status) IN ('success', 'success with error'), log_id, NULL)
      IGNORE NULLS ORDER BY IF(company_db = 'RCB_LIVE_DB'
        AND attachment_parse_status = 'PARSED'
        AND NULLIF(txt_gcs_uri, '') IS NOT NULL
        AND LOWER(status) IN ('success', 'success with error'), log_id, NULL))
      AS terminal_log_ids
  FROM `pacific-plating-282708.sap_integration_v3.sap_import_result_header_v3`
  GROUP BY file_name
),
delivery AS (
  SELECT export_run_id,
    COUNT(*) AS delivery_manifest_rows,
    ARRAY_AGG(production_uri ORDER BY recorded_at DESC LIMIT 1)[SAFE_OFFSET(0)]
      AS production_uri,
    ARRAY_AGG(production_generation ORDER BY recorded_at DESC LIMIT 1)[SAFE_OFFSET(0)]
      AS production_generation,
    ARRAY_AGG(production_file_name ORDER BY recorded_at DESC LIMIT 1)[SAFE_OFFSET(0)]
      AS production_file_name,
    ARRAY_AGG(sap_file_name ORDER BY recorded_at DESC LIMIT 1)[SAFE_OFFSET(0)]
      AS sap_file_name,
    ARRAY_AGG(file_sha256 ORDER BY recorded_at DESC LIMIT 1)[SAFE_OFFSET(0)]
      AS file_sha256,
    ARRAY_AGG(delivery_status ORDER BY recorded_at DESC LIMIT 1)[SAFE_OFFSET(0)]
      AS delivery_status
  FROM `pacific-plating-282708.sap_integration_v3.sap_delivery_manifest_v3`
  GROUP BY export_run_id
),
reconciliation AS (
  SELECT export_run_id, log_id,
    COUNT(*) AS reconciled_rows,
    COUNTIF(outcome = 'ACKNOWLEDGED') AS acknowledged_rows,
    COUNTIF(outcome = 'REJECTED_BY_SAP') AS rejected_rows,
    COUNTIF(outcome = 'PENDING_ACK') AS pending_rows
  FROM `pacific-plating-282708.sap_integration_v3.v3_post_import_row_reconciliation`
  GROUP BY export_run_id, log_id
),
joined AS (
  SELECT c.*,
    IFNULL(d.delivery_manifest_rows, 0) AS delivery_manifest_rows,
    d.production_uri, d.production_generation, d.production_file_name,
    d.sap_file_name, d.file_sha256, d.delivery_status,
    IFNULL(p.pickup_rows, 0) AS pickup_rows,
    IFNULL(p.successful_pickup_rows, 0) AS successful_pickup_rows,
    IFNULL(p.duplicate_pickup_key_rows, 0) AS duplicate_pickup_key_rows,
    p.pickup_statuses,
    IFNULL(h.import_header_rows, 0) AS import_header_rows,
    IFNULL(h.duplicate_log_id_rows, 0) AS duplicate_log_id_rows,
    IFNULL(h.terminal_import_rows, 0) AS terminal_import_rows,
    h.terminal_log_ids,
    IFNULL(r.reconciled_rows, 0) AS reconciled_rows,
    IFNULL(r.acknowledged_rows, 0) AS acknowledged_rows,
    IFNULL(r.rejected_rows, 0) AS rejected_rows,
    IFNULL(r.pending_rows, 0) AS pending_rows
  FROM `pacific-plating-282708.sap_integration_v3.v3_flow_export_claim` c
  LEFT JOIN delivery d
    USING (export_run_id)
  LEFT JOIN pickup p ON p.file_name = d.production_file_name
  LEFT JOIN import_header h ON h.file_name = d.sap_file_name
  LEFT JOIN reconciliation r
    ON r.export_run_id = c.export_run_id
      AND ARRAY_LENGTH(IFNULL(h.terminal_log_ids, ARRAY<STRING>[])) = 1
      AND r.log_id = h.terminal_log_ids[SAFE_OFFSET(0)]
)
SELECT *, CASE
  WHEN claim_state = 'PREPARING_ARCHIVE' THEN 'BLOCKED_INCOMPLETE_ARCHIVE_ATTEMPT'
  WHEN claim_state NOT IN ('ARCHIVED_PENDING_OBJECT_METADATA', 'DELIVERED')
    THEN CONCAT('BLOCKED_UNKNOWN_CLAIM_STATE_', claim_state)
  WHEN claim_state = 'DELIVERED' AND delivery_manifest_rows != 1
    THEN 'BLOCKED_DELIVERED_CLAIM_WITHOUT_EXACT_MANIFEST'
  WHEN delivery_manifest_rows > 1 THEN 'BLOCKED_DUPLICATE_DELIVERY_MANIFEST'
  WHEN production_uri IS NULL THEN 'ARCHIVED_PENDING_DELIVERY'
  WHEN delivery_status NOT IN ('DELIVERED','PICKED_UP','ACKNOWLEDGED','PARTIAL_REJECT','REJECTED')
    THEN CONCAT('BLOCKED_DELIVERY_STATE_', IFNULL(delivery_status, '<NULL>'))
  WHEN duplicate_pickup_key_rows > 0 THEN 'BLOCKED_DUPLICATE_PICKUP_LOGICAL_KEY'
  WHEN successful_pickup_rows < 1 THEN 'DELIVERED_PENDING_EXACT_SAP_PICKUP'
  WHEN duplicate_log_id_rows > 0 THEN 'BLOCKED_DUPLICATE_IMPORT_LOGICAL_KEY'
  WHEN terminal_import_rows != 1 THEN 'PICKED_UP_PENDING_TERMINAL_IMPORT'
  WHEN ARRAY_LENGTH(IFNULL(terminal_log_ids, ARRAY<STRING>[])) != 1
    THEN 'BLOCKED_IMPORT_LOG_ID_CARDINALITY'
  WHEN reconciled_rows = 0 THEN 'IMPORTED_PENDING_ROW_RECONCILIATION'
  WHEN reconciled_rows != released_identity_count
    THEN 'BLOCKED_ROW_RECONCILIATION_COUNT_MISMATCH'
  WHEN acknowledged_rows + rejected_rows + pending_rows != released_identity_count
    THEN 'BLOCKED_ROW_OUTCOME_CONSERVATION'
  WHEN pending_rows > 0 THEN 'PENDING_ROW_ACK'
  WHEN rejected_rows > 0 THEN 'SAP_REJECTED_OR_PARTIAL_REJECT'
  WHEN acknowledged_rows = released_identity_count THEN 'ACKNOWLEDGED_COMPLETE'
  ELSE 'BLOCKED_UNCLASSIFIED_LIFECYCLE_STATE'
END AS lifecycle_state
FROM joined;

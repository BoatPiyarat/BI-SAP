-- SOURCE ONLY / Class A. Do not CALL without a separate reviewed rehearsal approval.
-- Seeds three retained, explicitly synthetic post-import cases without writing GCS or calling SAP.
-- The caller supplies a unique 14-digit UTC timestamp nonce (YYYYMMDDHHMMSS).

CREATE OR REPLACE PROCEDURE
  `pacific-plating-282708.sap_integration_v3.sp_seed_post_import_rehearsal_fixtures`(
    p_nonce STRING
  )
BEGIN
  DECLARE v_order_item STRING;
  DECLARE v_period INT64;
  DECLARE v_invoice_no STRING;
  DECLARE v_status STRING;

  ASSERT REGEXP_CONTAINS(p_nonce, r'^[0-9]{14}$')
    AS 'rehearsal nonce must be a unique 14-digit UTC timestamp';

  CREATE TEMP TABLE _mirror_seed AS
  SELECT
    U_OrderItem AS order_item,
    SAFE_CAST(U_Period AS INT64) AS period,
    IFNULL(U_InvoiceNo, '') AS invoice_no,
    TransactionStatus AS transaction_status
  FROM `pacific-plating-282708.sap_integration_v3.sap_mirror_doc`
  WHERE NULLIF(TRIM(U_OrderItem), '') IS NOT NULL
    AND SAFE_CAST(U_Period AS INT64) IS NOT NULL
    AND LOWER(TransactionStatus) IN ('paid', 'cancelled')
  QUALIFY ROW_NUMBER() OVER (
    ORDER BY UpdateDate DESC, UpdateTime DESC, DocEntry DESC
  ) = 1;

  ASSERT (SELECT COUNT(*) FROM _mirror_seed) = 1
    AS 'one stable mirror identity is required for ACK/error-precedence fixtures';

  SET v_order_item = (SELECT order_item FROM _mirror_seed);
  SET v_period = (SELECT period FROM _mirror_seed);
  SET v_invoice_no = (SELECT invoice_no FROM _mirror_seed);
  SET v_status = (SELECT transaction_status FROM _mirror_seed);

  CREATE TEMP TABLE _cases AS
  SELECT
    'ACK' AS case_name,
    CONCAT('99', p_nonce, '01') AS log_id,
    CONCAT('SYNTH-POSTIMPORT-', p_nonce, '-ACK') AS export_run_id,
    CONCAT('RCB_TEST_POST_IMPORT_', p_nonce, '_ACK.csv') AS sap_file_name,
    v_order_item AS order_item,
    v_period AS period,
    CONCAT('SYNTH-', p_nonce, '-ACK-CHARGE') AS charge_id,
    TO_JSON_STRING(STRUCT(
      v_invoice_no AS InvoiceNo,
      v_status AS TransactionStatus
    )) AS payload_json,
    FALSE AS has_exact_error
  UNION ALL
  SELECT
    'REJECT',
    CONCAT('99', p_nonce, '02'),
    CONCAT('SYNTH-POSTIMPORT-', p_nonce, '-REJECT'),
    CONCAT('RCB_TEST_POST_IMPORT_', p_nonce, '_REJECT.csv'),
    v_order_item,
    v_period,
    CONCAT('SYNTH-', p_nonce, '-REJECT-CHARGE'),
    TO_JSON_STRING(STRUCT(
      v_invoice_no AS InvoiceNo,
      v_status AS TransactionStatus
    )),
    TRUE
  UNION ALL
  SELECT
    'RESIDUAL',
    CONCAT('99', p_nonce, '03'),
    CONCAT('SYNTH-POSTIMPORT-', p_nonce, '-RESIDUAL'),
    CONCAT('RCB_TEST_POST_IMPORT_', p_nonce, '_RESIDUAL.csv'),
    CONCAT('SYNTHETIC-NO-MIRROR-', p_nonce),
    1,
    CONCAT('SYNTH-', p_nonce, '-RESIDUAL-CHARGE'),
    TO_JSON_STRING(STRUCT(
      CONCAT('SYNTHETIC-NO-MATCH-', p_nonce) AS InvoiceNo,
      'Paid' AS TransactionStatus
    )),
    FALSE;

  ASSERT (SELECT COUNT(*) FROM _cases) = 3
    AS 'rehearsal must contain exactly ACK, REJECT, and RESIDUAL cases';
  ASSERT (SELECT COUNT(*) FROM _cases
    WHERE NOT REGEXP_CONTAINS(log_id, r'^[0-9]{1,20}$')
      OR NOT REGEXP_CONTAINS(export_run_id, r'^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$')
      OR NOT REGEXP_CONTAINS(sap_file_name, r'^[A-Za-z0-9][A-Za-z0-9._-]*[.]csv$')) = 0
    AS 'synthetic event identity violates dispatcher validation';
  ASSERT (SELECT COUNT(*)
    FROM `pacific-plating-282708.sap_integration_v3.export_archive`
    WHERE export_run_id IN (SELECT export_run_id FROM _cases)) = 0
    AS 'rehearsal nonce already exists in export_archive';
  ASSERT (SELECT COUNT(*)
    FROM `pacific-plating-282708.sap_integration_v3.sap_import_result_header_v3`
    WHERE log_id IN (SELECT log_id FROM _cases)) = 0
    AS 'rehearsal nonce already exists in SAP import headers';
  ASSERT (SELECT COUNT(*)
    FROM `pacific-plating-282708.sap_integration_v3.v3_post_import_refresh_outbox`
    WHERE log_id IN (SELECT log_id FROM _cases)) = 0
    AS 'rehearsal nonce already exists in the post-import outbox';

  BEGIN TRANSACTION;

  INSERT INTO `pacific-plating-282708.sap_integration_v3.export_archive`
    (export_run_id, order_item, period, charge_id, raw_payment_date, file_name, gcs_uri,
     archive_uri, delivery_folder, contract_version, payload_hash, payload_json, run_type,
     delivery_status, object_generation, file_sha256, uat2_status, exported_at, sap_log_id,
     sap_result_status, acknowledged_at)
  SELECT
    export_run_id, order_item, period, charge_id, CURRENT_DATE('Asia/Bangkok'), sap_file_name,
    CONCAT('gs://rcb-bronze-zone/post_import_rehearsal/', export_run_id, '/', sap_file_name),
    CONCAT('gs://rcb-bronze-zone/post_import_rehearsal/', export_run_id, '/archive/', sap_file_name),
    'SYNTHETIC_ONLY', 'POST_IMPORT_REHEARSAL_V1',
    LOWER(TO_HEX(SHA256(CONCAT(export_run_id, '|', charge_id, '|', payload_json)))),
    payload_json, 'REHEARSAL', 'DELIVERED', CONCAT('SYNTHETIC-', p_nonce),
    LOWER(TO_HEX(SHA256(CONCAT('FILE|', export_run_id)))),
    'SYNTHETIC_ONLY', CURRENT_TIMESTAMP(), NULL, NULL, NULL
  FROM _cases;
  ASSERT @@row_count = 3 AS 'failed to seed exactly three synthetic archive rows';

  INSERT INTO `pacific-plating-282708.sap_integration_v3.export_file_manifest`
    (export_run_id, archive_uri, production_uri, archive_generation, production_generation,
     sha256, size_bytes, header_column_count, data_row_count, uat2_status, uat2_accepted_by,
     uat2_accepted_at, delivery_status, recorded_at)
  SELECT
    export_run_id,
    CONCAT('gs://rcb-bronze-zone/post_import_rehearsal/', export_run_id, '/archive/', sap_file_name),
    CONCAT('gs://rcb-bronze-zone/post_import_rehearsal/', export_run_id, '/', sap_file_name),
    CONCAT('SYNTHETIC-ARCHIVE-', p_nonce),
    CONCAT('SYNTHETIC-PRODUCTION-', p_nonce),
    LOWER(TO_HEX(SHA256(CONCAT('FILE|', export_run_id)))),
    0, 56, 1, 'SYNTHETIC_ONLY', 'POST_IMPORT_REHEARSAL', CURRENT_TIMESTAMP(),
    'DELIVERED', CURRENT_TIMESTAMP()
  FROM _cases;
  ASSERT @@row_count = 3 AS 'failed to seed exactly three synthetic file manifests';

  INSERT INTO `pacific-plating-282708.sap_integration_v3.sap_delivery_manifest_v3`
    (export_run_id, production_uri, production_generation, sap_file_name, file_sha256,
     data_row_count, delivery_status, recorded_at)
  SELECT
    export_run_id,
    CONCAT('gs://rcb-bronze-zone/post_import_rehearsal/', export_run_id, '/', sap_file_name),
    CONCAT('SYNTHETIC-PRODUCTION-', p_nonce),
    sap_file_name,
    LOWER(TO_HEX(SHA256(CONCAT('FILE|', export_run_id)))),
    1, 'DELIVERED', CURRENT_TIMESTAMP()
  FROM _cases;
  ASSERT @@row_count = 3 AS 'failed to seed exactly three synthetic SAP delivery manifests';

  INSERT INTO `pacific-plating-282708.sap_integration_v3.sap_import_result_header_v3`
    (log_id, file_name, status, import_type, company_db, email_date, gmail_message_id,
     txt_gcs_uri, xlsx_gcs_uri, je_reference, reconciliation_reference,
     attachment_parse_status, ingested_at)
  SELECT
    log_id, sap_file_name, 'success', 'INSURANCE_RCB', 'RCB_LIVE_DB', CURRENT_TIMESTAMP(),
    CONCAT('SYNTHETIC-GMAIL-', log_id),
    CONCAT('gs://rcb-bronze-zone/post_import_rehearsal/', export_run_id, '/result.txt'),
    IF(has_exact_error,
      CONCAT('gs://rcb-bronze-zone/post_import_rehearsal/', export_run_id, '/error.xlsx'),
      NULL),
    NULL, CONCAT('POST_IMPORT_REHEARSAL_', p_nonce), 'PARSED', CURRENT_TIMESTAMP()
  FROM _cases;
  ASSERT @@row_count = 3 AS 'failed to seed exactly three synthetic SAP result headers';

  INSERT INTO `pacific-plating-282708.sap_integration_v3.sap_import_error_detail_v3`
    (log_id, detail_seq, error_class, error_template, error_message_raw, row_ref, order_item,
     period, parsed_at)
  SELECT
    log_id, 1, 'ROW_LEVEL', 'SYNTHETIC_REHEARSAL_REJECT', NULL, 'SYNTHETIC_ROW_1',
    order_item, period, CURRENT_TIMESTAMP()
  FROM _cases
  WHERE has_exact_error;
  ASSERT @@row_count = 1 AS 'failed to seed one exact synthetic rejection';

  INSERT INTO `pacific-plating-282708.sap_integration_v3.v3_post_import_refresh_outbox`
    (log_id, export_run_id, sap_file_name, import_status, email_date, request_status,
     workflow_execution_name, claimed_at, completed_at, attempt_count, last_error_template,
     requested_at, claim_token)
  SELECT
    log_id, export_run_id, sap_file_name, 'success', CURRENT_TIMESTAMP(), 'PENDING',
    NULL, NULL, NULL, 0, NULL, CURRENT_TIMESTAMP(), NULL
  FROM _cases;
  ASSERT @@row_count = 3 AS 'failed to seed exactly three synthetic outbox requests';

  COMMIT TRANSACTION;

  SELECT
    case_name,
    log_id,
    export_run_id,
    sap_file_name,
    'success' AS import_status,
    FORMAT_TIMESTAMP('%Y-%m-%dT%H:%M:%E6SZ', CURRENT_TIMESTAMP(), 'UTC') AS email_date,
    CASE case_name
      WHEN 'ACK' THEN 'ACKNOWLEDGED and outbox SUCCEEDED'
      WHEN 'REJECT' THEN 'REJECTED_BY_SAP overrides mirror match; outbox SUCCEEDED'
      ELSE 'PENDING_ACK; outbox HUMAN_ACTION and workflow FAILED'
    END AS expected_result
  FROM _cases
  ORDER BY case_name;
END;

-- SOURCE ONLY / Class A. Scenario 1 manual archive + delivery evidence marker.
-- Call only after a human has create-only uploaded the same reviewed local CSV to both the durable
-- archive prefix and production. This procedure never writes GCS and never infers pickup or ACK.

CREATE TABLE IF NOT EXISTS
  `pacific-plating-282708.sap_integration_v3.v3_onetime_manual_delivery_evidence` (
    export_run_id STRING NOT NULL,pipeline_run_id STRING NOT NULL,
    archive_uri STRING NOT NULL,archive_generation STRING NOT NULL,archive_size_bytes INT64 NOT NULL,
    archive_crc32c STRING NOT NULL,archive_sha256 STRING NOT NULL,
    production_uri STRING NOT NULL,production_generation STRING NOT NULL,
    production_size_bytes INT64 NOT NULL,production_crc32c STRING NOT NULL,
    production_sha256 STRING NOT NULL,header_column_count INT64 NOT NULL,data_row_count INT64 NOT NULL,
    production_file_name STRING NOT NULL,sap_result_file_name STRING NOT NULL,
    recorded_by STRING NOT NULL,marker_commit STRING NOT NULL,recorded_at TIMESTAMP NOT NULL
  )
PARTITION BY DATE(recorded_at)
CLUSTER BY export_run_id,pipeline_run_id;

CREATE OR REPLACE PROCEDURE
  `pacific-plating-282708.sap_integration_v3.sp_mark_v3_onetime_create_manual_delivery`(
    p_pipeline_run_id STRING,p_export_run_id STRING,p_archive_uri STRING,
    p_archive_generation STRING,p_archive_size_bytes INT64,p_archive_crc32c STRING,
    p_archive_sha256 STRING,p_production_uri STRING,p_production_generation STRING,
    p_production_size_bytes INT64,p_production_crc32c STRING,p_production_sha256 STRING,
    p_header_column_count INT64,p_data_row_count INT64,p_production_file_name STRING,
    p_sap_result_file_name STRING,p_recorded_by STRING,p_marker_commit STRING)
BEGIN
  DECLARE v_identity_rows INT64;
  DECLARE v_run_date STRING;

  ASSERT NULLIF(TRIM(p_pipeline_run_id),'') IS NOT NULL AS 'pipeline_run_id is required';
  ASSERT REGEXP_CONTAINS(p_export_run_id,r'^V3MANUAL-ONETIME-[0-9]{8}-[A-Za-z0-9-]+$')
    AS 'export_run_id does not satisfy Scenario 1 manual contract';
  ASSERT STARTS_WITH(p_archive_uri,
    'gs://rcb-bronze-zone/sap-interface-archive/manual/onetime-create/')
    AS 'archive URI is outside Scenario 1 durable prefix';
  ASSERT STARTS_WITH(p_production_uri,'gs://interface-file/RCB_MOTOR/')
    AS 'production URI is outside approved RCB_MOTOR prefix';
  ASSERT REGEXP_CONTAINS(p_archive_generation,r'^[1-9][0-9]*$')
    AND REGEXP_CONTAINS(p_production_generation,r'^[1-9][0-9]*$')
    AS 'exact archive and production generations are required';
  ASSERT p_archive_size_bytes>0 AND p_production_size_bytes>0
    AND NULLIF(TRIM(p_archive_crc32c),'') IS NOT NULL
    AND NULLIF(TRIM(p_production_crc32c),'') IS NOT NULL
    AS 'independent non-empty archive and production size/CRC32C evidence is required';
  ASSERT p_archive_size_bytes=p_production_size_bytes
    AND p_archive_crc32c=p_production_crc32c
    AND LOWER(p_archive_sha256)=LOWER(p_production_sha256)
    AS 'archive and production object bytes differ';
  ASSERT p_header_column_count=56 AS 'observed physical CSV header must have 56 columns';
  ASSERT p_data_row_count>0 AS 'manual delivery cannot mark a zero-row file';
  ASSERT REGEXP_CONTAINS(p_archive_sha256,r'^[0-9A-Fa-f]{64}$')
    AND REGEXP_CONTAINS(p_production_sha256,r'^[0-9A-Fa-f]{64}$')
    AS 'independent archive and production SHA-256 evidence is required';
  ASSERT REGEXP_CONTAINS(p_production_file_name,
    r'^INSURANCE_RCB_06_V3_ONETIME_CREATE_[0-9]{8}_[A-Za-z0-9._-]+[.]csv$')
    AS 'production filename does not satisfy Scenario 1 contract';
  ASSERT p_sap_result_file_name=CONCAT('RCB_MOTOR_',p_production_file_name)
    AS 'SAP result filename must be RCB_MOTOR_ plus production filename';
  ASSERT REGEXP_EXTRACT(p_archive_uri,r'([^/]+)$')=p_production_file_name
    AND REGEXP_EXTRACT(p_production_uri,r'([^/]+)$')=p_production_file_name
    AS 'archive and production basenames must equal the recorded filename';
  ASSERT NULLIF(TRIM(p_recorded_by),'') IS NOT NULL AS 'recorded_by is required';
  ASSERT REGEXP_CONTAINS(p_marker_commit,r'^[0-9a-f]{7,40}$') AS 'reviewed marker commit is required';
  SET v_run_date=REGEXP_EXTRACT(p_export_run_id,r'^V3MANUAL-ONETIME-([0-9]{8})-');
  ASSERT SAFE.PARSE_DATE('%Y%m%d',v_run_date) IS NOT NULL
    AS 'export-run date token is not a real calendar date';
  ASSERT p_production_file_name=CONCAT('INSURANCE_RCB_06_V3_ONETIME_CREATE_',v_run_date,'_',
      p_export_run_id,'.csv') AS 'filename is not bound to exact export-run date and token';
  ASSERT p_archive_uri=CONCAT('gs://rcb-bronze-zone/sap-interface-archive/manual/onetime-create/',
      SUBSTR(v_run_date,1,4),'/',SUBSTR(v_run_date,5,2),'/',SUBSTR(v_run_date,7,2),'/',
      p_export_run_id,'/',p_production_file_name)
    AS 'archive path is not bound to exact export-run date, token, and filename';
  ASSERT p_production_uri=CONCAT('gs://interface-file/RCB_MOTOR/',p_production_file_name)
    AS 'production URI must be the exact approved folder plus filename';
  ASSERT (SELECT COUNT(*) FROM `pacific-plating-282708.sap_integration_v3.pipeline_run_log`
    WHERE run_id=p_pipeline_run_id AND step='UNIT1_COMPLETE' AND status='SUCCESS')=1
    AS 'Scenario 1 delivery requires exactly one successful Unit 1 row';

  CREATE TEMP TABLE _identity AS
  SELECT * FROM `pacific-plating-282708.sap_integration_v3.v3_unit5_payload_identity`
  WHERE pipeline_run_id=p_pipeline_run_id AND file_role='CREATE_ONETIME';
  CREATE TEMP TABLE _payload AS
  SELECT * FROM `pacific-plating-282708.sap_integration_v3.v3_onetime_create_ready`;

  ASSERT (SELECT COUNT(DISTINCT DATE(a.built_at,'Asia/Bangkok'))
    FROM _identity i JOIN `pacific-plating-282708.sap_integration_v3.v3_onetime_create_identity` a
      ON a.pipeline_run_id=i.pipeline_run_id AND a.order_item=i.order_item AND a.period=i.period
     AND a.charge_id=i.charge_id AND a.invoice_no=i.invoice_no)=1
    AND (SELECT ANY_VALUE(DATE(a.built_at,'Asia/Bangkok'))
    FROM _identity i JOIN `pacific-plating-282708.sap_integration_v3.v3_onetime_create_identity` a
      ON a.pipeline_run_id=i.pipeline_run_id AND a.order_item=i.order_item AND a.period=i.period
     AND a.charge_id=i.charge_id AND a.invoice_no=i.invoice_no)=SAFE.PARSE_DATE('%Y%m%d',v_run_date)
    AS 'export-run date does not equal the single ICT Scenario 1 build date';

  SET v_identity_rows=(SELECT COUNT(*) FROM _identity);
  ASSERT v_identity_rows>0 AND v_identity_rows=p_data_row_count
    AS 'physical data-row count differs from Scenario 1 released identities';
  ASSERT (SELECT COUNT(*) FROM _payload)=v_identity_rows
    AS 'mutable ready table is not bound to the target run identity count';
  ASSERT (SELECT COUNT(*) FROM (SELECT order_item,period,invoice_no,COUNT(*) n FROM _identity
    GROUP BY 1,2,3 HAVING n!=1))=0 AS 'Scenario 1 identity key is duplicated';
  ASSERT (SELECT COUNT(*) FROM (SELECT OrderItem,Period,InvoiceNo,COUNT(*) n FROM _payload
    GROUP BY 1,2,3 HAVING n!=1))=0 AS 'Scenario 1 payload key is duplicated';
  ASSERT (SELECT COUNT(*) FROM _identity i FULL OUTER JOIN _payload p
    ON p.OrderItem=i.order_item AND p.Period=CAST(i.period AS STRING) AND p.InvoiceNo=i.invoice_no
    WHERE i.order_item IS NULL OR p.OrderItem IS NULL
      OR i.payload_hash!=TO_HEX(SHA256(TO_JSON_STRING(p))))=0
    AS 'Scenario 1 payload and target-run identity are not an exact hash-bound bijection';
  ASSERT (SELECT COUNT(*) FROM _identity i
    JOIN `pacific-plating-282708.sap_integration_v3.v3_onetime_create_hold` h
      ON h.pipeline_run_id=i.pipeline_run_id AND h.order_item=i.order_item AND h.period=i.period
     AND h.invoice_no IS NOT DISTINCT FROM i.invoice_no AND h.charge_id=i.charge_id)=0
    AS 'Scenario 1 released identity intersects a durable hold';
  BEGIN TRANSACTION;
  MERGE `pacific-plating-282708.sap_integration_v3.v3_onetime_manual_delivery_evidence` t
  USING (SELECT p_export_run_id export_run_id,p_pipeline_run_id pipeline_run_id,
    p_archive_uri archive_uri,p_archive_generation archive_generation,
    p_archive_size_bytes archive_size_bytes,p_archive_crc32c archive_crc32c,
    LOWER(p_archive_sha256) archive_sha256,p_production_uri production_uri,
    p_production_generation production_generation,p_production_size_bytes production_size_bytes,
    p_production_crc32c production_crc32c,LOWER(p_production_sha256) production_sha256,
    p_header_column_count header_column_count,p_data_row_count data_row_count,
    p_production_file_name production_file_name,p_sap_result_file_name sap_result_file_name,
    TRIM(p_recorded_by) recorded_by,p_marker_commit marker_commit,CURRENT_TIMESTAMP() recorded_at) s
  ON t.export_run_id=s.export_run_id OR t.archive_uri=s.archive_uri OR t.production_uri=s.production_uri
    OR t.production_file_name=s.production_file_name OR t.sap_result_file_name=s.sap_result_file_name
  WHEN NOT MATCHED THEN INSERT ROW;
  ASSERT @@row_count=1 AS 'manual delivery evidence identity already claimed; refusing replay';

  ASSERT (SELECT COUNT(*) FROM _identity i
    JOIN `pacific-plating-282708.sap_integration_v3.export_archive` a
      ON a.order_item=i.order_item AND a.period=i.period AND a.charge_id=i.charge_id)=0
    AS 'Scenario 1 identity has prior archive/delivery evidence; refusing replay';
  ASSERT (SELECT COUNT(*) FROM `pacific-plating-282708.sap_integration_v3.export_file_manifest`
    WHERE export_run_id=p_export_run_id OR archive_uri=p_archive_uri
      OR production_uri=p_production_uri)=0 AS 'file manifest or object already recorded';
  ASSERT (SELECT COUNT(*) FROM `pacific-plating-282708.sap_integration_v3.sap_delivery_manifest_v3`
    WHERE export_run_id=p_export_run_id OR production_file_name=p_production_file_name
      OR sap_file_name=p_sap_result_file_name)=0 AS 'SAP manifest identity already recorded';

  INSERT INTO `pacific-plating-282708.sap_integration_v3.export_archive`
    (export_run_id,order_item,period,charge_id,raw_payment_date,file_name,gcs_uri,archive_uri,
     delivery_folder,contract_version,payload_hash,payload_json,run_type,delivery_status,exported_at)
  SELECT p_export_run_id,i.order_item,i.period,i.charge_id,a.source_payment_date,
    p_production_file_name,p_production_uri,p_archive_uri,'RCB_MOTOR','SAP_INSURANCE_56_V1',
    i.payload_hash,TO_JSON_STRING(p),'MANUAL','DELIVERED',CURRENT_TIMESTAMP()
  FROM _identity i JOIN _payload p
    ON p.OrderItem=i.order_item AND p.Period=CAST(i.period AS STRING) AND p.InvoiceNo=i.invoice_no
  JOIN `pacific-plating-282708.sap_integration_v3.v3_onetime_create_identity` a
    ON a.pipeline_run_id=i.pipeline_run_id AND a.order_item=i.order_item AND a.period=i.period
   AND a.charge_id=i.charge_id AND a.invoice_no=i.invoice_no;
  ASSERT @@row_count=v_identity_rows AS 'Scenario 1 archive ledger conservation failed';

  INSERT INTO `pacific-plating-282708.sap_integration_v3.export_file_manifest`
    (export_run_id,archive_uri,production_uri,archive_generation,production_generation,sha256,
     size_bytes,header_column_count,data_row_count,event_identity_count,uat2_status,delivery_status,
     recorded_at)
  VALUES (p_export_run_id,p_archive_uri,p_production_uri,p_archive_generation,
    p_production_generation,LOWER(p_production_sha256),p_production_size_bytes,
    p_header_column_count,p_data_row_count,v_identity_rows,
    NULL,'DELIVERED',CURRENT_TIMESTAMP());

  INSERT INTO `pacific-plating-282708.sap_integration_v3.sap_delivery_manifest_v3`
    (export_run_id,production_uri,production_generation,sap_file_name,file_sha256,data_row_count,
     event_identity_count,delivery_status,recorded_at,production_file_name)
  VALUES (p_export_run_id,p_production_uri,p_production_generation,p_sap_result_file_name,
    LOWER(p_production_sha256),p_data_row_count,v_identity_rows,'DELIVERED',CURRENT_TIMESTAMP(),
    p_production_file_name);
  COMMIT TRANSACTION;
END;

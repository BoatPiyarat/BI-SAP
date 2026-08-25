-- Class A / called only after an exact-generation, create-only GCS copy has succeeded.
-- GCS is mutated by the orchestrator, not by this procedure. This procedure only persists
-- delivery evidence; it never infers SAP pickup or row-level acknowledgement from the copy.
-- Deploy reviewed DDL 070's production_file_name schema delta before this replacement.

ALTER TABLE `pacific-plating-282708.sap_integration_v3.export_file_manifest`
ADD COLUMN IF NOT EXISTS event_identity_count INT64;

ALTER TABLE `pacific-plating-282708.sap_integration_v3.sap_delivery_manifest_v3`
ADD COLUMN IF NOT EXISTS event_identity_count INT64;

CREATE OR REPLACE PROCEDURE `pacific-plating-282708.sap_integration_v3.sp_mark_v3_exact_delivery`(
  p_pipeline_run_id STRING,
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
  DECLARE v_archive_rows INT64;
  DECLARE v_identity_unmatched INT64;
  DECLARE v_archive_unmatched INT64;

  ASSERT NULLIF(TRIM(p_pipeline_run_id),'') IS NOT NULL AS 'pipeline_run_id is required';
  ASSERT NULLIF(TRIM(p_export_run_id),'') IS NOT NULL AS 'export_run_id is required';
  ASSERT STARTS_WITH(p_archive_uri,'gs://rcb-bronze-zone/sap-interface-archive/')
    AS 'archive URI is outside the approved durable prefix';
  ASSERT STARTS_WITH(p_production_uri,'gs://interface-file/RCB_MOTOR/')
    AS 'production URI is outside the approved RCB_MOTOR prefix';
  ASSERT NULLIF(TRIM(p_archive_generation),'') IS NOT NULL
    AS 'archive generation evidence is required';
  ASSERT NULLIF(TRIM(p_production_generation),'') IS NOT NULL
    AS 'production generation evidence is required';
  ASSERT p_size_bytes>0 AS 'production object must be non-empty';
  ASSERT NULLIF(TRIM(p_crc32c),'') IS NOT NULL AS 'matching CRC32C evidence is required';
  ASSERT p_header_column_count=56 AS 'physical CSV must have exactly 56 header columns';
  ASSERT p_data_row_count>0 AS 'physical CSV must have at least one data row';
  ASSERT REGEXP_CONTAINS(p_production_file_name,
    r'^INSURANCE_RCB_[A-Za-z0-9._-]*[.]csv$')
    AS 'exact production filename must satisfy the INSURANCE_RCB CSV contract';
  ASSERT REGEXP_CONTAINS(p_sap_result_file_name,
    r'^RCB_MOTOR_INSURANCE_RCB_[A-Za-z0-9._-]*[.]csv$')
    AS 'exact SAP result filename must satisfy the RCB_MOTOR reporting contract';
  ASSERT REGEXP_CONTAINS(p_file_sha256,r'^[0-9A-Fa-f]{64}$')
    AS 'exact delivery SHA-256 evidence is required';
  ASSERT REGEXP_EXTRACT(p_production_uri,r'([^/]+)$')=p_production_file_name
    AS 'production filename must exactly equal the production object basename';
  ASSERT p_sap_result_file_name=CONCAT('RCB_MOTOR_',p_production_file_name)
    AS 'SAP result filename must be the approved BU reporting prefix plus production filename';

  SET v_identity_rows=(SELECT COUNT(*)
    FROM `pacific-plating-282708.sap_integration_v3.v3_unit5_payload_identity` i
    WHERE pipeline_run_id=p_pipeline_run_id AND file_role='NEWPAYMENT'
      AND NOT EXISTS (SELECT 1
        FROM `pacific-plating-282708.sap_integration_v3.v3_unit5_balance_hold` h
        WHERE h.pipeline_run_id=p_pipeline_run_id AND h.order_item=i.order_item));
  SET v_archive_rows=(SELECT COUNT(*)
    FROM `pacific-plating-282708.sap_integration_v3.export_archive`
    WHERE export_run_id=p_export_run_id
      AND delivery_status='ARCHIVED_PENDING_OBJECT_METADATA');
  SET v_identity_unmatched=(SELECT COUNT(*)
    FROM `pacific-plating-282708.sap_integration_v3.v3_unit5_payload_identity` i
    WHERE i.pipeline_run_id=p_pipeline_run_id AND i.file_role='NEWPAYMENT'
      AND NOT EXISTS (SELECT 1
        FROM `pacific-plating-282708.sap_integration_v3.v3_unit5_balance_hold` h
        WHERE h.pipeline_run_id=p_pipeline_run_id AND h.order_item=i.order_item)
      AND NOT EXISTS (SELECT 1
        FROM `pacific-plating-282708.sap_integration_v3.export_archive` a
        WHERE a.export_run_id=p_export_run_id
          AND a.delivery_status='ARCHIVED_PENDING_OBJECT_METADATA'
          AND a.order_item=i.order_item AND a.period=i.period AND a.charge_id=i.charge_id
          AND a.payload_hash=i.payload_hash));
  SET v_archive_unmatched=(SELECT COUNT(*)
    FROM `pacific-plating-282708.sap_integration_v3.export_archive` a
    WHERE a.export_run_id=p_export_run_id
      AND a.delivery_status='ARCHIVED_PENDING_OBJECT_METADATA'
      AND NOT EXISTS (SELECT 1
        FROM `pacific-plating-282708.sap_integration_v3.v3_unit5_payload_identity` i
        WHERE i.pipeline_run_id=p_pipeline_run_id AND i.file_role='NEWPAYMENT'
          AND i.order_item=a.order_item AND i.period=a.period AND i.charge_id=a.charge_id
          AND i.payload_hash=a.payload_hash
          AND NOT EXISTS (SELECT 1
            FROM `pacific-plating-282708.sap_integration_v3.v3_unit5_balance_hold` h
            WHERE h.pipeline_run_id=p_pipeline_run_id AND h.order_item=i.order_item)));
  ASSERT v_identity_rows>0 AS 'delivery cannot be marked for a zero-row run';
  ASSERT v_archive_rows=v_identity_rows
    AS 'archive ledger does not conserve against the same pipeline run identity';
  ASSERT v_identity_unmatched=0 AND v_archive_unmatched=0
    AS 'archive ledger identity set does not exactly match the same pipeline run payload';
  ASSERT p_data_row_count>=v_archive_rows
    AS 'physical CSV rows cannot be fewer than released event identities';
  ASSERT (SELECT COUNT(DISTINCT archive_uri)
    FROM `pacific-plating-282708.sap_integration_v3.export_archive`
    WHERE export_run_id=p_export_run_id)=1 AS 'export run has multiple archive URIs';
  ASSERT STARTS_WITH(p_archive_uri,(SELECT REGEXP_REPLACE(ANY_VALUE(archive_uri),r'[*][.]csv$','')
    FROM `pacific-plating-282708.sap_integration_v3.export_archive`
    WHERE export_run_id=p_export_run_id))
    AS 'archive object URI is outside the exact export-run URI pattern';
  ASSERT REGEXP_EXTRACT(p_archive_uri,r'([^/]+)$')=p_production_file_name
    AS 'archive and production basenames must match for exact-byte promotion';
  ASSERT (SELECT COUNT(*)
    FROM `pacific-plating-282708.sap_integration_v3.export_file_manifest`
    WHERE export_run_id=p_export_run_id OR production_uri=p_production_uri)=0
    AS 'manifest/export destination already recorded; refusing replay';
  ASSERT (SELECT COUNT(*)
    FROM `pacific-plating-282708.sap_integration_v3.sap_delivery_manifest_v3`
    WHERE export_run_id=p_export_run_id
      OR production_file_name=p_production_file_name
      OR sap_file_name=p_sap_result_file_name)=0
    AS 'SAP delivery manifest production/result filename or export run already recorded';

  BEGIN TRANSACTION;
  UPDATE `pacific-plating-282708.sap_integration_v3.export_archive`
  SET gcs_uri=p_production_uri,
      object_generation=p_production_generation,
      file_sha256=p_file_sha256,
      delivery_status='DELIVERED'
  WHERE export_run_id=p_export_run_id
    AND delivery_status='ARCHIVED_PENDING_OBJECT_METADATA';

  ASSERT @@row_count=v_archive_rows AS 'not every archive ledger row was marked DELIVERED';

  INSERT INTO `pacific-plating-282708.sap_integration_v3.export_file_manifest`
    (export_run_id,archive_uri,production_uri,archive_generation,production_generation,sha256,
     size_bytes,header_column_count,data_row_count,event_identity_count,uat2_status,delivery_status,
     recorded_at)
  VALUES
    (p_export_run_id,p_archive_uri,p_production_uri,p_archive_generation,p_production_generation,
     p_file_sha256,p_size_bytes,p_header_column_count,p_data_row_count,v_archive_rows,NULL,
     'DELIVERED',CURRENT_TIMESTAMP());

  INSERT INTO `pacific-plating-282708.sap_integration_v3.sap_delivery_manifest_v3`
    (export_run_id,production_uri,production_generation,sap_file_name,file_sha256,data_row_count,
     event_identity_count,delivery_status,recorded_at,production_file_name)
  VALUES
    (p_export_run_id,p_production_uri,p_production_generation,p_sap_result_file_name,p_file_sha256,
     p_data_row_count,v_archive_rows,'DELIVERED',CURRENT_TIMESTAMP(),p_production_file_name);
  COMMIT TRANSACTION;

  -- DELIVERED is only GCS evidence. PICKED_UP/ACKNOWLEDGED remain untouched until independent
  -- SAP result or refreshed mirror evidence is ingested. Deploy DDL 070 before this replacement.
END;

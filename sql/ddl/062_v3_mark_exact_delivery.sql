-- Class A / called only after an exact-generation, create-only GCS copy has succeeded.
-- GCS is mutated by the orchestrator, not by this procedure. This procedure only persists
-- delivery evidence; it never infers SAP pickup or row-level acknowledgement from the copy.

CREATE OR REPLACE PROCEDURE `pacific-plating-282708.sap_integration_v3.sp_mark_v3_exact_delivery`(
  p_pipeline_run_id STRING,
  p_export_run_id STRING,
  p_archive_uri STRING,
  p_archive_generation STRING,
  p_production_uri STRING,
  p_production_generation STRING,
  p_size_bytes INT64,
  p_crc32c STRING
)
BEGIN
  DECLARE v_identity_rows INT64;
  DECLARE v_archive_rows INT64;

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

  SET v_identity_rows=(SELECT COUNT(*)
    FROM `pacific-plating-282708.sap_integration_v3.v3_unit5_payload_identity`
    WHERE pipeline_run_id=p_pipeline_run_id AND file_role='NEWPAYMENT');
  SET v_archive_rows=(SELECT COUNT(*)
    FROM `pacific-plating-282708.sap_integration_v3.export_archive`
    WHERE export_run_id=p_export_run_id
      AND delivery_status='ARCHIVED_PENDING_OBJECT_METADATA');

  ASSERT v_identity_rows>0 AS 'delivery cannot be marked for a zero-row run';
  ASSERT v_archive_rows=v_identity_rows
    AS 'archive ledger does not conserve against the same pipeline run identity';
  ASSERT (SELECT COUNT(DISTINCT archive_uri)
    FROM `pacific-plating-282708.sap_integration_v3.export_archive`
    WHERE export_run_id=p_export_run_id)=1 AS 'export run has multiple archive URIs';
  ASSERT (SELECT COUNT(*)
    FROM `pacific-plating-282708.sap_integration_v3.export_file_manifest`
    WHERE export_run_id=p_export_run_id OR production_uri=p_production_uri)=0
    AS 'manifest/export destination already recorded; refusing replay';

  UPDATE `pacific-plating-282708.sap_integration_v3.export_archive`
  SET gcs_uri=p_production_uri,
      object_generation=p_production_generation,
      delivery_status='DELIVERED'
  WHERE export_run_id=p_export_run_id
    AND delivery_status='ARCHIVED_PENDING_OBJECT_METADATA';

  ASSERT @@row_count=v_archive_rows AS 'not every archive ledger row was marked DELIVERED';

  INSERT INTO `pacific-plating-282708.sap_integration_v3.export_file_manifest`
    (export_run_id,archive_uri,production_uri,archive_generation,production_generation,sha256,
     size_bytes,header_column_count,data_row_count,uat2_status,delivery_status,recorded_at)
  VALUES
    (p_export_run_id,p_archive_uri,p_production_uri,p_archive_generation,p_production_generation,
     NULL,p_size_bytes,56,v_archive_rows,NULL,'DELIVERED',CURRENT_TIMESTAMP());

  -- DELIVERED is only GCS evidence. PICKED_UP/ACKNOWLEDGED remain untouched until independent
  -- SAP result or refreshed mirror evidence is ingested.
END;

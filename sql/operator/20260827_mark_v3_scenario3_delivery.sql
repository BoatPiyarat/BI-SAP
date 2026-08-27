-- MUTATING EVIDENCE MARKER. Run only after a human has copied one exact immutable archive shard
-- to gs://interface-file/RCB_MOTOR/ with create-only generation preconditions and independently
-- captured the archive + production object metadata. This SQL does not copy/write a GCS object.
-- Deploy reviewed DDL 100 first and replace every sentinel before execution.

DECLARE target_export_run_id STRING DEFAULT 'REPLACE_WITH_EXACT_EXPORT_RUN_ID';
DECLARE archive_uri STRING DEFAULT 'REPLACE_WITH_EXACT_ARCHIVE_OBJECT_URI';
DECLARE archive_generation STRING DEFAULT 'REPLACE_WITH_ARCHIVE_GENERATION';
DECLARE production_uri STRING DEFAULT 'REPLACE_WITH_EXACT_PRODUCTION_OBJECT_URI';
DECLARE production_generation STRING DEFAULT 'REPLACE_WITH_PRODUCTION_GENERATION';
DECLARE size_bytes INT64 DEFAULT -1;
DECLARE crc32c STRING DEFAULT 'REPLACE_WITH_MATCHING_CRC32C';
DECLARE header_column_count INT64 DEFAULT -1;
DECLARE data_row_count INT64 DEFAULT -1;
DECLARE production_file_name STRING DEFAULT 'REPLACE_WITH_EXACT_PRODUCTION_BASENAME';
DECLARE sap_result_file_name STRING DEFAULT 'REPLACE_WITH_EXACT_SAP_RESULT_FILENAME';
DECLARE file_sha256 STRING DEFAULT 'REPLACE_WITH_EXACT_SHA256';

ASSERT target_export_run_id != 'REPLACE_WITH_EXACT_EXPORT_RUN_ID'
  AND archive_uri != 'REPLACE_WITH_EXACT_ARCHIVE_OBJECT_URI'
  AND archive_generation != 'REPLACE_WITH_ARCHIVE_GENERATION'
  AND production_uri != 'REPLACE_WITH_EXACT_PRODUCTION_OBJECT_URI'
  AND production_generation != 'REPLACE_WITH_PRODUCTION_GENERATION'
  AND crc32c != 'REPLACE_WITH_MATCHING_CRC32C'
  AND production_file_name != 'REPLACE_WITH_EXACT_PRODUCTION_BASENAME'
  AND sap_result_file_name != 'REPLACE_WITH_EXACT_SAP_RESULT_FILENAME'
  AND file_sha256 != 'REPLACE_WITH_EXACT_SHA256'
  AND size_bytes > 0 AND header_column_count = 56 AND data_row_count > 0
  AS 'Replace all delivery-evidence sentinels with independently observed exact values';

CALL `pacific-plating-282708.sap_integration_v3.sp_mark_v3_flow_exact_delivery`(
  target_export_run_id, archive_uri, archive_generation, production_uri,
  production_generation, size_bytes, crc32c, header_column_count, data_row_count,
  production_file_name, sap_result_file_name, file_sha256);

SELECT *
FROM `pacific-plating-282708.sap_integration_v3.vw_v3_flow_export_lifecycle`
WHERE export_run_id = target_export_run_id;

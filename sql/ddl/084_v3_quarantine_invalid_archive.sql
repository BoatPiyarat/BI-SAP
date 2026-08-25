-- Class A / ledger mutation when called. Quarantines an archive-only export whose physical CSV
-- failed payload validation. It does not delete or rewrite GCS and cannot touch delivered/SAP-seen
-- runs. The immutable object metadata is recorded for audit before replay is permitted.

CREATE TABLE IF NOT EXISTS `pacific-plating-282708.sap_integration_v3.v3_archive_quarantine_log` (
  export_run_id STRING NOT NULL,
  prior_delivery_status STRING NOT NULL,
  archive_uri_pattern STRING NOT NULL,
  archive_object_uri STRING NOT NULL,
  archive_generation STRING NOT NULL,
  file_sha256 STRING NOT NULL,
  ledger_rows INT64 NOT NULL,
  quarantine_reason STRING NOT NULL,
  quarantined_by STRING NOT NULL,
  quarantined_at TIMESTAMP NOT NULL
)
PARTITION BY DATE(quarantined_at)
CLUSTER BY export_run_id;

CREATE OR REPLACE PROCEDURE `pacific-plating-282708.sap_integration_v3.sp_quarantine_invalid_v3_archive`(
  p_export_run_id STRING,
  p_archive_object_uri STRING,
  p_archive_generation STRING,
  p_file_sha256 STRING,
  p_expected_ledger_rows INT64,
  p_quarantine_reason STRING,
  p_quarantined_by STRING
)
BEGIN
  DECLARE v_prior_status STRING;
  DECLARE v_archive_uri_pattern STRING;
  DECLARE v_ledger_rows INT64;

  ASSERT NULLIF(TRIM(p_export_run_id),'') IS NOT NULL AS 'export_run_id is required';
  ASSERT STARTS_WITH(p_archive_object_uri,
    'gs://rcb-bronze-zone/sap-interface-archive/')
    AS 'archive object is outside the durable archive prefix';
  ASSERT NULLIF(TRIM(p_archive_generation),'') IS NOT NULL
    AS 'archive generation evidence is required';
  ASSERT REGEXP_CONTAINS(p_file_sha256,r'^[0-9A-Fa-f]{64}$')
    AS 'archive SHA-256 evidence is required';
  ASSERT p_expected_ledger_rows>0 AS 'expected ledger rows must be positive';
  ASSERT LENGTH(TRIM(p_quarantine_reason))>=20 AS 'specific quarantine reason is required';
  ASSERT NULLIF(TRIM(p_quarantined_by),'') IS NOT NULL AS 'quarantined_by is required';

  SET v_ledger_rows=(SELECT COUNT(*)
    FROM `pacific-plating-282708.sap_integration_v3.export_archive`
    WHERE export_run_id=p_export_run_id);
  SET v_prior_status=(SELECT ANY_VALUE(delivery_status)
    FROM `pacific-plating-282708.sap_integration_v3.export_archive`
    WHERE export_run_id=p_export_run_id);
  SET v_archive_uri_pattern=(SELECT ANY_VALUE(archive_uri)
    FROM `pacific-plating-282708.sap_integration_v3.export_archive`
    WHERE export_run_id=p_export_run_id);

  ASSERT v_ledger_rows=p_expected_ledger_rows
    AS 'archive ledger row count differs from reviewed evidence';
  ASSERT (SELECT COUNT(DISTINCT delivery_status)
    FROM `pacific-plating-282708.sap_integration_v3.export_archive`
    WHERE export_run_id=p_export_run_id)=1
    AS 'archive run has mixed delivery statuses';
  ASSERT v_prior_status='ARCHIVED_PENDING_OBJECT_METADATA'
    AS 'only an archive-only run pending object metadata can be quarantined';
  ASSERT (SELECT COUNT(DISTINCT archive_uri)
    FROM `pacific-plating-282708.sap_integration_v3.export_archive`
    WHERE export_run_id=p_export_run_id)=1
    AS 'archive run does not have exactly one URI pattern';
  ASSERT STARTS_WITH(p_archive_object_uri,
    REGEXP_REPLACE(v_archive_uri_pattern,r'[*][.]csv$',''))
    AS 'physical archive object is outside the ledger URI prefix';
  ASSERT (SELECT COUNT(*)
    FROM `pacific-plating-282708.sap_integration_v3.export_archive`
    WHERE export_run_id=p_export_run_id
      AND (gcs_uri IS NOT NULL OR object_generation IS NOT NULL OR file_sha256 IS NOT NULL
        OR sap_log_id IS NOT NULL OR sap_result_status IS NOT NULL OR acknowledged_at IS NOT NULL))=0
    AS 'archive run has production delivery, object metadata, or SAP evidence';
  ASSERT (SELECT COUNT(*)
    FROM `pacific-plating-282708.sap_integration_v3.export_file_manifest`
    WHERE export_run_id=p_export_run_id)=0
    AS 'archive run already has a delivery file manifest';
  ASSERT (SELECT COUNT(*)
    FROM `pacific-plating-282708.sap_integration_v3.sap_delivery_manifest_v3`
    WHERE export_run_id=p_export_run_id)=0
    AS 'archive run already has an SAP delivery manifest';
  ASSERT (SELECT COUNT(*)
    FROM `pacific-plating-282708.sap_integration_v3.v3_archive_quarantine_log`
    WHERE export_run_id=p_export_run_id)=0
    AS 'archive run already has quarantine evidence';

  BEGIN TRANSACTION;
  INSERT INTO `pacific-plating-282708.sap_integration_v3.v3_archive_quarantine_log`
    (export_run_id,prior_delivery_status,archive_uri_pattern,archive_object_uri,
     archive_generation,file_sha256,ledger_rows,quarantine_reason,quarantined_by,quarantined_at)
  VALUES
    (p_export_run_id,v_prior_status,v_archive_uri_pattern,p_archive_object_uri,
     p_archive_generation,LOWER(p_file_sha256),v_ledger_rows,TRIM(p_quarantine_reason),
     TRIM(p_quarantined_by),CURRENT_TIMESTAMP());

  UPDATE `pacific-plating-282708.sap_integration_v3.export_archive`
  SET delivery_status='QUARANTINED_INVALID_PAYLOAD'
  WHERE export_run_id=p_export_run_id
    AND delivery_status='ARCHIVED_PENDING_OBJECT_METADATA';

  ASSERT @@row_count=v_ledger_rows AS 'not every archive ledger row was quarantined';
  COMMIT TRANSACTION;
END;

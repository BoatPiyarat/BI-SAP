-- Durable, structured evidence and atomic registration for a manually verified Unit 1 chain.
CREATE TABLE IF NOT EXISTS
  `pacific-plating-282708.sap_integration_v3.v3_manual_unit1_evidence` (
    pipeline_run_id STRING NOT NULL,extract_execution STRING NOT NULL,
    extract_run_uuid STRING NOT NULL,source_object_uri STRING NOT NULL,
    watermark_before TIMESTAMP NOT NULL,watermark_after TIMESTAMP NOT NULL,
    caught_up BOOL NOT NULL,extracted_rows INT64 NOT NULL,load_job_id STRING NOT NULL,
    load_output_rows INT64 NOT NULL,load_bad_records INT64 NOT NULL,load_input_files INT64 NOT NULL,
    mirror_doc_run_id STRING NOT NULL,mirror_state_run_id STRING NOT NULL,
    verified_by STRING NOT NULL,evidence_reference STRING NOT NULL,recorded_at TIMESTAMP NOT NULL
  )
CLUSTER BY pipeline_run_id;

CREATE OR REPLACE PROCEDURE
  `pacific-plating-282708.sap_integration_v3.sp_register_v3_manual_unit1`(
    p_pipeline_run_id STRING,p_extract_execution STRING,p_extract_run_uuid STRING,
    p_source_object_uri STRING,p_watermark_before TIMESTAMP,p_watermark_after TIMESTAMP,
    p_caught_up BOOL,p_extracted_rows INT64,p_load_job_id STRING,p_load_output_rows INT64,
    p_load_bad_records INT64,p_load_input_files INT64,p_mirror_doc_run_id STRING,
    p_mirror_state_run_id STRING,p_verified_by STRING,p_evidence_reference STRING)
BEGIN
  ASSERT NULLIF(TRIM(p_pipeline_run_id),'') IS NOT NULL AS 'pipeline_run_id is required';
  ASSERT NULLIF(TRIM(p_extract_execution),'') IS NOT NULL AS 'extract execution is required';
  ASSERT NULLIF(TRIM(p_extract_run_uuid),'') IS NOT NULL AS 'extract run UUID is required';
  ASSERT STARTS_WITH(p_source_object_uri,
    'gs://rcb-bronze-zone/SAP/production_database/Results') AS 'unexpected SAP source object';
  ASSERT p_watermark_after>p_watermark_before AS 'extract watermark did not advance';
  ASSERT p_caught_up IS TRUE AS 'extract did not prove caught_up';
  ASSERT p_extracted_rows>=0 AND p_load_output_rows=p_extracted_rows
    AS 'extract/load row conservation failed';
  ASSERT p_load_bad_records=0 AND p_load_input_files=1
    AS 'load must have zero bad records and exactly one input file';
  ASSERT NULLIF(TRIM(p_verified_by),'') IS NOT NULL
    AND NULLIF(TRIM(p_evidence_reference),'') IS NOT NULL AS 'manual verifier/evidence required';
  ASSERT (SELECT COUNT(*)
    FROM `pacific-plating-282708.region-asia-southeast1`.INFORMATION_SCHEMA.JOBS_BY_PROJECT
    WHERE job_id=p_load_job_id AND job_type='LOAD' AND state='DONE' AND error_result IS NULL
      AND destination_table=STRUCT('pacific-plating-282708' AS project_id,
        'sap_integration_v2' AS dataset_id,'SAP_LIVE' AS table_id))=1
    AS 'exact successful SAP_LIVE load job not found';
  ASSERT (SELECT COUNT(*) FROM `pacific-plating-282708.sap_integration_v3.pipeline_run_log`
    WHERE run_id=p_mirror_doc_run_id AND step='sap_mirror_doc_incremental'
      AND scope='ADHOC:manual-operator' AND status='SUCCESS'
      AND rows_out=p_load_output_rows)=1 AS 'exact mirror-doc evidence missing';
  ASSERT (SELECT COUNT(*) FROM `pacific-plating-282708.sap_integration_v3.pipeline_run_log`
    WHERE run_id=p_mirror_state_run_id AND step='sap_mirror_state'
      AND scope='ADHOC:manual-operator' AND status='SUCCESS')=1
    AS 'exact mirror-state evidence missing';

  CREATE TEMP TABLE _evidence AS
  SELECT p_pipeline_run_id AS pipeline_run_id,p_extract_execution AS extract_execution,
    p_extract_run_uuid AS extract_run_uuid,p_source_object_uri AS source_object_uri,
    p_watermark_before AS watermark_before,p_watermark_after AS watermark_after,
    p_caught_up AS caught_up,p_extracted_rows AS extracted_rows,p_load_job_id AS load_job_id,
    p_load_output_rows AS load_output_rows,p_load_bad_records AS load_bad_records,
    p_load_input_files AS load_input_files,p_mirror_doc_run_id AS mirror_doc_run_id,
    p_mirror_state_run_id AS mirror_state_run_id,p_verified_by AS verified_by,
    p_evidence_reference AS evidence_reference,CURRENT_TIMESTAMP() AS recorded_at;

  BEGIN TRANSACTION;
  MERGE `pacific-plating-282708.sap_integration_v3.v3_manual_unit1_evidence` target
  USING _evidence source
  ON target.pipeline_run_id=source.pipeline_run_id
    OR target.extract_execution=source.extract_execution OR target.load_job_id=source.load_job_id
  WHEN NOT MATCHED THEN INSERT ROW;
  ASSERT @@row_count=1 AS 'Unit 1 evidence/run/extract/load already registered';
  MERGE `pacific-plating-282708.sap_integration_v3.pipeline_run_log` target
  USING _evidence source ON target.run_id=source.pipeline_run_id
  WHEN NOT MATCHED THEN INSERT
    (run_id,run_type,step,scope,rows_in,rows_out,started_at,ended_at,status,error_message)
  VALUES (source.pipeline_run_id,'NIGHTLY','UNIT1_COMPLETE','NIGHTLY:manual-reviewed-fresh-sap',
    source.extracted_rows,source.load_output_rows,source.watermark_before,source.recorded_at,'SUCCESS',
    CONCAT('structured evidence: sap_integration_v3.v3_manual_unit1_evidence; extract=',
      source.extract_execution,'; load_job=',source.load_job_id));
  ASSERT @@row_count=1 AS 'pipeline run_id already registered';
  COMMIT TRANSACTION;
END;

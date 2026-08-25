-- One-time downstream V3 run approved by Boat after the manual SAP refresh.
-- Extract sap-extract-job-gkwt4 was a healthy zero: 0 rows, caught_up=True,
-- watermark 2026-08-25T22:15:39.479508Z. Unit 6 remains outside this script.
DECLARE v_run_id STRING DEFAULT 'V3NIGHTLY-2026-08-25T22:21:31-manual';

ASSERT (SELECT COUNT(*)
  FROM `pacific-plating-282708.sap_integration_v3.pipeline_run_log`
  WHERE run_id=v_run_id)=0 AS 'manual downstream run_id already exists';

CALL `pacific-plating-282708.sap_integration_v3.sp_refresh_sap_mirror_doc_incremental`(
  'NIGHTLY:manual-post-fresh-sap');
CALL `pacific-plating-282708.sap_integration_v3.sp_refresh_sap_mirror_state`(
  'NIGHTLY:manual-post-fresh-sap');

INSERT INTO `pacific-plating-282708.sap_integration_v3.pipeline_run_log`
  (run_id,run_type,step,scope,rows_in,rows_out,started_at,ended_at,status,error_message)
VALUES
  (v_run_id,'NIGHTLY','UNIT1_COMPLETE','NIGHTLY:manual-post-fresh-sap',NULL,NULL,
   CURRENT_TIMESTAMP(),CURRENT_TIMESTAMP(),'SUCCESS',
   'manual downstream continuation; extract=sap-extract-job-gkwt4; healthy-zero; caught_up=True; watermark=2026-08-25T22:15:39.479508Z; loader_not_required=true');

CALL `pacific-plating-282708.sap_integration_v3.sp_run_v3_units2_5`(v_run_id);

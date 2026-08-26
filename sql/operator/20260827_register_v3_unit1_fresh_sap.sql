-- Register the exact reviewed fresh SAP extract/load/mirror chain as Unit 1.
DECLARE v_run_id STRING DEFAULT 'V3NIGHTLY-2026-08-27T00:17:51-manual-fresh-sap';

ASSERT (SELECT COUNT(*)
  FROM `pacific-plating-282708.sap_integration_v3.pipeline_run_log`
  WHERE run_id=v_run_id)=0 AS 'fresh Unit 1 run_id already exists';
ASSERT (SELECT COUNT(*)
  FROM `pacific-plating-282708.sap_integration_v3.pipeline_run_log`
  WHERE run_id='e0261e71-0615-4685-ae6b-60f528965384'
    AND step='sap_mirror_doc_incremental' AND scope='ADHOC:manual-operator'
    AND status='SUCCESS' AND rows_out=4920
    AND ended_at=TIMESTAMP '2026-08-26 17:14:09+00')=1
  AS 'exact fresh mirror-doc refresh evidence missing';
ASSERT (SELECT COUNT(*)
  FROM `pacific-plating-282708.sap_integration_v3.pipeline_run_log`
  WHERE run_id='bd571c7f-5500-4145-8910-04dd93dbe032'
    AND step='sap_mirror_state' AND scope='ADHOC:manual-operator'
    AND status='SUCCESS' AND rows_out=1342203
    AND ended_at=TIMESTAMP '2026-08-26 17:14:33+00')=1
  AS 'exact fresh mirror-state refresh evidence missing';

INSERT INTO `pacific-plating-282708.sap_integration_v3.pipeline_run_log`
  (run_id,run_type,step,scope,rows_in,rows_out,started_at,ended_at,status,error_message)
VALUES (
  v_run_id,'NIGHTLY','UNIT1_COMPLETE','NIGHTLY:manual-reviewed-fresh-sap',4920,4920,
  TIMESTAMP '2026-08-26 17:12:07+00',TIMESTAMP '2026-08-26 17:17:51+00','SUCCESS',
  'extract=sap-extract-job-mgt5v; extract_uuid=285e4b37-5349-4f8e-8155-9d1e2ab034e5; source=Results2026_08_27_285e4b37.json; watermark_before=2026-08-26T14:21:49.546587Z; watermark_after=2026-08-26T17:12:07.041305Z; caught_up=true; load_job=f44aa0c8-bf8d-4823-9b7f-d57260aa668f; outputRows=4920; badRecords=0; inputFiles=1; mirror_doc_run=e0261e71-0615-4685-ae6b-60f528965384; mirror_state_run=bd571c7f-5500-4145-8910-04dd93dbe032'
);
ASSERT @@row_count=1 AS 'fresh Unit 1 registration failed';

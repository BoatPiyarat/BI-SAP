-- Register the exact manually verified extract/load/mirror chain as Unit 1.
CALL `pacific-plating-282708.sap_integration_v3.sp_register_v3_manual_unit1`(
  'V3NIGHTLY-2026-08-27T00:17:51-manual-fresh-sap',
  'sap-extract-job-mgt5v','285e4b37-5349-4f8e-8155-9d1e2ab034e5',
  'gs://rcb-bronze-zone/SAP/production_database/Results2026_08_27_285e4b37.json',
  TIMESTAMP '2026-08-26 14:21:49.546587+00',TIMESTAMP '2026-08-26 17:12:07.041305+00',
  TRUE,4920,'f44aa0c8-bf8d-4823-9b7f-d57260aa668f',4920,0,1,
  JSON '{"jobReference":{"jobId":"f44aa0c8-bf8d-4823-9b7f-d57260aa668f","projectId":"pacific-plating-282708","location":"asia-southeast1"},"configuration":{"jobType":"LOAD","load":{"destinationTable":{"projectId":"pacific-plating-282708","datasetId":"sap_integration_v2","tableId":"SAP_LIVE"}}},"statistics":{"startTime":"1787764343687","endTime":"1787764345571","load":{"outputRows":"4920","badRecords":"0","inputFiles":"1"}},"status":{"state":"DONE"}}',
  'e0261e71-0615-4685-ae6b-60f528965384','bd571c7f-5500-4145-8910-04dd93dbe032',
  'data@rabbit.co.th',
  'Cloud Run execution metadata+logs; BigQuery Job API; loader service logs; pipeline_run_log'
);

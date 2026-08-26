SELECT run_id,step,rows_out,started_at,ended_at,status
FROM `pacific-plating-282708.sap_integration_v3.pipeline_run_log`
WHERE run_id IN ('e0261e71-0615-4685-ae6b-60f528965384','bd571c7f-5500-4145-8910-04dd93dbe032')
ORDER BY started_at;

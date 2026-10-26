SELECT run_id,step,scope,rows_in,rows_out,started_at,ended_at,status,error_message
FROM `pacific-plating-282708.sap_integration_v3.pipeline_run_log`
WHERE ended_at>=TIMESTAMP '2026-08-26 17:12:00+00'
ORDER BY ended_at,step;

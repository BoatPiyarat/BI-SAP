SELECT job_id,creation_time,end_time,state,error_result,destination_table
FROM `pacific-plating-282708.region-asia-southeast1`.INFORMATION_SCHEMA.JOBS_BY_PROJECT
WHERE creation_time>=TIMESTAMP '2026-08-26 17:10:00+00'
  AND job_type='LOAD'
ORDER BY creation_time DESC;

-- L5 decisive R1 test: BigQuery jobs targeting SAP_LIVE during loader OOM storms.
-- INFORMATION_SCHEMA metadata only; no production mutation.
SELECT
  creation_time,
  end_time,
  job_id,
  job_type,
  statement_type,
  state,
  error_result.reason AS error_reason,
  error_result.message AS error_message,
  destination_table.project_id AS destination_project,
  destination_table.dataset_id AS destination_dataset,
  destination_table.table_id AS destination_table,
  dml_statistics.inserted_row_count AS inserted_row_count,
  (SELECT SUM(records_written) FROM UNNEST(job_stages)) AS stage_records_written,
  user_email
FROM `region-asia-southeast1`.INFORMATION_SCHEMA.JOBS_BY_PROJECT
WHERE creation_time >= TIMESTAMP '2026-07-27 00:00:00+00'
  AND creation_time < TIMESTAMP '2026-08-01 00:00:00+00'
  AND destination_table.project_id = 'pacific-plating-282708'
  AND destination_table.dataset_id = 'sap_integration_v2'
  AND destination_table.table_id = 'SAP_LIVE'
ORDER BY creation_time;

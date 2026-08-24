-- READ ONLY reviewer verification query (Claude Code, RQ-20260824-2306).
-- Attempts to identify the unattributed writer that set sap_period_state.updated_at
-- to 2026-08-24 11:16:31 UTC (August cutoff already at 09:00 UTC / state_version=3).
-- Metadata-only read of job history around that window. No mutation.
SELECT
  creation_time,
  user_email,
  job_id,
  statement_type,
  state,
  error_result.message AS error_message,
  query
FROM `region-asia-southeast1`.INFORMATION_SCHEMA.JOBS_BY_PROJECT
WHERE creation_time BETWEEN TIMESTAMP '2026-08-24 10:30:00 UTC' AND TIMESTAMP '2026-08-24 11:30:00 UTC'
  AND (
    REGEXP_CONTAINS(IFNULL(query, ''), r'(?i)sap_period_state|sap_period_lock')
    OR EXISTS (
      SELECT 1 FROM UNNEST(referenced_tables) t
      WHERE t.table_id IN ('sap_period_state', 'sap_period_lock')
    )
  )
ORDER BY creation_time;

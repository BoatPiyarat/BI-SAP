-- READ ONLY reviewer verification query (Claude Code, RQ-20260824-1756).
-- Independently reproduces the claimed live pre-state for the August cutoff correction.
SELECT
  'sap_period_state' AS src, period_id, period_start, period_end, status, closing_at,
  state_version, CAST(NULL AS TIMESTAMP) AS lock_datetime,
  CAST(NULL AS STRING) AS locked_by, CAST(NULL AS TIMESTAMP) AS locked_at
FROM `pacific-plating-282708.sap_integration_v3.sap_period_state`
WHERE period_start IN (DATE '2026-08-01', DATE '2026-09-01')
UNION ALL
SELECT
  'sap_period_lock', period, open_period_start, CAST(NULL AS DATE), CAST(NULL AS STRING),
  CAST(NULL AS TIMESTAMP), CAST(NULL AS INT64), lock_datetime, locked_by, locked_at
FROM `pacific-plating-282708.sap_integration_v3.sap_period_lock`
WHERE period='2026-08'
ORDER BY src;

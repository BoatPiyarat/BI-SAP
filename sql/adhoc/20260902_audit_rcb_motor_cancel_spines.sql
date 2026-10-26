-- Read-only red/green audit for sap_view.RCB_Motor_process_2_cancel_new.
-- Duplicate rows for the same period are allowed business events. A spine fails only when
-- its distinct integer periods are not exactly 1..TotalPeriods, TotalPeriods conflicts,
-- or Period/TotalPeriods is NULL or non-integer.

WITH item_spines AS (
  SELECT
    OrderItem,
    COUNT(*) AS row_count,
    COUNTIF(SAFE_CAST(Period AS INT64) IS NULL) AS invalid_period_rows,
    COUNTIF(SAFE_CAST(TotalPeriods AS INT64) IS NULL) AS invalid_total_period_rows,
    COUNT(DISTINCT SAFE_CAST(TotalPeriods AS INT64)) AS total_period_versions,
    MAX(SAFE_CAST(TotalPeriods AS INT64)) AS total_periods,
    MIN(SAFE_CAST(Period AS INT64)) AS min_period,
    MAX(SAFE_CAST(Period AS INT64)) AS max_period,
    COUNT(DISTINCT SAFE_CAST(Period AS INT64)) AS distinct_period_count,
    ARRAY_AGG(
      DISTINCT SAFE_CAST(Period AS INT64)
      IGNORE NULLS
      ORDER BY SAFE_CAST(Period AS INT64)
    ) AS distinct_periods
  FROM `pacific-plating-282708.sap_view.RCB_Motor_process_2_cancel_new`
  GROUP BY OrderItem
)

SELECT
  *,
  CASE
    WHEN invalid_period_rows > 0 THEN 'INVALID_PERIOD'
    WHEN invalid_total_period_rows > 0 THEN 'INVALID_TOTAL_PERIODS'
    WHEN total_period_versions != 1 THEN 'TOTAL_PERIODS_CONFLICT'
    WHEN min_period != 1 THEN 'MISSING_PERIOD_1'
    WHEN max_period != total_periods THEN 'MISSING_LAST_PERIOD'
    WHEN distinct_period_count != total_periods THEN 'PERIOD_GAP'
    ELSE 'PASS'
  END AS audit_result
FROM item_spines
WHERE invalid_period_rows > 0
   OR invalid_total_period_rows > 0
   OR total_period_versions != 1
   OR min_period != 1
   OR max_period != total_periods
   OR distinct_period_count != total_periods
ORDER BY OrderItem;

-- Read-only scope audit for every row the cancel root-fix would supplement.

WITH live_items AS (
  SELECT DISTINCT OrderItem
  FROM `pacific-plating-282708.sap_view.RCB_Motor_process_2_cancel_new`
),
sap_periods AS (
  SELECT DISTINCT sap.U_OrderItem AS OrderItem, sap.U_Period AS Period
  FROM `pacific-plating-282708.sap_integration_v2.SAP_LIVE_FULL` AS sap
  JOIN live_items
    ON live_items.OrderItem = sap.U_OrderItem
),
live_spines AS (
  SELECT
    OrderItem,
    COUNT(*) AS live_rows,
    COUNT(DISTINCT Period) AS live_distinct_periods,
    COUNT(DISTINCT TotalPeriods) AS live_total_versions,
    MAX(TotalPeriods) AS live_total_periods
  FROM `pacific-plating-282708.sap_view.RCB_Motor_process_2_cancel_new`
  GROUP BY OrderItem
),
installment_spines AS (
  SELECT
    installment.OrderItem,
    COUNTIF(SAFE_CAST(installment.Period AS INT64) IS NULL) AS invalid_period_rows,
    COUNTIF(SAFE_CAST(installment.TotalPeriods AS INT64) IS NULL) AS invalid_total_period_rows,
    COUNT(DISTINCT SAFE_CAST(installment.TotalPeriods AS INT64)) AS total_period_versions,
    MAX(SAFE_CAST(installment.TotalPeriods AS INT64)) AS total_periods,
    MIN(SAFE_CAST(installment.Period AS INT64)) AS min_period,
    MAX(SAFE_CAST(installment.Period AS INT64)) AS max_period,
    COUNT(DISTINCT SAFE_CAST(installment.Period AS INT64)) AS distinct_period_count
  FROM `pacific-plating-282708.sap_data_engineer.sap_dashboard_carepay_installment` AS installment
  JOIN live_items
    USING (OrderItem)
  GROUP BY installment.OrderItem
  HAVING invalid_period_rows = 0
    AND invalid_total_period_rows = 0
    AND total_period_versions = 1
    AND min_period = 1
    AND max_period = total_periods
    AND distinct_period_count = total_periods
),
supplement AS (
  SELECT installment.OrderItem, installment.Period, installment.TotalPeriods
  FROM `pacific-plating-282708.sap_data_engineer.sap_dashboard_carepay_installment` AS installment
  JOIN installment_spines
    USING (OrderItem)
  LEFT JOIN sap_periods
    ON sap_periods.OrderItem = installment.OrderItem
   AND sap_periods.Period = installment.Period
  WHERE sap_periods.OrderItem IS NULL
)

SELECT
  supplement.OrderItem,
  ANY_VALUE(live_spines.live_rows) AS live_rows,
  ANY_VALUE(live_spines.live_distinct_periods) AS live_distinct_periods,
  ANY_VALUE(live_spines.live_total_versions) AS live_total_versions,
  ANY_VALUE(live_spines.live_total_periods) AS live_total_periods,
  ANY_VALUE(supplement.TotalPeriods) AS schedule_total_periods,
  COUNT(*) AS supplemental_rows,
  COUNT(DISTINCT supplement.Period) AS supplemental_distinct_periods,
  ARRAY_AGG(DISTINCT supplement.Period ORDER BY supplement.Period) AS supplemental_periods
FROM supplement
JOIN live_spines
  USING (OrderItem)
GROUP BY supplement.OrderItem
ORDER BY supplement.OrderItem;

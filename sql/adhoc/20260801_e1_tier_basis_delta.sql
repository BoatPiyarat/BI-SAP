-- E1 review evidence: movement caused only by changing tier classification from the old
-- GREATEST(OrderDate, PolicyDate) basis to the locked OrderDate-only basis.
-- Grain: stg_schedule (order_item, period); read only.
WITH classified AS (
  SELECT
    s.order_item,
    s.period,
    CASE
      WHEN d.order_create_time IS NULL AND d.policy_start_date IS NULL THEN 'DATE_BASIS_MISSING'
      WHEN EXTRACT(YEAR FROM GREATEST(DATE(d.order_create_time), DATE(d.policy_start_date))) <= 2024
        THEN 'LE_2024'
      WHEN EXTRACT(YEAR FROM GREATEST(DATE(d.order_create_time), DATE(d.policy_start_date))) = 2025
        THEN 'YEAR_2025'
      ELSE 'GE_2026'
    END AS old_tier_by_greatest,
    CASE
      WHEN d.order_create_time IS NULL THEN 'ORDERDATE_MISSING'
      WHEN EXTRACT(YEAR FROM DATE(d.order_create_time)) <= 2024 THEN 'LE_2024'
      WHEN EXTRACT(YEAR FROM DATE(d.order_create_time)) = 2025 THEN 'YEAR_2025'
      ELSE 'GE_2026'
    END AS new_tier_by_orderdate
  FROM `pacific-plating-282708.sap_integration_v3.stg_schedule` s
  LEFT JOIN `pacific-plating-282708.sap_integration_v3.stg_order_dim` d USING (order_item)
)
SELECT
  old_tier_by_greatest,
  new_tier_by_orderdate,
  COUNT(*) AS records,
  COUNT(DISTINCT order_item) AS orders
FROM classified
WHERE old_tier_by_greatest != new_tier_by_orderdate
GROUP BY old_tier_by_greatest, new_tier_by_orderdate
ORDER BY old_tier_by_greatest, new_tier_by_orderdate;

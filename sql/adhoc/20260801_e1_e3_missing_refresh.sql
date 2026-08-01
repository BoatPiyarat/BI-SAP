-- Read-only impact measurement for the pre-deploy Class A review.
-- Grain: current delta_export rows at (order_item, period), restricted to MISSING_NO_ROW_IN_SAP,
-- then evaluated against the proposed E1-E3 rules. This does not CALL or mutate V3.
WITH successful_insurer_master AS (
  SELECT DISTINCT
    COALESCE(REGEXP_EXTRACT(TRIM(U_InsurerCode), r'/(.+)$'),
      REGEXP_EXTRACT(TRIM(U_InsurerCode), r'^[^-]+-(.+)$'), TRIM(U_InsurerCode)) AS insurer_code
  FROM `pacific-plating-282708.sap_integration_v2.SAP_LIVE_FULL`
  WHERE SAFE_CAST(DocEntry AS INT64) > 0
    AND NULLIF(TRIM(U_InsurerCode), '') IS NOT NULL
),
sap_order_items AS (
  SELECT DISTINCT U_OrderItem AS order_item
  FROM `pacific-plating-282708.sap_integration_v3.sap_mirror_state`
),
missing AS (
  SELECT
    x.order_item, x.order_id, x.period, x.flow,
    DATE(d.order_create_time) AS order_date,
    GREATEST(DATE(d.order_create_time), DATE(d.policy_start_date)) AS processing_date_basis,
    (IFNULL(oi.is_cancelled, FALSE) OR oi.cancel_time IS NOT NULL) AS is_cancelled_effective,
    soi.order_item IS NOT NULL AS already_in_sap,
    LOWER(TRIM(d.first_name)) IN ('test', 'test div')
      OR LOWER(TRIM(d.last_name)) IN ('test', 'test div') AS is_test_customer,
    COALESCE(REGEXP_EXTRACT(TRIM(d.insurer_code), r'/(.+)$'),
      REGEXP_EXTRACT(TRIM(d.insurer_code), r'^[^-]+-(.+)$'), TRIM(d.insurer_code)) AS insurer_code_plain,
    d.insured_id
  FROM `pacific-plating-282708.sap_integration_v3.delta_export` x
  LEFT JOIN `pacific-plating-282708.sap_integration_v3.stg_order_dim` d USING (order_item)
  LEFT JOIN `pacific-plating-282708.careos.careos_order_items` oi ON oi.human_id = x.order_item
  LEFT JOIN sap_order_items soi USING (order_item)
  WHERE x.delta_type = 'MISSING_NO_ROW_IN_SAP'
),
classified AS (
  SELECT m.*,
    CASE
      WHEN order_date IS NULL THEN 'DATE_BASIS_MISSING'
      WHEN EXTRACT(YEAR FROM order_date) <= 2024 THEN 'YEAR_OUT_OF_SCOPE'
      WHEN EXTRACT(YEAR FROM order_date) = 2025
        AND NOT (already_in_sap AND is_cancelled_effective) THEN 'YEAR_2025_NON_CANCEL_EXCLUDED'
      WHEN is_test_customer THEN 'TEST_CUSTOMER'
      WHEN NOT EXISTS (
        SELECT 1 FROM successful_insurer_master s WHERE s.insurer_code = m.insurer_code_plain
      ) THEN 'INSURER_NOT_IN_MASTER'
      ELSE NULL
    END AS first_exclusion_rule
  FROM missing m
)
SELECT
  IF(first_exclusion_rule IS NULL AND processing_date_basis IS NOT NULL,
    'RETAINED_MISSING_NO_ROW_IN_SAP', IFNULL(first_exclusion_rule, 'DATE_BASIS_MISSING')) AS classification,
  COUNT(*) AS records,
  COUNT(DISTINCT order_item) AS orders,
  COUNT(DISTINCT insurer_code_plain) AS distinct_insurer_codes,
  COUNTIF(NULLIF(TRIM(insured_id), '') IS NULL) AS f1_source_rows_needing_default,
  ARRAY_AGG(DISTINCT IF(NULLIF(TRIM(insured_id), '') IS NULL, flow, NULL) IGNORE NULLS
    ORDER BY IF(NULLIF(TRIM(insured_id), '') IS NULL, flow, NULL)) AS f1_flows_needing_default
FROM classified
GROUP BY classification
ORDER BY classification;

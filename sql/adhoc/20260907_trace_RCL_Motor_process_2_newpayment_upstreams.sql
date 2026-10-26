-- Read-only root-cause trace for incomplete spines and NonMotor leakage in:
--   pacific-plating-282708.sap_view.RCL_Motor_process_2_newpayment

WITH
output AS (
  SELECT
    OrderID,
    OrderItem,
    InsuranceGroup,
    InsuranceType,
    SAFE_CAST(Period AS INT64) AS Period,
    SAFE_CAST(TotalPeriods AS INT64) AS TotalPeriods
  FROM `pacific-plating-282708.sap_view.RCL_Motor_process_2_newpayment`
),

gate_items AS (
  SELECT DISTINCT order_item AS OrderItem
  FROM `pacific-plating-282708.sap_integration_v2.RCL 05_paid by period`
),

paid_source AS (
  SELECT DISTINCT
    OrderItem,
    SAFE_CAST(Period AS INT64) AS Period
  FROM `pacific-plating-282708.sap_integration_v2.RCL 05_paid`
),

new_source AS (
  SELECT DISTINCT
    OrderItem,
    SAFE_CAST(Period AS INT64) AS Period
  FROM `pacific-plating-282708.sap_integration_v2.RCL 05_newpayment`
),

item_spines AS (
  SELECT
    OrderItem,
    ANY_VALUE(OrderID) AS OrderID,
    ANY_VALUE(InsuranceGroup) AS InsuranceGroup,
    ANY_VALUE(InsuranceType) AS InsuranceType,
    MIN(Period) AS min_period,
    MAX(Period) AS max_period,
    MAX(TotalPeriods) AS total_periods,
    COUNT(DISTINCT Period) AS distinct_periods,
    COUNT(DISTINCT TotalPeriods) AS total_period_versions
  FROM output
  GROUP BY OrderItem
),

incomplete_items AS (
  SELECT *
  FROM item_spines
  WHERE min_period != 1
     OR max_period != total_periods
     OR distinct_periods != total_periods
     OR total_period_versions != 1
),

expected_periods AS (
  SELECT
    i.OrderID,
    i.OrderItem,
    i.InsuranceGroup,
    i.InsuranceType,
    expected_period AS Period
  FROM incomplete_items i,
  UNNEST(GENERATE_ARRAY(1, i.total_periods)) AS expected_period
),

missing_periods AS (
  SELECT e.*
  FROM expected_periods e
  LEFT JOIN output o USING (OrderItem, Period)
  WHERE o.OrderItem IS NULL
),

sap_periods AS (
  SELECT
    U_OrderItem AS OrderItem,
    SAFE_CAST(U_Period AS INT64) AS Period,
    LOGICAL_OR(TransactionStatus IN ('Paid', 'paid')) AS has_paid_status,
    LOGICAL_OR(PaymentChannel LIKE '%RCL%') AS has_rcl_channel,
    ARRAY_AGG(DISTINCT PaymentChannel IGNORE NULLS LIMIT 10) AS payment_channels,
    ARRAY_AGG(DISTINCT TransactionStatus IGNORE NULLS LIMIT 10) AS transaction_statuses
  FROM `pacific-plating-282708.sap_integration_v2.SAP_LIVE_FULL`
  JOIN gate_items ON gate_items.OrderItem = U_OrderItem
  WHERE SAFE_CAST(U_Period AS INT64) IS NOT NULL
  GROUP BY OrderItem, Period
),

missing_classified AS (
  SELECT
    m.*,
    p.OrderItem IS NOT NULL AS in_paid_source,
    n.OrderItem IS NOT NULL AS in_new_source,
    s.OrderItem IS NOT NULL AS in_sap,
    COALESCE(s.has_paid_status, FALSE) AS sap_has_paid_status,
    COALESCE(s.has_rcl_channel, FALSE) AS sap_has_rcl_channel,
    s.payment_channels,
    s.transaction_statuses,
    CASE
      WHEN p.OrderItem IS NOT NULL OR n.OrderItem IS NOT NULL
        THEN 'WRAPPER_DROPPED_AVAILABLE_UPSTREAM'
      WHEN s.has_paid_status AND NOT s.has_rcl_channel
        THEN 'SAP_PAID_NON_RCL_CHANNEL_EXCLUDED_FROM_PAID_SOURCE'
      WHEN s.has_paid_status AND s.has_rcl_channel
        THEN 'SAP_PAID_RCL_ROW_EXCLUDED_BY_OTHER_PAID_SOURCE_GATE'
      WHEN s.OrderItem IS NOT NULL
        THEN 'SAP_PRESENT_NOT_PAID_AND_ABSENT_FROM_CURRENT_SCHEDULE'
      ELSE 'ABSENT_FROM_SAP_AND_CURRENT_SCHEDULE'
    END AS root_category
  FROM missing_periods m
  LEFT JOIN paid_source p USING (OrderItem, Period)
  LEFT JOIN new_source n USING (OrderItem, Period)
  LEFT JOIN sap_periods s USING (OrderItem, Period)
),

category_counts AS (
  SELECT root_category, COUNT(*) AS missing_periods, COUNT(DISTINCT OrderItem) AS items
  FROM missing_classified
  GROUP BY root_category
),

shape_counts AS (
  SELECT
    o.InsuranceGroup,
    o.InsuranceType,
    COUNT(*) AS output_rows,
    COUNT(DISTINCT OrderItem) AS items,
    COUNT(DISTINCT IF(i.OrderItem IS NOT NULL, OrderItem, NULL)) AS incomplete_items
  FROM output o
  LEFT JOIN incomplete_items i USING (OrderItem)
  GROUP BY o.InsuranceGroup, o.InsuranceType
)

SELECT
  (SELECT COUNT(*) FROM gate_items) AS gate_items,
  (SELECT COUNT(DISTINCT OrderItem) FROM output) AS output_items,
  (SELECT COUNT(*) FROM incomplete_items) AS incomplete_items,
  (SELECT COUNT(*) FROM missing_periods) AS missing_periods,
  (SELECT COUNTIF(InsuranceGroup != 'Motor') FROM output) AS nonmotor_output_rows,
  (SELECT COUNT(DISTINCT IF(InsuranceGroup != 'Motor', OrderItem, NULL)) FROM output) AS nonmotor_output_items,
  ARRAY(SELECT AS STRUCT * FROM category_counts ORDER BY missing_periods DESC) AS missing_root_categories,
  ARRAY(SELECT AS STRUCT * FROM shape_counts ORDER BY InsuranceGroup, InsuranceType) AS output_shapes,
  ARRAY(
    SELECT AS STRUCT
      OrderID, OrderItem, InsuranceGroup, InsuranceType, Period, root_category,
      in_sap, sap_has_paid_status, sap_has_rcl_channel, payment_channels, transaction_statuses
    FROM missing_classified
    ORDER BY root_category, OrderItem, Period
    LIMIT 50
  ) AS missing_samples
;

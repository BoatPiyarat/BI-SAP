WITH population AS (
  SELECT
    e.order_item,
    e.order_id,
    e.period,
    e.charge_amount,
    CASE
      WHEN e.expected_payment_date >= DATE '2026-07-01'
       AND e.expected_payment_date < DATE '2026-08-01'
       AND s.U_OrderItem IS NULL THEN 'A'
      WHEN e.expected_payment_date >= DATE '2026-07-01'
       AND e.expected_payment_date < DATE '2026-08-01'
       AND s.U_OrderItem IS NOT NULL
       AND LOWER(IFNULL(s.TransactionStatus, '')) = 'pending' THEN 'D'
    END AS population_group
  FROM `pacific-plating-282708.sap_integration_v3.expected_state` e
  LEFT JOIN `pacific-plating-282708.sap_integration_v3.sap_mirror_state` s
    ON s.U_OrderItem = e.order_item
   AND s.U_Period = e.period
  WHERE e.expected_status = 'Paid'
    AND e.expected_payment_date >= DATE '2026-07-01'
    AND e.expected_payment_date < DATE '2026-08-01'
),
view_keys AS (
  SELECT DISTINCT 'RCB_Motor_process_create' AS view_name, OrderItem AS order_item, Period AS period
  FROM `pacific-plating-282708.sap_view.RCB_Motor_process_create`
  UNION ALL
  SELECT DISTINCT 'RCB_NonMotor_process_1_create', OrderItem, Period
  FROM `pacific-plating-282708.sap_view.RCB_NonMotor_process_1_create`
  UNION ALL
  SELECT DISTINCT 'RCL_Motor_process_1_create', OrderItem, Period
  FROM `pacific-plating-282708.sap_view.RCL_Motor_process_1_create`
  UNION ALL
  SELECT DISTINCT 'RCL_NonMotor_process_1_create', OrderItem, Period
  FROM `pacific-plating-282708.sap_view.RCL_NonMotor_process_1_create`
  UNION ALL
  SELECT DISTINCT 'RCL_Motor_process_2_newpayment', OrderItem, Period
  FROM `pacific-plating-282708.sap_view.RCL_Motor_process_2_newpayment`
  UNION ALL
  SELECT DISTINCT 'RCL_NonMotor_process_2_newpayment', OrderItem, Period
  FROM `pacific-plating-282708.sap_view.RCL_NonMotor_process_2_newpayment`
),
relevant AS (
  SELECT
    p.*,
    v.view_name
  FROM population p
  LEFT JOIN view_keys v
    ON v.order_item = p.order_item
   AND v.period = p.period
   AND (
     (p.population_group = 'A' AND v.view_name IN (
       'RCB_Motor_process_create', 'RCB_NonMotor_process_1_create',
       'RCL_Motor_process_1_create', 'RCL_NonMotor_process_1_create'
     ))
     OR (p.population_group = 'D' AND v.view_name IN (
       'RCL_Motor_process_2_newpayment', 'RCL_NonMotor_process_2_newpayment'
     ))
   )
  WHERE p.population_group IS NOT NULL
),
summary AS (
  SELECT
    population_group,
    'ANY_RELEVANT_VIEW' AS view_name,
    COUNT(DISTINCT FORMAT('%s|%d', order_item, period)) AS population_records,
    COUNT(DISTINCT order_id) AS population_orders,
    COUNT(DISTINCT IF(view_name IS NOT NULL, FORMAT('%s|%d', order_item, period), NULL)) AS in_view_records,
    COUNT(DISTINCT IF(view_name IS NULL, FORMAT('%s|%d', order_item, period), NULL)) AS not_in_view_records,
    COUNT(DISTINCT IF(view_name IS NOT NULL, order_id, NULL)) AS in_view_orders,
    COUNT(DISTINCT IF(view_name IS NULL, order_id, NULL)) AS not_in_view_orders,
    ROUND(SUM(IF(view_name IS NULL,
      SAFE_DIVIDE(CAST(charge_amount AS NUMERIC), 100), NULL)), 2) AS not_in_view_amount_thb
  FROM relevant
  GROUP BY population_group
),
per_view AS (
  SELECT
    population_group,
    view_name,
    CAST(NULL AS INT64) AS population_records,
    CAST(NULL AS INT64) AS population_orders,
    COUNT(DISTINCT FORMAT('%s|%d', order_item, period)) AS in_view_records,
    CAST(NULL AS INT64) AS not_in_view_records,
    COUNT(DISTINCT order_id) AS in_view_orders,
    CAST(NULL AS INT64) AS not_in_view_orders,
    CAST(NULL AS NUMERIC) AS not_in_view_amount_thb
  FROM relevant
  WHERE view_name IS NOT NULL
  GROUP BY population_group, view_name
)
SELECT CURRENT_TIMESTAMP() AS query_timestamp, * FROM summary
UNION ALL
SELECT CURRENT_TIMESTAMP(), * FROM per_view
ORDER BY population_group, view_name;

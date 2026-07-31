WITH rule_catalog AS (
  SELECT * FROM UNNEST([
    STRUCT('OLD_YEAR_NO_TOUCH' AS rule_code, TRUE AS hard_exclusion),
    ('TEST_CUSTOMER_NAME', TRUE),
    ('TEST_CUSTOMER_PHONE', FALSE),
    ('INSURER_NOT_IN_MASTER', TRUE),
    ('DATE_BASIS_MISSING', TRUE),
    ('NO_NEW_PAID_2025', TRUE),
    ('CANCEL_2025_NOT_IN_SAP', TRUE)
  ])
),
payment_events_dedup AS (
  SELECT * EXCEPT(rn)
  FROM (
    SELECT
      order_item,
      order_id,
      period,
      amount,
      charge_time,
      ROW_NUMBER() OVER (
        PARTITION BY order_item, period ORDER BY charge_time ASC
      ) AS rn
    FROM `pacific-plating-282708.sap_integration_v3.stg_payment_events`
  )
  WHERE rn = 1
),
order_txn_any_paid AS (
  SELECT DISTINCT
    s.transaction_id,
    FIRST_VALUE(c.update_time) OVER (
      PARTITION BY s.transaction_id ORDER BY c.update_time ASC
    ) AS first_charge_time
  FROM `pacific-plating-282708.sap_integration_v3.stg_schedule` s
  JOIN `pacific-plating-282708.careos.carepay_charges` c
    ON c.transaction_id = s.transaction_id
   AND c.status = 'SUCCESSFUL'
  WHERE s.motor_item_type = 'MOTOR_TYPE_COMPULSORY'
),
pre_exclusion AS (
  SELECT
    s.order_item,
    s.order_id,
    s.period,
    CASE
      WHEN s.motor_item_type = 'MOTOR_TYPE_COMPULSORY' THEN DATE(otp.first_charge_time)
      ELSE DATE(pe.charge_time)
    END AS payment_date,
    pe.amount AS amount_satang,
    CASE
      WHEN d.order_create_time IS NULL AND d.policy_start_date IS NULL THEN NULL
      WHEN d.order_create_time IS NULL THEN DATE(d.policy_start_date)
      WHEN d.policy_start_date IS NULL THEN DATE(d.order_create_time)
      ELSE GREATEST(DATE(d.order_create_time), DATE(d.policy_start_date))
    END AS date_basis,
    REGEXP_EXTRACT(d.insurer_code, r'/(.+)$') AS insurer_code_plain
  FROM `pacific-plating-282708.sap_integration_v3.stg_schedule` s
  LEFT JOIN payment_events_dedup pe
    ON pe.order_item = s.order_item AND pe.period = s.period
  LEFT JOIN order_txn_any_paid otp
    ON s.motor_item_type = 'MOTOR_TYPE_COMPULSORY'
   AND otp.transaction_id = s.transaction_id
  LEFT JOIN `pacific-plating-282708.sap_integration_v3.stg_order_dim` d
    ON d.order_item = s.order_item
),
excluded AS (
  SELECT
    x.rule_code,
    x.order_item,
    x.period,
    p.order_id,
    p.payment_date,
    p.amount_satang,
    p.date_basis,
    p.insurer_code_plain
  FROM `pacific-plating-282708.sap_integration_v3.sap_excluded_records` x
  LEFT JOIN pre_exclusion p USING (order_item, period)
),
july_excluded AS (
  SELECT *
  FROM excluded
  WHERE payment_date >= DATE '2026-07-01'
    AND payment_date < DATE '2026-08-01'
),
abc AS (
  SELECT
    e.order_item,
    e.order_id,
    e.period,
    CASE
      WHEN e.expected_payment_date >= DATE '2026-07-01'
       AND e.expected_payment_date < DATE '2026-08-01'
       AND s.U_OrderItem IS NULL THEN 'A'
      WHEN e.expected_payment_date < DATE '2026-07-01'
       AND (s.U_OrderItem IS NULL OR (
         LOWER(IFNULL(s.TransactionStatus, '')) != 'paid'
         AND NOT STARTS_WITH(LOWER(IFNULL(s.TransactionStatus, '')), 'cancelled')
       )) THEN 'C'
      WHEN e.expected_payment_date >= DATE '2026-07-01'
       AND e.expected_payment_date < DATE '2026-08-01'
       AND s.U_OrderItem IS NOT NULL
       AND LOWER(IFNULL(s.TransactionStatus, '')) = 'pending' THEN 'D'
    END AS segment
  FROM `pacific-plating-282708.sap_integration_v3.expected_state` e
  LEFT JOIN `pacific-plating-282708.sap_integration_v3.sap_mirror_state` s
    ON s.U_OrderItem = e.order_item AND s.U_Period = e.period
  WHERE e.expected_status = 'Paid'
    AND e.expected_payment_date IS NOT NULL
),
output AS (
  SELECT
    'A_ALL_REGISTER' AS section,
    c.rule_code,
    c.hard_exclusion,
    COUNT(x.order_item) AS records,
    COUNT(DISTINCT x.order_id) AS orders,
    CAST(NULL AS NUMERIC) AS amount_thb,
    CAST(NULL AS STRING) AS detail
  FROM rule_catalog c
  LEFT JOIN excluded x USING (rule_code)
  GROUP BY c.rule_code, c.hard_exclusion

  UNION ALL
  SELECT
    'B_JULY_PAYMENT_DATE',
    c.rule_code,
    c.hard_exclusion,
    COUNT(j.order_item),
    COUNT(DISTINCT j.order_id),
    ROUND(SUM(SAFE_DIVIDE(CAST(j.amount_satang AS NUMERIC), 100)), 2),
    CONCAT('amount_null_records=', CAST(COUNTIF(j.order_item IS NOT NULL AND j.amount_satang IS NULL) AS STRING))
  FROM rule_catalog c
  LEFT JOIN july_excluded j USING (rule_code)
  GROUP BY c.rule_code, c.hard_exclusion

  UNION ALL
  SELECT
    'C_DATE_BASIS_STRADDLE',
    'OLD_YEAR_NO_TOUCH',
    TRUE,
    COUNT(*),
    COUNT(DISTINCT order_id),
    ROUND(SUM(SAFE_DIVIDE(CAST(amount_satang AS NUMERIC), 100)), 2),
    CONCAT('amount_null_records=', CAST(COUNTIF(amount_satang IS NULL) AS STRING))
  FROM july_excluded
  WHERE rule_code = 'OLD_YEAR_NO_TOUCH'
    AND EXTRACT(YEAR FROM date_basis) <= (
      SELECT CAST(ANY_VALUE(config_value) AS INT64)
      FROM `pacific-plating-282708.sap_integration_v3.sap_config`
      WHERE config_key = 'year_no_touch_max'
    )

  UNION ALL
  SELECT
    'D_INSURER_CODE',
    'INSURER_NOT_IN_MASTER',
    TRUE,
    COUNT(*),
    COUNT(DISTINCT order_id),
    ROUND(SUM(SAFE_DIVIDE(CAST(amount_satang AS NUMERIC), 100)), 2),
    insurer_code_plain
  FROM july_excluded
  WHERE rule_code = 'INSURER_NOT_IN_MASTER'
  GROUP BY insurer_code_plain

  UNION ALL
  SELECT
    'E_CONFIG',
    'year_no_touch_max',
    CAST(NULL AS BOOL),
    CAST(NULL AS INT64),
    CAST(NULL AS INT64),
    CAST(NULL AS NUMERIC),
    ANY_VALUE(config_value)
  FROM `pacific-plating-282708.sap_integration_v3.sap_config`
  WHERE config_key = 'year_no_touch_max'

  UNION ALL
  SELECT
    'F_ABC_UNIQUE_ORDERS',
    'A+C+D',
    CAST(NULL AS BOOL),
    COUNT(*),
    COUNT(DISTINCT order_id),
    CAST(NULL AS NUMERIC),
    'records column is A+C+D records; orders column is exact union distinct order_id'
  FROM abc
  WHERE segment IS NOT NULL
)
SELECT CURRENT_TIMESTAMP() AS query_timestamp, *
FROM output
ORDER BY section, rule_code, detail;

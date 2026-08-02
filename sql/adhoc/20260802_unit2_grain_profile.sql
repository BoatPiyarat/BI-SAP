-- Read-only Unit 2 grain/coverage profile. Dry-run before every execution.
WITH metrics AS (
  SELECT 'expected_rows' metric, COUNT(*) n,
    COUNT(DISTINCT TO_JSON_STRING(STRUCT(order_item, period, charge_id, expected_invoice_no))) d
  FROM `pacific-plating-282708.sap_integration_v3.expected_state`
  UNION ALL
  SELECT 'expected_schedule_keys', COUNT(*),
    COUNT(DISTINCT TO_JSON_STRING(STRUCT(order_item, period)))
  FROM `pacific-plating-282708.sap_integration_v3.expected_state`
  UNION ALL
  SELECT 'payment_event_rows', COUNT(*),
    COUNT(DISTINCT TO_JSON_STRING(STRUCT(order_item, period, charge_id)))
  FROM `pacific-plating-282708.sap_integration_v3.stg_payment_events`
  UNION ALL
  SELECT 'schedule_rows', COUNT(*),
    COUNT(DISTINCT TO_JSON_STRING(STRUCT(order_item, period)))
  FROM `pacific-plating-282708.sap_integration_v3.stg_schedule`
  UNION ALL
  SELECT 'mirror_state_rows', COUNT(*),
    COUNT(DISTINCT TO_JSON_STRING(STRUCT(U_OrderItem, U_Period)))
  FROM `pacific-plating-282708.sap_integration_v3.sap_mirror_state`
  UNION ALL
  SELECT 'excluded_rows', COUNT(*),
    COUNT(DISTINCT TO_JSON_STRING(STRUCT(order_item, period)))
  FROM `pacific-plating-282708.sap_integration_v3.sap_excluded_records`
  UNION ALL
  SELECT 'validation_rows', COUNT(*),
    COUNT(DISTINCT TO_JSON_STRING(STRUCT(order_item, period)))
  FROM `pacific-plating-282708.sap_integration_v3.sap_validation_error`
  UNION ALL
  SELECT 'archive_rows', COUNT(*),
    COUNT(DISTINCT TO_JSON_STRING(STRUCT(order_item, period, charge_id)))
  FROM `pacific-plating-282708.sap_integration_v3.export_archive`
  UNION ALL
  SELECT 'import_result_rows', COUNT(*), COUNT(DISTINCT order_item)
  FROM `pacific-plating-282708.sap_integration_v3.sap_import_result`
),
coverage AS (
  SELECT
    COUNT(*) expected_rows,
    COUNTIF(p.charge_id IS NOT NULL) payment_event_joined,
    COUNTIF(s.U_OrderItem IS NOT NULL) sap_joined,
    COUNTIF(x.order_item IS NOT NULL) excluded_joined,
    COUNTIF(v.order_item IS NOT NULL) validation_joined,
    COUNTIF(a.order_item IS NOT NULL) archive_joined
  FROM `pacific-plating-282708.sap_integration_v3.expected_state` e
  LEFT JOIN `pacific-plating-282708.sap_integration_v3.stg_payment_events` p
    USING (order_item, period, charge_id)
  LEFT JOIN `pacific-plating-282708.sap_integration_v3.sap_mirror_state` s
    ON s.U_OrderItem = e.order_item AND s.U_Period = e.period
  LEFT JOIN (
    SELECT DISTINCT order_item, period
    FROM `pacific-plating-282708.sap_integration_v3.sap_excluded_records`
  ) x USING (order_item, period)
  LEFT JOIN (
    SELECT DISTINCT order_item, period
    FROM `pacific-plating-282708.sap_integration_v3.sap_validation_error`
  ) v USING (order_item, period)
  LEFT JOIN (
    SELECT DISTINCT order_item, period, charge_id
    FROM `pacific-plating-282708.sap_integration_v3.export_archive`
  ) a USING (order_item, period, charge_id)
)
SELECT metric, n, d,
  CAST(NULL AS INT64) expected_rows,
  CAST(NULL AS INT64) payment_event_joined,
  CAST(NULL AS INT64) sap_joined,
  CAST(NULL AS INT64) excluded_joined,
  CAST(NULL AS INT64) validation_joined,
  CAST(NULL AS INT64) archive_joined
FROM metrics
UNION ALL
SELECT 'coverage', NULL, NULL, * FROM coverage;

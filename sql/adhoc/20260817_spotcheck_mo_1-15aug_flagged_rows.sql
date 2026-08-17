-- Read-only follow-up for TASK_1_15AUG_MISSING_INTERFACE_20260817 Phase 1.
-- Separately checks the one annotated systematic row and the six non-standard -M1 sheet rows.

WITH targets AS (
  SELECT 'L80416399' AS order_item, 1 AS reported_period, 'ANNOTATED_SYSTEMATIC' AS target_type
  UNION ALL SELECT 'L80544270-M1', NULL, 'NON_STANDARD_M1'
  UNION ALL SELECT 'L80519533-M1', NULL, 'NON_STANDARD_M1'
  UNION ALL SELECT 'L80489663-M1', NULL, 'NON_STANDARD_M1'
  UNION ALL SELECT 'L80541540-M1', NULL, 'NON_STANDARD_M1'
  UNION ALL SELECT 'L80498125-M1', NULL, 'NON_STANDARD_M1'
),
expected AS (
  SELECT order_item,
    COUNT(*) AS expected_rows,
    STRING_AGG(DISTINCT flow, ',' ORDER BY flow) AS expected_flows,
    STRING_AGG(DISTINCT CAST(period AS STRING), ',' ORDER BY CAST(period AS STRING)) AS expected_periods
  FROM `pacific-plating-282708.sap_integration_v3.expected_state`
  WHERE order_item IN (SELECT order_item FROM targets)
  GROUP BY order_item
),
sap AS (
  SELECT U_OrderItem AS order_item,
    COUNT(*) AS sap_rows,
    COUNTIF(NULLIF(TRIM(U_InvoiceNo), '') IS NOT NULL) AS sap_real_invoice_rows,
    STRING_AGG(DISTINCT CAST(U_Period AS STRING), ',' ORDER BY CAST(U_Period AS STRING)) AS sap_periods,
    STRING_AGG(DISTINCT TransactionStatus, ',' ORDER BY TransactionStatus) AS sap_statuses
  FROM `pacific-plating-282708.sap_integration_v3.stg_sap_state`
  WHERE U_OrderItem IN (SELECT order_item FROM targets)
  GROUP BY U_OrderItem
),
recon AS (
  SELECT order_item, COUNT(*) AS recon_rows,
    STRING_AGG(DISTINCT CAST(period AS STRING), ',' ORDER BY CAST(period AS STRING)) AS recon_periods,
    STRING_AGG(DISTINCT recon_status, ',' ORDER BY recon_status) AS recon_statuses
  FROM `pacific-plating-282708.sap_integration_v3.recon_careos_charges`
  WHERE order_item IN (SELECT order_item FROM targets)
  GROUP BY order_item
),
excluded AS (
  SELECT order_item, COUNT(*) AS excluded_rows,
    STRING_AGG(DISTINCT rule_code, ',' ORDER BY rule_code) AS excluded_rules
  FROM `pacific-plating-282708.sap_integration_v3.sap_excluded_records`
  WHERE order_item IN (SELECT order_item FROM targets)
  GROUP BY order_item
),
validation AS (
  SELECT order_item, COUNT(*) AS validation_rows,
    STRING_AGG(DISTINCT check_name, ',' ORDER BY check_name) AS validation_checks
  FROM `pacific-plating-282708.sap_integration_v3.sap_validation_error`
  WHERE order_item IN (SELECT order_item FROM targets)
  GROUP BY order_item
)
SELECT t.*,
  IFNULL(e.expected_rows, 0) AS expected_rows, e.expected_flows, e.expected_periods,
  IFNULL(s.sap_rows, 0) AS sap_rows, IFNULL(s.sap_real_invoice_rows, 0) AS sap_real_invoice_rows,
  s.sap_periods, s.sap_statuses,
  IFNULL(r.recon_rows, 0) AS recon_rows, r.recon_periods, r.recon_statuses,
  IFNULL(x.excluded_rows, 0) AS excluded_rows, x.excluded_rules,
  IFNULL(v.validation_rows, 0) AS validation_rows, v.validation_checks
FROM targets t
LEFT JOIN expected e USING (order_item)
LEFT JOIN sap s USING (order_item)
LEFT JOIN recon r USING (order_item)
LEFT JOIN excluded x USING (order_item)
LEFT JOIN validation v USING (order_item)
ORDER BY target_type, order_item;

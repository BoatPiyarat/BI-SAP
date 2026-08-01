-- 035_policyno_too_long_validation.sql
-- KNOWLEDGE_ADDENDUM_20260729 v2, item F2: PolicyNo > 50 chars = BLOCK (never truncate).
-- V3-native validation only. Contract-shaped F2/F3 checks run in 048 against july_export_ready;
-- do not couple this procedure to drift-prone legacy sap_view.* objects. Full CREATE OR REPLACE
-- PROCEDURE, same convention as
-- 034: each versioned file carries the complete procedure body, not a diff, since BigQuery routines
-- have no ALTER PROCEDURE ADD CHECK equivalent.
--
-- Verified read-only 2026-07-29 against the current (post-034) expected_state: 28 rows / 11
-- distinct order_items have policy_no > 50 chars. All 3 sampled examples are the same data-quality
-- pattern - upstream is storing an operational status note (Thai text: "แจ้งงานแล้ว/ต่ออายุ/..."
-- - roughly "notified/renewal/...") concatenated in front of or instead of a real policy number,
-- not a genuinely long policy number. Per Boat's rule: BLOCK, do not truncate - truncating a
-- string like this would produce a corrupted, semantically wrong PolicyNo in SAP, worse than
-- blocking it for manual review.
--
-- Source of policy_no: stg_order_dim.policy_no (added in 033, from careos_order_items.policy_number
-- verbatim, no transformation) - the same field F1's InsuredID fix and E1's date-basis logic
-- already rely on, so this check joins expected_state -> stg_order_dim exactly like PK_DUP/
-- SCHEDULE_GAP operate directly on expected_state (no additional not-in-SAP restriction - unlike
-- MASTER_INSURER_UNKNOWN/MASTER_PAYMENTDATE_LOCKED, a too-long PolicyNo is a formatting problem
-- that blocks a row regardless of whether SAP has seen this order_item before).

CREATE OR REPLACE PROCEDURE `pacific-plating-282708.sap_integration_v3.sp_run_validation`()
BEGIN
  CREATE OR REPLACE TABLE `pacific-plating-282708.sap_integration_v3.sap_validation_error`
  CLUSTER BY check_name AS
  SELECT order_item, period, 'PK_DUP' AS check_name,
    CONCAT('(order_item, period) appears ', CAST(COUNT(*) AS STRING), ' times in expected_state') AS detail,
    CURRENT_TIMESTAMP() AS detected_at
  FROM `pacific-plating-282708.sap_integration_v3.expected_state`
  GROUP BY order_item, period
  HAVING COUNT(*) > 1;

  INSERT INTO `pacific-plating-282708.sap_integration_v3.sap_validation_error`
  WITH agg AS (
    SELECT order_item, COUNT(DISTINCT period) AS n_periods, MAX(total_periods) AS n_total_periods
    FROM `pacific-plating-282708.sap_integration_v3.expected_state`
    GROUP BY order_item
  )
  SELECT order_item, CAST(NULL AS INT64) AS period, 'SCHEDULE_GAP' AS check_name,
    CONCAT('expected periods 1..', CAST(n_total_periods AS STRING),
           ', found ', CAST(n_periods AS STRING), ' distinct periods') AS detail,
    CURRENT_TIMESTAMP() AS detected_at
  FROM agg
  WHERE n_periods != n_total_periods;

  -- Count equality alone can miss malformed sets such as {2,3} with TotalPeriods=2.
  INSERT INTO `pacific-plating-282708.sap_integration_v3.sap_validation_error`
  WITH per_item AS (
    SELECT order_item, MAX(total_periods) AS total_periods,
      COUNT(DISTINCT total_periods) AS total_periods_versions,
      ARRAY_AGG(DISTINCT period ORDER BY period) AS actual_periods
    FROM `pacific-plating-282708.sap_integration_v3.expected_state`
    GROUP BY order_item
  )
  SELECT order_item, CAST(NULL AS INT64), 'SCHEDULE_PERIOD_SET_INVALID',
    FORMAT('expected 1..%d; TotalPeriods versions=%d; found %s',
      IFNULL(total_periods, -1), total_periods_versions,
      ARRAY_TO_STRING(ARRAY(SELECT CAST(p AS STRING) FROM UNNEST(actual_periods) p), ',')),
    CURRENT_TIMESTAMP()
  FROM per_item
  WHERE total_periods IS NULL OR total_periods < 1 OR total_periods_versions != 1
     OR TO_JSON_STRING(actual_periods) != TO_JSON_STRING(GENERATE_ARRAY(1, total_periods));

  INSERT INTO `pacific-plating-282708.sap_integration_v3.sap_validation_error`
  SELECT order_item, period, 'FLOW_TOTAL_PERIODS_INVALID',
    FORMAT('flow=%s; TotalPeriods=%d', flow, total_periods), CURRENT_TIMESTAMP()
  FROM `pacific-plating-282708.sap_integration_v3.expected_state`
  WHERE (flow IN ('ONETIME', 'RCL_CMI') AND total_periods != 1)
     OR (flow = 'RCL' AND total_periods <= 1);

  INSERT INTO `pacific-plating-282708.sap_integration_v3.sap_validation_error`
  WITH known_insurers AS (
    SELECT DISTINCT SPLIT(U_InsurerCode, '-')[OFFSET(1)] AS insurer_code
    FROM `pacific-plating-282708.sap_integration_v3.stg_sap_state`
    WHERE U_InsurerCode LIKE '%-%'
  ),
  candidates AS (
    SELECT OrderItem AS order_item, InsurerCode AS insurer_code
    FROM `pacific-plating-282708.sap_data_engineer.sap_dashboard_carepay_fully_paid`
    WHERE InsurerCode IS NOT NULL AND InsurerCode != ''
    UNION DISTINCT
    SELECT OrderItem, InsurerCode
    FROM `pacific-plating-282708.sap_data_engineer.sap_dashboard_carepay_installment`
    WHERE InsurerCode IS NOT NULL AND InsurerCode != ''
  )
  SELECT c.order_item, CAST(NULL AS INT64) AS period, 'MASTER_INSURER_UNKNOWN' AS check_name,
    CONCAT('InsurerCode ', c.insurer_code, ' not found anywhere in SAP history') AS detail,
    CURRENT_TIMESTAMP() AS detected_at
  FROM candidates c
  LEFT JOIN known_insurers k ON k.insurer_code = c.insurer_code
  WHERE k.insurer_code IS NULL
    AND c.order_item NOT IN (
      SELECT DISTINCT U_OrderItem FROM `pacific-plating-282708.sap_integration_v2.SAP_LIVE_FULL`
    );

  INSERT INTO `pacific-plating-282708.sap_integration_v3.sap_validation_error`
  WITH candidates AS (
    SELECT OrderItem AS order_item, PaymentDate AS payment_date
    FROM `pacific-plating-282708.sap_data_engineer.sap_dashboard_carepay_fully_paid`
    WHERE PaymentDate IS NOT NULL AND PaymentDate != ''
    UNION DISTINCT
    SELECT OrderItem, PaymentDate
    FROM `pacific-plating-282708.sap_data_engineer.sap_dashboard_carepay_installment`
    WHERE PaymentDate IS NOT NULL AND PaymentDate != ''
  )
  SELECT c.order_item, CAST(NULL AS INT64) AS period, 'MASTER_PAYMENTDATE_LOCKED' AS check_name,
    CONCAT('PaymentDate ', c.payment_date, ' falls before the current accounting month') AS detail,
    CURRENT_TIMESTAMP() AS detected_at
  FROM candidates c
  WHERE SAFE.PARSE_DATE('%d%m%Y', c.payment_date) < DATE_TRUNC(CURRENT_DATE(), MONTH)
    AND c.order_item NOT IN (
      SELECT DISTINCT U_OrderItem FROM `pacific-plating-282708.sap_integration_v2.SAP_LIVE_FULL`
    );

  -- F2 (new): PolicyNo > 50 chars = BLOCK, never truncate.
  INSERT INTO `pacific-plating-282708.sap_integration_v3.sap_validation_error`
  SELECT e.order_item, e.period, 'POLICYNO_TOO_LONG' AS check_name,
    CONCAT('flow=', e.flow, '; PolicyNo length=', CAST(LENGTH(d.policy_no) AS STRING), ' (max 50)') AS detail,
    CURRENT_TIMESTAMP() AS detected_at
  FROM `pacific-plating-282708.sap_integration_v3.expected_state` e
  JOIN `pacific-plating-282708.sap_integration_v3.stg_order_dim` d USING (order_item)
  WHERE LENGTH(d.policy_no) > 50;
END;

-- 035_policyno_too_long_validation.sql
-- KNOWLEDGE_ADDENDUM_20260729 v2, item F2: PolicyNo > 50 chars = BLOCK (never truncate).
-- NOT DEPLOYED YET - written and verified read-only against live data per Boat's "no deploy this
-- round" instruction (2026-07-29 session). Full CREATE OR REPLACE PROCEDURE, same convention as
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
  -- Contract-shaped inputs from all 12 currently exported flows. Keep columns named rather than
  -- SELECT *: SAP consumes the CSV by ordinal position, while this validation is by semantic name.
  CREATE TEMP TABLE _contract_rows AS
  SELECT 'RCB_Motor_process_create' flow, OrderItem, SAFE_CAST(Period AS INT64) period,
    CAST(InsuredID AS STRING) InsuredID, CAST(PolicyNo AS STRING) PolicyNo,
    CAST(OrderDate AS STRING) OrderDate, CAST(PolicyDate AS STRING) PolicyDate,
    CAST(PaymentDate AS STRING) PaymentDate, CAST(ExpectedDate AS STRING) ExpectedDate,
    CAST(BatchRunDate AS STRING) BatchRunDate FROM `pacific-plating-282708.sap_view.RCB_Motor_process_create`
  UNION ALL SELECT 'RCB_Motor_process_2_cancel_new', OrderItem, SAFE_CAST(Period AS INT64), CAST(InsuredID AS STRING), CAST(PolicyNo AS STRING), CAST(OrderDate AS STRING), CAST(PolicyDate AS STRING), CAST(PaymentDate AS STRING), CAST(ExpectedDate AS STRING), CAST(BatchRunDate AS STRING) FROM `pacific-plating-282708.sap_view.RCB_Motor_process_2_cancel_new`
  UNION ALL SELECT 'RCB_Motor_process_3_change', OrderItem, SAFE_CAST(Period AS INT64), CAST(InsuredID AS STRING), CAST(PolicyNo AS STRING), CAST(OrderDate AS STRING), CAST(PolicyDate AS STRING), CAST(PaymentDate AS STRING), CAST(ExpectedDate AS STRING), CAST(BatchRunDate AS STRING) FROM `pacific-plating-282708.sap_view.RCB_Motor_process_3_change`
  UNION ALL SELECT 'RCB_Motor_process_4_creditshell', OrderItem, SAFE_CAST(Period AS INT64), CAST(InsuredID AS STRING), CAST(PolicyNo AS STRING), CAST(OrderDate AS STRING), CAST(PolicyDate AS STRING), CAST(PaymentDate AS STRING), CAST(ExpectedDate AS STRING), CAST(BatchRunDate AS STRING) FROM `pacific-plating-282708.sap_view.RCB_Motor_process_4_creditshell`
  UNION ALL SELECT 'RCL_Motor_process_1_create', OrderItem, SAFE_CAST(Period AS INT64), CAST(InsuredID AS STRING), CAST(PolicyNo AS STRING), CAST(OrderDate AS STRING), CAST(PolicyDate AS STRING), CAST(PaymentDate AS STRING), CAST(ExpectedDate AS STRING), CAST(BatchRunDate AS STRING) FROM `pacific-plating-282708.sap_view.RCL_Motor_process_1_create`
  UNION ALL SELECT 'RCL_Motor_process_2_newpayment', OrderItem, SAFE_CAST(Period AS INT64), CAST(InsuredID AS STRING), CAST(PolicyNo AS STRING), CAST(OrderDate AS STRING), CAST(PolicyDate AS STRING), CAST(PaymentDate AS STRING), CAST(ExpectedDate AS STRING), CAST(BatchRunDate AS STRING) FROM `pacific-plating-282708.sap_view.RCL_Motor_process_2_newpayment`
  UNION ALL SELECT 'RCL_Motor_process_3_cancel', OrderItem, SAFE_CAST(Period AS INT64), CAST(InsuredID AS STRING), CAST(PolicyNo AS STRING), CAST(OrderDate AS STRING), CAST(PolicyDate AS STRING), CAST(PaymentDate AS STRING), CAST(ExpectedDate AS STRING), CAST(BatchRunDate AS STRING) FROM `pacific-plating-282708.sap_view.RCL_Motor_process_3_cancel`
  UNION ALL SELECT 'RCL_Motor_process_4_creditshell', OrderItem, SAFE_CAST(Period AS INT64), CAST(InsuredID AS STRING), CAST(PolicyNo AS STRING), CAST(OrderDate AS STRING), CAST(PolicyDate AS STRING), CAST(PaymentDate AS STRING), CAST(ExpectedDate AS STRING), CAST(BatchRunDate AS STRING) FROM `pacific-plating-282708.sap_view.RCL_Motor_process_4_creditshell`
  UNION ALL SELECT 'RCB_NonMotor_process_1_create', OrderItem, SAFE_CAST(Period AS INT64), CAST(InsuredID AS STRING), CAST(PolicyNo AS STRING), CAST(OrderDate AS STRING), CAST(PolicyDate AS STRING), CAST(PaymentDate AS STRING), CAST(ExpectedDate AS STRING), CAST(BatchRunDate AS STRING) FROM `pacific-plating-282708.sap_view.RCB_NonMotor_process_1_create`
  UNION ALL SELECT 'RCB_NonMotor_process_2_cancel', OrderItem, SAFE_CAST(Period AS INT64), CAST(InsuredID AS STRING), CAST(PolicyNo AS STRING), CAST(OrderDate AS STRING), CAST(PolicyDate AS STRING), CAST(PaymentDate AS STRING), CAST(ExpectedDate AS STRING), CAST(BatchRunDate AS STRING) FROM `pacific-plating-282708.sap_view.RCB_NonMotor_process_2_cancel`
  UNION ALL SELECT 'RCL_NonMotor_process_1_create', OrderItem, SAFE_CAST(Period AS INT64), CAST(InsuredID AS STRING), CAST(PolicyNo AS STRING), CAST(OrderDate AS STRING), CAST(PolicyDate AS STRING), CAST(PaymentDate AS STRING), CAST(ExpectedDate AS STRING), CAST(BatchRunDate AS STRING) FROM `pacific-plating-282708.sap_view.RCL_NonMotor_process_1_create`
  UNION ALL SELECT 'RCL_NonMotor_process_2_newpayment', OrderItem, SAFE_CAST(Period AS INT64), CAST(InsuredID AS STRING), CAST(PolicyNo AS STRING), CAST(OrderDate AS STRING), CAST(PolicyDate AS STRING), CAST(PaymentDate AS STRING), CAST(ExpectedDate AS STRING), CAST(BatchRunDate AS STRING) FROM `pacific-plating-282708.sap_view.RCL_NonMotor_process_2_newpayment`;

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
  SELECT OrderItem, period, 'POLICYNO_TOO_LONG' AS check_name,
    CONCAT('flow=', flow, '; PolicyNo length=', CAST(LENGTH(PolicyNo) AS STRING), ' (max 50)') AS detail,
    CURRENT_TIMESTAMP() AS detected_at
  FROM _contract_rows
  WHERE LENGTH(PolicyNo) > 50;

  -- F3: every date column in the verified 56-column contract. Empty is allowed; every non-empty
  -- value must be exactly DDMMYYYY and parse to a real calendar date.
  INSERT INTO `pacific-plating-282708.sap_integration_v3.sap_validation_error`
  SELECT OrderItem, period, 'DATE_FORMAT_INVALID' AS check_name,
    CONCAT('flow=', flow, '; column=', date_column, '; value=', IFNULL(date_value, '<NULL>')) AS detail,
    CURRENT_TIMESTAMP() AS detected_at
  FROM _contract_rows
  UNPIVOT(date_value FOR date_column IN (OrderDate, PolicyDate, PaymentDate, ExpectedDate, BatchRunDate))
  WHERE NOT (IFNULL(date_value, '') = '' OR (
    LENGTH(date_value) = 8 AND SAFE.PARSE_DATE('%d%m%Y', date_value) IS NOT NULL));
END;

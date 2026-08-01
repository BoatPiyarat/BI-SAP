-- 037_fix_expected_invoice_no_null_unsafe.sql
-- Live source definition of sp_refresh_expected_state. It supersedes 034 and combines:
--   * 2026-07-29: NULL-safe expected_invoice_no generation;
--   * 2026-07-31: RULE-01 calendar-period PaymentDate clamp, RULE-02 period-lock control,
--     and RULE-08 payment_date_clamped audit marker.
--   * 2026-08-01: fail closed unless exactly one non-expired period exists and its
--     open_period_start is not in the future.
--   * 2026-08-01: E1 tiering supersedes RULE-09 rescue: OrderDate <=2024 is untouched,
--     2025 is cancel-only when already in SAP, and >=2026 follows normal processing.
--     Processing date_basis remains GREATEST(OrderDate, PolicyDate); it is not the tier field.
--
-- Historical blast-radius evidence for the 2026-07-29 NULL-safe change:
-- Verified directly against live `expected_state` (pre-fix):
--   26,801 rows total where motor_item_type IS NULL
--   status_null = 0                (expected_status always computed - unaffected, already NULL-safe)
--   payment_date_null = 15,216     (= exactly the Pending rows - correct, not a symptom)
--   charge_id_null    = 15,216     (= exactly the Pending rows - correct, not a symptom)
--   invoice_no_null   = 26,801     (= ALL rows, including the 11,585 that are expected_status='Paid'
--                                    with a real charge_id already - THIS is the isolated symptom)
-- That earlier fix was confirmed to touch exactly one column for the affected rows. This file's
-- current scope is broader because the locked 2026-07-31 rules above were subsequently folded in.
-- Distinct-item count of the harmful subset (Paid + NULL invoice, post-exclusion, in live
-- expected_state right now): 5,579 order_items / 11,585 rows.
--
-- Compliance check: this does NOT violate "InvoiceNo... generate only via fn_invoice_no" - the bug
-- was that fn_invoice_no was never CALLED for these rows (falling straight to ELSE NULL); the fix
-- makes them correctly reach the same fn_invoice_no() call NonMotor Paid rows already use, nothing
-- new is introduced.
--
-- 034 is retained only as historical source; do not apply it after this live definition.

CREATE OR REPLACE PROCEDURE `pacific-plating-282708.sap_integration_v3.sp_refresh_expected_state`()
BEGIN
  DECLARE year_no_touch_max INT64 DEFAULT (
    SELECT CAST(config_value AS INT64) FROM `pacific-plating-282708.sap_integration_v3.sap_config`
    WHERE config_key = 'year_no_touch_max'
  );
  DECLARE year_cancel_only INT64 DEFAULT (
    SELECT CAST(config_value AS INT64) FROM `pacific-plating-282708.sap_integration_v3.sap_config`
    WHERE config_key = 'year_cancel_only'
  );
  DECLARE active_period_count INT64 DEFAULT (
    SELECT COUNT(*)
    FROM `pacific-plating-282708.sap_integration_v3.sap_period_lock`
    WHERE lock_datetime > CURRENT_TIMESTAMP()
  );
  DECLARE open_period_start DATE DEFAULT (
    SELECT MAX(open_period_start)
    FROM `pacific-plating-282708.sap_integration_v3.sap_period_lock`
    WHERE lock_datetime > CURRENT_TIMESTAMP()
  );

  ASSERT active_period_count = 1
    AS 'RULE-09 requires exactly one active period in sap_period_lock';
  ASSERT year_no_touch_max = 2024 AND year_cancel_only = 2025
    AS 'E1 requires year_no_touch_max=2024 and year_cancel_only=2025';
  ASSERT open_period_start IS NOT NULL AND open_period_start <= CURRENT_DATE()
    AS 'sap_period_lock open_period_start is NULL or future-dated; refusing to derive PaymentDate';

  -- Step 1: original candidate set - unchanged logic from 016_expected_state.sql
  CREATE TEMP TABLE _base AS
  WITH payment_events_dedup AS (
    SELECT * EXCEPT(rn) FROM (
      SELECT *, ROW_NUMBER() OVER (
        PARTITION BY order_item, period ORDER BY charge_time ASC
      ) AS rn
      FROM `pacific-plating-282708.sap_integration_v3.stg_payment_events`
    ) WHERE rn = 1
  ),
  order_txn_any_paid AS (
    SELECT DISTINCT
      s.transaction_id,
      FIRST_VALUE(c.id) OVER (
        PARTITION BY s.transaction_id ORDER BY c.update_time ASC
      ) AS first_charge_id,
      FIRST_VALUE(COALESCE(c.third_party_id, s.order_item)) OVER (
        PARTITION BY s.transaction_id ORDER BY c.update_time ASC
      ) AS first_third_party_id,
      FIRST_VALUE(c.update_time) OVER (
        PARTITION BY s.transaction_id ORDER BY c.update_time ASC
      ) AS first_charge_time
    FROM `pacific-plating-282708.sap_integration_v3.stg_schedule` s
    JOIN `pacific-plating-282708.careos.carepay_charges` c
      ON c.transaction_id = s.transaction_id AND c.status = 'SUCCESSFUL'
    WHERE s.motor_item_type = 'MOTOR_TYPE_COMPULSORY'
  )
  SELECT
    s.order_item,
    s.order_id,
    s.period,
    s.total_periods,
    s.flow,
    s.payment_option,
    CASE
      WHEN s.motor_item_type = 'MOTOR_TYPE_COMPULSORY' THEN IF(otp.transaction_id IS NOT NULL, 'Paid', 'Pending')
      ELSE IF(pe.charge_id IS NOT NULL, 'Paid', 'Pending')
    END AS expected_status,
    CASE
      WHEN s.motor_item_type = 'MOTOR_TYPE_COMPULSORY' AND otp.transaction_id IS NOT NULL THEN
        `pacific-plating-282708.sap_integration_v3.fn_invoice_no`(otp.first_third_party_id)
      WHEN (s.motor_item_type != 'MOTOR_TYPE_COMPULSORY' OR s.motor_item_type IS NULL) AND pe.charge_id IS NOT NULL THEN
        `pacific-plating-282708.sap_integration_v3.fn_invoice_no`(pe.third_party_id)
      ELSE NULL
    END AS expected_invoice_no,
    CASE
      WHEN s.motor_item_type = 'MOTOR_TYPE_COMPULSORY' THEN DATE(otp.first_charge_time)
      ELSE DATE(pe.charge_time)
    END AS expected_payment_date,
    COALESCE(IF(s.motor_item_type = 'MOTOR_TYPE_COMPULSORY', otp.first_charge_id, NULL), pe.charge_id) AS charge_id,
    pe.amount AS charge_amount
  FROM `pacific-plating-282708.sap_integration_v3.stg_schedule` s
  LEFT JOIN payment_events_dedup pe
    ON pe.order_item = s.order_item AND pe.period = s.period
  LEFT JOIN order_txn_any_paid otp
    ON s.motor_item_type = 'MOTOR_TYPE_COMPULSORY' AND otp.transaction_id = s.transaction_id;

  -- Step 2: enrich with everything the exclusion rules need
  CREATE TEMP TABLE _enriched AS
  SELECT
    b.* REPLACE(
      GREATEST(b.expected_payment_date, open_period_start) AS expected_payment_date
    ),
    b.expected_payment_date AS raw_payment_date,
    b.expected_payment_date IS NOT NULL
      AND b.expected_payment_date < open_period_start AS payment_date_clamped,
    d.insured_id,
    d.first_name,
    d.last_name,
    d.insurer_code,
    d.policy_no,
    d.is_cancelled_effective,
    DATE(d.order_create_time) AS order_date,
    CASE
      WHEN d.order_create_time IS NULL AND d.policy_start_date IS NULL THEN NULL
      WHEN d.order_create_time IS NULL THEN DATE(d.policy_start_date)
      WHEN d.policy_start_date IS NULL THEN DATE(d.order_create_time)
      ELSE GREATEST(DATE(d.order_create_time), DATE(d.policy_start_date))
    END AS date_basis,
    mirror.U_OrderItem IS NOT NULL AS already_in_sap
  FROM _base b
  LEFT JOIN `pacific-plating-282708.sap_integration_v3.stg_order_dim` d ON d.order_item = b.order_item
  LEFT JOIN (
    SELECT DISTINCT U_OrderItem FROM `pacific-plating-282708.sap_integration_v3.sap_mirror_state`
  ) mirror ON mirror.U_OrderItem = b.order_item;

  -- Step 3: compute each rule's applicability per row
  CREATE TEMP TABLE _rules AS
  SELECT
    e.*,
    EXTRACT(YEAR FROM e.order_date) AS order_year,
    FALSE AS old_year_rescued,
    EXISTS(
      SELECT 1 FROM `pacific-plating-282708.sap_integration_v3.sap_test_customer_name_patterns` p
      WHERE LOWER(TRIM(e.first_name)) = p.pattern OR LOWER(TRIM(e.last_name)) = p.pattern
    ) AS is_test_name,
    COALESCE(REGEXP_EXTRACT(TRIM(e.insurer_code), r'/(.+)$'),
      REGEXP_EXTRACT(TRIM(e.insurer_code), r'^[^-]+-(.+)$'), TRIM(e.insurer_code)) AS insurer_code_plain,
    NOT EXISTS(
      SELECT 1 FROM `pacific-plating-282708.sap_integration_v3.sap_insurer_master` m
      WHERE m.insurer_code = COALESCE(REGEXP_EXTRACT(TRIM(e.insurer_code), r'/(.+)$'),
        REGEXP_EXTRACT(TRIM(e.insurer_code), r'^[^-]+-(.+)$'), TRIM(e.insurer_code))
    ) AS insurer_not_in_master
  FROM _enriched e;

  -- Step 4: log every applicable exclusion - EXCLUDED != DELETED, nothing disappears silently.
  -- Full rebuild each run (CREATE OR REPLACE on the first write, plain INSERT after within the
  -- same run) - same "full rebuild every run" convention as delta_export/sap_validation_error -
  -- otherwise this table would grow unbounded, re-appending every prior run's rows forever.
  CREATE OR REPLACE TABLE `pacific-plating-282708.sap_integration_v3.sap_excluded_records`
  CLUSTER BY rule_code
  AS
  SELECT order_item, period, 'DATE_BASIS_MISSING' AS rule_code,
    'OrderDate is NULL; E1 tier cannot be determined' AS reason, CURRENT_TIMESTAMP() AS detected_at
  FROM _rules WHERE order_date IS NULL;

  INSERT INTO `pacific-plating-282708.sap_integration_v3.sap_excluded_records`
    (order_item, period, rule_code, reason, detected_at)
  SELECT order_item, period, 'YEAR_OUT_OF_SCOPE',
    CONCAT('OrderDate year ', CAST(order_year AS STRING), ' <= ', CAST(year_no_touch_max AS STRING),
      '; untouched: no interface, backlog, or recovery'),
    CURRENT_TIMESTAMP()
  FROM _rules
  WHERE order_year <= year_no_touch_max;

  INSERT INTO `pacific-plating-282708.sap_integration_v3.sap_excluded_records`
    (order_item, period, rule_code, reason, detected_at)
  SELECT order_item, period, 'YEAR_2025_NON_CANCEL_EXCLUDED',
    CONCAT('OrderDate year 2025 excluded: cancel-only requires already_in_sap=TRUE and ',
      'is_cancelled_effective=TRUE; actual already_in_sap=', CAST(already_in_sap AS STRING),
      ', is_cancelled_effective=', CAST(IFNULL(is_cancelled_effective, FALSE) AS STRING)),
    CURRENT_TIMESTAMP()
  FROM _rules
  WHERE order_year = year_cancel_only
    AND NOT (already_in_sap AND IFNULL(is_cancelled_effective, FALSE));

  INSERT INTO `pacific-plating-282708.sap_integration_v3.sap_excluded_records`
    (order_item, period, rule_code, reason, detected_at)
  SELECT order_item, period, 'TEST_CUSTOMER',
    'LOWER(TRIM(FirstName or LastName)) exactly matches test or test div', CURRENT_TIMESTAMP()
  FROM _rules WHERE is_test_name;

  INSERT INTO `pacific-plating-282708.sap_integration_v3.sap_excluded_records`
    (order_item, period, rule_code, reason, detected_at)
  SELECT order_item, period, 'INSURER_NOT_IN_MASTER',
    CONCAT('insurer_code=', IFNULL(insurer_code_plain, '<NULL>'),
      ' not found in SAP_LIVE_FULL valid-DocEntry master'), CURRENT_TIMESTAMP()
  FROM _rules WHERE insurer_not_in_master;

  -- Step 5: final expected_state - same output schema as 016, only hard-excluded rows removed
  CREATE OR REPLACE TABLE `pacific-plating-282708.sap_integration_v3.expected_state`
  CLUSTER BY order_item AS
  SELECT
    order_item, order_id, period, total_periods, flow, payment_option, expected_status,
    expected_invoice_no, expected_payment_date, payment_date_clamped, old_year_rescued,
    insured_id,
    charge_id, charge_amount,
    CURRENT_TIMESTAMP() AS computed_at
  FROM _rules
  WHERE order_date IS NOT NULL
    AND date_basis IS NOT NULL
    AND (order_year >= year_cancel_only + 1
      OR (order_year = year_cancel_only AND already_in_sap AND IFNULL(is_cancelled_effective, FALSE)))
    AND NOT is_test_name
    AND NOT insurer_not_in_master;
END;

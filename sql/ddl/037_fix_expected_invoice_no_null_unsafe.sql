-- 037_fix_expected_invoice_no_null_unsafe.sql
-- Live source definition of sp_refresh_expected_state. It supersedes 034 and combines:
--   * 2026-07-29: NULL-safe expected_invoice_no generation;
--   * 2026-07-31: RULE-01 calendar-period PaymentDate clamp, RULE-02 period-lock control,
--     RULE-08 payment_date_clamped audit marker, and RULE-09's narrowly scoped
--     OLD_YEAR_NO_TOUCH rescue for raw payments inside the open calendar month.
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
  DECLARE open_period_start DATE DEFAULT (
    SELECT MAX(open_period_start)
    FROM `pacific-plating-282708.sap_integration_v3.sap_period_lock`
  );

  ASSERT open_period_start IS NOT NULL
    AS 'sap_period_lock has no open_period_start; refusing to derive PaymentDate';

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
    d.first_name,
    d.last_name,
    d.insurer_code,
    d.is_cancelled,
    d.phone_normalized,
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
    EXTRACT(YEAR FROM e.date_basis) AS basis_year,
    e.date_basis IS NOT NULL
      AND EXTRACT(YEAR FROM e.date_basis) <= year_no_touch_max
      AND e.raw_payment_date IS NOT NULL
      AND e.raw_payment_date >= open_period_start
      AND e.raw_payment_date < DATE_ADD(open_period_start, INTERVAL 1 MONTH)
      AS old_year_rescued,
    EXISTS(
      SELECT 1 FROM `pacific-plating-282708.sap_integration_v3.sap_test_customer_name_patterns` p
      WHERE LOWER(TRIM(e.first_name)) = p.pattern OR LOWER(TRIM(e.last_name)) = p.pattern
    ) AS is_test_name,
    REGEXP_EXTRACT(e.insurer_code, r'/(.+)$') AS insurer_code_plain,
    NOT EXISTS(
      SELECT 1 FROM `pacific-plating-282708.sap_integration_v3.sap_insurer_master` m
      WHERE m.insurer_code = REGEXP_EXTRACT(e.insurer_code, r'/(.+)$')
    ) AS insurer_not_in_master,
    ph.pattern_normalized AS phone_match_pattern,
    ph.enforce_hard_filter AS phone_enforce
  FROM _enriched e
  LEFT JOIN `pacific-plating-282708.sap_integration_v3.sap_test_customer_phone_patterns` ph
    ON ph.pattern_normalized = e.phone_normalized;

  -- Step 4: log every applicable exclusion - EXCLUDED != DELETED, nothing disappears silently.
  -- Full rebuild each run (CREATE OR REPLACE on the first write, plain INSERT after within the
  -- same run) - same "full rebuild every run" convention as delta_export/sap_validation_error -
  -- otherwise this table would grow unbounded, re-appending every prior run's rows forever.
  CREATE OR REPLACE TABLE `pacific-plating-282708.sap_integration_v3.sap_excluded_records`
  CLUSTER BY rule_code
  AS
  SELECT order_item, period, 'DATE_BASIS_MISSING' AS rule_code,
    'OrderDate and PolicyDate both NULL' AS reason, CURRENT_TIMESTAMP() AS detected_at
  FROM _rules WHERE date_basis IS NULL;

  INSERT INTO `pacific-plating-282708.sap_integration_v3.sap_excluded_records`
    (order_item, period, rule_code, reason, detected_at)
  SELECT order_item, period, 'OLD_YEAR_NO_TOUCH',
    CONCAT('date basis year ', CAST(basis_year AS STRING), ' <= ', CAST(year_no_touch_max AS STRING)),
    CURRENT_TIMESTAMP()
  FROM _rules
  WHERE date_basis IS NOT NULL
    AND basis_year <= year_no_touch_max
    AND NOT (raw_payment_date IS NOT NULL
      AND raw_payment_date >= open_period_start
      AND raw_payment_date < DATE_ADD(open_period_start, INTERVAL 1 MONTH));

  INSERT INTO `pacific-plating-282708.sap_integration_v3.sap_excluded_records`
    (order_item, period, rule_code, reason, detected_at)
  SELECT order_item, period, 'NO_NEW_PAID_2025',
    'year 2025, not cancelled - no new Paid status sent for this year per E1', CURRENT_TIMESTAMP()
  FROM _rules WHERE date_basis IS NOT NULL AND basis_year = year_cancel_only AND NOT is_cancelled;

  INSERT INTO `pacific-plating-282708.sap_integration_v3.sap_excluded_records`
    (order_item, period, rule_code, reason, detected_at)
  SELECT order_item, period, 'CANCEL_2025_NOT_IN_SAP',
    'year 2025, cancelled, but never interfaced into SAP - cannot cancel what was never created (R4/R5)',
    CURRENT_TIMESTAMP()
  FROM _rules
  WHERE date_basis IS NOT NULL AND basis_year = year_cancel_only AND is_cancelled AND NOT already_in_sap;

  INSERT INTO `pacific-plating-282708.sap_integration_v3.sap_excluded_records`
    (order_item, period, rule_code, reason, detected_at)
  SELECT order_item, period, 'TEST_CUSTOMER_NAME',
    'FirstName or LastName exact-matches a configured test-customer name pattern', CURRENT_TIMESTAMP()
  FROM _rules WHERE is_test_name;

  INSERT INTO `pacific-plating-282708.sap_integration_v3.sap_excluded_records`
    (order_item, period, rule_code, reason, detected_at)
  SELECT order_item, period, 'INSURER_NOT_IN_MASTER',
    CONCAT('insurer_code=', insurer_code_plain, ' not found in sap_insurer_master'), CURRENT_TIMESTAMP()
  FROM _rules WHERE insurer_not_in_master AND insurer_code_plain IS NOT NULL;

  INSERT INTO `pacific-plating-282708.sap_integration_v3.sap_excluded_records`
    (order_item, period, rule_code, reason, detected_at)
  SELECT order_item, period, 'TEST_CUSTOMER_PHONE',
    CONCAT('phone matches configured test pattern ', phone_match_pattern,
      IF(phone_enforce, ' (hard-filtered)', ' (report-only, NOT removed from expected_state)')),
    CURRENT_TIMESTAMP()
  FROM _rules WHERE phone_match_pattern IS NOT NULL;

  -- Step 5: final expected_state - same output schema as 016, only hard-excluded rows removed
  CREATE OR REPLACE TABLE `pacific-plating-282708.sap_integration_v3.expected_state`
  CLUSTER BY order_item AS
  SELECT
    order_item, order_id, period, total_periods, flow, payment_option, expected_status,
    expected_invoice_no, expected_payment_date, payment_date_clamped, old_year_rescued,
    charge_id, charge_amount,
    CURRENT_TIMESTAMP() AS computed_at
  FROM _rules
  WHERE date_basis IS NOT NULL
    AND (basis_year > year_no_touch_max OR old_year_rescued)
    AND NOT (basis_year = year_cancel_only AND NOT is_cancelled)
    AND NOT (basis_year = year_cancel_only AND is_cancelled AND NOT already_in_sap)
    AND NOT is_test_name
    AND NOT (insurer_not_in_master AND insurer_code_plain IS NOT NULL)
    AND NOT (phone_match_pattern IS NOT NULL AND phone_enforce);
END;

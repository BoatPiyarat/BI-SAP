-- 032_exclusion_config_and_excluded_records.sql
-- KNOWLEDGE_ADDENDUM_20260729 v2, items 2 + 4: EXCLUDED != DELETED tracking table, and config
-- tables for year scope / test-customer patterns / insurer master so these can be changed by
-- Boat editing a table (no deploy needed), not hardcoded into procedure bodies.

-- ============================================================================
-- sap_excluded_records: every row any exclusion rule below removes from expected_state lands
-- here, never silently. Grain: one row per (order_item, period, rule_code) - a row can in
-- principle be excluded by more than one rule; keep both, don't dedup across rule_code.
-- ============================================================================
CREATE TABLE IF NOT EXISTS `pacific-plating-282708.sap_integration_v3.sap_excluded_records` (
  order_item STRING,
  period INT64,
  amount INT64 OPTIONS(description = 'Successful charge amount in satang; NULL for rows without a charge'),
  date_basis DATE OPTIONS(description = 'Processing basis GREATEST(OrderDate, PolicyDate), not the E1 year-tier field'),
  rule_code STRING,
  reason STRING,
  detected_at TIMESTAMP
)
CLUSTER BY rule_code;

-- ============================================================================
-- sap_config: scalar tunables. E1's year cutoffs today (year_no_touch_max=2024,
-- year_cancel_only=2025) - editing these rows changes behavior on the next
-- sp_refresh_expected_state run, no deploy.
-- ============================================================================
CREATE TABLE IF NOT EXISTS `pacific-plating-282708.sap_integration_v3.sap_config` (
  config_key STRING,
  config_value STRING,
  updated_at TIMESTAMP
);

MERGE `pacific-plating-282708.sap_integration_v3.sap_config` T
USING (
  SELECT * FROM UNNEST([
    STRUCT('year_no_touch_max' AS config_key, '2024' AS config_value),
    STRUCT('year_cancel_only', '2025')
  ])
) S
ON T.config_key = S.config_key
WHEN NOT MATCHED THEN INSERT (config_key, config_value, updated_at)
  VALUES (S.config_key, S.config_value, CURRENT_TIMESTAMP());

-- ============================================================================
-- sap_test_customer_name_patterns: exact-match patterns (LOWER/TRIM'd) for E2/TEST_CUSTOMER_NAME.
-- E2 locked 2026-08-01: exact normalized values are 'test' and 'test div'.
-- ============================================================================
CREATE TABLE IF NOT EXISTS `pacific-plating-282708.sap_integration_v3.sap_test_customer_name_patterns` (
  pattern STRING,
  added_at TIMESTAMP
);

MERGE `pacific-plating-282708.sap_integration_v3.sap_test_customer_name_patterns` T
USING (SELECT pattern FROM UNNEST(['test', 'test div']) AS pattern) S
ON T.pattern = S.pattern
WHEN NOT MATCHED THEN INSERT (pattern, added_at) VALUES (S.pattern, CURRENT_TIMESTAMP());

-- ============================================================================
-- sap_test_customer_phone_patterns: normalized-phone exact-match patterns for
-- E2/TEST_CUSTOMER_PHONE. enforce_hard_filter starts FALSE (report-only) per Boat's own
-- criterion: only flip to TRUE once a pattern is confirmed either 0 matches or all-test-named -
-- '0999999999' is neither (252 matched, 72 non-test-named, real ActualReceived - see
-- 30_SAP_CHANGELOG.md 2026-07-29), so it stays report-only until Boat says otherwise. Flipping
-- this to TRUE for a given row is the only change needed to hard-filter it - no redeploy.
-- ============================================================================
CREATE TABLE IF NOT EXISTS `pacific-plating-282708.sap_integration_v3.sap_test_customer_phone_patterns` (
  pattern_normalized STRING,
  enforce_hard_filter BOOL,
  added_at TIMESTAMP
);

MERGE `pacific-plating-282708.sap_integration_v3.sap_test_customer_phone_patterns` T
USING (SELECT '0999999999' AS pattern_normalized, FALSE AS enforce_hard_filter) S
ON T.pattern_normalized = S.pattern_normalized
WHEN NOT MATCHED THEN INSERT (pattern_normalized, enforce_hard_filter, added_at)
  VALUES (S.pattern_normalized, S.enforce_hard_filter, CURRENT_TIMESTAMP());

-- ============================================================================
-- sap_insurer_master: E3's master list. "Successfully received" means a non-empty
-- U_InsurerCode on a SAP_LIVE_FULL row with a non-NULL, positive DocEntry. SAP_LIVE_FULL is the
-- confirmed truth source; stg_sap_state is deliberately not used to seed this master.
-- ============================================================================
CREATE TABLE IF NOT EXISTS `pacific-plating-282708.sap_integration_v3.sap_insurer_master` (
  insurer_code STRING,
  source STRING,
  added_at TIMESTAMP
);

MERGE `pacific-plating-282708.sap_integration_v3.sap_insurer_master` T
USING (
  SELECT DISTINCT
    COALESCE(
      REGEXP_EXTRACT(TRIM(U_InsurerCode), r'/(.+)$'),
      REGEXP_EXTRACT(TRIM(U_InsurerCode), r'^[^-]+-(.+)$'),
      TRIM(U_InsurerCode)
    ) AS insurer_code
  FROM `pacific-plating-282708.sap_integration_v2.SAP_LIVE_FULL`
  WHERE SAFE_CAST(DocEntry AS INT64) > 0
    AND NULLIF(TRIM(U_InsurerCode), '') IS NOT NULL
) S
ON T.insurer_code = S.insurer_code
WHEN NOT MATCHED THEN INSERT (insurer_code, source, added_at)
  VALUES (S.insurer_code, 'SAP_LIVE_FULL_valid_DocEntry', CURRENT_TIMESTAMP());

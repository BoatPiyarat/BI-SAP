-- 029_validation_regression_alert.sql
-- Boat 2026-07-27 "away 26-30" plan, item 1.3: wire an email alert for validation failures
-- (distinct from 028's column-contract guard, which already self-alerts on its own check_name).
-- Covers a spike in ANY sap_validation_error rule (PK_DUP, SCHEDULE_GAP,
-- MASTER_INSURER_UNKNOWN, MASTER_PAYMENTDATE_LOCKED, COLUMN_CONTRACT_DRIFT).
--
-- Threshold rationale (UNVERIFIED as a permanent number, a starting heuristic only): baseline
-- was 24 rows before 2026-07-27's stg_sap_state fix, 22 after (see 30_SAP_CHANGELOG.md). Alerts
-- at >60 total (~2.7x current baseline) - generous enough to avoid noise from normal day-to-day
-- variance, tight enough to catch a real regression. Revisit once more days of real baseline
-- data exist.

CREATE OR REPLACE PROCEDURE `pacific-plating-282708.sap_integration_v3.sp_check_validation_regression`()
BEGIN
  DECLARE total_errors INT64;
  DECLARE breakdown STRING;

  SET total_errors = (SELECT COUNT(*) FROM `pacific-plating-282708.sap_integration_v3.sap_validation_error`);
  SET breakdown = (
    SELECT STRING_AGG(FORMAT('%s=%d', check_name, n), ', ' ORDER BY n DESC)
    FROM (
      SELECT check_name, COUNT(*) n
      FROM `pacific-plating-282708.sap_integration_v3.sap_validation_error`
      GROUP BY check_name
    )
  );

  IF total_errors > 60 THEN
    RAISE USING MESSAGE = FORMAT(
      'sap_validation_error regression: %d total rows (baseline ~22-24) - breakdown: %s. Check sap_validation_error before tonight\'s legacy export if these represent real new SAP rejections.',
      total_errors, breakdown
    );
  END IF;
END;

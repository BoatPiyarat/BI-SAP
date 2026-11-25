-- docs/assistant/data_watch.sql
-- Daily read-only data health check + KPI anomaly watch for Boat's proactive assistant.
-- Read-only. No DDL, no writes. Dry-run first; expected scan ~100 MB (2026-11-25 measured run: 100,661,892 bytes;
-- vw_dash_freshness 84 MB, vw_dash_export_pipeline_health ~59 MB for 8 days, recon <2 MB).
-- All thresholds are INITIAL ESTIMATES (not business-confirmed) — tune via FEEDBACK_LOG.md.
-- Output: one row per check with status OK / WARN / ALERT and a Thai-readable detail.

WITH
fresh AS (
  -- SAP_LIVE U_BatchRunDate is date-granular (midnight UTC), so the view's hour-based
  -- STALE flag (>26h) reads STALE every afternoon. Use calendar-day lag instead:
  -- after the 20:30 ICT extract, last load date should be >= yesterday.
  SELECT DATE(last_load_ts, 'Asia/Bangkok') AS last_load_date
  FROM `pacific-plating-282708.sap_integration_v3.vw_dash_freshness`
),
pipe AS (
  SELECT SUM(n_extract_jobs) AS jobs, SUM(n_failed) AS failed
  FROM `pacific-plating-282708.sap_integration_v3.vw_dash_export_pipeline_health`
  WHERE export_date = DATE_SUB(CURRENT_DATE('Asia/Bangkok'), INTERVAL 1 DAY)
),
recon_daily AS (
  SELECT
    DATE(first_paid_time, 'Asia/Bangkok') AS d,
    COUNT(*) AS n_charges,
    SUM(total_amount_thb) AS amt_thb,
    COUNTIF(recon_status = 'MISSING_FROM_SAP') AS n_missing,
    MAX(recon_checked_at) AS checked_at
  FROM `pacific-plating-282708.sap_integration_v3.recon_careos_charges`
  WHERE first_paid_time >= TIMESTAMP(DATE_SUB(CURRENT_DATE('Asia/Bangkok'), INTERVAL 36 DAY), 'Asia/Bangkok')
  GROUP BY d
),
kpi AS (
  -- D-2 vs average of the same weekday in the previous 4 weeks. D-2, not yesterday:
  -- recon_careos_charges is rebuilt ~21:00 ICT, so at the morning run "yesterday" is cut off
  -- at ~21:00 and would read artificially low (observed 2026-11-25: -34% on a partial day).
  SELECT
    y.n_charges, y.amt_thb,
    AVG(b.n_charges) AS base_n, AVG(b.amt_thb) AS base_amt
  FROM recon_daily y
  LEFT JOIN recon_daily b
    ON b.d IN (DATE_SUB(y.d, INTERVAL 7 DAY), DATE_SUB(y.d, INTERVAL 14 DAY),
               DATE_SUB(y.d, INTERVAL 21 DAY), DATE_SUB(y.d, INTERVAL 28 DAY))
  WHERE y.d = DATE_SUB(CURRENT_DATE('Asia/Bangkok'), INTERVAL 2 DAY)
  GROUP BY y.n_charges, y.amt_thb
),
settled AS (
  -- days D-7..D-3 should have settled into SAP; MISSING share above 3% = backlog
  SELECT STRING_AGG(FORMAT('%t: %d/%d (%.1f%%)', d, n_missing, n_charges,
                           100 * SAFE_DIVIDE(n_missing, n_charges)), ' | ' ORDER BY d) AS detail,
         MAX(SAFE_DIVIDE(n_missing, n_charges)) AS worst_ratio
  FROM recon_daily
  WHERE d BETWEEN DATE_SUB(CURRENT_DATE('Asia/Bangkok'), INTERVAL 7 DAY) AND DATE_SUB(CURRENT_DATE('Asia/Bangkok'), INTERVAL 3 DAY)
)
SELECT 'H1_sap_extract_freshness' AS check_id,
       IF(last_load_date >= DATE_SUB(CURRENT_DATE('Asia/Bangkok'), INTERVAL 1 DAY), 'OK', 'ALERT') AS status,
       FORMAT('SAP_LIVE โหลดล่าสุดวันที่ %t (ต้อง >= %t)', last_load_date, DATE_SUB(CURRENT_DATE('Asia/Bangkok'), INTERVAL 1 DAY)) AS detail
FROM fresh
UNION ALL
SELECT 'H2_extract_jobs_yesterday',
       CASE WHEN IFNULL(jobs, 0) = 0 THEN 'ALERT' WHEN failed > 0 THEN 'ALERT' ELSE 'OK' END,
       FORMAT('extract jobs เมื่อวาน: %d, failed: %d', IFNULL(jobs, 0), IFNULL(failed, 0))
FROM pipe
UNION ALL
SELECT 'H3_recon_table_refreshed',
       IF(TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), MAX(checked_at), HOUR) <= 30, 'OK', 'WARN'),
       FORMAT('recon_careos_charges checked_at ล่าสุด %t (%d ชม.ก่อน)', MAX(checked_at),
              TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), MAX(checked_at), HOUR))
FROM recon_daily
UNION ALL
SELECT 'H4_settled_days_missing_from_sap',
       CASE WHEN worst_ratio > 0.10 THEN 'ALERT' WHEN worst_ratio > 0.03 THEN 'WARN' ELSE 'OK' END,
       CONCAT('MISSING_FROM_SAP D-7..D-3: ', IFNULL(detail, 'no data'))
FROM settled
UNION ALL
SELECT 'K1_paid_charges_count_vs_4wk_same_weekday',
       CASE WHEN base_n IS NULL OR base_n = 0 THEN 'WARN'
            WHEN ABS(n_charges / base_n - 1) > 0.35 THEN 'ALERT' ELSE 'OK' END,
       FORMAT('D-2 %d charges vs baseline %.0f (%+.0f%%)', n_charges, base_n,
              100 * SAFE_DIVIDE(n_charges - base_n, base_n))
FROM kpi
UNION ALL
SELECT 'K2_paid_amount_vs_4wk_same_weekday',
       CASE WHEN base_amt IS NULL OR base_amt = 0 THEN 'WARN'
            WHEN ABS(amt_thb / base_amt - 1) > 0.35 THEN 'ALERT' ELSE 'OK' END,
       FORMAT('D-2 ฿%.0f vs baseline ฿%.0f (%+.0f%%)', amt_thb, base_amt,
              100 * SAFE_DIVIDE(amt_thb - base_amt, base_amt))
FROM kpi
ORDER BY check_id;

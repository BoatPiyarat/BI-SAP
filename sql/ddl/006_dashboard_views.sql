-- 006_dashboard_views.sql
-- Looker Studio data source views (Boat, 2026-07-25: "prepare data for dashboard Looker studio
-- data source"). Follows SAP_DASHBOARD_DESIGN_v1.md's Page 2 (Completeness) and Page 1/4
-- (Pipeline Status / Freshness) intent, built against what's real and already verified tonight
-- rather than the full 4-page design (Page 3 Correctness needs sap_validation_error, which
-- doesn't exist yet - P2 territory, not attempted here).
--
-- Connect Looker Studio directly to these views (BigQuery connector, project
-- pacific-plating-282708, dataset sap_integration_v3). No Looker-side transformation needed -
-- each view is already shaped for a specific chart type (see comments per view).

-- ============================================================================
-- vw_dash_completeness — Page 2 Completeness: funnel / donut / backlog-by-flow
-- Source: recon_careos_charges (sp_recon_all_charges, 2026-only scope per Boat's call)
-- ============================================================================
CREATE OR REPLACE VIEW `pacific-plating-282708.sap_integration_v3.vw_dash_completeness` AS
SELECT
  DATE(first_paid_time) AS paid_date,
  payment_option,
  recon_status,
  CASE
    WHEN recon_status = 'NO_ORDER_ITEM' THEN 'CareOS gap (no order ever created)'
    WHEN recon_status = 'MISSING_FROM_SAP' THEN 'SAP interface gap'
    ELSE 'Healthy'
  END AS gap_category,
  DATE_DIFF(CURRENT_DATE(), DATE(first_paid_time), DAY) AS age_days,
  COUNT(*) AS n_periods,
  ROUND(SUM(total_amount_thb), 2) AS total_thb
FROM `pacific-plating-282708.sap_integration_v3.recon_careos_charges`
GROUP BY paid_date, payment_option, recon_status, gap_category, age_days;

-- ============================================================================
-- vw_dash_completeness_summary — single-row KPI tile: completeness %
-- ============================================================================
CREATE OR REPLACE VIEW `pacific-plating-282708.sap_integration_v3.vw_dash_completeness_summary` AS
SELECT
  COUNT(*) AS total_periods,
  COUNTIF(recon_status = 'IN_SAP') AS in_sap_periods,
  COUNTIF(recon_status = 'MISSING_FROM_SAP') AS missing_periods,
  COUNTIF(recon_status = 'NO_ORDER_ITEM') AS no_order_item_periods,
  ROUND(COUNTIF(recon_status = 'IN_SAP') / COUNT(*) * 100, 2) AS completeness_pct,
  CURRENT_TIMESTAMP() AS computed_at
FROM `pacific-plating-282708.sap_integration_v3.recon_careos_charges`;

-- ============================================================================
-- vw_dash_export_pipeline_health — Page 1 Pipeline Status: is the real export
-- (Cloud Scheduler -> Pub/Sub -> Cloud Functions -> gs://interface-file/) actually
-- running? Built from real BigQuery EXTRACT-type jobs (2026-07-25 finding: this is
-- the real export mechanism, confirmed via job history - not EXPORT DATA SQL text,
-- which this pipeline doesn't use). 180-day retention (BigQuery JOBS system view
-- limit) - Looker will just show whatever's in that window.
-- ============================================================================
CREATE OR REPLACE VIEW `pacific-plating-282708.sap_integration_v3.vw_dash_export_pipeline_health` AS
SELECT
  DATE(creation_time) AS export_date,
  user_email AS run_as,
  COUNT(*) AS n_extract_jobs,
  COUNTIF(state = 'DONE' AND error_result IS NULL) AS n_success,
  COUNTIF(error_result IS NOT NULL) AS n_failed
FROM `region-asia-southeast1`.INFORMATION_SCHEMA.JOBS_BY_PROJECT
WHERE job_type = 'EXTRACT'
  AND creation_time > TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 90 DAY)
GROUP BY export_date, run_as
ORDER BY export_date DESC;

-- ============================================================================
-- vw_dash_freshness — Page 4 Freshness: SAP truth age (real signal, not the
-- design docs' original raw_sap_live assumption - see 10_SAP_CONTEXT.md)
-- ============================================================================
CREATE OR REPLACE VIEW `pacific-plating-282708.sap_integration_v3.vw_dash_freshness` AS
SELECT
  last_load_ts,
  hours_since_last_load,
  status,
  CURRENT_TIMESTAMP() AS checked_at
FROM `pacific-plating-282708.sap_integration_v3.vw_dead_mans_switch`;

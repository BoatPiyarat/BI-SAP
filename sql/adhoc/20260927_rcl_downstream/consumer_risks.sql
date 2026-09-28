CREATE TEMP TABLE live_create AS -- Full source-only legacy root-fix proposal for:
--   pacific-plating-282708.sap_view.RCL_Motor_process_1_create
--
-- Root cause:
--   sap_dashboard_carepay_installment correctly emits an RCL compulsory M1 as one
--   Period/TotalPeriods 1/1 row. The legacy wrapper then discards it because its
--   final QUALIFY requires every OrderItem to have more than one row and
--   TotalPeriods > 1. That schedule rule is valid for voluntary V1, but not M1.
--
-- Surgical fix:
--   * Allow compulsory M1 through only as Period/TotalPeriods 1/1.
--   * Keep the original multi-row and TotalPeriods > 1 gate for all voluntary rows.
--   * Require RABBIT_CARE_INSTALLMENT plus at least one SUCCESSFUL
--     RABBIT_LENDING charge before any row can enter this RCL interface.
--   * Admit V1 only as an all-or-nothing complete 1..TotalPeriods spine with
--     non-NULL ExpectedReceived, ActualReceived, and ExpectedDate.
--   * Preserve all existing SAP, change-order, year, insurer, and Test exclusions.
--
-- SELECT only: this file does not replace or deploy the live legacy view.

WITH
  eligible_rcl_items AS (
    SELECT DISTINCT order_items.human_id AS OrderItem
    FROM `pacific-plating-282708.careos.careos_orders` AS orders
    JOIN `pacific-plating-282708.careos.careos_order_items` AS order_items
      ON order_items.order_id = orders.id
    JOIN `pacific-plating-282708.careos.carepay_transactions` AS transactions
      ON CONCAT('transactions/', transactions.id) = orders.payment
     AND transactions.payment_option = 'RABBIT_CARE_INSTALLMENT'
    WHERE EXISTS (
      SELECT 1
      FROM `pacific-plating-282708.careos.carepay_charges` AS charges
      WHERE charges.transaction_id = transactions.id
        AND charges.status = 'SUCCESSFUL'
        AND charges.service_provider = 'RABBIT_LENDING'
    )
  ),

  interface AS (
    SELECT dashboard.*
    FROM `pacific-plating-282708._script7c6faf4dc1f287623ae26f66d20de48b274328dd.live_dashboard` AS dashboard
    JOIN eligible_rcl_items USING (OrderItem)
  ),

  filtered AS (
    SELECT interface.*
    FROM interface
    WHERE interface.OrderItem NOT IN (
      SELECT U_OrderItem
      FROM `pacific-plating-282708._script7c6faf4dc1f287623ae26f66d20de48b274328dd.evidence_sap`
    )
      AND interface.OrderID NOT IN (
        SELECT current_human_id
        FROM `pacific-plating-282708.careos.cancelled_change_orders`
      )
      AND interface.OrderDate NOT LIKE '%2023%'
      AND interface.OrderDate NOT LIKE '%2024%'
      AND interface.InsurerCode NOT IN ('45', '49')
      AND LOWER(TRIM(COALESCE(interface.FirstName, ''))) != 'test'
      AND LOWER(TRIM(COALESCE(interface.LastName, ''))) != 'test'
  ),

  spine_metrics AS (
    SELECT
      OrderItem,
      COUNT(*) AS row_count,
      COUNT(DISTINCT SAFE_CAST(Period AS INT64)) AS distinct_periods,
      MIN(SAFE_CAST(Period AS INT64)) AS min_period,
      MAX(SAFE_CAST(Period AS INT64)) AS max_period,
      COUNT(DISTINCT SAFE_CAST(TotalPeriods AS INT64)) AS total_period_versions,
      MAX(SAFE_CAST(TotalPeriods AS INT64)) AS total_periods,
      COUNTIF(SAFE_CAST(ExpectedReceived AS FLOAT64) IS NULL) AS null_expected_rows,
      COUNTIF(SAFE_CAST(ActualReceived AS FLOAT64) IS NULL) AS null_actual_rows,
      COUNTIF(
        NULLIF(TRIM(COALESCE(ExpectedDate, '')), '') IS NULL
      ) AS blank_expected_date_rows
    FROM filtered
    GROUP BY OrderItem
  )

SELECT
  filtered.*
FROM filtered
JOIN spine_metrics USING (OrderItem)
WHERE
  (
    filtered.InsuranceType = 'MOTOR_TYPE_COMPULSORY'
    AND SAFE_CAST(filtered.Period AS INT64) = 1
    AND SAFE_CAST(filtered.TotalPeriods AS INT64) = 1
    AND SAFE_CAST(filtered.ExpectedReceived AS FLOAT64) IS NOT NULL
    AND SAFE_CAST(filtered.ActualReceived AS FLOAT64) IS NOT NULL
    AND NULLIF(TRIM(COALESCE(filtered.ExpectedDate, '')), '') IS NOT NULL
  )
  OR (
    COALESCE(filtered.InsuranceType, '') != 'MOTOR_TYPE_COMPULSORY'
    AND spine_metrics.row_count > 1
    AND spine_metrics.total_periods > 1
    AND spine_metrics.total_period_versions = 1
    AND spine_metrics.min_period = 1
    AND spine_metrics.max_period = spine_metrics.total_periods
    AND spine_metrics.distinct_periods = spine_metrics.total_periods
    AND spine_metrics.null_expected_rows = 0
    AND spine_metrics.null_actual_rows = 0
    AND spine_metrics.blank_expected_date_rows = 0
  )
ORDER BY
  filtered.OrderItem,
  filtered.Period;
WITH old_added AS (
SELECT a.* FROM `pacific-plating-282708._script3d0fd839afdb12a19a0c5b125df9ae7a8484cf15.added` a JOIN `pacific-plating-282708._script3d0fd839afdb12a19a0c5b125df9ae7a8484cf15.receipt_lineage` l ON l.OrderItem=a.OrderItem AND l.Period=a.Period AND l.InvoiceNo IS NOT DISTINCT FROM a.InvoiceNo
WHERE LOWER(a.TransactionStatus)='paid' AND DATE(l.raw_update_time)<DATE_TRUNC(DATE_SUB(CURRENT_DATE(),INTERVAL 2 MONTH),MONTH)
), create_issues AS (
SELECT DISTINCT a.OrderItem,a.Period,a.InvoiceNo,d.rule_code FROM live_create a JOIN `pacific-plating-282708._script7c6faf4dc1f287623ae26f66d20de48b274328dd.lineage_diagnostics` d ON a.OrderItem=d.OrderItem AND a.Period=d.Period AND a.InvoiceNo IS NOT DISTINCT FROM d.InvoiceNo
)
SELECT CURRENT_TIMESTAMP() AS checked_at_utc,
(SELECT COUNT(*) FROM old_added) AS old_added_paid,
(SELECT COUNT(*) FROM old_added a WHERE TO_JSON_STRING(a) NOT IN (SELECT TO_JSON_STRING(p) FROM `pacific-plating-282708._script7c6faf4dc1f287623ae26f66d20de48b274328dd.evidence_paid` p)) AS old_paid_not_verbatim_sap_context,
(SELECT COUNT(*) FROM live_create) AS live_create_rows,
ARRAY(SELECT AS STRUCT * FROM create_issues) AS live_create_issues,
ARRAY(SELECT AS STRUCT a.OrderItem,a.Period,a.InvoiceNo,a.ActualReceived,a.PrincipleThisPeriod,a.PrincipleEIRThisPeriod FROM `pacific-plating-282708._script3d0fd839afdb12a19a0c5b125df9ae7a8484cf15.candidate_wrapper` a JOIN `pacific-plating-282708._script3d0fd839afdb12a19a0c5b125df9ae7a8484cf15.receipt_lineage` l ON a.OrderItem=l.OrderItem AND a.Period=l.Period AND a.InvoiceNo IS NOT DISTINCT FROM l.InvoiceNo WHERE l.source_charge_rank>1 AND a.TransactionStatus='paid' AND a.Period>1 AND (a.PrincipleThisPeriod IS DISTINCT FROM a.ActualReceived OR a.PrincipleEIRThisPeriod IS DISTINCT FROM a.ActualReceived)) AS additional_principal_review;

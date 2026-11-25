-- Rabbit Care BI query patterns — BigQuery Standard SQL, project pacific-plating-282708
-- Replace @start_date / @end_date (DATE, end exclusive). Always dry-run first.
-- Every pattern excludes test customers and states its date basis in the header.

-- =====================================================================
-- P1. Motor sales by ORDER CREATED date (sales-team view)
--     measure: gross premium + item count; cancelled excluded via gross_premium_after_cancelled
-- =====================================================================
SELECT
  FORMAT_DATE('%Y-%m', create_at_date)                  AS month,
  order_type,                                            -- voluntary / mandatory
  car_insurance_type,
  COUNT(DISTINCT item_id)                                AS policies_all,
  COUNT(DISTINCT IF(status != 'cancelled' OR status IS NULL, item_id, NULL)) AS policies_active,
  ROUND(SUM(gross_premium), 2)                           AS gross_premium_all,
  ROUND(SUM(gross_premium_after_cancelled), 2)           AS gross_premium_net_of_cancel
FROM `pacific-plating-282708.analytics_reports.report_order_items`
WHERE create_at_date >= @start_date AND create_at_date < @end_date
  AND NOT (LOWER(TRIM(IFNULL(customer_first_name, ''))) IN ('test', 'test div')
        OR LOWER(TRIM(IFNULL(customer_last_name, ''))) IN ('test', 'test div'))
GROUP BY 1, 2, 3
ORDER BY 1, 2, 3;

-- =====================================================================
-- P2. Same metric, four date bases side by side (to show users the difference)
--     note: SUM may include the few duplicated item_id rows (see tables.md grain warning)
-- =====================================================================
WITH items AS (
  SELECT item_id, gross_premium_after_cancelled AS gp,
         create_at_date, paid_date, policy_start_date, DATE(approval_time) AS approval_date
  FROM `pacific-plating-282708.analytics_reports.report_order_items`
  WHERE NOT (LOWER(TRIM(IFNULL(customer_first_name, ''))) IN ('test', 'test div')
          OR LOWER(TRIM(IFNULL(customer_last_name, ''))) IN ('test', 'test div'))
)
SELECT 'order_created'  AS date_basis, COUNT(DISTINCT item_id) AS policies, ROUND(SUM(gp), 2) AS gross_premium FROM items WHERE create_at_date    >= @start_date AND create_at_date    < @end_date
UNION ALL
SELECT 'payment_date',               COUNT(DISTINCT item_id),             ROUND(SUM(gp), 2)                   FROM items WHERE paid_date         >= @start_date AND paid_date         < @end_date
UNION ALL
SELECT 'policy_start_date',          COUNT(DISTINCT item_id),             ROUND(SUM(gp), 2)                   FROM items WHERE policy_start_date >= @start_date AND policy_start_date < @end_date
UNION ALL
SELECT 'insurer_approval_date',      COUNT(DISTINCT item_id),             ROUND(SUM(gp), 2)                   FROM items WHERE approval_date     >= @start_date AND approval_date     < @end_date;

-- =====================================================================
-- P3. Sales by COMMISSION MONTH (16th -> 15th)
-- =====================================================================
SELECT
  cm.commission_month,
  COUNT(DISTINCT oi.item_id)                    AS policies,
  ROUND(SUM(oi.gross_premium_after_cancelled), 2) AS gross_premium_net_of_cancel
FROM `pacific-plating-282708.analytics_reports.report_order_items` oi
JOIN `pacific-plating-282708.analytics_dimensional_modelling.dim_commission_months` cm
  ON oi.create_at_date BETWEEN cm.start_date AND cm.end_date   -- basis: order created (confirm with user)
WHERE oi.create_at_date >= @start_date AND oi.create_at_date < @end_date
GROUP BY 1
ORDER BY 1;

-- =====================================================================
-- P4. Cash collected by PAYMENT date (finance view, includes every installment)
--     CarePay timestamps are true UTC -> convert to Bangkok
--     amount in satang -> /100 ; only SUCCESSFUL charges are cash
-- =====================================================================
SELECT
  DATE(c.payment_date, 'Asia/Bangkok')               AS payment_day,
  IF(c.service_provider = 'RABBIT_LENDING', 'RCL installment', 'RCB / other') AS flow,
  COUNT(*)                                            AS charges,
  ROUND(SUM(c.amount) / 100, 2)                       AS cash_thb
FROM `pacific-plating-282708.careos.carepay_charges` c
WHERE c.status = 'SUCCESSFUL'
  AND c.delete_time IS NULL
  AND c.payment_date >= TIMESTAMP(@start_date, 'Asia/Bangkok')
  AND c.payment_date <  TIMESTAMP(@end_date,   'Asia/Bangkok')
GROUP BY 1, 2
ORDER BY 1, 2;

-- =====================================================================
-- P5. Policies by insurer on INSURER APPROVAL date (insurer view)
-- =====================================================================
SELECT
  insurer_name,
  order_type,
  COUNT(DISTINCT item_id)       AS approved_policies,
  ROUND(SUM(gross_premium), 2)  AS gross_premium
FROM `pacific-plating-282708.analytics_reports.report_order_items`
WHERE DATE(approval_time) >= @start_date   -- CareOS timestamps already hold Bangkok time: no conversion
  AND DATE(approval_time) <  @end_date
GROUP BY 1, 2
ORDER BY gross_premium DESC;

-- =====================================================================
-- P6. Cancellation rate by order-created cohort
-- =====================================================================
SELECT
  FORMAT_DATE('%Y-%m', create_at_date)                         AS created_month,
  COUNT(DISTINCT item_id)                                      AS policies,
  COUNT(DISTINCT IF(status = 'cancelled', item_id, NULL))      AS cancelled,
  ROUND(SAFE_DIVIDE(COUNT(DISTINCT IF(status = 'cancelled', item_id, NULL)),
                    COUNT(DISTINCT item_id)) * 100, 2)         AS cancel_rate_pct
FROM `pacific-plating-282708.analytics_reports.report_order_items`
WHERE create_at_date >= @start_date AND create_at_date < @end_date
GROUP BY 1
ORDER BY 1;

-- =====================================================================
-- P7. Payment-type mix (full vs RCL installment vs credit-card installment)
-- =====================================================================
SELECT
  IFNULL(payment_type, 'UNKNOWN')        AS payment_type,
  COUNT(DISTINCT item_id)                AS policies,
  ROUND(SUM(gross_premium), 2)           AS gross_premium
FROM `pacific-plating-282708.analytics_reports.report_order_items`
WHERE create_at_date >= @start_date AND create_at_date < @end_date
  AND (status != 'cancelled' OR status IS NULL)
GROUP BY 1
ORDER BY 3 DESC;

-- =====================================================================
-- P8. Cancellations split into plain cancel vs change order (cancel + replacement = one sale)
--     basis: item cancel date (CareOS timestamps already Bangkok time); change-order link from careos.cancelled_change_orders
-- =====================================================================
WITH cco AS (
  SELECT DISTINCT old_human_id
  FROM `pacific-plating-282708.careos.cancelled_change_orders`
),
cancelled AS (
  SELECT oi.short_id, oi.item_id, oi.gross_premium,
         DATE(oi.cancel_time) AS cancel_date
  FROM `pacific-plating-282708.analytics_reports.report_order_items` oi
  WHERE oi.status = 'cancelled'
    AND DATE(oi.cancel_time) >= @start_date
    AND DATE(oi.cancel_time) <  @end_date
)
SELECT
  IF(cco.old_human_id IS NOT NULL, 'change_order (replaced)', 'plain_cancel') AS cancel_type,
  COUNT(DISTINCT c.item_id)         AS items,
  ROUND(SUM(c.gross_premium), 2)    AS gross_premium
FROM cancelled c
LEFT JOIN cco ON cco.old_human_id = c.short_id
GROUP BY 1;

-- =====================================================================
-- P9. Freshness check — run before quoting today / yesterday
-- =====================================================================
-- created_at_timestamp holds Bangkok wall-clock time (labelled UTC), so compare with Bangkok "now"
SELECT
  DATETIME(MAX(created_at_timestamp))                                AS latest_order_in_report_bkk,
  DATETIME_DIFF(CURRENT_DATETIME('Asia/Bangkok'),
                DATETIME(MAX(created_at_timestamp)), HOUR)           AS hours_behind_now
FROM `pacific-plating-282708.analytics_reports.report_orders`
WHERE created_at_date >= DATE_SUB(CURRENT_DATE('Asia/Bangkok'), INTERVAL 7 DAY);

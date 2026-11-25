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
  AND NOT (LOWER(TRIM(IFNULL(customer_first_name, ''))) = 'test'
        OR LOWER(TRIM(IFNULL(customer_last_name, ''))) = 'test')
GROUP BY 1, 2, 3
ORDER BY 1, 2, 3;

-- =====================================================================
-- P2. Same metric, four date bases side by side (to show users the difference)
--     note: SUM may include the few duplicated item_id rows (see tables.md grain warning)
-- =====================================================================
WITH items AS (
  SELECT item_id, gross_premium_after_cancelled AS gp,
         create_at_date, paid_date, policy_start_date, DATE(approval_time, 'Asia/Bangkok') AS approval_date
  FROM `pacific-plating-282708.analytics_reports.report_order_items`
  WHERE NOT (LOWER(TRIM(IFNULL(customer_first_name, ''))) = 'test'
          OR LOWER(TRIM(IFNULL(customer_last_name, ''))) = 'test')
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
WHERE DATE(approval_time, 'Asia/Bangkok') >= @start_date
  AND DATE(approval_time, 'Asia/Bangkok') <  @end_date
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

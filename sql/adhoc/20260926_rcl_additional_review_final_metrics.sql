SELECT CURRENT_TIMESTAMP() AS checked_at_utc,
 (SELECT COUNT(*) FROM `pacific-plating-282708._script46ab18514cd926b622b3c7ad4e224e5f9fa65717.population_a`) AS population_rows,
 (SELECT COUNT(*) FROM `pacific-plating-282708._script22234d72759a494d0e2640bb0d5570acdd1ebc77.population_ledger`) AS ledger_rows,
 (SELECT COUNT(*) FROM `pacific-plating-282708._script22234d72759a494d0e2640bb0d5570acdd1ebc77.population_ledger` WHERE disposition IS NULL) AS unclassified_rows,
 (SELECT COUNT(*) FROM `pacific-plating-282708._script22234d72759a494d0e2640bb0d5570acdd1ebc77.population_ledger` WHERE older_than_window) AS historical_rows,
 (SELECT COUNT(*) FROM `pacific-plating-282708._script22234d72759a494d0e2640bb0d5570acdd1ebc77.population_ledger` WHERE additional_with_compulsory_item) AS additional_compulsory_linked_rows,
 (SELECT COUNT(*) FROM `pacific-plating-282708._script22234d72759a494d0e2640bb0d5570acdd1ebc77.population_ledger` WHERE disposition LIKE 'HOLD_%') AS requires_hold_rows;
SELECT CURRENT_TIMESTAMP() AS checked_at_utc,products,IF(source_charge_rank=1,'first','additional') AS charge_kind,
 IF(period=1,'period_1','period_2_plus') AS period_group,charge_month,payment_method,disposition,
 COUNT(*) AS charge_rows,ROUND(SUM(charge_amount_thb),2) AS charge_amount_thb
FROM `pacific-plating-282708._script22234d72759a494d0e2640bb0d5570acdd1ebc77.population_ledger` GROUP BY 2,3,4,5,6,7 ORDER BY 2,3,4,5,6,7;
SELECT CURRENT_TIMESTAMP() AS checked_at_utc,COUNT(*) AS additional_shape_without_raw_rank
FROM `pacific-plating-282708._script22234d72759a494d0e2640bb0d5570acdd1ebc77.added_wrapper_rows` w WHERE w.ExpectedReceived=0 AND w.ActualReceived>0 AND NOT EXISTS (
 SELECT 1 FROM `pacific-plating-282708._script46ab18514cd926b622b3c7ad4e224e5f9fa65717.ranked_charges` c JOIN `pacific-plating-282708.careos.careos_orders` o ON o.payment=CONCAT('transactions/',c.transaction_id)
 JOIN `pacific-plating-282708.careos.careos_order_items` oi ON oi.order_id=o.id
 WHERE oi.human_id=w.OrderItem AND c.installment_number=SAFE_CAST(w.Period AS INT64)
 AND w.InvoiceNo=IF(c.installment_number=1,CONCAT('2_',c.third_party_id),c.third_party_id) AND c.source_charge_rank>1);
CREATE TEMP TABLE create_baseline AS -- Full source-only legacy root-fix proposal for:
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
    FROM `pacific-plating-282708._scriptb14b3a9ebead07d9ecd3b3177c5b3bbe7a0379aa.baseline_dashboard` AS dashboard
    JOIN eligible_rcl_items USING (OrderItem)
  ),

  filtered AS (
    SELECT interface.*
    FROM interface
    WHERE interface.OrderItem NOT IN (
      SELECT U_OrderItem
      FROM `pacific-plating-282708._scriptb14b3a9ebead07d9ecd3b3177c5b3bbe7a0379aa.evidence_sap`
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
CREATE TEMP TABLE create_candidate AS -- Full source-only legacy root-fix proposal for:
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
    FROM `pacific-plating-282708._scriptb14b3a9ebead07d9ecd3b3177c5b3bbe7a0379aa.candidate_dashboard` AS dashboard
    JOIN eligible_rcl_items USING (OrderItem)
  ),

  filtered AS (
    SELECT interface.*
    FROM interface
    WHERE interface.OrderItem NOT IN (
      SELECT U_OrderItem
      FROM `pacific-plating-282708._scriptb14b3a9ebead07d9ecd3b3177c5b3bbe7a0379aa.evidence_sap`
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
SELECT CURRENT_TIMESTAMP() AS checked_at_utc,'sap_view.RCL_Motor_process_1_create' AS dependent,
 (SELECT COUNT(*) FROM create_baseline) AS old_rows,(SELECT COUNT(*) FROM create_candidate) AS new_rows,
 (SELECT COUNT(*) FROM (SELECT TO_JSON_STRING(c) FROM create_candidate c EXCEPT DISTINCT SELECT TO_JSON_STRING(b) FROM create_baseline b)) AS added_payloads,
 (SELECT COUNT(*) FROM (SELECT TO_JSON_STRING(b) FROM create_baseline b EXCEPT DISTINCT SELECT TO_JSON_STRING(c) FROM create_candidate c)) AS removed_payloads,
 (SELECT COUNT(*) FROM (SELECT OrderItem,Period,InvoiceNo FROM create_candidate GROUP BY 1,2,3 HAVING COUNT(*)>1)) AS duplicate_event_keys;
WITH missing AS (
 SELECT TO_JSON_STRING(b) AS payload FROM `pacific-plating-282708._scriptb14b3a9ebead07d9ecd3b3177c5b3bbe7a0379aa.baseline_dashboard` b
 EXCEPT DISTINCT SELECT TO_JSON_STRING(c) FROM `pacific-plating-282708._scriptb14b3a9ebead07d9ecd3b3177c5b3bbe7a0379aa.candidate_dashboard` c
), affected AS (
 SELECT DISTINCT b.OrderItem,b.Period FROM `pacific-plating-282708._scriptb14b3a9ebead07d9ecd3b3177c5b3bbe7a0379aa.baseline_dashboard` b JOIN missing m ON m.payload=TO_JSON_STRING(b)
), facts AS (
 SELECT a.OrderItem,a.Period,COUNTIF(c.create_time=f.create_time) AS first_time_ties
 FROM affected a JOIN `pacific-plating-282708.careos.careos_order_items` oi ON oi.human_id=a.OrderItem
 JOIN `pacific-plating-282708.careos.careos_orders` o ON o.id=oi.order_id
 JOIN `pacific-plating-282708._script46ab18514cd926b622b3c7ad4e224e5f9fa65717.ranked_charges` c ON o.payment=CONCAT('transactions/',c.transaction_id) AND c.installment_number=a.Period
 JOIN `pacific-plating-282708._script46ab18514cd926b622b3c7ad4e224e5f9fa65717.ranked_charges` f ON f.transaction_id=c.transaction_id AND f.installment_number=c.installment_number AND f.source_charge_rank=1
 GROUP BY 1,2
), old_sums AS (
 SELECT OrderItem,Period,ROUND(SUM(ExpectedReceived),2) AS expected,ROUND(SUM(InterestThisPeriod),2) AS interest,ROUND(SUM(InterestEIRThisPeriod),2) AS eir
 FROM `pacific-plating-282708._scriptb14b3a9ebead07d9ecd3b3177c5b3bbe7a0379aa.baseline_dashboard` GROUP BY 1,2
), new_sums AS (
 SELECT OrderItem,Period,ROUND(SUM(ExpectedReceived),2) AS expected,ROUND(SUM(InterestThisPeriod),2) AS interest,ROUND(SUM(InterestEIRThisPeriod),2) AS eir
 FROM `pacific-plating-282708._scriptb14b3a9ebead07d9ecd3b3177c5b3bbe7a0379aa.candidate_dashboard` GROUP BY 1,2
)
SELECT CURRENT_TIMESTAMP() AS checked_at_utc,(SELECT COUNT(*) FROM affected) AS affected_item_periods,
 (SELECT COUNT(*) FROM facts WHERE first_time_ties>1) AS affected_with_tied_first_charge,
 (SELECT COUNT(*) FROM affected a JOIN old_sums o USING(OrderItem,Period) JOIN new_sums n USING(OrderItem,Period) WHERE o.expected IS DISTINCT FROM n.expected OR o.interest IS DISTINCT FROM n.interest OR o.eir IS DISTINCT FROM n.eir) AS affected_schedule_sum_changes;
SELECT CURRENT_TIMESTAMP() AS checked_at_utc,
 (SELECT COUNT(*) FROM (SELECT TO_JSON_STRING(b) FROM `pacific-plating-282708._scriptb14b3a9ebead07d9ecd3b3177c5b3bbe7a0379aa.baseline_newpayment` b EXCEPT DISTINCT SELECT TO_JSON_STRING(c) FROM `pacific-plating-282708._script22234d72759a494d0e2640bb0d5570acdd1ebc77.candidate_newpayment` c)) AS raw_newpayment_old_payloads_removed,
 (SELECT COUNT(*) FROM `pacific-plating-282708._script22234d72759a494d0e2640bb0d5570acdd1ebc77.candidate_newpayment` WHERE InsuranceType='MOTOR_TYPE_COMPULSORY' AND InvoiceNo IS NULL AND ActualReceived>0) AS preserved_compulsory_null_invoice_rows;

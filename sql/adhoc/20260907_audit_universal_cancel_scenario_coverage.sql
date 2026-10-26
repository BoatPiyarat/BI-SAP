-- Red-capable, read-only scenario matrix for making
-- sap_view.RCB_Motor_process_2_cancel_new the universal item-level cancel interface.

WITH
sap_history AS (
  SELECT DISTINCT
    U_OrderID AS OrderID,
    U_OrderItem AS OrderItem,
    CompanyDB,
    U_InsuranceGroup AS InsuranceGroup,
    U_InsuranceType AS InsuranceType,
    SAFE_CAST(U_Period AS INT64) AS Period,
    SAFE_CAST(TotalPeriods AS INT64) AS TotalPeriods,
    TransactionStatus,
    PaymentChannel,
    OrderDate,
    BatchRunDate
  FROM `pacific-plating-282708.sap_integration_v2.SAP_LIVE_FULL`
  WHERE U_OrderItem IS NOT NULL
),

already_cancelled AS (
  SELECT DISTINCT OrderItem
  FROM sap_history
  WHERE OrderID LIKE 'C#%'
     OR TransactionStatus IN ('Cancelled', 'Cancelled (Change order / Rejected)')
),

sap_item AS (
  SELECT
    OrderItem,
    ARRAY_AGG(OrderID IGNORE NULLS ORDER BY BatchRunDate DESC LIMIT 1)[SAFE_OFFSET(0)] AS OrderID,
    ARRAY_AGG(CompanyDB IGNORE NULLS ORDER BY BatchRunDate DESC LIMIT 1)[SAFE_OFFSET(0)] AS CompanyDB,
    ARRAY_AGG(InsuranceGroup IGNORE NULLS ORDER BY BatchRunDate DESC LIMIT 1)[SAFE_OFFSET(0)] AS InsuranceGroup,
    ARRAY_AGG(InsuranceType IGNORE NULLS ORDER BY BatchRunDate DESC LIMIT 1)[SAFE_OFFSET(0)] AS InsuranceType,
    MAX(TotalPeriods) AS TotalPeriods,
    COUNT(DISTINCT Period) AS sap_distinct_periods,
    COUNTIF(STARTS_WITH(UPPER(COALESCE(PaymentChannel, '')), 'RCL')) > 0 AS has_rcl_payment_route,
    ARRAY_AGG(OrderDate IGNORE NULLS ORDER BY BatchRunDate DESC LIMIT 1)[SAFE_OFFSET(0)] AS OrderDate
  FROM sap_history
  WHERE OrderID NOT LIKE 'C#%'
    AND TransactionStatus NOT IN ('Cancelled', 'Cancelled (Change order / Rejected)')
  GROUP BY OrderItem
),

refund_items AS (
  SELECT DISTINCT SPLIT(order_item, '/')[SAFE_OFFSET(3)] AS item_id
  FROM `pacific-plating-282708.careos.refunds`
  WHERE order_item IS NOT NULL
),

care_item AS (
  SELECT
    item.id AS item_id,
    item.human_id AS OrderItem,
    item.order_id,
    orders.human_id AS care_order_id,
    orders.product,
    item.is_cancelled,
    item.cancel_time,
    item.underwriting_status,
    accounting.cancellation_status,
    refund_items.item_id IS NOT NULL AS has_refund,
    COUNT(*) OVER (PARTITION BY item.order_id) AS order_item_count,
    COUNTIF(item.is_cancelled IS TRUE OR item.cancel_time IS NOT NULL)
      OVER (PARTITION BY item.order_id) AS order_item_cancel_count
  FROM `pacific-plating-282708.careos.careos_order_items` AS item
  LEFT JOIN `pacific-plating-282708.careos.careos_orders` AS orders
    ON orders.id = item.order_id
  LEFT JOIN `pacific-plating-282708.careos.careos_accounting` AS accounting
    ON accounting.id = item.id
  LEFT JOIN refund_items
    ON refund_items.item_id = item.id
),

change_orders AS (
  SELECT DISTINCT old_human_id, current_human_id
  FROM `pacific-plating-282708.careos.cancelled_change_orders`
),

universal_output AS (
  SELECT DISTINCT OrderItem
  FROM `pacific-plating-282708.sap_view.RCB_Motor_process_2_cancel_new`
),

rcb_nonmotor_output AS (
  SELECT DISTINCT OrderItem
  FROM `pacific-plating-282708.sap_view.RCB_NonMotor_process_2_cancel`
),

rcl_motor_output AS (
  SELECT DISTINCT OrderItem
  FROM `pacific-plating-282708.sap_view.RCL_Motor_process_3_cancel`
),

scenario_universe AS (
  SELECT
    sap_item.*,
    care_item.care_order_id,
    care_item.product,
    care_item.is_cancelled,
    care_item.cancel_time,
    care_item.underwriting_status,
    care_item.cancellation_status,
    care_item.has_refund,
    care_item.order_item_count,
    care_item.order_item_cancel_count,
    change_orders.current_human_id,
    change_orders.old_human_id IS NOT NULL AS is_change_order_cancel,
    universal_output.OrderItem IS NOT NULL AS in_universal_view,
    rcb_nonmotor_output.OrderItem IS NOT NULL AS in_rcb_nonmotor_cancel,
    rcl_motor_output.OrderItem IS NOT NULL AS in_rcl_motor_cancel,
    CASE
      WHEN sap_item.has_rcl_payment_route THEN 'RCL' ELSE 'RCB'
    END AS company_route,
    CASE
      WHEN sap_item.InsuranceGroup = 'Motor' OR care_item.product = 'products/car-insurance'
        THEN 'Motor'
      ELSE 'NonMotor'
    END AS product_route,
    CASE
      WHEN care_item.is_cancelled IS TRUE OR care_item.cancel_time IS NOT NULL THEN 'ITEM_CANCEL'
      WHEN care_item.has_refund THEN 'REFUND_ONLY'
      WHEN care_item.underwriting_status = 'ITEM_UNDERWRITING_STATUS_REJECTED' THEN 'UW_REJECT_ONLY'
      WHEN care_item.cancellation_status IS NOT NULL THEN 'ACCOUNTING_CANCEL_ONLY'
      ELSE 'NO_CANCEL_SIGNAL'
    END AS cancel_signal,
    CASE
      WHEN care_item.order_item_count > 1
        AND care_item.order_item_cancel_count < care_item.order_item_count THEN 'PARTIAL_ITEM_CANCEL'
      ELSE 'FULL_OR_SINGLE_ITEM_CANCEL'
    END AS item_scope
  FROM sap_item
  JOIN care_item USING (OrderItem)
  LEFT JOIN already_cancelled USING (OrderItem)
  LEFT JOIN change_orders
    ON change_orders.old_human_id = sap_item.OrderID
    OR change_orders.old_human_id = care_item.care_order_id
  LEFT JOIN universal_output USING (OrderItem)
  LEFT JOIN rcb_nonmotor_output USING (OrderItem)
  LEFT JOIN rcl_motor_output USING (OrderItem)
  WHERE already_cancelled.OrderItem IS NULL
    AND (
      care_item.is_cancelled IS TRUE
      OR care_item.cancel_time IS NOT NULL
      OR care_item.has_refund
      OR care_item.underwriting_status = 'ITEM_UNDERWRITING_STATUS_REJECTED'
      OR care_item.cancellation_status IS NOT NULL
    )
),

classified AS (
  SELECT
    *,
    CASE
      WHEN in_universal_view THEN 'COVERED_BY_UNIVERSAL'
      WHEN in_rcb_nonmotor_cancel OR in_rcl_motor_cancel THEN 'ONLY_OTHER_CANCEL_VIEW'
      WHEN cancel_signal != 'ITEM_CANCEL' THEN CONCAT('MISSING_', cancel_signal)
      WHEN cancel_time IS NULL THEN 'MISSING_IS_CANCELLED_TRUE_BUT_NULL_CANCEL_TIME'
      WHEN DATE(cancel_time) < DATE '2026-01-01' THEN 'MISSING_PRE_2026_CANCEL_TIME'
      WHEN OrderID LIKE '%_X%' THEN 'MISSING_ORDER_X_FILTER'
      WHEN OrderID LIKE 'C#%' THEN 'MISSING_CANCEL_ORDER_ID_FILTER'
      WHEN OrderDate LIKE '%2023%' OR OrderDate LIKE '%2024%' THEN 'MISSING_ORDER_YEAR_FILTER'
      ELSE 'MISSING_UNEXPLAINED_ELIGIBLE_ITEM_CANCEL'
    END AS coverage_disposition
  FROM scenario_universe
)

SELECT
  CASE
    WHEN COUNTIF(NOT in_universal_view) > 0 THEN 'RED' ELSE 'GREEN'
  END AS verdict,
  COUNT(*) AS cancellation_candidate_items,
  COUNTIF(in_universal_view) AS universal_covered_items,
  COUNTIF(NOT in_universal_view) AS universal_missing_items,
  COUNTIF(NOT in_universal_view AND (in_rcb_nonmotor_cancel OR in_rcl_motor_cancel))
    AS missing_but_other_cancel_view_items,
  COUNTIF(NOT in_universal_view AND NOT in_rcb_nonmotor_cancel AND NOT in_rcl_motor_cancel)
    AS missing_from_all_cancel_views,
  COUNTIF(
    NOT in_universal_view
    AND (
      cancel_time >= TIMESTAMP '2026-01-01'
      OR (is_cancelled IS TRUE AND cancel_time IS NULL)
      OR cancel_signal != 'ITEM_CANCEL'
    )
  ) AS current_scope_missing_items,
  COUNTIF(NOT in_universal_view AND cancel_time < TIMESTAMP '2026-01-01')
    AS historical_pre_2026_missing_items,
  ARRAY(
    SELECT AS STRUCT company_route, product_route,
      IF(is_change_order_cancel, 'Change', 'Cancel') AS cancel_or_change,
      item_scope, cancel_signal, coverage_disposition,
      COUNT(*) AS item_count
    FROM classified
    GROUP BY company_route, product_route, cancel_or_change,
      item_scope, cancel_signal, coverage_disposition
    ORDER BY coverage_disposition, company_route, product_route,
      cancel_or_change, item_scope, cancel_signal
  ) AS scenario_matrix,
  ARRAY(
    SELECT AS STRUCT OrderID, OrderItem, company_route, product_route,
      IF(is_change_order_cancel, 'Change', 'Cancel') AS cancel_or_change,
      item_scope, cancel_signal, coverage_disposition,
      cancel_time, is_cancelled, underwriting_status, cancellation_status,
      TotalPeriods, sap_distinct_periods
    FROM classified
    WHERE NOT in_universal_view
      AND (
        cancel_time >= TIMESTAMP '2026-01-01'
        OR (is_cancelled IS TRUE AND cancel_time IS NULL)
        OR cancel_signal != 'ITEM_CANCEL'
      )
    ORDER BY coverage_disposition, OrderItem
  ) AS current_missing_details,
  ARRAY(
    SELECT AS STRUCT OrderID, OrderItem, CompanyDB, InsuranceGroup, InsuranceType,
      product, TotalPeriods, sap_distinct_periods, has_rcl_payment_route,
      cancel_time, is_cancelled,
      underwriting_status, cancellation_status, has_refund,
      company_route, product_route,
      IF(is_change_order_cancel, 'Change', 'Cancel') AS cancel_or_change,
      item_scope, cancel_signal, coverage_disposition,
      in_rcb_nonmotor_cancel, in_rcl_motor_cancel
    FROM classified
    WHERE NOT in_universal_view
    ORDER BY coverage_disposition, company_route, product_route, OrderItem
    LIMIT 50
  ) AS missing_samples
FROM classified;

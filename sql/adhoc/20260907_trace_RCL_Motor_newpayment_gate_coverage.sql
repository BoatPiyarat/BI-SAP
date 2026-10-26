-- Read-only coverage trace for the eligibility gate used by
-- sap_view.RCL_Motor_process_2_newpayment.

WITH
gate AS (
  SELECT DISTINCT
    p.human_id AS OrderID,
    p.order_item AS OrderItem,
    DATE(p.order_create_time) AS order_date,
    p.payment_option,
    p.product,
    p.InsuranceType,
    i.is_cancelled AS item_is_cancelled,
    i.cancel_time AS item_cancel_time
  FROM `pacific-plating-282708.sap_integration_v2.RCL 05_paid by period` p
  LEFT JOIN `pacific-plating-282708.careos.careos_order_items` i
    ON i.human_id = p.order_item
),

output_items AS (
  SELECT DISTINCT OrderItem
  FROM `pacific-plating-282708.sap_view.RCL_Motor_process_2_newpayment`
),

classified AS (
  SELECT
    g.*,
    o.OrderItem IS NOT NULL AS in_output,
    CASE
      WHEN o.OrderItem IS NOT NULL THEN 'IN_OUTPUT'
      WHEN g.order_date < DATE '2026-01-01' THEN 'EXCLUDED_PRE_2026'
      WHEN g.order_date IS NULL THEN 'EXCLUDED_MALFORMED_OR_NULL_ORDER_DATE'
      WHEN g.product != 'products/car-insurance' OR g.product IS NULL THEN 'EXCLUDED_NONMOTOR_PRODUCT'
      WHEN g.InsuranceType = 'MOTOR_TYPE_COMPULSORY' THEN 'EXCLUDED_CMI'
      WHEN g.item_is_cancelled IS TRUE OR g.item_cancel_time IS NOT NULL THEN 'EXCLUDED_CANONICAL_ITEM_CANCELLED'
      ELSE 'ELIGIBLE_ACTIVE_MOTOR_MISSING_OUTPUT'
    END AS coverage_category
  FROM gate g
  LEFT JOIN output_items o USING (OrderItem)
),

six_incomplete_motor AS (
  SELECT *
  FROM classified
  WHERE OrderItem IN (
    'L78268213-V1', 'L78275116-V1', 'L78633176-V1',
    'L78710141-V1', 'L80237197-V1', 'L80339825-V1'
  )
)

SELECT
  (SELECT COUNT(*) FROM gate) AS gate_items,
  (SELECT COUNT(*) FROM classified WHERE in_output) AS gate_items_in_output,
  (SELECT COUNT(*) FROM classified WHERE coverage_category = 'ELIGIBLE_ACTIVE_MOTOR_MISSING_OUTPUT') AS eligible_active_motor_missing_items,
  ARRAY(
    SELECT AS STRUCT coverage_category, COUNT(*) AS items
    FROM classified
    GROUP BY coverage_category
    ORDER BY items DESC
  ) AS coverage_categories,
  ARRAY(
    SELECT AS STRUCT OrderID, OrderItem, order_date, payment_option, product,
      InsuranceType, item_is_cancelled, item_cancel_time, coverage_category
    FROM classified
    WHERE coverage_category = 'ELIGIBLE_ACTIVE_MOTOR_MISSING_OUTPUT'
    ORDER BY OrderItem
    LIMIT 50
  ) AS eligible_missing_samples,
  ARRAY(
    SELECT AS STRUCT OrderID, OrderItem, order_date, payment_option, product,
      InsuranceType, item_is_cancelled, item_cancel_time, in_output, coverage_category
    FROM six_incomplete_motor
    ORDER BY OrderItem
  ) AS six_incomplete_motor_details
;

-- Read-only root-cause confirmation for MS-05 candidate:
-- active RCL Motor compulsory (M1) items with a SUCCESSFUL RABBIT_LENDING charge,
-- absent from SAP and from RCL_Motor_process_1_create.

WITH
  latest_snapshot AS (
    SELECT transaction_id, number_of_installment
    FROM `pacific-plating-282708.careos.carepay_transaction_snapshots`
    QUALIFY ROW_NUMBER() OVER (
      PARTITION BY transaction_id
      ORDER BY update_time DESC, create_time DESC, id DESC
    ) = 1
  ),

  raw_candidates AS (
    SELECT
      orders.id AS order_uuid,
      orders.human_id AS OrderID,
      order_items.human_id AS OrderItem,
      latest_snapshot.number_of_installment,
      DATE(orders.create_time, 'Asia/Bangkok') AS order_date,
      DATE(order_items.policy_start_date, 'Asia/Bangkok') AS policy_date,
      COUNT(DISTINCT charges.id) AS successful_charge_count
    FROM `pacific-plating-282708.careos.careos_orders` AS orders
    JOIN `pacific-plating-282708.careos.careos_order_items` AS order_items
      ON order_items.order_id = orders.id
    JOIN `pacific-plating-282708.careos.carepay_transactions` AS transactions
      ON CONCAT('transactions/', transactions.id) = orders.payment
    JOIN `pacific-plating-282708.careos.carepay_charges` AS charges
      ON charges.transaction_id = transactions.id
     AND charges.status = 'SUCCESSFUL'
     AND charges.service_provider = 'RABBIT_LENDING'
    LEFT JOIN latest_snapshot
      ON latest_snapshot.transaction_id = transactions.id
    LEFT JOIN `pacific-plating-282708.sap_integration_v2.SAP_LIVE_FULL` AS sap
      ON sap.U_OrderItem = order_items.human_id
    WHERE order_items.product = 'products/car-insurance'
      AND order_items.motor_item_type = 'MOTOR_TYPE_COMPULSORY'
      AND order_items.is_cancelled IS NOT TRUE
      AND order_items.cancel_time IS NULL
      AND transactions.payment_option = 'RABBIT_CARE_INSTALLMENT'
      AND GREATEST(
        DATE(orders.create_time, 'Asia/Bangkok'),
        COALESCE(
          DATE(order_items.policy_start_date, 'Asia/Bangkok'),
          DATE(orders.create_time, 'Asia/Bangkok')
        )
      ) >= DATE '2026-01-01'
      AND sap.U_OrderItem IS NULL
      AND LOWER(TRIM(COALESCE(
        JSON_VALUE(orders.data, '$.policyHolder.firstName'),
        JSON_VALUE(orders.data, '$.policyHolder.policyAddress.companyName'),
        ''
      ))) != 'test'
      AND LOWER(TRIM(COALESCE(
        JSON_VALUE(orders.data, '$.policyHolder.lastName'), ''
      ))) != 'test'
    GROUP BY
      order_uuid, OrderID, OrderItem, number_of_installment,
      order_date, policy_date
  ),

  dashboard AS (
    SELECT
      OrderItem,
      COUNT(*) AS dashboard_rows,
      MIN(Period) AS min_period,
      MAX(Period) AS max_period,
      MIN(TotalPeriods) AS min_total_periods,
      MAX(TotalPeriods) AS max_total_periods
    FROM `pacific-plating-282708.sap_data_engineer.sap_dashboard_carepay_installment`
    WHERE OrderItem IN (SELECT OrderItem FROM raw_candidates)
    GROUP BY OrderItem
  ),

  target AS (
    SELECT OrderItem, COUNT(*) AS target_rows
    FROM `pacific-plating-282708.sap_view.RCL_Motor_process_1_create`
    WHERE OrderItem IN (SELECT OrderItem FROM raw_candidates)
    GROUP BY OrderItem
  ),

  sibling_rollup AS (
    SELECT
      raw_candidates.OrderItem,
      COUNT(DISTINCT sibling.human_id) AS voluntary_sibling_count,
      COUNT(DISTINCT IF(sap.U_OrderItem IS NOT NULL, sibling.human_id, NULL))
        AS voluntary_siblings_in_sap,
      COUNT(DISTINCT IF(target.OrderItem IS NOT NULL, sibling.human_id, NULL))
        AS voluntary_siblings_in_current_create
    FROM raw_candidates
    LEFT JOIN `pacific-plating-282708.careos.careos_order_items` AS sibling
      ON sibling.order_id = raw_candidates.order_uuid
     AND (
       sibling.motor_item_type != 'MOTOR_TYPE_COMPULSORY'
       OR sibling.motor_item_type IS NULL
     )
    LEFT JOIN `pacific-plating-282708.sap_integration_v2.SAP_LIVE_FULL` AS sap
      ON sap.U_OrderItem = sibling.human_id
    LEFT JOIN `pacific-plating-282708.sap_view.RCL_Motor_process_1_create` AS target
      ON target.OrderItem = sibling.human_id
    GROUP BY raw_candidates.OrderItem
  ),

  detail AS (
    SELECT
      raw_candidates.*,
      dashboard.dashboard_rows,
      dashboard.min_period,
      dashboard.max_period,
      dashboard.min_total_periods,
      dashboard.max_total_periods,
      COALESCE(target.target_rows, 0) AS target_rows,
      sibling_rollup.voluntary_sibling_count,
      sibling_rollup.voluntary_siblings_in_sap,
      sibling_rollup.voluntary_siblings_in_current_create
    FROM raw_candidates
    LEFT JOIN dashboard USING (OrderItem)
    LEFT JOIN target USING (OrderItem)
    LEFT JOIN sibling_rollup USING (OrderItem)
  )

SELECT
  COUNT(*) AS candidate_m1_items,
  SUM(successful_charge_count) AS successful_charge_count,
  COUNTIF(dashboard_rows = 1) AS upstream_exactly_one_row,
  COUNTIF(dashboard_rows > 1) AS upstream_more_than_one_row,
  COUNTIF(dashboard_rows IS NULL) AS missing_from_dashboard,
  COUNTIF(target_rows > 0) AS present_in_target,
  COUNTIF(
    dashboard_rows = 1
    AND min_period = 1
    AND max_period = 1
    AND min_total_periods > 1
    AND max_total_periods > 1
  ) AS exact_wrapper_filter_signature,
  COUNTIF(voluntary_sibling_count > 0) AS items_with_voluntary_sibling,
  COUNTIF(voluntary_siblings_in_sap > 0) AS items_with_voluntary_sibling_in_sap,
  COUNTIF(voluntary_siblings_in_current_create > 0)
    AS items_with_voluntary_sibling_in_current_create,
  MIN(order_date) AS earliest_order_date,
  MAX(order_date) AS latest_order_date,
  ARRAY_AGG(
    STRUCT(
      OrderID, OrderItem, number_of_installment, order_date, policy_date,
      successful_charge_count, dashboard_rows, min_period, max_period,
      min_total_periods, max_total_periods, target_rows,
      voluntary_sibling_count, voluntary_siblings_in_sap,
      voluntary_siblings_in_current_create
    )
    ORDER BY OrderItem
    LIMIT 25
  ) AS samples
FROM detail;

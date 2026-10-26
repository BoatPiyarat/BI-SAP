-- Read-only discovery for the next V2 legacy missing-interface scenario.
-- Grain: active 2026 CareOS OrderItem with at least one SUCCESSFUL charge.
-- Excludes exact-name Test rows and compares against SAP plus all 12 sap_view interfaces.

WITH
  latest_snapshot AS (
    SELECT transaction_id, number_of_installment
    FROM `pacific-plating-282708.careos.carepay_transaction_snapshots`
    QUALIFY ROW_NUMBER() OVER (
      PARTITION BY transaction_id
      ORDER BY update_time DESC, create_time DESC, id DESC
    ) = 1
  ),

  candidate_items AS (
    SELECT
      orders.human_id AS OrderID,
      order_items.human_id AS OrderItem,
      order_items.product,
      order_items.motor_item_type AS InsuranceType,
      transactions.payment_option,
      transactions.status AS transaction_status,
      latest_snapshot.number_of_installment,
      DATE(orders.create_time, 'Asia/Bangkok') AS order_date,
      DATE(order_items.policy_start_date, 'Asia/Bangkok') AS policy_date,
      COUNT(DISTINCT charges.id) AS successful_charge_count,
      COUNTIF(charges.service_provider = 'RABBIT_LENDING') AS rabbit_lending_charge_count,
      ARRAY_AGG(DISTINCT CONCAT(
        COALESCE(charges.payment_method, '<NULL>'), '|',
        COALESCE(charges.service_provider, '<NULL>')
      ) ORDER BY CONCAT(
        COALESCE(charges.payment_method, '<NULL>'), '|',
        COALESCE(charges.service_provider, '<NULL>')
      )) AS payment_pairs
    FROM `pacific-plating-282708.careos.careos_orders` AS orders
    JOIN `pacific-plating-282708.careos.careos_order_items` AS order_items
      ON order_items.order_id = orders.id
    JOIN `pacific-plating-282708.careos.carepay_transactions` AS transactions
      ON CONCAT('transactions/', transactions.id) = orders.payment
    JOIN `pacific-plating-282708.careos.carepay_charges` AS charges
      ON charges.transaction_id = transactions.id
     AND charges.status = 'SUCCESSFUL'
     AND charges.service_provider != 'ICOLLECTION'
    LEFT JOIN latest_snapshot
      ON latest_snapshot.transaction_id = transactions.id
    WHERE order_items.is_cancelled IS NOT TRUE
      AND order_items.cancel_time IS NULL
      AND GREATEST(
        DATE(orders.create_time, 'Asia/Bangkok'),
        COALESCE(
          DATE(order_items.policy_start_date, 'Asia/Bangkok'),
          DATE(orders.create_time, 'Asia/Bangkok')
        )
      ) >= DATE '2026-01-01'
      AND LOWER(TRIM(COALESCE(
        JSON_VALUE(orders.data, '$.policyHolder.firstName'),
        JSON_VALUE(orders.data, '$.policyHolder.policyAddress.companyName'),
        ''
      ))) != 'test'
      AND LOWER(TRIM(COALESCE(
        JSON_VALUE(orders.data, '$.policyHolder.lastName'), ''
      ))) != 'test'
    GROUP BY
      OrderID, OrderItem, product, InsuranceType, payment_option,
      transaction_status, number_of_installment, order_date, policy_date
  ),

  sap_items AS (
    SELECT DISTINCT U_OrderItem AS OrderItem
    FROM `pacific-plating-282708.sap_integration_v2.SAP_LIVE_FULL`
    WHERE U_OrderItem IS NOT NULL
  ),

  interface_items AS (
    SELECT DISTINCT OrderItem, view_name
    FROM (
      SELECT OrderItem, 'RCB_Motor_process_create' AS view_name
      FROM `pacific-plating-282708.sap_view.RCB_Motor_process_create`
      UNION ALL
      SELECT OrderItem, 'RCB_Motor_process_2_cancel_new'
      FROM `pacific-plating-282708.sap_view.RCB_Motor_process_2_cancel_new`
      UNION ALL
      SELECT OrderItem, 'RCB_Motor_process_3_change'
      FROM `pacific-plating-282708.sap_view.RCB_Motor_process_3_change`
      UNION ALL
      SELECT OrderItem, 'RCB_Motor_process_4_creditshell'
      FROM `pacific-plating-282708.sap_view.RCB_Motor_process_4_creditshell`
      UNION ALL
      SELECT OrderItem, 'RCL_Motor_process_1_create'
      FROM `pacific-plating-282708.sap_view.RCL_Motor_process_1_create`
      UNION ALL
      SELECT OrderItem, 'RCL_Motor_process_2_newpayment'
      FROM `pacific-plating-282708.sap_view.RCL_Motor_process_2_newpayment`
      UNION ALL
      SELECT OrderItem, 'RCL_Motor_process_3_cancel'
      FROM `pacific-plating-282708.sap_view.RCL_Motor_process_3_cancel`
      UNION ALL
      SELECT OrderItem, 'RCL_Motor_process_4_creditshell'
      FROM `pacific-plating-282708.sap_view.RCL_Motor_process_4_creditshell`
      UNION ALL
      SELECT OrderItem, 'RCB_NonMotor_process_1_create'
      FROM `pacific-plating-282708.sap_view.RCB_NonMotor_process_1_create`
      UNION ALL
      SELECT OrderItem, 'RCB_NonMotor_process_2_cancel'
      FROM `pacific-plating-282708.sap_view.RCB_NonMotor_process_2_cancel`
      UNION ALL
      SELECT OrderItem, 'RCL_NonMotor_process_1_create'
      FROM `pacific-plating-282708.sap_view.RCL_NonMotor_process_1_create`
      UNION ALL
      SELECT OrderItem, 'RCL_NonMotor_process_2_newpayment'
      FROM `pacific-plating-282708.sap_view.RCL_NonMotor_process_2_newpayment`
    )
  ),

  interface_rollup AS (
    SELECT
      OrderItem,
      ARRAY_AGG(DISTINCT view_name ORDER BY view_name) AS interface_views
    FROM interface_items
    GROUP BY OrderItem
  ),

  change_orders AS (
    SELECT DISTINCT current_human_id AS OrderID
    FROM `pacific-plating-282708.careos.cancelled_change_orders`
    WHERE current_human_id IS NOT NULL
  ),

  classified AS (
    SELECT
      candidate_items.*,
      CASE
        WHEN product = 'products/car-insurance' THEN 'Motor'
        WHEN product IN ('products/health-insurance', 'products/travel-insurance') THEN 'NonMotor'
        ELSE 'OtherProduct'
      END AS product_group,
      CASE
        WHEN payment_option = 'RABBIT_CARE_INSTALLMENT'
          OR rabbit_lending_charge_count > 0 THEN 'RCL'
        ELSE 'RCB'
      END AS expected_route,
      change_orders.OrderID IS NOT NULL AS is_change_order,
      sap_items.OrderItem IS NOT NULL AS in_sap,
      interface_rollup.OrderItem IS NOT NULL AS in_any_interface,
      interface_rollup.interface_views,
      CASE
        WHEN sap_items.OrderItem IS NOT NULL THEN 'ALREADY_IN_SAP'
        WHEN interface_rollup.OrderItem IS NOT NULL THEN 'IN_INTERFACE_NOW'
        WHEN product = 'products/health-insurance'
          AND change_orders.OrderID IS NOT NULL
          AND payment_option != 'RABBIT_CARE_INSTALLMENT'
          AND rabbit_lending_charge_count = 0 THEN 'KNOWN_MS01_RCB_HEALTH_CHANGE'
        WHEN product = 'products/health-insurance'
          AND payment_option = 'CREDIT_CARD_INSTALLMENT'
          AND rabbit_lending_charge_count = 0 THEN 'KNOWN_MS02_RCB_HEALTH_CARD_INSTALLMENT'
        ELSE 'MS05_CANDIDATE'
      END AS disposition
    FROM candidate_items
    LEFT JOIN sap_items USING (OrderItem)
    LEFT JOIN interface_rollup USING (OrderItem)
    LEFT JOIN change_orders USING (OrderID)
  )

SELECT
  disposition,
  expected_route,
  product_group,
  product,
  payment_option,
  transaction_status,
  is_change_order,
  number_of_installment,
  COUNT(*) AS item_count,
  COUNT(DISTINCT OrderID) AS order_count,
  SUM(successful_charge_count) AS successful_charge_count,
  MIN(order_date) AS earliest_order_date,
  MAX(order_date) AS latest_order_date,
  ARRAY_AGG(
    STRUCT(
      OrderID, OrderItem, InsuranceType, order_date, policy_date,
      successful_charge_count, payment_pairs, interface_views
    )
    ORDER BY OrderItem
    LIMIT 30
  ) AS samples
FROM classified
WHERE disposition NOT IN ('ALREADY_IN_SAP', 'IN_INTERFACE_NOW')
GROUP BY
  disposition, expected_route, product_group, product, payment_option,
  transaction_status, is_change_order, number_of_installment
ORDER BY disposition, item_count DESC, expected_route, product, payment_option;

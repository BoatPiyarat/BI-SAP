-- Read-only charge-driven coverage trace for current RCB NonMotor one-time items.
-- This intentionally starts from SUCCESSFUL CarePay charges rather than from the
-- legacy upstream views, so an upstream exclusion remains visible.

WITH
  candidate_items AS (
    SELECT
      orders.human_id AS OrderID,
      order_items.human_id AS OrderItem,
      order_items.product,
      DATE(orders.create_time) AS order_date,
      DATE(order_items.policy_start_date) AS policy_date,
      transactions.payment_option,
      COUNT(DISTINCT charges.id) AS successful_charge_count,
      ARRAY_AGG(DISTINCT CONCAT(
        COALESCE(charges.payment_method, '<NULL>'),
        '|',
        COALESCE(charges.service_provider, '<NULL>')
      )) AS successful_payment_pairs
    FROM `pacific-plating-282708.careos.careos_orders` AS orders
    JOIN `pacific-plating-282708.careos.careos_order_items` AS order_items
      ON order_items.order_id = orders.id
    JOIN `pacific-plating-282708.careos.carepay_transactions` AS transactions
      ON CONCAT('transactions/', transactions.id) = orders.payment
    JOIN `pacific-plating-282708.careos.carepay_charges` AS charges
      ON charges.transaction_id = transactions.id
    WHERE order_items.product IN (
        'products/health-insurance',
        'products/travel-insurance'
      )
      AND charges.status = 'SUCCESSFUL'
      AND charges.service_provider NOT IN ('RABBIT_LENDING', 'ICOLLECTION')
      AND order_items.is_cancelled IS NOT TRUE
      AND order_items.cancel_time IS NULL
      AND LOWER(TRIM(COALESCE(
        JSON_VALUE(orders.data, '$.policyHolder.firstName'),
        JSON_VALUE(orders.data, '$.policyHolder.policyAddress.companyName'),
        ''
      ))) != 'test'
      AND LOWER(TRIM(COALESCE(JSON_VALUE(orders.data, '$.policyHolder.lastName'), ''))) != 'test'
      AND GREATEST(
        DATE(orders.create_time),
        COALESCE(DATE(order_items.policy_start_date), DATE(orders.create_time))
      ) >= DATE '2026-01-01'
    GROUP BY
      OrderID, OrderItem, product, order_date, policy_date,
      transactions.payment_option
  ),

  upstream_items AS (
    SELECT DISTINCT OrderItem, 'RCB_HEALTH' AS source_name
    FROM `pacific-plating-282708.sap_data_engineer.RCB_HEALTH`
    UNION ALL
    SELECT DISTINCT OrderItem, 'RCB_TRAVEL' AS source_name
    FROM `pacific-plating-282708.sap_data_engineer.RCB_TRAVEL`
  ),

  target_items AS (
    SELECT DISTINCT OrderItem
    FROM `pacific-plating-282708.sap_view.RCB_NonMotor_process_1_create`
  ),

  sap_items AS (
    SELECT DISTINCT U_OrderItem AS OrderItem
    FROM `pacific-plating-282708.sap_integration_v2.SAP_LIVE_FULL`
  ),

  change_orders AS (
    SELECT DISTINCT current_human_id AS OrderID
    FROM `pacific-plating-282708.careos.cancelled_change_orders`
  ),

  classified AS (
    SELECT
      candidate_items.*,
      upstream_items.source_name,
      target_items.OrderItem IS NOT NULL AS in_target_view,
      sap_items.OrderItem IS NOT NULL AS in_sap,
      change_orders.OrderID IS NOT NULL AS is_change_order,
      CASE
        WHEN sap_items.OrderItem IS NOT NULL THEN 'ALREADY_IN_SAP'
        WHEN target_items.OrderItem IS NOT NULL THEN 'IN_TARGET_VIEW'
        WHEN change_orders.OrderID IS NOT NULL THEN 'CHANGE_ORDER_EXCLUDED_UPSTREAM'
        WHEN upstream_items.OrderItem IS NULL THEN 'MISSING_FROM_UPSTREAM'
        ELSE 'UPSTREAM_PRESENT_BUT_TARGET_MISSING'
      END AS disposition
    FROM candidate_items
    LEFT JOIN upstream_items USING (OrderItem)
    LEFT JOIN target_items USING (OrderItem)
    LEFT JOIN sap_items USING (OrderItem)
    LEFT JOIN change_orders USING (OrderID)
  )

SELECT
  COUNT(*) AS current_candidate_items,
  COUNTIF(in_sap) AS already_in_sap_items,
  COUNTIF(in_target_view) AS in_target_view_items,
  COUNTIF(NOT in_sap AND NOT in_target_view) AS absent_from_sap_and_target_items,
  COUNTIF(disposition = 'MISSING_FROM_UPSTREAM') AS missing_from_upstream_items,
  COUNTIF(disposition = 'UPSTREAM_PRESENT_BUT_TARGET_MISSING')
    AS upstream_present_but_target_missing_items,
  COUNTIF(disposition = 'CHANGE_ORDER_EXCLUDED_UPSTREAM')
    AS change_order_excluded_items,
  ARRAY(
    SELECT AS STRUCT
      disposition, product, payment_option,
      COUNT(*) AS item_count,
      COUNT(DISTINCT OrderID) AS order_count
    FROM classified
    GROUP BY disposition, product, payment_option
    ORDER BY disposition, item_count DESC, product, payment_option
  ) AS disposition_breakdown,
  ARRAY(
    SELECT AS STRUCT
      OrderID, OrderItem, product, order_date, policy_date,
      payment_option, successful_charge_count, successful_payment_pairs,
      source_name, is_change_order, disposition
    FROM classified
    WHERE NOT in_sap AND NOT in_target_view
    ORDER BY disposition, OrderItem
    LIMIT 100
  ) AS uncovered_samples
FROM classified;

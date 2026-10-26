-- Read-only proof for the first missing-scenario inventory candidate:
-- RCB NonMotor replacement/new-order items created through a Change/CreditShell relation.

WITH
  scoped_items AS (
    SELECT OrderItem
    FROM UNNEST([
      'L80720286-1',
      'L80797823-1',
      'L80799909-1'
    ]) AS OrderItem
  ),

  item_detail AS (
    SELECT
      order_items.human_id AS OrderItem,
      orders.human_id AS OrderID,
      changes.old_human_id AS RefOrder,
      order_items.product,
      order_items.is_cancelled,
      order_items.cancel_time,
      transactions.payment_option,
      transactions.status AS transaction_status,
      COUNT(DISTINCT IF(charges.status = 'SUCCESSFUL', charges.id, NULL))
        AS successful_charge_count,
      ARRAY_AGG(DISTINCT CONCAT(
        COALESCE(charges.payment_method, '<NULL>'),
        '|',
        COALESCE(charges.service_provider, '<NULL>')
      ) IGNORE NULLS) AS successful_payment_pairs
    FROM scoped_items
    JOIN `pacific-plating-282708.careos.careos_order_items` AS order_items
      ON order_items.human_id = scoped_items.OrderItem
    JOIN `pacific-plating-282708.careos.careos_orders` AS orders
      ON orders.id = order_items.order_id
    JOIN `pacific-plating-282708.careos.cancelled_change_orders` AS changes
      ON changes.current_human_id = orders.human_id
    LEFT JOIN `pacific-plating-282708.careos.carepay_transactions` AS transactions
      ON CONCAT('transactions/', transactions.id) = orders.payment
    LEFT JOIN `pacific-plating-282708.careos.carepay_charges` AS charges
      ON charges.transaction_id = transactions.id
      AND charges.status = 'SUCCESSFUL'
    GROUP BY
      OrderItem, OrderID, RefOrder, order_items.product,
      order_items.is_cancelled, order_items.cancel_time,
      transactions.payment_option, transactions.status
  ),

  interface_membership AS (
    SELECT 'RCB_Motor_process_create' AS view_name, OrderItem
    FROM `pacific-plating-282708.sap_view.RCB_Motor_process_create`
    WHERE OrderItem IN (SELECT OrderItem FROM scoped_items)
    UNION ALL
    SELECT 'RCB_Motor_process_2_cancel_new', OrderItem
    FROM `pacific-plating-282708.sap_view.RCB_Motor_process_2_cancel_new`
    WHERE OrderItem IN (SELECT OrderItem FROM scoped_items)
    UNION ALL
    SELECT 'RCB_Motor_process_3_change', OrderItem
    FROM `pacific-plating-282708.sap_view.RCB_Motor_process_3_change`
    WHERE OrderItem IN (SELECT OrderItem FROM scoped_items)
    UNION ALL
    SELECT 'RCB_Motor_process_4_creditshell', OrderItem
    FROM `pacific-plating-282708.sap_view.RCB_Motor_process_4_creditshell`
    WHERE OrderItem IN (SELECT OrderItem FROM scoped_items)
    UNION ALL
    SELECT 'RCL_Motor_process_1_create', OrderItem
    FROM `pacific-plating-282708.sap_view.RCL_Motor_process_1_create`
    WHERE OrderItem IN (SELECT OrderItem FROM scoped_items)
    UNION ALL
    SELECT 'RCL_Motor_process_2_newpayment', OrderItem
    FROM `pacific-plating-282708.sap_view.RCL_Motor_process_2_newpayment`
    WHERE OrderItem IN (SELECT OrderItem FROM scoped_items)
    UNION ALL
    SELECT 'RCL_Motor_process_3_cancel', OrderItem
    FROM `pacific-plating-282708.sap_view.RCL_Motor_process_3_cancel`
    WHERE OrderItem IN (SELECT OrderItem FROM scoped_items)
    UNION ALL
    SELECT 'RCL_Motor_process_4_creditshell', OrderItem
    FROM `pacific-plating-282708.sap_view.RCL_Motor_process_4_creditshell`
    WHERE OrderItem IN (SELECT OrderItem FROM scoped_items)
    UNION ALL
    SELECT 'RCB_NonMotor_process_1_create', OrderItem
    FROM `pacific-plating-282708.sap_view.RCB_NonMotor_process_1_create`
    WHERE OrderItem IN (SELECT OrderItem FROM scoped_items)
    UNION ALL
    SELECT 'RCB_NonMotor_process_2_cancel', OrderItem
    FROM `pacific-plating-282708.sap_view.RCB_NonMotor_process_2_cancel`
    WHERE OrderItem IN (SELECT OrderItem FROM scoped_items)
    UNION ALL
    SELECT 'RCL_NonMotor_process_1_create', OrderItem
    FROM `pacific-plating-282708.sap_view.RCL_NonMotor_process_1_create`
    WHERE OrderItem IN (SELECT OrderItem FROM scoped_items)
    UNION ALL
    SELECT 'RCL_NonMotor_process_2_newpayment', OrderItem
    FROM `pacific-plating-282708.sap_view.RCL_NonMotor_process_2_newpayment`
    WHERE OrderItem IN (SELECT OrderItem FROM scoped_items)
  ),

  current_sap AS (
    SELECT DISTINCT U_OrderItem AS OrderItem
    FROM `pacific-plating-282708.sap_integration_v2.SAP_LIVE_FULL`
    WHERE U_OrderItem IN (SELECT OrderItem FROM scoped_items)
  ),

  predecessor_sap AS (
    SELECT DISTINCT item_detail.OrderItem
    FROM item_detail
    JOIN `pacific-plating-282708.sap_integration_v2.SAP_LIVE_FULL` AS sap
      ON sap.U_OrderID = item_detail.RefOrder
  )

SELECT
  COUNT(*) AS scoped_items,
  COUNTIF(product != 'products/car-insurance') AS nonmotor_items,
  COUNTIF(transaction_status = 'SUCCESSFUL') AS successful_transaction_items,
  COUNTIF(successful_charge_count > 0) AS items_with_successful_charge,
  COUNTIF(is_cancelled IS TRUE OR cancel_time IS NOT NULL) AS cancelled_new_items,
  (SELECT COUNT(DISTINCT OrderItem) FROM current_sap) AS current_items_in_sap,
  (SELECT COUNT(DISTINCT OrderItem) FROM predecessor_sap) AS items_with_predecessor_in_sap,
  (SELECT COUNT(DISTINCT OrderItem) FROM interface_membership) AS items_in_any_sap_view,
  ARRAY(
    SELECT AS STRUCT view_name, COUNT(DISTINCT OrderItem) AS item_count
    FROM interface_membership
    GROUP BY view_name
    ORDER BY view_name
  ) AS interface_memberships,
  ARRAY(
    SELECT AS STRUCT *
    FROM item_detail
    ORDER BY OrderItem
  ) AS item_detail
FROM item_detail;

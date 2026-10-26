-- Read-only proof for the 23 current Health CREDIT_CARD_INSTALLMENT items that
-- have a SUCCESSFUL RCB charge but are absent from RCB_HEALTH and SAP.

WITH
  scoped_items AS (
    SELECT OrderItem
    FROM UNNEST([
      'L78942256-1', 'L79054575-1', 'L79843011-1', 'L80510945-1',
      'L80511058-1', 'L80511060-1', 'L80511303-1', 'L80511320-1',
      'L80511606-1', 'L80512448-1', 'L80512459-1', 'L80512507-1',
      'L80512573-1', 'L80632226-1', 'L80680870-1', 'L80680918-1',
      'L80728451-1', 'L80739961-1', 'L80768434-1', 'L80769993-1',
      'L80770034-1', 'L80783263-1', 'L80784046-1'
    ]) AS OrderItem
  ),

  source_trace AS (
    SELECT
      scoped_items.OrderItem,
      orders.human_id AS OrderID,
      orders.is_fully_paid,
      transactions.id AS transaction_id,
      transactions.status AS transaction_status,
      transactions.payment_option,
      COUNT(DISTINCT IF(charges.status = 'SUCCESSFUL', charges.id, NULL))
        AS successful_charge_count,
      COUNT(DISTINCT follow_ups.id) AS follow_up_count,
      ARRAY_AGG(DISTINCT transaction_snapshots.number_of_installment IGNORE NULLS)
        AS snapshot_installment_counts,
      COUNTIF(transaction_snapshots.number_of_installment = 1) > 0
        AS has_one_installment_snapshot
    FROM scoped_items
    JOIN `pacific-plating-282708.careos.careos_order_items` AS order_items
      ON order_items.human_id = scoped_items.OrderItem
    JOIN `pacific-plating-282708.careos.careos_orders` AS orders
      ON orders.id = order_items.order_id
    JOIN `pacific-plating-282708.careos.carepay_transactions` AS transactions
      ON CONCAT('transactions/', transactions.id) = orders.payment
    LEFT JOIN `pacific-plating-282708.careos.carepay_charges` AS charges
      ON charges.transaction_id = transactions.id
      AND charges.service_provider != 'ICOLLECTION'
    LEFT JOIN `pacific-plating-282708.careos.carepay_follow_ups` AS follow_ups
      ON follow_ups.transaction_id = transactions.id
    LEFT JOIN `pacific-plating-282708.careos.carepay_transaction_snapshots`
      AS transaction_snapshots
      ON transaction_snapshots.transaction_id = transactions.id
    GROUP BY
      scoped_items.OrderItem, OrderID, orders.is_fully_paid,
      transactions.id, transactions.status, transactions.payment_option
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

  sap_membership AS (
    SELECT DISTINCT U_OrderItem AS OrderItem
    FROM `pacific-plating-282708.sap_integration_v2.SAP_LIVE_FULL`
    WHERE U_OrderItem IN (SELECT OrderItem FROM scoped_items)
  )

SELECT
  COUNT(*) AS scoped_items,
  COUNTIF(is_fully_paid IS TRUE) AS fully_paid_items,
  COUNTIF(transaction_status = 'SUCCESSFUL') AS successful_transaction_items,
  COUNTIF(payment_option = 'CREDIT_CARD_INSTALLMENT') AS credit_card_installment_items,
  COUNTIF(successful_charge_count > 0) AS items_with_successful_charge,
  COUNTIF(follow_up_count = 0) AS items_without_follow_up,
  COUNTIF(has_one_installment_snapshot) AS items_with_one_installment_snapshot,
  (SELECT COUNT(DISTINCT OrderItem) FROM sap_membership) AS items_in_sap,
  (SELECT COUNT(DISTINCT OrderItem) FROM interface_membership) AS items_in_any_sap_view,
  ARRAY(
    SELECT AS STRUCT view_name, COUNT(DISTINCT OrderItem) AS item_count
    FROM interface_membership
    GROUP BY view_name
    ORDER BY view_name
  ) AS interface_memberships,
  ARRAY(
    SELECT AS STRUCT *
    FROM source_trace
    ORDER BY OrderItem
  ) AS source_detail
FROM source_trace;

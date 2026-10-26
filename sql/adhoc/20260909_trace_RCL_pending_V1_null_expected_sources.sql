-- Root-source trace for the pending V1 rows reproduced with NULL ExpectedReceived.

WITH
  affected AS (
    SELECT DISTINCT OrderID, OrderItem
    FROM `pacific-plating-282708.sap_data_engineer.sap_dashboard_carepay_installment`
    WHERE COALESCE(InsuranceType, '') != 'MOTOR_TYPE_COMPULSORY'
      AND SAFE_CAST(TotalPeriods AS INT64) > 1
      AND LOWER(COALESCE(TransactionStatus, 'pending')) = 'pending'
      AND SAFE_CAST(ExpectedReceived AS FLOAT64) IS NULL
      AND OrderItem NOT IN (
        SELECT U_OrderItem
        FROM `pacific-plating-282708.sap_integration_v2.SAP_LIVE_FULL`
      )
      AND OrderID NOT IN (
        SELECT current_human_id
        FROM `pacific-plating-282708.careos.cancelled_change_orders`
      )
      AND OrderDate NOT LIKE '%2023%'
      AND OrderDate NOT LIKE '%2024%'
      AND InsurerCode NOT IN ('45', '49')
      AND LOWER(TRIM(COALESCE(FirstName, ''))) != 'test'
      AND LOWER(TRIM(COALESCE(LastName, ''))) != 'test'
  ),

  item_transactions AS (
    SELECT
      affected.OrderID,
      affected.OrderItem,
      transactions.id AS transaction_id,
      transactions.status AS transaction_status,
      transactions.payment_option
    FROM affected
    JOIN `pacific-plating-282708.careos.careos_order_items` AS order_items
      ON order_items.human_id = affected.OrderItem
    JOIN `pacific-plating-282708.careos.careos_orders` AS orders
      ON orders.id = order_items.order_id
     AND orders.human_id = affected.OrderID
    JOIN `pacific-plating-282708.careos.carepay_transactions` AS transactions
      ON CONCAT('transactions/', transactions.id) = orders.payment
  ),

  snapshot_detail AS (
    SELECT
      item_transactions.*,
      snapshots.id AS snapshot_id,
      snapshots.is_current,
      snapshots.number_of_installment,
      snapshots.create_time AS snapshot_create_time,
      snapshots.update_time AS snapshot_update_time,
      ROW_NUMBER() OVER (
        PARTITION BY item_transactions.OrderItem
        ORDER BY snapshots.update_time DESC, snapshots.id DESC
      ) AS snapshot_rank,
      COUNT(details.id) AS detail_rows,
      COUNT(DISTINCT details.period) AS detail_periods,
      COUNTIF(details.payment_amount IS NULL) AS null_payment_amount_rows,
      MIN(details.period) AS min_detail_period,
      MAX(details.period) AS max_detail_period,
      ARRAY_AGG(details.period IGNORE NULLS ORDER BY details.period) AS detail_period_list,
      ARRAY_AGG(details.payment_amount IGNORE NULLS ORDER BY details.period) AS payment_amount_list
    FROM item_transactions
    JOIN `pacific-plating-282708.careos.carepay_transaction_snapshots` AS snapshots
      ON snapshots.transaction_id = item_transactions.transaction_id
    LEFT JOIN `pacific-plating-282708.careos.carepay_transaction_snapshot_installment_details`
      AS details
      ON details.snapshot_id = snapshots.id
    GROUP BY
      OrderID, OrderItem, transaction_id, transaction_status, payment_option,
      snapshot_id, is_current, number_of_installment,
      snapshot_create_time, snapshot_update_time
  ),

  followup_rollup AS (
    SELECT
      item_transactions.OrderItem,
      COUNT(follow_ups.id) AS followup_rows,
      COUNT(DISTINCT follow_ups.installment) AS followup_periods,
      COUNTIF(follow_ups.due_date IS NULL) AS null_due_date_rows,
      MIN(follow_ups.installment) AS min_followup_period,
      MAX(follow_ups.installment) AS max_followup_period,
      MIN(DATE(follow_ups.due_date)) AS first_due_date,
      ARRAY_AGG(follow_ups.installment IGNORE NULLS ORDER BY follow_ups.installment)
        AS followup_period_list
    FROM item_transactions
    LEFT JOIN `pacific-plating-282708.careos.carepay_follow_ups` AS follow_ups
      ON follow_ups.transaction_id = item_transactions.transaction_id
    GROUP BY item_transactions.OrderItem
  )

SELECT
  snapshot_detail.*,
  followup_rollup.* EXCEPT (OrderItem)
FROM snapshot_detail
LEFT JOIN followup_rollup USING (OrderItem)
ORDER BY OrderItem, snapshot_rank;

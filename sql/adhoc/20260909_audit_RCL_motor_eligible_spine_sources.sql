-- Read-only completeness audit for true RCL Motor installment transactions.
-- Eligibility: RABBIT_CARE_INSTALLMENT plus at least one SUCCESSFUL RABBIT_LENDING charge.

WITH
  latest_snapshot AS (
    SELECT *
    FROM `pacific-plating-282708.careos.carepay_transaction_snapshots`
    QUALIFY ROW_NUMBER() OVER (
      PARTITION BY transaction_id
      ORDER BY update_time DESC, id DESC
    ) = 1
  ),

  detail_rollup AS (
    SELECT
      snapshot_id,
      COUNT(*) AS detail_rows,
      COUNT(DISTINCT period) AS detail_periods,
      COUNTIF(payment_amount IS NULL) AS null_payment_amount_rows,
      MIN(period) AS min_period,
      MAX(period) AS max_period
    FROM `pacific-plating-282708.careos.carepay_transaction_snapshot_installment_details`
    GROUP BY snapshot_id
  ),

  followup_rollup AS (
    SELECT
      transaction_id,
      COUNT(*) AS followup_rows,
      COUNT(DISTINCT installment) AS followup_periods,
      MIN(DATE(due_date)) AS first_due_date
    FROM `pacific-plating-282708.careos.carepay_follow_ups`
    GROUP BY transaction_id
  ),

  eligible AS (
    SELECT DISTINCT
      orders.human_id AS OrderID,
      order_items.human_id AS OrderItem,
      transactions.id AS transaction_id,
      transactions.status AS transaction_status,
      latest_snapshot.id AS snapshot_id,
      latest_snapshot.number_of_installment AS total_periods,
      COALESCE(detail_rollup.detail_rows, 0) AS detail_rows,
      COALESCE(detail_rollup.detail_periods, 0) AS detail_periods,
      COALESCE(detail_rollup.null_payment_amount_rows, 0) AS null_payment_amount_rows,
      detail_rollup.min_period,
      detail_rollup.max_period,
      COALESCE(followup_rollup.followup_rows, 0) AS followup_rows,
      COALESCE(followup_rollup.followup_periods, 0) AS followup_periods,
      followup_rollup.first_due_date
    FROM `pacific-plating-282708.careos.careos_orders` AS orders
    JOIN `pacific-plating-282708.careos.careos_order_items` AS order_items
      ON order_items.order_id = orders.id
    JOIN `pacific-plating-282708.careos.carepay_transactions` AS transactions
      ON CONCAT('transactions/', transactions.id) = orders.payment
     AND transactions.payment_option = 'RABBIT_CARE_INSTALLMENT'
    JOIN latest_snapshot
      ON latest_snapshot.transaction_id = transactions.id
     AND latest_snapshot.number_of_installment > 1
    JOIN (
      SELECT DISTINCT transaction_id
      FROM `pacific-plating-282708.careos.carepay_charges`
      WHERE status = 'SUCCESSFUL'
        AND service_provider = 'RABBIT_LENDING'
    ) AS successful_rcl_charge
      ON successful_rcl_charge.transaction_id = transactions.id
    LEFT JOIN detail_rollup
      ON detail_rollup.snapshot_id = latest_snapshot.id
    LEFT JOIN followup_rollup
      ON followup_rollup.transaction_id = transactions.id
    WHERE order_items.product = 'products/car-insurance'
      AND order_items.motor_item_type != 'MOTOR_TYPE_COMPULSORY'
      AND order_items.is_cancelled IS NOT TRUE
      AND order_items.cancel_time IS NULL
  )

SELECT
  COUNT(*) AS eligible_v1_items,
  COUNTIF(
    detail_periods != total_periods
    OR min_period != 1
    OR max_period != total_periods
    OR null_payment_amount_rows > 0
  ) AS incomplete_detail_items,
  COUNTIF(first_due_date IS NULL) AS missing_first_due_date_items,
  COUNTIF(
    detail_periods = total_periods
    AND min_period = 1
    AND max_period = total_periods
    AND null_payment_amount_rows = 0
  ) AS complete_detail_items,
  ARRAY_AGG(
    IF(
      detail_periods != total_periods
        OR min_period != 1
        OR max_period != total_periods
        OR null_payment_amount_rows > 0
        OR first_due_date IS NULL,
      STRUCT(
        OrderID, OrderItem, transaction_id, transaction_status,
        total_periods, detail_rows, detail_periods,
        null_payment_amount_rows, min_period, max_period,
        followup_rows, followup_periods, first_due_date
      ),
      NULL
    ) IGNORE NULLS
    ORDER BY OrderItem
    LIMIT 50
  ) AS incomplete_samples
FROM eligible;

-- Read-only red/green audit at the snapshot join seam used by
-- sap_integration_v2.04_new order credit shell.

WITH successful_charges AS (
  SELECT transaction_id, COUNT(*) AS successful_charge_count
  FROM `pacific-plating-282708.careos.carepay_charges`
  WHERE status = 'SUCCESSFUL'
    AND service_provider != 'RABBIT_LENDING'
  GROUP BY transaction_id
),
eligible AS (
  SELECT DISTINCT
    transactions.id AS transaction_id,
    orders.human_id AS OrderID,
    order_items.human_id AS OrderItem,
    successful_charges.successful_charge_count
  FROM `pacific-plating-282708.careos.careos_orders` AS orders
  JOIN `pacific-plating-282708.careos.cancelled_change_orders` AS changes
    ON changes.current_human_id = orders.human_id
  JOIN `pacific-plating-282708.careos.carepay_transactions` AS transactions
    ON CONCAT('transactions/', transactions.id) = orders.payment
  JOIN successful_charges
    ON successful_charges.transaction_id = transactions.id
  JOIN `pacific-plating-282708.careos.careos_order_items` AS order_items
    ON order_items.order_id = orders.id
  WHERE orders.product = 'products/car-insurance'
    AND order_items.policy_start_date >= '2025-01-01'
),
snapshot_stats AS (
  SELECT
    transaction_id,
    COUNT(*) AS snapshot_count,
    COUNT(DISTINCT number_of_installment) AS installment_versions,
    ARRAY_AGG(
      STRUCT(id AS snapshot_id, number_of_installment, update_time)
      ORDER BY update_time DESC, id DESC
      LIMIT 10
    ) AS snapshots
  FROM `pacific-plating-282708.careos.carepay_transaction_snapshots`
  GROUP BY transaction_id
),
fanout AS (
  SELECT eligible.*, snapshot_stats.* EXCEPT (transaction_id)
  FROM eligible
  JOIN snapshot_stats
    USING (transaction_id)
  WHERE snapshot_stats.snapshot_count > 1
)

SELECT
  (SELECT COUNT(DISTINCT transaction_id) FROM eligible) AS eligible_transactions,
  (SELECT COUNT(DISTINCT OrderItem) FROM eligible) AS eligible_items,
  (SELECT COUNT(DISTINCT transaction_id) FROM fanout) AS multi_snapshot_transactions,
  (SELECT COUNT(DISTINCT OrderItem) FROM fanout) AS multi_snapshot_items,
  (SELECT COUNT(DISTINCT transaction_id) FROM fanout WHERE installment_versions > 1)
    AS conflicting_installment_transactions,
  ARRAY(
    SELECT AS STRUCT
      transaction_id,
      OrderID,
      OrderItem,
      successful_charge_count,
      snapshot_count,
      installment_versions,
      snapshots
    FROM fanout
    ORDER BY snapshot_count DESC, OrderItem
    LIMIT 50
  ) AS fanout_samples;

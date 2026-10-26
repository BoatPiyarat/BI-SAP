-- Read-only raw trace for RCB CreditShell rows whose Period is not compatible with TotalPeriods=1.

WITH ranked_charges AS (
  SELECT
    charges.*,
    ROW_NUMBER() OVER (
      PARTITION BY transaction_id
      ORDER BY create_time, id
    ) AS charge_rank
  FROM `pacific-plating-282708.careos.carepay_charges` AS charges
  WHERE status = 'SUCCESSFUL'
    AND service_provider != 'RABBIT_LENDING'
),
snapshot_stats AS (
  SELECT
    transaction_id,
    COUNT(*) AS snapshot_count,
    COUNT(DISTINCT number_of_installment) AS snapshot_installment_versions,
    MAX(number_of_installment) AS max_snapshot_installments
  FROM `pacific-plating-282708.careos.carepay_transaction_snapshots`
  GROUP BY transaction_id
),
sap_items AS (
  SELECT DISTINCT U_OrderItem AS OrderItem
  FROM `pacific-plating-282708.sap_integration_v2.SAP_LIVE_FULL`
)

SELECT
  orders.human_id AS OrderID,
  order_items.human_id AS OrderItem,
  transactions.id AS transaction_id,
  transactions.payment_option,
  ranked_charges.id AS charge_id,
  ranked_charges.third_party_id,
  ranked_charges.installment_number,
  ranked_charges.payment_method,
  ranked_charges.service_provider,
  ranked_charges.amount,
  ranked_charges.charge_rank,
  order_items.motor_item_type,
  order_items.packagetype,
  snapshot_stats.snapshot_count,
  snapshot_stats.snapshot_installment_versions,
  snapshot_stats.max_snapshot_installments,
  sap_items.OrderItem IS NOT NULL AS already_in_sap
FROM `pacific-plating-282708.careos.careos_orders` AS orders
JOIN `pacific-plating-282708.careos.cancelled_change_orders` AS changes
  ON changes.current_human_id = orders.human_id
JOIN `pacific-plating-282708.careos.carepay_transactions` AS transactions
  ON CONCAT('transactions/', transactions.id) = orders.payment
JOIN ranked_charges
  ON ranked_charges.transaction_id = transactions.id
JOIN `pacific-plating-282708.careos.careos_order_items` AS order_items
  ON order_items.order_id = orders.id
LEFT JOIN snapshot_stats
  ON snapshot_stats.transaction_id = transactions.id
LEFT JOIN sap_items
  ON sap_items.OrderItem = order_items.human_id
WHERE orders.product = 'products/car-insurance'
  AND order_items.policy_start_date >= '2025-01-01'
  AND ranked_charges.service_provider != 'ICOLLECTION'
  AND SAFE_CAST(ranked_charges.installment_number AS INT64) != 1
ORDER BY OrderItem, ranked_charges.charge_rank, charge_id;

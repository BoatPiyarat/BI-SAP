-- Read-only coverage audit for the RABBIT_CARE_INSTALLMENT items removed from RCB CreditShell.

WITH rcb_rcl_items AS (
  SELECT DISTINCT upstream.OrderItem
  FROM `pacific-plating-282708.sap_integration_v2.04_new order credit shell` AS upstream
  JOIN `pacific-plating-282708.careos.careos_order_items` AS order_items
    ON order_items.human_id = upstream.OrderItem
  JOIN `pacific-plating-282708.careos.careos_orders` AS orders
    ON orders.id = order_items.order_id
  JOIN `pacific-plating-282708.careos.carepay_transactions` AS transactions
    ON CONCAT('transactions/', transactions.id) = orders.payment
  WHERE transactions.payment_option = 'RABBIT_CARE_INSTALLMENT'
),
rcl_upstream_items AS (
  SELECT DISTINCT OrderItem
  FROM `pacific-plating-282708.sap_integration_v2.RCL 04_new order credit shell`
),
sap_items AS (
  SELECT DISTINCT U_OrderItem AS OrderItem
  FROM `pacific-plating-282708.sap_integration_v2.SAP_LIVE_FULL`
),
coverage AS (
  SELECT
    rcb_rcl_items.OrderItem,
    rcl_upstream_items.OrderItem IS NOT NULL AS in_rcl_creditshell_upstream,
    sap_items.OrderItem IS NOT NULL AS already_in_sap
  FROM rcb_rcl_items
  LEFT JOIN rcl_upstream_items USING (OrderItem)
  LEFT JOIN sap_items USING (OrderItem)
)

SELECT
  COUNT(*) AS removed_rcl_items,
  COUNTIF(in_rcl_creditshell_upstream) AS in_rcl_creditshell_upstream,
  COUNTIF(already_in_sap) AS already_in_sap,
  COUNTIF(NOT in_rcl_creditshell_upstream AND NOT already_in_sap) AS uncovered_items,
  ARRAY_AGG(
    IF(NOT in_rcl_creditshell_upstream AND NOT already_in_sap, OrderItem, NULL)
    IGNORE NULLS
    ORDER BY OrderItem
    LIMIT 100
  ) AS uncovered_item_samples
FROM coverage;

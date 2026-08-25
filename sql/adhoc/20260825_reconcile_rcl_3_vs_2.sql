-- READ ONLY reconciliation. The original population scan found 3 RCL/RABBIT_CARE_INSTALLMENT
-- affected order_items; the 082 view-body reproduction found only 2. Identify the 3rd and why.
WITH affected_snapshots AS (
  SELECT ts.id AS snapshot_id, ts.transaction_id, ts.number_of_installment
  FROM `pacific-plating-282708.careos.carepay_transaction_snapshots` ts
  WHERE ts.number_of_installment > 1
    AND NOT EXISTS (
      SELECT 1 FROM `pacific-plating-282708.careos.carepay_transaction_snapshot_installment_details` d
      WHERE d.snapshot_id = ts.id)
  QUALIFY ROW_NUMBER() OVER (PARTITION BY ts.transaction_id ORDER BY ts.update_time DESC, ts.id DESC) = 1
),
affected_orders AS (
  SELECT DISTINCT o.human_id AS order_item, o.order_id, t.payment_option, s.number_of_installment,
    s.transaction_id
  FROM affected_snapshots s
  JOIN `pacific-plating-282708.careos.carepay_transactions` t ON t.id = s.transaction_id
  JOIN `pacific-plating-282708.careos.careos_orders` ord ON ord.payment = CONCAT('transactions/', t.id)
  JOIN `pacific-plating-282708.careos.careos_order_items` o ON o.order_id = ord.id
)
SELECT ao.order_item, ao.transaction_id, ao.payment_option, ao.number_of_installment,
  sc.flow, sc.total_periods
FROM affected_orders ao
LEFT JOIN `pacific-plating-282708.sap_integration_v3.stg_schedule` sc ON sc.order_item = ao.order_item
WHERE ao.payment_option = 'RABBIT_CARE_INSTALLMENT'
GROUP BY 1,2,3,4,5,6;

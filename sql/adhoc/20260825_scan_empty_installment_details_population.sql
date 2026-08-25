-- READ ONLY investigation. No mutation.
-- Scans for the L78753909-V1 defect pattern: a transaction_snapshot declaring
-- number_of_installment > 1 with ZERO rows in carepay_transaction_snapshot_installment_details.
-- Buckets by stg_schedule.flow to see whether any RCL-flow (genuine installment) items are
-- affected -- those would NOT be rescued by V3's independent ONETIME source path.
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
  SELECT DISTINCT o.human_id AS order_item, o.order_id, t.payment_option, s.number_of_installment
  FROM affected_snapshots s
  JOIN `pacific-plating-282708.careos.carepay_transactions` t ON t.id = s.transaction_id
  JOIN `pacific-plating-282708.careos.careos_orders` ord ON ord.payment = CONCAT('transactions/', t.id)
  JOIN `pacific-plating-282708.careos.careos_order_items` o ON o.order_id = ord.id
)
SELECT
  sc.flow,
  ao.payment_option,
  COUNT(DISTINCT ao.order_item) AS affected_items,
  COUNTIF(EXISTS(SELECT 1 FROM `pacific-plating-282708.sap_integration_v3.stg_sap_state` st
    WHERE st.U_OrderItem = ao.order_item AND IFNULL(st.U_InvoiceNo,'') != '')) AS already_in_sap
FROM affected_orders ao
LEFT JOIN `pacific-plating-282708.sap_integration_v3.stg_schedule` sc ON sc.order_item = ao.order_item
GROUP BY sc.flow, ao.payment_option
ORDER BY affected_items DESC;

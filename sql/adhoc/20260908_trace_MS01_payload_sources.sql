-- Read-only source proof for MS-01 before reusing
-- sap_view.RCB_NonMotor_process_2_cancel as the missing RCB NonMotor
-- new-order-after-change interface.

WITH
  scoped_items AS (
    SELECT OrderItem
    FROM UNNEST(['L80720286-1', 'L80797823-1', 'L80799909-1']) AS OrderItem
  ),
  latest_snapshot AS (
    SELECT *
    FROM `pacific-plating-282708.careos.carepay_transaction_snapshots`
    QUALIFY ROW_NUMBER() OVER (
      PARTITION BY transaction_id
      ORDER BY update_time DESC, create_time DESC, id DESC
    ) = 1
  )

SELECT
  oi.human_id AS OrderItem,
  o.human_id AS OrderID,
  chg.old_human_id AS RefOrder,
  t.id AS transaction_id,
  t.payment_option,
  t.status AS transaction_status,
  s.id AS snapshot_id,
  s.number_of_installment,
  ps.wht_amount,
  ps.interest_amount,
  ps.processing_fee_amount,
  ps.shipment_fee,
  ps.discount_amount,
  oi.product,
  oi.packagetype,
  oi.package,
  oi.insurer,
  oi.motor_item_type,
  oi.net_premium,
  oi.stamp_duty,
  oi.vat_amount,
  oi.gross_premium,
  oi.policy_start_date,
  oi.policy_number,
  c.id AS charge_id,
  c.third_party_id,
  c.status AS charge_status,
  c.amount AS charge_amount_satang,
  c.installment_number,
  c.payment_method,
  c.service_provider,
  c.create_time AS charge_create_time,
  c.update_time AS charge_update_time,
  c.payment_date,
  ROW_NUMBER() OVER (
    PARTITION BY oi.human_id
    ORDER BY COALESCE(c.payment_date, c.update_time, c.create_time), c.create_time, c.id
  ) AS item_charge_rank
FROM scoped_items x
JOIN `pacific-plating-282708.careos.careos_order_items` oi
  ON oi.human_id = x.OrderItem
JOIN `pacific-plating-282708.careos.careos_orders` o
  ON o.id = oi.order_id
JOIN `pacific-plating-282708.careos.cancelled_change_orders` chg
  ON chg.current_human_id = o.human_id
JOIN `pacific-plating-282708.careos.carepay_transactions` t
  ON CONCAT('transactions/', t.id) = o.payment
JOIN `pacific-plating-282708.careos.carepay_charges` c
  ON c.transaction_id = t.id
 AND c.status = 'SUCCESSFUL'
LEFT JOIN latest_snapshot s
  ON s.transaction_id = t.id
LEFT JOIN `pacific-plating-282708.careos.carepay_transaction_snapshot_price_summaries` ps
  ON ps.snapshot_id = s.id
ORDER BY OrderItem, item_charge_rank;

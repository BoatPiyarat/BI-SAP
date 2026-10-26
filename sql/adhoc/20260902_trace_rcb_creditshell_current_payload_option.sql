-- Read-only control: prove the currently exportable RCB CreditShell row is not an RCL payment.

SELECT
  payload.OrderID,
  payload.OrderItem,
  payload.InvoiceNo,
  payload.Period,
  payload.TotalPeriods,
  payload.PaymentMethod,
  payload.PaymentChannel,
  transactions.payment_option,
  snapshots.number_of_installment AS snapshot_installments
FROM `pacific-plating-282708.sap_view.RCB_Motor_process_4_creditshell` AS payload
JOIN `pacific-plating-282708.careos.careos_order_items` AS order_items
  ON order_items.human_id = payload.OrderItem
JOIN `pacific-plating-282708.careos.careos_orders` AS orders
  ON orders.id = order_items.order_id
JOIN `pacific-plating-282708.careos.carepay_transactions` AS transactions
  ON CONCAT('transactions/', transactions.id) = orders.payment
LEFT JOIN `pacific-plating-282708.careos.carepay_transaction_snapshots` AS snapshots
  ON snapshots.transaction_id = transactions.id
QUALIFY ROW_NUMBER() OVER (
  PARTITION BY payload.OrderItem, payload.InvoiceNo
  ORDER BY snapshots.update_time DESC, snapshots.id DESC
) = 1;

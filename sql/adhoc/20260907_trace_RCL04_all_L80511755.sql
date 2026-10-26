-- Red-capable, read-only gate trace for the missing legacy CreditShell order.
-- Target: pacific-plating-282708.sap_integration_v2.RCL 04_new order credit shell_all

WITH
target_order AS (
  SELECT id, human_id, payment, create_time, product, lead
  FROM `pacific-plating-282708.careos.careos_orders`
  WHERE human_id = 'L80511755'
),

target_transaction AS (
  SELECT t.id, t.status, t.payment_option, t.installments
  FROM `pacific-plating-282708.careos.carepay_transactions` t
  JOIN target_order o
    ON o.payment = CONCAT('transactions/', t.id)
),

target_items AS (
  SELECT
    i.id,
    i.human_id,
    i.motor_item_type,
    i.product,
    i.policy_start_date,
    i.is_cancelled,
    i.cancel_time
  FROM `pacific-plating-282708.careos.careos_order_items` i
  JOIN target_order o ON i.order_id = o.id
),

target_snapshots AS (
  SELECT s.id, s.transaction_id, s.number_of_installment, s.create_time
  FROM `pacific-plating-282708.careos.carepay_transaction_snapshots` s
  JOIN target_transaction t ON s.transaction_id = t.id
),

target_details AS (
  SELECT d.id, d.snapshot_id, d.period, d.payment_amount
  FROM `pacific-plating-282708.careos.carepay_transaction_snapshot_installment_details` d
  JOIN target_snapshots s ON d.snapshot_id = s.id
),

target_charges AS (
  SELECT
    c.id,
    c.transaction_id,
    c.installment_number,
    c.status,
    c.payment_method,
    c.service_provider,
    c.third_party_id,
    c.create_time,
    c.update_time
  FROM `pacific-plating-282708.careos.carepay_charges` c
  JOIN target_transaction t ON c.transaction_id = t.id
),

target_followups AS (
  SELECT f.transaction_id, f.installment, f.status, f.due_date
  FROM `pacific-plating-282708.careos.carepay_follow_ups` f
  JOIN target_transaction t ON f.transaction_id = t.id
),

target_changes AS (
  SELECT current_human_id, old_human_id
  FROM `pacific-plating-282708.careos.cancelled_change_orders`
  WHERE current_human_id = 'L80511755' OR old_human_id = 'L80511755'
),

branch_grain AS (
  SELECT DISTINCT
    i.human_id AS OrderItem,
    i.motor_item_type,
    d.period,
    EXISTS (
      SELECT 1
      FROM target_followups f
      WHERE f.transaction_id = t.id AND f.installment = d.period
    ) AS has_followup,
    EXISTS (
      SELECT 1
      FROM target_charges c
      WHERE c.transaction_id = t.id
        AND c.installment_number = d.period
        AND c.status NOT IN ('FAILED', 'PENDING')
    ) AS has_completed_charge
  FROM target_order o
  JOIN target_transaction t ON TRUE
  LEFT JOIN target_snapshots s ON s.transaction_id = t.id
  LEFT JOIN target_details d ON d.snapshot_id = s.id
  LEFT JOIN target_items i ON TRUE
),

live_result AS (
  SELECT OrderID, OrderItem, Period, TransactionStatus, PaymentChannel
  FROM `pacific-plating-282708.sap_integration_v2.RCL 04_new order credit shell_all`
  WHERE OrderID = 'L80511755'
),

live_primary_source AS (
  SELECT OrderID, OrderItem, Period, TransactionStatus, PaymentChannel
  FROM `pacific-plating-282708.sap_integration_v2.RCL 04_new order credit shell`
  WHERE OrderID = 'L80511755'
),

live_interface AS (
  SELECT OrderID, OrderItem, Period, TransactionStatus, PaymentChannel
  FROM `pacific-plating-282708.sap_view.RCL_Motor_process_4_creditshell`
  WHERE OrderID = 'L80511755'
),

sap_history AS (
  SELECT U_OrderID, U_OrderItem, U_Period, TransactionStatus, PaymentChannel, RefOrder
  FROM `pacific-plating-282708.sap_integration_v2.SAP_LIVE_FULL`
  WHERE U_OrderID = 'L80511755' OR RefOrder = 'L80511755'
)

SELECT
  CASE WHEN (SELECT COUNT(*) FROM live_result) = 0 THEN 'RED_MISSING_FROM_VIEW' ELSE 'GREEN_PRESENT' END AS verdict,
  (SELECT COUNT(*) FROM target_order) AS order_rows,
  (SELECT ANY_VALUE(STRUCT(human_id AS OrderID, payment, create_time, product)) FROM target_order) AS order_detail,
  (SELECT COUNT(*) FROM target_transaction) AS transaction_rows,
  (SELECT ARRAY_AGG(STRUCT(id, status, payment_option, installments)) FROM target_transaction) AS transaction_detail,
  (SELECT COUNT(*) FROM target_items) AS item_rows,
  (SELECT ARRAY_AGG(STRUCT(human_id AS OrderItem, motor_item_type, product, policy_start_date, is_cancelled, cancel_time)) FROM target_items) AS item_detail,
  (SELECT COUNT(*) FROM target_snapshots) AS snapshot_rows,
  (SELECT ARRAY_AGG(STRUCT(id, number_of_installment, create_time) ORDER BY create_time) FROM target_snapshots) AS snapshot_detail,
  (SELECT COUNT(*) FROM target_details) AS installment_detail_rows,
  (SELECT ARRAY_AGG(DISTINCT period ORDER BY period) FROM target_details) AS installment_periods,
  (SELECT COUNT(*) FROM target_charges) AS charge_rows,
  (SELECT COUNTIF(status = 'SUCCESSFUL') FROM target_charges) AS successful_charge_rows,
  (SELECT ARRAY_AGG(STRUCT(installment_number, status, payment_method, service_provider, third_party_id, update_time) ORDER BY create_time) FROM target_charges) AS charge_detail,
  (SELECT COUNT(*) FROM target_followups) AS followup_rows,
  (SELECT ARRAY_AGG(STRUCT(installment, status, due_date) ORDER BY installment) FROM target_followups) AS followup_detail,
  (SELECT COUNTIF(current_human_id = 'L80511755') FROM target_changes) AS change_current_rows,
  (SELECT COUNTIF(old_human_id = 'L80511755') FROM target_changes) AS change_old_rows,
  (SELECT ARRAY_AGG(STRUCT(current_human_id, old_human_id)) FROM target_changes) AS change_detail,
  (SELECT COUNTIF(period IS NOT NULL AND (motor_item_type != 'MOTOR_TYPE_COMPULSORY' OR motor_item_type IS NULL) AND NOT has_followup) FROM branch_grain) AS rcb_voluntary_gate_rows,
  (SELECT COUNTIF(period IS NOT NULL AND (motor_item_type != 'MOTOR_TYPE_COMPULSORY' OR motor_item_type IS NULL) AND has_followup) FROM branch_grain) AS rcl_voluntary_gate_rows,
  (SELECT COUNTIF(period = 1 AND motor_item_type = 'MOTOR_TYPE_COMPULSORY' AND has_completed_charge) FROM branch_grain) AS compulsory_gate_rows,
  (SELECT COUNT(*) FROM live_result) AS live_view_rows,
  (SELECT ARRAY_AGG(STRUCT(OrderItem, Period, TransactionStatus, PaymentChannel)) FROM live_result) AS live_view_detail,
  (SELECT COUNT(*) FROM live_primary_source) AS live_primary_source_rows,
  (SELECT ARRAY_AGG(STRUCT(OrderItem, Period, TransactionStatus, PaymentChannel)) FROM live_primary_source) AS live_primary_source_detail,
  (SELECT COUNT(*) FROM live_interface) AS live_interface_rows,
  (SELECT ARRAY_AGG(STRUCT(OrderItem, Period, TransactionStatus, PaymentChannel)) FROM live_interface) AS live_interface_detail,
  (SELECT COUNT(*) FROM sap_history) AS sap_history_rows,
  (SELECT ARRAY_AGG(STRUCT(U_OrderID, U_OrderItem, U_Period, TransactionStatus, PaymentChannel, RefOrder)) FROM sap_history) AS sap_history_detail;

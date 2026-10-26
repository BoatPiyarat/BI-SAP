-- Read-only trace for the only remaining active 2026 successful-charge item
-- absent from SAP and all 12 current interface views after MS-01/MS-02/MS-05.

WITH
  order_trace AS (
    SELECT
      orders.id AS order_key,
      orders.human_id AS OrderID,
      order_items.human_id AS OrderItem,
      order_items.product,
      order_items.motor_item_type,
      order_items.is_cancelled,
      order_items.cancel_time,
      order_items.policy_start_date,
      transactions.id AS transaction_id,
      transactions.payment_option,
      transactions.status AS transaction_status
    FROM `pacific-plating-282708.careos.careos_orders` AS orders
    JOIN `pacific-plating-282708.careos.careos_order_items` AS order_items
      ON order_items.order_id = orders.id
    LEFT JOIN `pacific-plating-282708.careos.carepay_transactions` AS transactions
      ON CONCAT('transactions/', transactions.id) = orders.payment
    WHERE orders.human_id = 'L80161278'
  ),

  charge_trace AS (
    SELECT
      charges.id AS charge_id,
      charges.transaction_id,
      charges.status,
      charges.installment_number,
      charges.third_party_id,
      charges.amount,
      charges.payment_method,
      charges.service_provider,
      charges.payment_date,
      charges.create_time,
      charges.update_time
    FROM `pacific-plating-282708.careos.carepay_charges` AS charges
    JOIN order_trace USING (transaction_id)
  ),

  snapshot_trace AS (
    SELECT
      snapshots.id AS snapshot_id,
      snapshots.transaction_id,
      snapshots.number_of_installment,
      snapshots.create_time,
      snapshots.update_time,
      COUNT(details.id) AS detail_rows,
      ARRAY_AGG(
        IF(
          details.id IS NULL,
          NULL,
          STRUCT(
            details.period,
            details.payment_amount,
            details.principal,
            details.interest,
            details.add_ons,
            details.principal_balance
          )
        ) IGNORE NULLS
        ORDER BY details.period
      ) AS details
    FROM `pacific-plating-282708.careos.carepay_transaction_snapshots` AS snapshots
    JOIN order_trace USING (transaction_id)
    LEFT JOIN `pacific-plating-282708.careos.carepay_transaction_snapshot_installment_details`
      AS details
      ON details.snapshot_id = snapshots.id
    GROUP BY
      snapshot_id, transaction_id, number_of_installment,
      create_time, update_time
  ),

  follow_up_trace AS (
    SELECT
      follow_ups.transaction_id,
      follow_ups.installment,
      follow_ups.status,
      follow_ups.due_date
    FROM `pacific-plating-282708.careos.carepay_follow_ups` AS follow_ups
    JOIN order_trace USING (transaction_id)
  ),

  dashboard_installment AS (
    SELECT
      OrderID, OrderItem, InvoiceNo, InsuranceGroup, InsuranceType,
      TransactionStatus, ExpectedReceived, ActualReceived,
      PaymentDate, Period, TotalPeriods, PaymentMethod, PaymentChannel,
      ExpectedDate
    FROM `pacific-plating-282708.sap_data_engineer.sap_dashboard_carepay_installment`
    WHERE OrderID = 'L80161278'
  ),

  dashboard_fully_paid AS (
    SELECT
      OrderID, OrderItem, InvoiceNo, InsuranceGroup, InsuranceType,
      TransactionStatus, ExpectedReceived, ActualReceived,
      PaymentDate, Period, TotalPeriods, PaymentMethod, PaymentChannel,
      ExpectedDate
    FROM `pacific-plating-282708.sap_data_engineer.sap_dashboard_carepay_fully_paid`
    WHERE OrderID = 'L80161278'
  ),

  sap_trace AS (
    SELECT
      U_OrderID AS OrderID,
      U_OrderItem AS OrderItem,
      U_InvoiceNo AS InvoiceNo,
      U_InsuranceGroup AS InsuranceGroup,
      U_InsuranceType AS InsuranceType,
      TransactionStatus,
      ExpectedReceived,
      U_ActualReceived AS ActualReceived,
      PaymentDate,
      U_Period AS Period,
      TotalPeriods,
      PaymentMethod,
      PaymentChannel,
      ExpectedDate,
      BatchRunDate
    FROM `pacific-plating-282708.sap_integration_v2.SAP_LIVE_FULL`
    WHERE U_OrderID = 'L80161278'
       OR U_OrderItem LIKE 'L80161278-%'
  ),

  interface_membership AS (
    SELECT 'RCB_Motor_process_create' AS view_name, OrderItem, Period, InvoiceNo
    FROM `pacific-plating-282708.sap_view.RCB_Motor_process_create`
    WHERE OrderID = 'L80161278'
    UNION ALL SELECT 'RCB_Motor_process_2_cancel_new', OrderItem, Period, InvoiceNo
    FROM `pacific-plating-282708.sap_view.RCB_Motor_process_2_cancel_new`
    WHERE OrderID = 'L80161278'
    UNION ALL SELECT 'RCB_Motor_process_3_change', OrderItem, Period, InvoiceNo
    FROM `pacific-plating-282708.sap_view.RCB_Motor_process_3_change`
    WHERE OrderID = 'L80161278'
    UNION ALL SELECT 'RCB_Motor_process_4_creditshell', OrderItem, Period, InvoiceNo
    FROM `pacific-plating-282708.sap_view.RCB_Motor_process_4_creditshell`
    WHERE OrderID = 'L80161278'
    UNION ALL SELECT 'RCL_Motor_process_1_create', OrderItem, Period, InvoiceNo
    FROM `pacific-plating-282708.sap_view.RCL_Motor_process_1_create`
    WHERE OrderID = 'L80161278'
    UNION ALL SELECT 'RCL_Motor_process_2_newpayment', OrderItem, Period, InvoiceNo
    FROM `pacific-plating-282708.sap_view.RCL_Motor_process_2_newpayment`
    WHERE OrderID = 'L80161278'
    UNION ALL SELECT 'RCL_Motor_process_3_cancel', OrderItem, Period, InvoiceNo
    FROM `pacific-plating-282708.sap_view.RCL_Motor_process_3_cancel`
    WHERE OrderID = 'L80161278'
    UNION ALL SELECT 'RCL_Motor_process_4_creditshell', OrderItem, Period, InvoiceNo
    FROM `pacific-plating-282708.sap_view.RCL_Motor_process_4_creditshell`
    WHERE OrderID = 'L80161278'
    UNION ALL SELECT 'RCB_NonMotor_process_1_create', OrderItem, Period, InvoiceNo
    FROM `pacific-plating-282708.sap_view.RCB_NonMotor_process_1_create`
    WHERE OrderID = 'L80161278'
    UNION ALL SELECT 'RCB_NonMotor_process_2_cancel', OrderItem, Period, InvoiceNo
    FROM `pacific-plating-282708.sap_view.RCB_NonMotor_process_2_cancel`
    WHERE OrderID = 'L80161278'
    UNION ALL SELECT 'RCL_NonMotor_process_1_create', OrderItem, Period, InvoiceNo
    FROM `pacific-plating-282708.sap_view.RCL_NonMotor_process_1_create`
    WHERE OrderID = 'L80161278'
    UNION ALL SELECT 'RCL_NonMotor_process_2_newpayment', OrderItem, Period, InvoiceNo
    FROM `pacific-plating-282708.sap_view.RCL_NonMotor_process_2_newpayment`
    WHERE OrderID = 'L80161278'
  )

SELECT
  CURRENT_TIMESTAMP() AS checked_at_utc,
  ARRAY(SELECT AS STRUCT * FROM order_trace ORDER BY OrderItem) AS order_rows,
  ARRAY(SELECT AS STRUCT * FROM charge_trace ORDER BY create_time, charge_id) AS charge_rows,
  ARRAY(SELECT AS STRUCT * FROM snapshot_trace ORDER BY update_time DESC, snapshot_id) AS snapshot_rows,
  ARRAY(SELECT AS STRUCT * FROM follow_up_trace ORDER BY installment) AS follow_up_rows,
  ARRAY(SELECT AS STRUCT * FROM dashboard_installment ORDER BY OrderItem, Period) AS installment_dashboard_rows,
  ARRAY(SELECT AS STRUCT * FROM dashboard_fully_paid ORDER BY OrderItem, Period) AS fully_paid_dashboard_rows,
  ARRAY(SELECT AS STRUCT * FROM sap_trace ORDER BY OrderItem, Period, InvoiceNo) AS sap_rows,
  ARRAY(SELECT AS STRUCT * FROM interface_membership ORDER BY view_name, OrderItem, Period) AS interface_rows;

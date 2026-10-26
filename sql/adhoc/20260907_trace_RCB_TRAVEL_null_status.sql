-- Read-only root-cause trace for RCB_TRAVEL rows removed by
-- sap_view.RCB_NonMotor_process_1_create because TransactionStatus is NULL.

WITH
  travel AS (
    SELECT
      OrderID, OrderItem, InvoiceNo, OrderDate, PolicyDate, PolicyNo,
      InsurerCode, TransactionStatus, ExpectedReceived, ActualReceived,
      Period, TotalPeriods, PaymentDate, PaymentMethod, PaymentChannel
    FROM `pacific-plating-282708.sap_data_engineer.RCB_TRAVEL`
    WHERE TransactionStatus IS NULL
  ),

  traced AS (
    SELECT
      travel.*,
      orders.id AS careos_order_uuid,
      orders.payment AS order_payment_ref,
      orders.is_fully_paid,
      transactions.id AS transaction_id,
      transactions.status AS raw_transaction_status,
      transactions.payment_option,
      COUNT(charges.id) AS raw_charge_count,
      COUNTIF(charges.status = 'SUCCESSFUL') AS successful_charge_count,
      ARRAY_AGG(
        IF(
          charges.id IS NULL,
          NULL,
          STRUCT(
            charges.id AS charge_id,
            charges.status AS charge_status,
            charges.payment_method AS payment_method,
            charges.service_provider AS service_provider,
            charges.third_party_id AS third_party_id,
            charges.installment_number AS installment_number,
            charges.amount AS amount
          )
        ) IGNORE NULLS
        ORDER BY charges.create_time
        LIMIT 10
      ) AS raw_charges
    FROM travel
    LEFT JOIN `pacific-plating-282708.careos.careos_orders` AS orders
      ON orders.human_id = travel.OrderID
    LEFT JOIN `pacific-plating-282708.careos.carepay_transactions` AS transactions
      ON CONCAT('transactions/', transactions.id) = orders.payment
    LEFT JOIN `pacific-plating-282708.careos.carepay_charges` AS charges
      ON charges.transaction_id = transactions.id
    GROUP BY ALL
  )

SELECT
  COUNT(*) AS null_status_rows,
  COUNT(DISTINCT OrderID) AS orders,
  COUNT(DISTINCT OrderItem) AS items,
  COUNTIF(order_payment_ref IS NULL OR order_payment_ref = '') AS blank_order_payment_ref_rows,
  COUNTIF(transaction_id IS NULL) AS missing_transaction_rows,
  COUNTIF(raw_charge_count = 0) AS no_charge_rows,
  COUNTIF(successful_charge_count = 0) AS no_successful_charge_rows,
  COUNTIF(successful_charge_count > 0) AS successful_charge_but_null_status_rows,
  ARRAY(
    SELECT AS STRUCT
      OrderID, OrderItem, OrderDate, PolicyDate, PolicyNo, InsurerCode,
      order_payment_ref, is_fully_paid, transaction_id, raw_transaction_status,
      payment_option, raw_charge_count, successful_charge_count, raw_charges
    FROM traced
    ORDER BY OrderID, OrderItem
  ) AS row_detail
FROM traced;

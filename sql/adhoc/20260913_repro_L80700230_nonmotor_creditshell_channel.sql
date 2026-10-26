-- RED/GREEN reproduction for Health/NonMotor CreditShell payment routing.
-- Expected contract:
--   * carried-over Period 1 stays RCL-Credit Shell;
--   * later successful Health QR/RABBIT_LENDING payments use the Health channel;
--   * pending periods keep payment method/channel blank.
-- Grain: (OrderItem, Period, InvoiceNo/charge_id).

WITH
  item_context AS (
    SELECT
      oi.human_id AS OrderItem,
      o.human_id AS OrderID,
      oi.product,
      t.id AS transaction_id,
      t.payment_option
    FROM `pacific-plating-282708.careos.careos_order_items` AS oi
    JOIN `pacific-plating-282708.careos.careos_orders` AS o
      ON o.id = oi.order_id
    JOIN `pacific-plating-282708.careos.carepay_transactions` AS t
      ON CONCAT('transactions/', t.id) = o.payment
    WHERE oi.human_id = 'L80700230-1'
  ),

  successful_charges AS (
    SELECT
      ic.OrderItem,
      ic.product,
      ic.payment_option,
      c.installment_number AS Period,
      c.id AS charge_id,
      c.third_party_id AS raw_invoice_no,
      c.payment_method AS raw_payment_method,
      c.service_provider AS raw_service_provider,
      COALESCE(c.payment_date, c.update_time) AS raw_payment_timestamp
    FROM item_context AS ic
    JOIN `pacific-plating-282708.careos.carepay_charges` AS c
      ON c.transaction_id = ic.transaction_id
     AND c.status = 'SUCCESSFUL'
  ),

  candidate AS (
    SELECT
      OrderID,
      OrderItem,
      Period,
      TotalPeriods,
      InvoiceNo,
      InsuranceGroup,
      TransactionStatus,
      PaymentDate,
      PaymentMethod,
      PaymentChannel,
      RefOrder
    FROM `pacific-plating-282708.sap_view.RCL_Motor_process_4_creditshell`
    WHERE OrderItem = 'L80700230-1'
  ),

  checked AS (
    SELECT
      c.*,
      s.charge_id,
      s.product AS raw_product,
      s.payment_option,
      s.raw_payment_method,
      s.raw_service_provider,
      s.raw_payment_timestamp,
      CASE
        WHEN c.TransactionStatus = 'pending' THEN ''
        WHEN c.InsuranceGroup = 'Health'
          AND c.Period = 1
          AND c.RefOrder IS NOT NULL
        THEN 'RCL-Credit Shell'
        WHEN c.InsuranceGroup = 'Health'
          AND s.raw_payment_method = 'QR_CODE'
          AND s.raw_service_provider = 'RABBIT_LENDING'
        THEN 'RCL-Omise QR Prompt Pay-Health'
        ELSE c.PaymentChannel
      END AS expected_payment_channel,
      CASE
        WHEN c.TransactionStatus = 'pending' THEN ''
        WHEN c.InsuranceGroup = 'Health'
          AND c.Period = 1
          AND c.RefOrder IS NOT NULL
        THEN 'RCL-Credit Shell'
        WHEN c.InsuranceGroup = 'Health'
          AND s.raw_payment_method = 'QR_CODE'
        THEN 'OME Omise QR Prompt Pay'
        ELSE c.PaymentMethod
      END AS expected_payment_method,
      CASE
        WHEN c.TransactionStatus = 'pending' THEN ''
        WHEN DATE(s.raw_payment_timestamp) < DATE_TRUNC(CURRENT_DATE(), MONTH)
        THEN FORMAT_DATE('%d%m%Y', DATE_TRUNC(CURRENT_DATE(), MONTH))
        ELSE FORMAT_DATE('%d%m%Y', DATE(s.raw_payment_timestamp))
      END AS expected_payment_date
    FROM candidate AS c
    LEFT JOIN successful_charges AS s
      ON s.OrderItem = c.OrderItem
     AND s.Period = c.Period
     AND (
       s.raw_invoice_no = c.InvoiceNo
       OR (s.raw_invoice_no IS NULL AND c.InvoiceNo IS NOT NULL)
     )
  )

SELECT
  CURRENT_TIMESTAMP() AS checked_at_utc,
  *,
  IF(
    COALESCE(PaymentChannel, '') = COALESCE(expected_payment_channel, '')
      AND COALESCE(PaymentMethod, '') = COALESCE(expected_payment_method, '')
      AND COALESCE(PaymentDate, '') = COALESCE(expected_payment_date, ''),
    'GREEN',
    CONCAT(
      IF(COALESCE(PaymentChannel, '') != COALESCE(expected_payment_channel, ''),
        'WRONG_CHANNEL;', ''),
      IF(COALESCE(PaymentMethod, '') != COALESCE(expected_payment_method, ''),
        'WRONG_METHOD;', ''),
      IF(COALESCE(PaymentDate, '') != COALESCE(expected_payment_date, ''),
        'WRONG_PAYMENT_DATE;', '')
    )
  ) AS verdict
FROM checked
ORDER BY Period, InvoiceNo, charge_id;

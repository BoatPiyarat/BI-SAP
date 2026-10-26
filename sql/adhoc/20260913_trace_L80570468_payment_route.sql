-- Read-only trace for OrderItem L80570468-1.
-- Grain: (OrderItem, Period, InvoiceNo/charge_id).

WITH
  item_context AS (
    SELECT
      oi.human_id AS OrderItem,
      o.human_id AS OrderID,
      oi.product,
      oi.motor_item_type AS raw_insurance_type,
      oi.package AS raw_insurance_product,
      t.id AS transaction_id,
      t.payment_option
    FROM `pacific-plating-282708.careos.careos_order_items` AS oi
    JOIN `pacific-plating-282708.careos.careos_orders` AS o
      ON o.id = oi.order_id
    LEFT JOIN `pacific-plating-282708.careos.carepay_transactions` AS t
      ON CONCAT('transactions/', t.id) = o.payment
    WHERE oi.human_id = 'L80570468-1'
  ),

  raw_successful_charges AS (
    SELECT
      ic.*,
      c.installment_number AS Period,
      c.id AS charge_id,
      c.third_party_id AS raw_invoice_no,
      c.status AS raw_charge_status,
      c.payment_method AS raw_payment_method,
      c.service_provider AS raw_service_provider,
      c.amount AS raw_amount_satang,
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
      InsuranceType,
      InsuranceProduct,
      TransactionStatus,
      ExpectedReceived,
      ActualReceived,
      PaymentDate,
      PaymentMethod,
      PaymentChannel,
      ExpectedDate,
      RefOrder
    FROM `pacific-plating-282708.sap_view.RCL_Motor_process_4_creditshell`
    WHERE OrderItem = 'L80570468-1'
  )

SELECT
  CURRENT_TIMESTAMP() AS checked_at_utc,
  c.OrderID,
  c.OrderItem,
  c.Period,
  c.TotalPeriods,
  c.InvoiceNo,
  r.charge_id,
  r.product AS raw_product,
  r.raw_insurance_type,
  r.raw_insurance_product,
  r.payment_option,
  r.raw_charge_status,
  r.raw_payment_method,
  r.raw_service_provider,
  c.InsuranceGroup,
  c.InsuranceType,
  c.InsuranceProduct,
  c.TransactionStatus,
  c.ExpectedReceived,
  c.ActualReceived,
  c.PaymentDate,
  c.PaymentMethod,
  c.PaymentChannel,
  c.ExpectedDate,
  c.RefOrder,
  CASE
    WHEN c.InsuranceGroup = 'Health'
      AND r.payment_option = 'RABBIT_CARE_INSTALLMENT'
      AND c.RefOrder IS NOT NULL
      AND c.PaymentMethod = 'RCL-Credit Shell'
      AND c.PaymentChannel = 'RCL-Credit Shell'
    THEN 'PASS_NONMOTOR_RCL_CREDIT_SHELL_FORMAT'
    WHEN c.InsuranceGroup = 'Health'
      AND r.raw_payment_method = 'QR_CODE'
      AND r.raw_service_provider = 'RABBIT_LENDING'
      AND c.PaymentMethod = 'OME Omise QR Prompt Pay'
      AND c.PaymentChannel = 'RCL-Omise QR Prompt Pay-Health'
    THEN 'PASS_NONMOTOR_HEALTH_FORMAT'
    WHEN c.InsuranceGroup = 'Health'
      AND r.raw_payment_method = 'QR_CODE'
      AND r.raw_service_provider = 'RABBIT_LENDING'
      AND c.PaymentChannel = 'RCL-Omise QR Prompt Pay-BAY'
    THEN 'HOLD_MOTOR_BAY_FORMAT_ON_HEALTH'
    WHEN c.TransactionStatus = 'pending'
      AND COALESCE(c.PaymentMethod, '') = ''
      AND COALESCE(c.PaymentChannel, '') = ''
    THEN 'PASS_PENDING_BLANK_PAYMENT_ROUTE'
    WHEN c.TransactionStatus = 'pending'
    THEN 'HOLD_PENDING_ROUTE_NOT_BLANK'
    ELSE 'REVIEW_ROUTE_MAPPING'
  END AS pre_import_route_check
FROM candidate AS c
LEFT JOIN raw_successful_charges AS r
  ON r.OrderItem = c.OrderItem
 AND r.Period = c.Period
 AND (
   r.raw_invoice_no = c.InvoiceNo
   OR (r.raw_invoice_no IS NULL AND c.InvoiceNo IS NOT NULL)
 )
ORDER BY c.Period, c.InvoiceNo, r.charge_id;

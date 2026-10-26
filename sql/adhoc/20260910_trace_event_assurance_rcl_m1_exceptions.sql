-- Root-source trace for the three RCL Motor M1 event-assurance exceptions.
-- Read-only; no SAP or production mutation.
WITH targets AS (
  SELECT * FROM UNNEST([
    STRUCT('L80161278-M1' AS OrderItem, '2_chrg_67i5i9355dpxs2imp64' AS InvoiceNo),
    ('L80738381-M1', '2_chrg_689hydn4u3coof2wrnz'),
    ('L80767177-M1', '2_chrg_68iihm14piwxqb96ik6')
  ])
),
item_source AS (
  SELECT
    oi.human_id AS OrderItem,
    o.human_id AS OrderID,
    oi.product,
    oi.motor_item_type,
    oi.insurer,
    oi.is_cancelled,
    oi.cancel_time,
    oi.policy_start_date,
    t.payment_option,
    c.id AS charge_id,
    c.third_party_id,
    c.installment_number,
    c.amount,
    c.payment_method,
    c.service_provider,
    c.status AS charge_status
  FROM `pacific-plating-282708.careos.careos_order_items` AS oi
  JOIN `pacific-plating-282708.careos.careos_orders` AS o ON o.id = oi.order_id
  LEFT JOIN `pacific-plating-282708.careos.carepay_transactions` AS t
    ON CONCAT('transactions/', t.id) = o.payment
  LEFT JOIN `pacific-plating-282708.careos.carepay_charges` AS c
    ON c.transaction_id = t.id AND c.status = 'SUCCESSFUL'
  WHERE oi.human_id IN (SELECT OrderItem FROM targets)
),
dashboard AS (
  SELECT
    d.OrderItem,
    SAFE_CAST(d.Period AS INT64) AS Period,
    SAFE_CAST(d.TotalPeriods AS INT64) AS TotalPeriods,
    NULLIF(TRIM(d.InvoiceNo), '') AS InvoiceNo,
    d.TransactionStatus,
    d.ExpectedReceived,
    d.ActualReceived,
    d.ExpectedDate,
    d.PaymentDate,
    d.PaymentMethod,
    d.PaymentChannel
  FROM `pacific-plating-282708.sap_data_engineer.sap_dashboard_carepay_installment` AS d
  WHERE d.OrderItem IN (SELECT OrderItem FROM targets)
)
SELECT
  t.OrderItem,
  t.InvoiceNo AS expected_invoice_no,
  ARRAY_AGG(STRUCT(
    s.OrderID, s.product, s.motor_item_type, s.insurer, s.is_cancelled,
    s.cancel_time, s.policy_start_date, s.payment_option, s.charge_id,
    s.third_party_id, s.installment_number, s.amount, s.payment_method,
    s.service_provider, s.charge_status
  ) LIMIT 20) AS source_rows,
  ARRAY_AGG(STRUCT(
    d.Period, d.TotalPeriods, d.InvoiceNo, d.TransactionStatus,
    d.ExpectedReceived, d.ActualReceived, d.ExpectedDate, d.PaymentDate,
    d.PaymentMethod, d.PaymentChannel
  ) LIMIT 20) AS dashboard_rows
FROM targets AS t
LEFT JOIN item_source AS s USING (OrderItem)
LEFT JOIN dashboard AS d USING (OrderItem)
GROUP BY t.OrderItem, t.InvoiceNo
ORDER BY t.OrderItem;

DECLARE target_run_id STRING DEFAULT 'V3NIGHTLY-2026-08-25T11:17:18-ca7ee9e7';

WITH delivery AS (
  SELECT
    OrderItem,
    SAFE_CAST(Period AS INT64) AS period,
    InvoiceNo,
    TransactionStatus,
    PaymentDate,
    BatchRunDate
  FROM `pacific-plating-282708.sap_integration_v3.v3_unit5_newpayment_delivery_ready`
),
identity_delivery AS (
  SELECT
    i.order_item,
    i.period,
    i.invoice_no,
    d.TransactionStatus,
    d.PaymentDate,
    d.BatchRunDate
  FROM `pacific-plating-282708.sap_integration_v3.v3_unit5_payload_identity` AS i
  LEFT JOIN delivery AS d
    ON d.OrderItem = i.order_item
   AND d.period = i.period
   AND d.InvoiceNo = i.invoice_no
  WHERE i.pipeline_run_id = target_run_id
    AND i.file_role = 'NEWPAYMENT'
)
SELECT
  'ALL_DELIVERY_SPINE' AS population,
  TransactionStatus AS status,
  COALESCE(FORMAT_DATE('%Y-%m', SAFE.PARSE_DATE('%d%m%Y', NULLIF(PaymentDate, ''))), '<blank>')
    AS payment_month_year,
  BatchRunDate AS batch_run_date,
  COUNT(*) AS row_count,
  COUNT(DISTINCT OrderItem) AS order_items
FROM delivery
GROUP BY 1, 2, 3, 4

UNION ALL

SELECT
  'CURRENT_RUN_EVENT_IDENTITIES',
  COALESCE(TransactionStatus, '<missing delivery join>'),
  COALESCE(FORMAT_DATE('%Y-%m', SAFE.PARSE_DATE('%d%m%Y', NULLIF(PaymentDate, ''))), '<blank>'),
  COALESCE(BatchRunDate, '<missing>'),
  COUNT(*),
  COUNT(DISTINCT order_item)
FROM identity_delivery
GROUP BY 1, 2, 3, 4

ORDER BY population, status, payment_month_year, batch_run_date;

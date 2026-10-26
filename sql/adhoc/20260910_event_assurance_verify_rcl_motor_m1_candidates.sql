-- Stage 2C: verify SAP-absent RCL compulsory M1 obligations in their owning legacy view.
-- Read-only; candidate list comes from event-assurance-20260910-173140.
WITH candidates AS (
  SELECT * FROM UNNEST([
    STRUCT('L80084414-M1' AS OrderItem, 1 AS Period, '2_chrg_67j7m60pa6osdys5yjm' AS InvoiceNo),
    ('L80096125-M1', 1, '2_chrg_67j95y4w5qlqvqiddzh'),
    ('L78437008-M1', 1, '2_chrg_67jbbnwxinv7cag9rkl'),
    ('L80738381-M1', 1, '2_chrg_689hydn4u3coof2wrnz'),
    ('L80767177-M1', 1, '2_chrg_68iihm14piwxqb96ik6'),
    ('L78877275-M1', 1, '2_chrg_68wxbq6w83fd7yqjhq7'),
    ('L78891729-M1', 1, '2_chrg_68xoajw7uw642cn31sr'),
    ('L78869592-M1', 1, '2_chrg_68yk3ji57o7g0m56o72'),
    ('L78935424-M1', 1, '2_chrg_68ykus5hrp5t46wf09h'),
    ('L80161278-M1', 1, '2_chrg_67i5i9355dpxs2imp64')
  ])
),
view_rows AS (
  SELECT OrderItem, SAFE_CAST(Period AS INT64) AS Period,
    NULLIF(TRIM(InvoiceNo), '') AS InvoiceNo, TransactionStatus
  FROM `pacific-plating-282708.sap_view.RCL_Motor_process_1_create`
)
SELECT
  c.*,
  COUNT(v.OrderItem) AS key_rows,
  COUNTIF(v.InvoiceNo = c.InvoiceNo) AS exact_rows,
  ARRAY_AGG(DISTINCT v.InvoiceNo IGNORE NULLS ORDER BY v.InvoiceNo LIMIT 10) AS view_invoices,
  ARRAY_AGG(DISTINCT v.TransactionStatus IGNORE NULLS ORDER BY v.TransactionStatus LIMIT 10)
    AS view_statuses,
  IF(COUNTIF(v.InvoiceNo = c.InvoiceNo) > 0, 'IN_EXPECTED_VIEW', 'MISSING_FROM_EXPECTED_VIEW')
    AS view_assurance_status
FROM candidates AS c
LEFT JOIN view_rows AS v USING (OrderItem, Period)
GROUP BY c.OrderItem, c.Period, c.InvoiceNo
ORDER BY view_assurance_status, c.OrderItem;

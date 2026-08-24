-- READ ONLY / Class A evidence. Qualifies the first bounded V3 production slice.
-- No BigQuery mutation, GCS write, SAP action, or scheduler change.
-- Scope: ordinary RCL Motor NEWPAYMENT only; fail closed on cancellation, change order,
-- CreditShell, EDC, compulsory one-period RCL, non-RCL output, incomplete spine, or stale identity.

DECLARE v_pipeline_run_id STRING;

SET v_pipeline_run_id = (
  SELECT pipeline_run_id
  FROM `pacific-plating-282708.sap_integration_v3.v3_unit5_payload_identity`
  WHERE file_role = 'NEWPAYMENT'
  ORDER BY built_at DESC, pipeline_run_id DESC
  LIMIT 1
);

ASSERT v_pipeline_run_id IS NOT NULL AS 'No V3 NEWPAYMENT run is available';

WITH
identity AS (
  SELECT pipeline_run_id, order_item, period, charge_id, invoice_no, payload_hash
  FROM `pacific-plating-282708.sap_integration_v3.v3_unit5_payload_identity`
  WHERE pipeline_run_id = v_pipeline_run_id
    AND file_role = 'NEWPAYMENT'
),
identity_item AS (
  SELECT
    order_item,
    COUNT(*) AS event_identity_count,
    STRING_AGG(
      FORMAT('period=%d,charge_id=%s,invoice=%s', period, charge_id, invoice_no),
      '|' ORDER BY period, charge_id
    ) AS event_identity_detail
  FROM identity
  GROUP BY order_item
),
change_link_rows AS (
  SELECT
    current_human_id AS order_id,
    'CURRENT' AS relationship_role,
    old_human_id AS counterpart_order_id
  FROM `pacific-plating-282708.careos.cancelled_change_orders`
  WHERE current_human_id IS NOT NULL
  UNION ALL
  SELECT
    old_human_id AS order_id,
    'OLD' AS relationship_role,
    current_human_id AS counterpart_order_id
  FROM `pacific-plating-282708.careos.cancelled_change_orders`
  WHERE old_human_id IS NOT NULL
),
change_link AS (
  SELECT
    order_id,
    COUNT(*) AS link_count,
    COUNTIF(relationship_role = 'CURRENT') AS current_link_count,
    COUNTIF(relationship_role = 'OLD') AS old_link_count,
    COUNT(DISTINCT counterpart_order_id) AS counterpart_count
  FROM change_link_rows
  GROUP BY order_id
),
payload AS (
  SELECT
    p.OrderID, p.OrderItem, p.InvoiceNo, p.TransactionStatus, p.PaymentDate,
    p.Period, p.TotalPeriods, p.PaymentMethod, p.PaymentChannel, p.BatchRunDate
  FROM `pacific-plating-282708.sap_integration_v3.v3_unit5_newpayment_delivery_ready` p
  WHERE EXISTS (
    SELECT 1 FROM identity i
    WHERE i.order_item = p.OrderItem
  )
),
item_shape AS (
  SELECT
    OrderItem,
    COUNT(*) AS payload_rows,
    COUNT(DISTINCT SAFE_CAST(Period AS INT64)) AS distinct_periods,
    MIN(SAFE_CAST(Period AS INT64)) AS min_period,
    MAX(SAFE_CAST(Period AS INT64)) AS max_period,
    COUNT(DISTINCT SAFE_CAST(TotalPeriods AS INT64)) AS total_period_values,
    MAX(SAFE_CAST(TotalPeriods AS INT64)) AS total_periods,
    STRING_AGG(DISTINCT IFNULL(TransactionStatus, '<NULL>'), '|' ORDER BY
      IFNULL(TransactionStatus, '<NULL>')) AS status_values,
    -- Preview the reviewed source correction in DDL 058. Unknown spellings still hold.
    COUNTIF(TransactionStatus NOT IN ('Paid', 'Pending', 'paid', 'pending')
      OR TransactionStatus IS NULL) AS invalid_status_rows,
    COUNTIF(TransactionStatus = 'Paid' AND NULLIF(TRIM(InvoiceNo), '') IS NULL)
      AS paid_blank_invoice_rows,
    COUNTIF(TransactionStatus = 'Paid' AND NULLIF(TRIM(PaymentDate), '') IS NULL)
      AS paid_blank_payment_date_rows
  FROM payload
  GROUP BY OrderItem
),
classified AS (
  SELECT
    i.pipeline_run_id, i.order_item, i.period, i.charge_id, i.invoice_no,
    i.payload_hash, e.flow, p.OrderID, p.TransactionStatus, p.PaymentMethod,
    p.PaymentChannel, p.PaymentDate, p.BatchRunDate,
    d.is_cancelled_effective, oi.motor_item_type,
    IFNULL(c.link_count, 0) AS change_link_count,
    IFNULL(c.current_link_count, 0) AS current_change_link_count,
    IFNULL(c.old_link_count, 0) AS old_change_link_count,
    IFNULL(c.counterpart_count, 0) AS change_counterpart_count,
    ii.event_identity_count, ii.event_identity_detail,
    s.payload_rows, s.distinct_periods, s.min_period, s.max_period,
    s.total_period_values, s.total_periods, s.status_values, s.invalid_status_rows,
    s.paid_blank_invoice_rows, s.paid_blank_payment_date_rows,
    CASE
      WHEN IFNULL(d.is_cancelled_effective, FALSE) THEN 'HOLD_CANCELLED'
      WHEN IFNULL(c.link_count, 0) > 1 OR IFNULL(c.counterpart_count, 0) > 1
        OR (IFNULL(c.current_link_count, 0) > 0 AND IFNULL(c.old_link_count, 0) > 0)
        THEN 'HOLD_CHANGE_LINK_AMBIGUOUS'
      WHEN IFNULL(c.current_link_count, 0) = 1 THEN 'HOLD_CREDITSHELL_OR_CHANGE_CURRENT'
      WHEN IFNULL(c.old_link_count, 0) = 1 THEN 'HOLD_CHANGE_PREVIOUS'
      WHEN UPPER(IFNULL(p.PaymentMethod, '')) LIKE '%EDC%'
        OR UPPER(IFNULL(p.PaymentChannel, '')) LIKE '%EDC%' THEN 'HOLD_EDC'
      WHEN UPPER(IFNULL(p.PaymentChannel, '')) NOT LIKE 'RCL%' THEN 'HOLD_NOT_RCL_CHANNEL'
      WHEN s.total_period_values != 1 OR s.total_periods IS NULL
        OR s.payload_rows != s.total_periods OR s.distinct_periods != s.total_periods
        OR s.min_period != 1 OR s.max_period != s.total_periods THEN 'HOLD_INCOMPLETE_RCL_SPINE'
      WHEN s.invalid_status_rows != 0 THEN 'HOLD_INVALID_RCL_STATUS'
      WHEN s.paid_blank_invoice_rows != 0 OR s.paid_blank_payment_date_rows != 0
        THEN 'HOLD_REQUIRED_PAID_FIELDS'
      WHEN s.total_periods = 1 AND oi.motor_item_type = 'MOTOR_TYPE_COMPULSORY'
        THEN 'HOLD_COMPULSORY_RCL_EDGE'
      WHEN s.total_periods <= 1 THEN 'HOLD_NOT_ORDINARY_RCL_INSTALLMENT'
      WHEN e.flow IS NULL OR e.flow != 'RCL' THEN 'HOLD_SOURCE_FLOW_DISAGREES'
      ELSE 'READY_NORMAL_RCL_MOTOR_NEWPAYMENT'
    END AS qualification
  FROM identity i
  JOIN identity_item ii USING (order_item)
  JOIN payload p
    ON p.OrderItem = i.order_item
   AND SAFE_CAST(p.Period AS INT64) = i.period
   AND p.InvoiceNo = i.invoice_no
  JOIN item_shape s ON s.OrderItem = i.order_item
  JOIN `pacific-plating-282708.sap_integration_v3.v3_unit2_event_shadow` e
    ON e.pipeline_run_id = i.pipeline_run_id
   AND e.order_item = i.order_item
   AND e.period = i.period
   AND e.charge_id = i.charge_id
  JOIN `pacific-plating-282708.sap_integration_v3.stg_order_dim` d
    ON d.order_item = i.order_item
  JOIN `pacific-plating-282708.careos.careos_order_items` oi
    ON oi.human_id = i.order_item
  LEFT JOIN change_link c ON c.order_id = p.OrderID
)
SELECT
  v_pipeline_run_id AS pipeline_run_id,
  qualification,
  COUNT(*) AS identity_rows,
  COUNT(DISTINCT order_item) AS order_items,
  COUNT(DISTINCT OrderID) AS orders,
  COUNT(DISTINCT charge_id) AS charges,
  COUNT(DISTINCT payload_hash) AS payload_hashes,
  COUNT(DISTINCT IF(event_identity_count > 1, order_item, NULL)) AS multi_event_order_items,
  STRING_AGG(DISTINCT IF(event_identity_count > 1,
    FORMAT('%s[%s]', order_item, event_identity_detail), NULL), ';' ORDER BY
    IF(event_identity_count > 1, FORMAT('%s[%s]', order_item, event_identity_detail), NULL))
    AS multi_event_detail,
  STRING_AGG(DISTINCT status_values, ';' ORDER BY status_values) AS status_values,
  MIN(BatchRunDate) AS min_batch_run_date,
  MAX(BatchRunDate) AS max_batch_run_date
FROM classified
GROUP BY qualification
ORDER BY qualification;

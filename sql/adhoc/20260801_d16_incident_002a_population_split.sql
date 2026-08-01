-- D16 BLOCK ground #1: INCIDENT-002a population grain separation.
-- READ ONLY. No table/view/procedure mutation. INCIDENT-002b is not quantified or re-scoped here;
-- cancelled_change_orders is used only as a boundary flag to prevent accidental conflation.
--
-- Intended grain:
--   candidate detail = one non-CMI (OrderItem, Period=1) SAP key per order;
--   reported population = distinct order_id within one mutually exclusive shape.
--
-- Live-schema constraint verified 2026-08-01: sap_mirror_doc does not yet contain
-- UpdateDate/UpdateTime. Until reviewed 024 is deployed, current SAP state is selected using the
-- existing status -> non-empty invoice -> parsed BatchRunDate -> DocEntry ordering.

WITH latest_orders AS (
  SELECT id, human_id
  FROM `pacific-plating-282708.careos.careos_orders`
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY id
    ORDER BY update_time DESC, _sdc_extracted_at DESC
  ) = 1
),
latest_order_items AS (
  SELECT
    o.human_id AS order_id,
    oi.human_id AS order_item,
    oi.motor_item_type,
    oi.packagetype,
    oi.gross_premium
  FROM `pacific-plating-282708.careos.careos_order_items` oi
  JOIN latest_orders o
    ON o.id = oi.order_id
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY oi.human_id
    ORDER BY oi.update_time DESC, oi._sdc_extracted_at DESC
  ) = 1
),
orders_with_cmi AS (
  SELECT
    order_id,
    MAX(IF(motor_item_type = 'MOTOR_TYPE_COMPULSORY', gross_premium, NULL)) AS cmi_premium,
    ARRAY_AGG(
      IF(motor_item_type = 'MOTOR_TYPE_COMPULSORY', order_item, NULL)
      IGNORE NULLS ORDER BY order_item LIMIT 1
    )[SAFE_OFFSET(0)] AS cmi_order_item
  FROM latest_order_items
  GROUP BY order_id
  HAVING cmi_order_item IS NOT NULL AND cmi_premium IS NOT NULL
),
mirror_current AS (
  SELECT *
  FROM `pacific-plating-282708.sap_integration_v3.sap_mirror_doc`
  WHERE U_OrderItem NOT IN ('Invoice', 'SaleOrder')
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY U_OrderItem, U_Period
    ORDER BY
      CASE TransactionStatus
        WHEN 'Cancelled' THEN 3
        WHEN 'Cancelled (Change order / Rejected)' THEN 3
        WHEN 'Paid' THEN 2
        WHEN 'Pending' THEN 1
        ELSE 0
      END DESC,
      IF(NULLIF(TRIM(U_InvoiceNo), '') IS NULL, 0, 1) DESC,
      SAFE.PARSE_DATE('%d%m%Y', BatchRunDate) DESC,
      DocEntry DESC
  ) = 1
),
raw_002a_arithmetic AS (
  SELECT
    m.U_OrderID AS order_id,
    m.U_OrderItem AS non_cmi_order_item,
    m.U_Period AS period,
    m.DocEntry AS non_cmi_doc_entry,
    m.U_InvoiceNo AS non_cmi_invoice_no,
    m.ExpectedReceived AS non_cmi_expected,
    m.U_ActualReceived AS non_cmi_actual,
    ROUND(m.U_ActualReceived - m.ExpectedReceived, 2) AS excess_amount,
    c.cmi_order_item,
    c.cmi_premium
  FROM mirror_current m
  JOIN orders_with_cmi c
    ON c.order_id = m.U_OrderID
  JOIN latest_order_items oi
    ON oi.order_item = m.U_OrderItem
  WHERE oi.motor_item_type != 'MOTOR_TYPE_COMPULSORY'
    AND m.U_Period = 1
    AND m.TransactionStatus = 'Paid'
    AND m.DocEntry IS NOT NULL
    AND m.ExpectedReceived > 0
    AND ROUND(m.U_ActualReceived - m.ExpectedReceived, 2) = ROUND(c.cmi_premium, 2)
),
classified AS (
  SELECT
    r.*,
    cm.DocEntry AS cmi_doc_entry,
    cm.U_InvoiceNo AS cmi_invoice_no,
    cm.TransactionStatus AS cmi_status,
    cm.ExpectedReceived AS cmi_expected,
    cm.U_ActualReceived AS cmi_actual,
    EXISTS (
      SELECT 1
      FROM `pacific-plating-282708.careos.cancelled_change_orders` cs
      WHERE cs.current_human_id = r.order_id OR cs.old_human_id = r.order_id
    ) AS credit_shell_boundary,
    CASE
      WHEN cm.U_OrderItem IS NOT NULL
       AND ROUND(cm.U_ActualReceived, 2) = ROUND(r.non_cmi_actual, 2)
       AND NULLIF(TRIM(cm.U_InvoiceNo), '') = NULLIF(TRIM(r.non_cmi_invoice_no), '')
        THEN 'SHARED_FULL_PAYMENT_OTHER_FINDING'
      WHEN cm.U_OrderItem IS NOT NULL
       AND cm.TransactionStatus = 'Paid'
       AND ROUND(cm.U_ActualReceived, 2) = ROUND(cm.ExpectedReceived, 2)
        THEN 'INCIDENT_002A_PURE'
      ELSE 'UNCLASSIFIED_REQUIRES_HUMAN_REVIEW'
    END AS mechanism_shape
  FROM raw_002a_arithmetic r
  LEFT JOIN mirror_current cm
    ON cm.U_OrderItem = r.cmi_order_item
   AND cm.U_Period = r.period
),
summary AS (
  SELECT
    mechanism_shape,
    credit_shell_boundary,
    COUNT(*) AS records,
    COUNT(DISTINCT order_id) AS orders,
    ROUND(SUM(excess_amount), 2) AS excess_amount
  FROM classified
  GROUP BY mechanism_shape, credit_shell_boundary
)
SELECT
  mechanism_shape,
  credit_shell_boundary,
  records,
  orders,
  excess_amount
FROM summary
ORDER BY mechanism_shape, credit_shell_boundary;

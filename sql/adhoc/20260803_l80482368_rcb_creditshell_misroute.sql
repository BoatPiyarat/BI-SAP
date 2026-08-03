-- Class A, read-only diagnostic. Source-only; do not deploy.
-- Grain: FULL_PAYMENT change orders whose SAP-posted M1 row is labelled RCL-Credit Shell.
-- Run with asia-southeast1 and maximum_bytes_billed=21474836480; dry-run first.

WITH current_snapshot AS (
  SELECT * EXCEPT (_rn)
  FROM (
    SELECT s.*, ROW_NUMBER() OVER (
      PARTITION BY transaction_id
      ORDER BY is_current DESC, update_time DESC, create_time DESC, id DESC
    ) AS _rn
    FROM `pacific-plating-282708.careos.carepay_transaction_snapshots` AS s
  )
  WHERE _rn = 1
),
source_rcb_change AS (
  SELECT
    o.human_id AS order_id,
    oi.human_id AS order_item,
    oi.motor_item_type,
    t.payment_option,
    t.installments,
    s.number_of_installment,
    change_order.old_human_id AS old_order_id
  FROM `pacific-plating-282708.careos.careos_orders` AS o
  JOIN `pacific-plating-282708.careos.careos_order_items` AS oi ON oi.order_id = o.id
  JOIN `pacific-plating-282708.careos.carepay_transactions` AS t
    ON CONCAT('transactions/', t.id) = o.payment
  JOIN current_snapshot AS s ON s.transaction_id = t.id
  JOIN `pacific-plating-282708.careos.cancelled_change_orders` AS change_order
    ON change_order.current_human_id = o.human_id
  WHERE t.payment_option = 'FULL_PAYMENT'
    AND t.installments = 1
    AND s.number_of_installment = 1
),
posted_latest AS (
  SELECT * EXCEPT (_rn)
  FROM (
    SELECT sap.*, ROW_NUMBER() OVER (
      PARTITION BY U_OrderItem, U_Period
      ORDER BY UpdateDate DESC, SAFE_CAST(DocEntry AS INT64) DESC
    ) AS _rn
    FROM `pacific-plating-282708.sap_integration_v2.SAP_LIVE_FULL` AS sap
    WHERE SAFE_CAST(DocEntry AS INT64) IS NOT NULL
  )
  WHERE _rn = 1
),
evidence AS (
  SELECT
    source.*,
    sap.DocEntry,
    sap.PaymentMethod,
    sap.PaymentChannel,
    sap.TransactionStatus,
    REGEXP_CONTAINS(
      UPPER(CONCAT(IFNULL(sap.PaymentMethod, ''), '|', IFNULL(sap.PaymentChannel, ''))),
      r'RCL[- ]?CREDIT[ -]?SHELL'
    ) AS has_wrong_rcl_credit_shell_label
  FROM source_rcb_change AS source
  LEFT JOIN posted_latest AS sap ON sap.U_OrderItem = source.order_item
)
SELECT
  COUNT(DISTINCT order_id) AS source_rcb_change_orders,
  COUNT(DISTINCT order_item) AS source_rcb_change_items,
  COUNT(DISTINCT IF(DocEntry IS NOT NULL, order_id, NULL)) AS posted_orders,
  COUNT(DISTINCT IF(DocEntry IS NOT NULL, order_item, NULL)) AS posted_items,
  COUNT(DISTINCT IF(has_wrong_rcl_credit_shell_label, order_id, NULL)) AS exact_wrong_orders,
  COUNT(DISTINCT IF(has_wrong_rcl_credit_shell_label, order_item, NULL)) AS exact_wrong_items,
  COUNT(DISTINCT IF(
    has_wrong_rcl_credit_shell_label AND motor_item_type = 'MOTOR_TYPE_COMPULSORY',
    order_id, NULL
  )) AS exact_wrong_m1_orders
FROM evidence;

-- Full source-only legacy root-fix proposal for:
--   pacific-plating-282708.sap_view.RCB_Motor_process_2_cancel_new
--
-- Root fixes from SAP Upload LogID 22049:
--   1. Emit only one current SAP document per (OrderItem, Period), using the
--      established status/invoice/date/DocEntry precedence.
--   2. Require the complete 1..TotalPeriods spine to exist in SAP already.
--      Do not synthesize missing periods from the CareOS dashboard and attempt
--      to cancel them in the same file. Such items wait for a separate
--      create/pending -> SAP refresh -> cancel sequence.
--   3. Hold the whole item when SAP is Pending but CareOS already has a
--      SUCCESSFUL charge for that period. Paid must reach SAP first.
--   4. Require Period 1 to be Paid and all later predecessor rows to be
--      Paid/Pending, matching the SAP cancel contract.
--   5. Normalize SQL NULL, blank, and literal NULL ProductType to Insurance.
--   6. Hold material TotalEIR-versus-period-interest inconsistencies; do not
--      rewrite historical accounting values. For valid items, canonicalize the
--      harmless <= 0.01 rounding difference to the period-interest sum.
--   7. Preserve SAP InvoiceNo/PaymentDate and Pending amounts verbatim; Pending
--      PaymentMethod and PaymentChannel remain blank.
--   8. Scope by the 2026 CareOS cancellation event, not original OrderDate, and
--      exclude Test items. is_cancelled=true with NULL cancel_time remains held
--      for human investigation.
--
-- SELECT only: this file does not replace or deploy the live legacy view.

WITH
  sap_distinct AS (
    SELECT DISTINCT *
    FROM `pacific-plating-282708.sap_integration_v2.SAP_LIVE_FULL`
  ),

  sap_ranked AS (
    SELECT
      sap_distinct.*,
      ROW_NUMBER() OVER (
        PARTITION BY U_OrderItem, SAFE_CAST(U_Period AS INT64)
        ORDER BY
          CASE
            WHEN TransactionStatus IN ('Cancelled', 'Cancelled (Change order / Rejected)') THEN 0
            WHEN LOWER(TransactionStatus) = 'paid' THEN 1
            WHEN LOWER(TransactionStatus) = 'pending' THEN 2
            ELSE 3
          END,
          CASE
            WHEN NULLIF(TRIM(COALESCE(U_InvoiceNo, '')), '') IS NOT NULL
              AND UPPER(TRIM(U_InvoiceNo)) != 'NULL'
            THEN 0 ELSE 1
          END,
          SAFE.PARSE_DATE('%d%m%Y', NULLIF(BatchRunDate, '')) DESC,
          DocEntry DESC
      ) AS current_doc_rank,
      MAX(
        CASE
          WHEN U_OrderID LIKE 'C#%'
            OR TransactionStatus IN ('Cancelled', 'Cancelled (Change order / Rejected)')
          THEN 1 ELSE 0
        END
      ) OVER (PARTITION BY U_OrderItem) AS is_already_cancelled_flag
    FROM sap_distinct
    WHERE U_OrderItem IS NOT NULL
      AND U_Period IS NOT NULL
  ),

  sap_current AS (
    SELECT * EXCEPT (current_doc_rank)
    FROM sap_ranked
    WHERE current_doc_rank = 1
  ),

  cancelled_items_2026 AS (
    SELECT
      order_item.human_id AS OrderItem,
      orders.human_id AS CareOSOrderID,
      transactions.id AS transaction_id,
      order_item.cancel_time
    FROM `pacific-plating-282708.careos.careos_order_items` AS order_item
    JOIN `pacific-plating-282708.careos.careos_orders` AS orders
      ON orders.id = order_item.order_id
    LEFT JOIN `pacific-plating-282708.careos.carepay_transactions` AS transactions
      ON CONCAT('transactions/', transactions.id) = orders.payment
    WHERE order_item.cancel_time IS NOT NULL
      AND DATE(order_item.cancel_time) >= DATE '2026-01-01'
  ),

  base_eligible_items AS (
    SELECT DISTINCT sap_current.U_OrderItem AS OrderItem
    FROM sap_current
    JOIN cancelled_items_2026
      ON cancelled_items_2026.OrderItem = sap_current.U_OrderItem
    WHERE sap_current.is_already_cancelled_flag = 0
      AND sap_current.U_OrderID NOT LIKE 'C#%'
      AND sap_current.U_OrderID NOT LIKE '%_X%'
      AND NOT EXISTS (
        SELECT 1
        FROM sap_current AS test_row
        WHERE test_row.U_OrderItem = sap_current.U_OrderItem
          AND (
            LOWER(TRIM(COALESCE(test_row.U_FirstName, ''))) = 'test'
            OR LOWER(TRIM(COALESCE(test_row.U_LastName, ''))) = 'test'
          )
      )
  ),

  spine_metrics AS (
    SELECT
      sap_current.U_OrderItem AS OrderItem,
      COUNT(*) AS row_count,
      COUNT(DISTINCT SAFE_CAST(sap_current.U_Period AS INT64)) AS distinct_period_count,
      MIN(SAFE_CAST(sap_current.U_Period AS INT64)) AS min_period,
      MAX(SAFE_CAST(sap_current.U_Period AS INT64)) AS max_period,
      MAX(SAFE_CAST(sap_current.TotalPeriods AS INT64)) AS canonical_total_periods,
      COUNTIF(
        SAFE_CAST(sap_current.U_Period AS INT64) = 1
          AND LOWER(sap_current.TransactionStatus) = 'paid'
      ) AS paid_first_period_rows,
      COUNTIF(
        LOWER(sap_current.TransactionStatus) NOT IN ('paid', 'pending')
      ) AS invalid_predecessor_rows,
      MAX(COALESCE(SAFE_CAST(sap_current.TotalEIR AS FLOAT64), 0)) AS max_total_eir,
      MIN(COALESCE(SAFE_CAST(sap_current.TotalEIR AS FLOAT64), 0)) AS min_total_eir,
      ROUND(SUM(COALESCE(SAFE_CAST(sap_current.U_InterestEIRThisPeriod AS FLOAT64), 0)), 2)
        AS period_interest_eir_sum
    FROM sap_current
    JOIN base_eligible_items
      ON base_eligible_items.OrderItem = sap_current.U_OrderItem
    GROUP BY sap_current.U_OrderItem
  ),

  stale_pending_paid_items AS (
    SELECT DISTINCT sap_current.U_OrderItem AS OrderItem
    FROM sap_current
    JOIN base_eligible_items
      ON base_eligible_items.OrderItem = sap_current.U_OrderItem
    JOIN cancelled_items_2026
      ON cancelled_items_2026.OrderItem = sap_current.U_OrderItem
    JOIN `pacific-plating-282708.careos.carepay_charges` AS charge
      ON charge.transaction_id = cancelled_items_2026.transaction_id
     AND charge.installment_number = SAFE_CAST(sap_current.U_Period AS INT64)
     AND charge.status = 'SUCCESSFUL'
    WHERE LOWER(sap_current.TransactionStatus) = 'pending'
  ),

  ready_items AS (
    SELECT
      spine_metrics.OrderItem,
      spine_metrics.canonical_total_periods,
      spine_metrics.period_interest_eir_sum AS canonical_total_eir
    FROM spine_metrics
    WHERE spine_metrics.canonical_total_periods >= 1
      AND spine_metrics.row_count = spine_metrics.canonical_total_periods
      AND spine_metrics.distinct_period_count = spine_metrics.canonical_total_periods
      AND spine_metrics.min_period = 1
      AND spine_metrics.max_period = spine_metrics.canonical_total_periods
      AND spine_metrics.paid_first_period_rows = 1
      AND spine_metrics.invalid_predecessor_rows = 0
      AND ABS(spine_metrics.max_total_eir - spine_metrics.min_total_eir) <= 0.01
      AND ABS(spine_metrics.max_total_eir - spine_metrics.period_interest_eir_sum) <= 0.01
      AND NOT EXISTS (
        SELECT 1
        FROM stale_pending_paid_items AS stale
        WHERE stale.OrderItem = spine_metrics.OrderItem
      )
  )

SELECT a.order_item,COUNT(DISTINCT a.cancellation_docentry) AS missing_documents,
 ANY_VALUE(m.row_count) AS selected_period_rows,ANY_VALUE(m.canonical_total_periods) AS total_periods,
 ANY_VALUE(m.paid_first_period_rows) AS paid_first_period_rows,ANY_VALUE(m.invalid_predecessor_rows) AS invalid_predecessor_rows,
 ANY_VALUE(m.min_period) AS min_period,ANY_VALUE(m.max_period) AS max_period,
 ANY_VALUE(m.min_total_eir) AS min_total_eir,ANY_VALUE(m.max_total_eir) AS max_total_eir,
 ANY_VALUE(m.period_interest_eir_sum) AS period_interest_eir_sum,
 COUNTIF(b.OrderItem IS NOT NULL)>0 AS base_eligible,
 COUNTIF(st.OrderItem IS NOT NULL)>0 AS stale_pending_paid,
 COUNTIF(r.OrderItem IS NOT NULL)>0 AS ready_item,
 MAX(sc.is_already_cancelled_flag) AS already_cancelled_flag
FROM `pacific-plating-282708._script854956d6400364d5179432334ac884bec17498b8.audit_result` a
LEFT JOIN sap_current sc ON sc.U_OrderItem=a.order_item
LEFT JOIN base_eligible_items b ON b.OrderItem=a.order_item
LEFT JOIN spine_metrics m ON m.OrderItem=a.order_item
LEFT JOIN stale_pending_paid_items st ON st.OrderItem=a.order_item
LEFT JOIN ready_items r ON r.OrderItem=a.order_item
WHERE a.event_type='CANCELLATION' AND a.reconciliation_status='MISSING_TERMINAL_SAP_EVIDENCE'
GROUP BY a.order_item;

-- Read-only regression for the eligibility gates in the full legacy proposal.

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
      MAX(IF(
        U_OrderID LIKE 'C#%'
          OR TransactionStatus IN ('Cancelled', 'Cancelled (Change order / Rejected)'),
        1, 0
      )) OVER (PARTITION BY U_OrderItem) AS is_already_cancelled_flag
    FROM sap_distinct
    WHERE U_OrderItem IS NOT NULL AND U_Period IS NOT NULL
  ),
  sap_current AS (
    SELECT * EXCEPT (current_doc_rank)
    FROM sap_ranked
    WHERE current_doc_rank = 1
  ),
  cancelled_items_2026 AS (
    SELECT
      oi.human_id AS OrderItem,
      tx.id AS transaction_id
    FROM `pacific-plating-282708.careos.careos_order_items` AS oi
    JOIN `pacific-plating-282708.careos.careos_orders` AS o ON o.id = oi.order_id
    LEFT JOIN `pacific-plating-282708.careos.carepay_transactions` AS tx
      ON CONCAT('transactions/', tx.id) = o.payment
    WHERE oi.cancel_time IS NOT NULL
      AND DATE(oi.cancel_time) >= DATE '2026-01-01'
  ),
  base_items AS (
    SELECT DISTINCT s.U_OrderItem AS OrderItem
    FROM sap_current AS s
    JOIN cancelled_items_2026 AS c ON c.OrderItem = s.U_OrderItem
    WHERE s.is_already_cancelled_flag = 0
      AND s.U_OrderID NOT LIKE 'C#%'
      AND s.U_OrderID NOT LIKE '%_X%'
      AND NOT EXISTS (
        SELECT 1 FROM sap_current AS t
        WHERE t.U_OrderItem = s.U_OrderItem
          AND (LOWER(TRIM(COALESCE(t.U_FirstName, ''))) = 'test'
            OR LOWER(TRIM(COALESCE(t.U_LastName, ''))) = 'test')
      )
  ),
  metrics AS (
    SELECT
      s.U_OrderItem AS OrderItem,
      ANY_VALUE(s.U_OrderID) AS OrderID,
      COUNT(*) AS row_count,
      COUNT(DISTINCT SAFE_CAST(s.U_Period AS INT64)) AS period_count,
      MIN(SAFE_CAST(s.U_Period AS INT64)) AS min_period,
      MAX(SAFE_CAST(s.U_Period AS INT64)) AS max_period,
      MAX(SAFE_CAST(s.TotalPeriods AS INT64)) AS total_periods,
      COUNTIF(SAFE_CAST(s.U_Period AS INT64) = 1 AND LOWER(s.TransactionStatus) = 'paid') AS p1_paid,
      COUNTIF(LOWER(s.TransactionStatus) NOT IN ('paid', 'pending')) AS invalid_status,
      MAX(COALESCE(SAFE_CAST(s.TotalEIR AS FLOAT64), 0)) AS max_total_eir,
      MIN(COALESCE(SAFE_CAST(s.TotalEIR AS FLOAT64), 0)) AS min_total_eir,
      ROUND(SUM(COALESCE(SAFE_CAST(s.U_InterestEIRThisPeriod AS FLOAT64), 0)), 2) AS eir_sum,
      COUNTIF(
        NULLIF(TRIM(COALESCE(s.U_ProductType, '')), '') IS NULL
          OR UPPER(TRIM(s.U_ProductType)) = 'NULL'
      ) AS blank_product_type_rows
    FROM sap_current AS s
    JOIN base_items AS b ON b.OrderItem = s.U_OrderItem
    GROUP BY s.U_OrderItem
  ),
  stale AS (
    SELECT DISTINCT s.U_OrderItem AS OrderItem
    FROM sap_current AS s
    JOIN base_items AS b ON b.OrderItem = s.U_OrderItem
    JOIN cancelled_items_2026 AS ci ON ci.OrderItem = s.U_OrderItem
    JOIN `pacific-plating-282708.careos.carepay_charges` AS c
      ON c.transaction_id = ci.transaction_id
     AND c.installment_number = SAFE_CAST(s.U_Period AS INT64)
     AND c.status = 'SUCCESSFUL'
    WHERE LOWER(s.TransactionStatus) = 'pending'
  ),
  classified AS (
    SELECT
      m.*,
      stale.OrderItem IS NOT NULL AS has_stale_pending_paid,
      NOT (
        total_periods >= 1
        AND row_count = total_periods
        AND period_count = total_periods
        AND min_period = 1
        AND max_period = total_periods
      ) AS incomplete_sap_spine,
      ABS(max_total_eir - min_total_eir) > 0.01
        OR ABS(max_total_eir - eir_sum) > 0.01 AS eir_mismatch,
      (
        total_periods >= 1
        AND row_count = total_periods
        AND period_count = total_periods
        AND min_period = 1
        AND max_period = total_periods
        AND p1_paid = 1
        AND invalid_status = 0
        AND ABS(max_total_eir - min_total_eir) <= 0.01
        AND ABS(max_total_eir - eir_sum) <= 0.01
        AND stale.OrderItem IS NULL
      ) AS is_ready
    FROM metrics AS m
    LEFT JOIN stale USING (OrderItem)
  ),
  target AS (
    SELECT *
    FROM classified
    WHERE OrderID IN (
      'L74079056', 'L77083183', 'L77121047', 'L77833033',
      'L79180940', 'L79308561', 'L79510340', 'L79949677',
      'L80511750', 'L80513404', 'L80518454'
    )
  )
SELECT
  CURRENT_TIMESTAMP() AS checked_at_utc,
  (SELECT COUNT(*) FROM classified) AS candidate_items_before_gates,
  (SELECT COUNTIF(is_ready) FROM classified) AS ready_items,
  (SELECT COUNTIF(incomplete_sap_spine) FROM classified) AS incomplete_spine_items,
  (SELECT COUNTIF(has_stale_pending_paid) FROM classified) AS stale_pending_paid_items,
  (SELECT COUNTIF(p1_paid != 1) FROM classified) AS first_period_not_paid_items,
  (SELECT COUNTIF(invalid_status > 0) FROM classified) AS invalid_status_items,
  (SELECT COUNTIF(eir_mismatch) FROM classified) AS eir_mismatch_items,
  (SELECT SUM(blank_product_type_rows) FROM classified) AS product_type_rows_normalized,
  (SELECT COUNT(*) FROM target) AS target_items,
  (SELECT COUNTIF(is_ready) FROM target) AS target_ready_items,
  (SELECT COUNTIF(incomplete_sap_spine) FROM target) AS target_incomplete_items,
  (SELECT COUNTIF(has_stale_pending_paid) FROM target) AS target_stale_pending_paid_items,
  (SELECT COUNTIF(eir_mismatch) FROM target) AS target_eir_mismatch_items,
  (SELECT SUM(IF(is_ready, blank_product_type_rows, 0)) FROM target) AS target_ready_product_types_fixed,
  ARRAY(
    SELECT AS STRUCT
      OrderID, OrderItem, is_ready, incomplete_sap_spine,
      has_stale_pending_paid, p1_paid, invalid_status, eir_mismatch,
      blank_product_type_rows
    FROM target
    ORDER BY OrderID, OrderItem
  ) AS target_detail;

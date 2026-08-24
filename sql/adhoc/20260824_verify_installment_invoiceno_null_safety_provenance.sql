-- CLASS A / READ ONLY.
-- Reproducible provenance for the InvoiceNo NULL-safety fix in commits a3d0305 + 0ac324f.
--
-- Direct source object (live baseline, not the repository capture):
--   pacific-plating-282708.sap_data_engineer.sap_dashboard_carepay_installment
-- BigQuery job metadata expands that view to these referenced base tables in `careos`:
--   cancelled_change_orders, careos_leads, careos_order_items, careos_orders, carepay_charges,
--   carepay_follow_ups, carepay_payment_options, carepay_prices, carepay_refunds,
--   carepay_transaction_snapshot_installment_details,
--   carepay_transaction_snapshot_price_summaries, carepay_transaction_snapshots,
--   carepay_transactions.
-- Live definition fetched with `bq show --format=prettyjson` on 2026-08-24. It still contains the
-- old NULL-unsafe final predicate and the production-only outer PaymentDate/BatchRunDate wrapper.
--
-- Candidate derivation below changes only final InvoiceNo semantics:
--   non-paid SQL NULL -> canonical empty string; paid InvoiceNo is preserved verbatim.
-- This is equivalent at the final output seam to changing the raw transformation predicate from
-- `TransactionStatus <> 'SUCCESSFUL'` to `COALESCE(TransactionStatus,'') <> 'SUCCESSFUL'`.
-- All other output columns and row grain come directly from the same live rows in the same scan.

WITH live_baseline AS (
  SELECT
    OrderItem,
    Period,
    TransactionStatus,
    InvoiceNo
  FROM `pacific-plating-282708.sap_data_engineer.sap_dashboard_carepay_installment`
),
comparison AS (
  SELECT
    *,
    CASE
      WHEN InvoiceNo IS NULL
        AND LOWER(COALESCE(TransactionStatus, '')) <> 'paid'
      THEN ''
      ELSE InvoiceNo
    END AS candidate_InvoiceNo
  FROM live_baseline
)
SELECT
  CURRENT_TIMESTAMP() AS source_timestamp_utc,
  COUNT(*) AS total_rows,
  COUNT(DISTINCT OrderItem) AS distinct_orderitems,
  COUNTIF(LOWER(TransactionStatus) = 'paid') AS paid_rows,
  COUNTIF(LOWER(TransactionStatus) <> 'paid' OR TransactionStatus IS NULL) AS non_paid_rows,
  COUNTIF(InvoiceNo IS NULL) AS baseline_invoiceno_null_count,
  COUNTIF(InvoiceNo = '') AS baseline_invoiceno_blank_count,
  COUNTIF(candidate_InvoiceNo IS NULL) AS candidate_invoiceno_null_count,
  COUNTIF(candidate_InvoiceNo = '') AS candidate_invoiceno_blank_count,
  COUNTIF(
    InvoiceNo IS NULL
    AND candidate_InvoiceNo = ''
    AND (LOWER(TransactionStatus) <> 'paid' OR TransactionStatus IS NULL)
  ) AS changed_non_paid_null_to_blank,
  COUNTIF(
    LOWER(TransactionStatus) = 'paid'
    AND candidate_InvoiceNo IS DISTINCT FROM InvoiceNo
  ) AS paid_invoiceno_changed,
  COUNTIF(
    LOWER(TransactionStatus) = 'paid'
    AND candidate_InvoiceNo IS NULL
  ) AS residual_paid_invoiceno_null_count,
  COUNTIF(
    OrderItem = 'L77833033-V1'
    AND Period = 1
    AND candidate_InvoiceNo IS DISTINCT FROM InvoiceNo
  ) AS scoped_paid_period1_changed,
  COUNTIF(
    OrderItem = 'L77833033-V1'
    AND Period BETWEEN 2 AND 6
    AND InvoiceNo IS NULL
    AND candidate_InvoiceNo = ''
  ) AS scoped_pending_periods_changed_to_blank
FROM comparison;

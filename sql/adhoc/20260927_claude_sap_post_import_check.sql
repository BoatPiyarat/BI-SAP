-- READ-ONLY. Post-import check (SAP_LIVE_FULL) after SAP_LIVE refresh (2026-09-26T23:49Z).
-- 1) Did the two reported extra receipts reach SAP?  2) How many rank>1 voluntary RCL Motor
-- invoices appear in SAP with UpdateDate on/after 2026-09-27 (i.e. from the 20260926 files)?
-- 3) Duplicate SAP documents for those identities. Aggregates only, no customer fields.
WITH ch AS (
  SELECT transaction_id, installment_number, third_party_id,
    ROW_NUMBER() OVER (PARTITION BY transaction_id, installment_number ORDER BY create_time, id) AS rk
  FROM `pacific-plating-282708.careos.carepay_charges`
  WHERE status = 'SUCCESSFUL' AND service_provider = 'RABBIT_LENDING'
),
rk2 AS (
  SELECT DISTINCT oi.human_id AS order_item, ch.installment_number AS period,
    IF(ch.installment_number = 1, CONCAT('2_', ch.third_party_id), ch.third_party_id) AS invoice_no
  FROM ch
  JOIN `pacific-plating-282708.careos.careos_orders` o ON o.payment = CONCAT('transactions/', ch.transaction_id)
  JOIN `pacific-plating-282708.careos.careos_order_items` oi ON oi.order_id = o.id
  WHERE ch.rk > 1 AND ch.third_party_id IS NOT NULL
    AND oi.product = 'products/car-insurance' AND oi.motor_item_type <> 'MOTOR_TYPE_COMPULSORY'
),
sap AS (
  SELECT U_OrderItem AS order_item, SAFE_CAST(U_Period AS INT64) AS period, U_InvoiceNo AS invoice_no,
    DocEntry, TransactionStatus, SAFE_CAST(ExpectedReceived AS FLOAT64) AS e,
    SAFE_CAST(U_ActualReceived AS FLOAT64) AS a, SAFE.PARSE_DATE('%Y-%m-%d', SUBSTR(CAST(UpdateDate AS STRING), 1, 10)) AS upd
  FROM `pacific-plating-282708.sap_integration_v2.SAP_LIVE_FULL`
),
m AS (SELECT s.* FROM sap s JOIN rk2 r USING (order_item, period, invoice_no))
SELECT
  (SELECT MAX(upd) FROM sap) AS sap_max_update_date,
  (SELECT COUNT(*) FROM m WHERE order_item IN ('L80570054-V1','L79109956-V1')) AS target_extra_rows_in_sap,
  (SELECT COUNT(*) FROM m) AS rank_gt1_rows_in_sap_all_time,
  (SELECT COUNT(*) FROM m WHERE upd >= DATE '2026-09-27') AS rank_gt1_rows_updated_0927,
  (SELECT COUNT(DISTINCT CONCAT(order_item,'|',period,'|',invoice_no)) FROM m WHERE upd >= DATE '2026-09-27') AS rank_gt1_identities_0927,
  (SELECT ROUND(SUM(a),2) FROM m WHERE upd >= DATE '2026-09-27') AS rank_gt1_actual_thb_0927,
  (SELECT COUNTIF(e = 0) FROM m WHERE upd >= DATE '2026-09-27') AS rank_gt1_0927_expected_zero,
  (SELECT COUNT(*) FROM (SELECT order_item, period, invoice_no FROM m WHERE upd >= DATE '2026-09-27'
     GROUP BY 1,2,3 HAVING COUNT(DISTINCT DocEntry) > 1)) AS dup_docentry_identities_0927,
  (SELECT ARRAY_AGG(STRUCT(TransactionStatus, n)) FROM (SELECT TransactionStatus, COUNT(*) n FROM m
     WHERE upd >= DATE '2026-09-27' GROUP BY 1)) AS status_0927

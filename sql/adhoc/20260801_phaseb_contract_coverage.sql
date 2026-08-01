-- Phase B gate: coverage of V3 expected_state by verified 56-column CareOS source views.
-- Read-only. Run with dry-run first, asia-southeast1, and 20 GiB ceiling.
WITH fp AS (
  SELECT OrderItem AS order_item, SAFE_CAST(Period AS INT64) AS period, COUNT(*) AS source_rows
  FROM `pacific-plating-282708.sap_data_engineer.sap_dashboard_carepay_fully_paid`
  GROUP BY order_item, period
), inst AS (
  SELECT OrderItem AS order_item, SAFE_CAST(Period AS INT64) AS period, COUNT(*) AS source_rows
  FROM `pacific-plating-282708.sap_data_engineer.sap_dashboard_carepay_installment`
  GROUP BY order_item, period
), joined AS (
  SELECT e.order_item, e.period, e.flow,
    fp.order_item IS NOT NULL AS in_fully_paid,
    inst.order_item IS NOT NULL AS in_installment,
    IFNULL(fp.source_rows, 0) AS fp_rows,
    IFNULL(inst.source_rows, 0) AS inst_rows
  FROM `pacific-plating-282708.sap_integration_v3.expected_state` e
  LEFT JOIN fp USING (order_item, period)
  LEFT JOIN inst USING (order_item, period)
), overall AS (
  SELECT COUNT(*) AS expected_records,
    COUNTIF(in_fully_paid) AS covered_fully_paid,
    COUNTIF(in_installment) AS covered_installment,
    COUNTIF(in_fully_paid AND in_installment) AS covered_both,
    COUNTIF(NOT in_fully_paid AND NOT in_installment) AS uncovered,
    COUNTIF(fp_rows > 1) AS fully_paid_duplicate_keys,
    COUNTIF(inst_rows > 1) AS installment_duplicate_keys
  FROM joined
), by_flow AS (
  SELECT flow, COUNT(*) AS records,
    COUNTIF(NOT in_fully_paid AND NOT in_installment) AS uncovered_records
  FROM joined
  GROUP BY flow
)
SELECT overall.*,
  (SELECT ARRAY_AGG(STRUCT(flow, records, uncovered_records) ORDER BY flow) FROM by_flow) AS by_flow
FROM overall;

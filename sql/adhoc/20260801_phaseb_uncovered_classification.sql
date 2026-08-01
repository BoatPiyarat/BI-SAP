-- Phase-B hard gate: classify 56-column source coverage gaps without writing data.
WITH fp AS (
  SELECT OrderItem AS order_item, SAFE_CAST(Period AS INT64) AS period, COUNT(*) source_rows
  FROM `pacific-plating-282708.sap_data_engineer.sap_dashboard_carepay_fully_paid`
  GROUP BY 1,2
), inst AS (
  SELECT OrderItem AS order_item, SAFE_CAST(Period AS INT64) AS period, COUNT(*) source_rows
  FROM `pacific-plating-282708.sap_data_engineer.sap_dashboard_carepay_installment`
  GROUP BY 1,2
), source_items AS (
  SELECT order_item, LOGICAL_OR(source_name='FP') in_fp_item, LOGICAL_OR(source_name='INST') in_inst_item
  FROM (
    SELECT DISTINCT order_item, 'FP' source_name FROM fp
    UNION ALL SELECT DISTINCT order_item, 'INST' FROM inst
  ) GROUP BY order_item
), uncovered AS (
  SELECT e.*, IFNULL(si.in_fp_item,FALSE) in_fp_item, IFNULL(si.in_inst_item,FALSE) in_inst_item
  FROM `pacific-plating-282708.sap_integration_v3.expected_state` e
  LEFT JOIN fp USING(order_item,period)
  LEFT JOIN inst USING(order_item,period)
  LEFT JOIN source_items si USING(order_item)
  WHERE fp.order_item IS NULL AND inst.order_item IS NULL
), classified AS (
  SELECT *, CASE
    WHEN in_fp_item OR in_inst_item THEN 'ORDER_ITEM_PRESENT_PERIOD_MISSING'
    WHEN charge_id IS NULL THEN 'NO_CHARGE_EVENT_PENDING_SPINE'
    ELSE 'PAID_KEY_ABSENT_FROM_BOTH_SOURCES'
  END gap_class
  FROM uncovered
)
SELECT
  (SELECT COUNT(*) FROM classified) uncovered_records,
  (SELECT COUNT(DISTINCT order_item) FROM classified) uncovered_items,
  (SELECT ARRAY_AGG(STRUCT(gap_class, records, items, july_output_payment, august_output_payment)
      ORDER BY gap_class)
   FROM (
     SELECT gap_class, COUNT(*) records, COUNT(DISTINCT order_item) items,
       COUNTIF(expected_payment_date >= DATE '2026-07-01' AND expected_payment_date < DATE '2026-08-01') july_output_payment,
       COUNTIF(expected_payment_date >= DATE '2026-08-01' AND expected_payment_date < DATE '2026-09-01') august_output_payment
     FROM classified GROUP BY gap_class
   )) classes,
  (SELECT ARRAY_AGG(STRUCT(flow, expected_status, records) ORDER BY flow, expected_status)
   FROM (SELECT flow, expected_status, COUNT(*) records FROM classified GROUP BY flow, expected_status)) flow_status;

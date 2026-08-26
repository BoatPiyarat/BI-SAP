-- Read-only deterministic Scenario 3 zero-ready feedback loop.
DECLARE v_run_id STRING DEFAULT 'V3NIGHTLY-2026-08-26T13:23:38-e830fff2';

SELECT
  IF(s.released_identity_rows=0,'RED_ZERO_READY','GREEN_READY') AS repro_verdict,
  s.*,
  (SELECT COUNT(*)
   FROM `pacific-plating-282708.sap_integration_v3.v3_rcl_later_newpayment_hold`
   WHERE pipeline_run_id=v_run_id) AS durable_hold_rows,
  (SELECT COUNT(*)
   FROM `pacific-plating-282708.sap_integration_v3.v3_rcl_later_newpayment_ready`) AS live_ready_rows
FROM `pacific-plating-282708.sap_integration_v3.v3_rcl_later_newpayment_summary` s
WHERE s.pipeline_run_id=v_run_id;

SELECT hold_code,COUNT(*) AS identity_rows,
  COUNT(DISTINCT order_item) AS order_items,
  COUNTIF(period<=1) AS non_later_period_rows,
  COUNTIF(NULLIF(invoice_no,'') IS NULL) AS blank_invoice_rows
FROM `pacific-plating-282708.sap_integration_v3.v3_rcl_later_newpayment_hold`
WHERE pipeline_run_id=v_run_id
GROUP BY hold_code
ORDER BY identity_rows DESC,hold_code;

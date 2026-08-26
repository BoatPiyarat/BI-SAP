-- HUMAN FALLBACK / READ ONLY. Scenario 2 RCL first-period CREATE hold-only report.
-- This scenario intentionally exports zero interface rows until InvoiceNo mapping is approved.

DECLARE target_run_id STRING DEFAULT 'REPLACE_WITH_REVIEWED_PIPELINE_RUN_ID';

ASSERT target_run_id!='REPLACE_WITH_REVIEWED_PIPELINE_RUN_ID'
  AS 'Set target_run_id to the exact reviewed pipeline run';
ASSERT (SELECT COUNT(*)
  FROM `pacific-plating-282708.sap_integration_v3.v3_rcl_first_create_gate_summary`
  WHERE pipeline_run_id=target_run_id)=1
  AS 'Scenario 2 requires exactly one durable gate summary';
ASSERT (SELECT gate_status='BLOCKED_NO_APPROVED_INVOICE_MAPPING'
  FROM `pacific-plating-282708.sap_integration_v3.v3_rcl_first_create_gate_summary`
  WHERE pipeline_run_id=target_run_id)
  AS 'Scenario 2 is not in the reviewed hold-only state';
ASSERT (SELECT ready_identity_rows=0
  FROM `pacific-plating-282708.sap_integration_v3.v3_rcl_first_create_gate_summary`
  WHERE pipeline_run_id=target_run_id)
  AS 'Scenario 2 must emit zero ready interface identities';
ASSERT (SELECT input_event_rows=outside_scenario_sap_rows+canonical_identity_rows
    AND canonical_identity_rows=held_identity_rows
  FROM `pacific-plating-282708.sap_integration_v3.v3_rcl_first_create_gate_summary`
  WHERE pipeline_run_id=target_run_id)
  AS 'Scenario 2 router/hold conservation failed';
ASSERT (SELECT held_identity_rows
  FROM `pacific-plating-282708.sap_integration_v3.v3_rcl_first_create_gate_summary`
  WHERE pipeline_run_id=target_run_id)=(SELECT COUNT(*)
  FROM `pacific-plating-282708.sap_integration_v3.v3_rcl_first_create_hold`
  WHERE pipeline_run_id=target_run_id)
  AS 'Scenario 2 durable hold rows differ from gate summary';

SELECT pipeline_run_id,input_event_rows,outside_scenario_sap_rows,canonical_identity_rows,
  held_identity_rows,ready_identity_rows,gate_status,built_at
FROM `pacific-plating-282708.sap_integration_v3.v3_rcl_first_create_gate_summary`
WHERE pipeline_run_id=target_run_id;

SELECT hold_code,COUNT(*) held_rows,
  COUNT(DISTINCT STRUCT(order_item,period,charge_id)) held_identities,
  MIN(detected_at) first_detected_at,MAX(detected_at) last_detected_at
FROM `pacific-plating-282708.sap_integration_v3.v3_rcl_first_create_hold`
WHERE pipeline_run_id=target_run_id
GROUP BY hold_code ORDER BY held_rows DESC,hold_code;

SELECT pipeline_run_id,hold_code,hold_reason,order_item,order_id,period,charge_id,
  raw_invoice_no,staged_invoice_no,event_invoice_no,source_invoice_variants,
  period_source_rows,exact_source_rows,legacy_prefix_rows,detected_at
FROM `pacific-plating-282708.sap_integration_v3.v3_rcl_first_create_hold`
WHERE pipeline_run_id=target_run_id
ORDER BY hold_code,order_item,period,charge_id;

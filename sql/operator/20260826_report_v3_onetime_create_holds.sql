-- HUMAN FALLBACK / READ ONLY. Scenario 1 durable hold report.
-- Replace the sentinel with the same pipeline run used by the manual export query.

DECLARE target_run_id STRING DEFAULT 'REPLACE_WITH_REVIEWED_PIPELINE_RUN_ID';

ASSERT target_run_id!='REPLACE_WITH_REVIEWED_PIPELINE_RUN_ID'
  AS 'Set target_run_id to the exact reviewed pipeline run';
ASSERT (SELECT COUNT(*) FROM `pacific-plating-282708.sap_integration_v3.pipeline_run_log`
  WHERE run_id=target_run_id AND step='UNIT1_COMPLETE' AND status='SUCCESS')=1
  AS 'Hold report requires exactly one successful Unit 1 row';
ASSERT (SELECT COUNT(*) FROM `pacific-plating-282708.sap_integration_v3.v3_unit5_payload_identity`
  WHERE pipeline_run_id=target_run_id AND file_role='CREATE_ONETIME')+
  (SELECT COUNT(*) FROM `pacific-plating-282708.sap_integration_v3.v3_onetime_create_hold`
  WHERE pipeline_run_id=target_run_id)>0
  AS 'No Scenario 1 build evidence exists for target run; refusing an ambiguous empty report';

SELECT hold_code,COUNT(*) AS held_rows,
  COUNT(DISTINCT STRUCT(order_item,period,invoice_no,charge_id)) AS held_identities,
  MIN(detected_at) AS first_detected_at,MAX(detected_at) AS last_detected_at
FROM `pacific-plating-282708.sap_integration_v3.v3_onetime_create_hold`
WHERE pipeline_run_id=target_run_id
GROUP BY hold_code
ORDER BY held_rows DESC,hold_code;

SELECT pipeline_run_id,hold_code,hold_reason,order_item,order_id,period,invoice_no,charge_id,detected_at
FROM `pacific-plating-282708.sap_integration_v3.v3_onetime_create_hold`
WHERE pipeline_run_id=target_run_id
ORDER BY hold_code,order_item,period,invoice_no,charge_id;

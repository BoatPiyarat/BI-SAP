-- Fresh Scenario 1 V2 build only; no Unit 5 archive, interface delivery, or scheduler activation.
DECLARE v_run_id STRING DEFAULT 'V3NIGHTLY-2026-08-27T00:17:51-manual-fresh-sap';

ASSERT (SELECT COUNT(*)
  FROM `pacific-plating-282708.sap_integration_v3.pipeline_run_log`
  WHERE run_id=v_run_id AND step='UNIT1_COMPLETE' AND status='SUCCESS')=1
  AS 'exactly one successful fresh Unit 1 row is required';
ASSERT (SELECT COUNT(*)
  FROM `pacific-plating-282708.sap_integration_v3.v3_onetime_create_build_manifest`
  WHERE pipeline_run_id=v_run_id)=0 AS 'Scenario 1 run already completed';

CALL `pacific-plating-282708.sap_integration_v3.sp_build_v3_unit2_shadow`(v_run_id);
CALL `pacific-plating-282708.sap_integration_v3.sp_evaluate_v3_unit2_magnitude`(v_run_id);
CALL `pacific-plating-282708.sap_integration_v3.sp_build_v3_unit3_mapping_holds`(v_run_id);
CALL `pacific-plating-282708.sap_integration_v3.sp_build_v3_onetime_create_shadow`(v_run_id);
CALL `pacific-plating-282708.sap_integration_v3.sp_snapshot_v3_onetime_create_activation`(v_run_id);

SELECT *
FROM `pacific-plating-282708.sap_integration_v3.vw_v3_business_flow_activation_readiness`
ORDER BY COALESCE(authoritative_scenario_number,999),flow_key;

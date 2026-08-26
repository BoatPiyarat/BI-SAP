-- Durable Scenario 1 activation-readiness evidence for the completed production build.
-- This does not activate a scheduler or write interface rows.
CALL `pacific-plating-282708.sap_integration_v3.sp_snapshot_v3_onetime_create_activation`(
  'V3NIGHTLY-2026-08-26T13:23:38-e830fff2'
);

SELECT *
FROM `pacific-plating-282708.sap_integration_v3.vw_v3_business_flow_activation_readiness`
ORDER BY COALESCE(authoritative_scenario_number, 999), flow_key;

SELECT *
FROM `pacific-plating-282708.sap_integration_v3.vw_v3_scheduler_activation_blockers`
ORDER BY COALESCE(authoritative_scenario_number, 999), flow_key;

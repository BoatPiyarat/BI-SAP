-- Read-only production verification for DDL 100 and DDL 101 definition deployment.
-- This query does not CALL a procedure or mutate lifecycle, archive, manifest, GCS, or SAP state.

ASSERT (SELECT COUNT(*)
  FROM `pacific-plating-282708.sap_integration_v3.INFORMATION_SCHEMA.ROUTINES`
  WHERE routine_name IN (
    'sp_export_v3_scenario3_archive',
    'sp_mark_v3_flow_exact_delivery',
    'sp_register_v3_scenario1_lifecycle')) = 3
  AS 'expected all three Scenario 1/3 lifecycle procedures live';

ASSERT (SELECT COUNT(*)
  FROM `pacific-plating-282708.sap_integration_v3.INFORMATION_SCHEMA.PARAMETERS`
  WHERE specific_name = 'sp_export_v3_scenario3_archive'
    AND ordinal_position > 0) = 3
  AS 'Scenario 3 archive procedure must have exactly 3 parameters';

ASSERT (SELECT COUNT(*)
  FROM `pacific-plating-282708.sap_integration_v3.INFORMATION_SCHEMA.PARAMETERS`
  WHERE specific_name = 'sp_mark_v3_flow_exact_delivery'
    AND ordinal_position > 0) = 12
  AS 'flow delivery marker must have exactly 12 parameters';

ASSERT (SELECT COUNT(*)
  FROM `pacific-plating-282708.sap_integration_v3.INFORMATION_SCHEMA.PARAMETERS`
  WHERE specific_name = 'sp_register_v3_scenario1_lifecycle'
    AND ordinal_position > 0) = 3
  AS 'Scenario 1 lifecycle adapter must have exactly 3 parameters';

ASSERT (SELECT COUNT(*)
  FROM `pacific-plating-282708.sap_integration_v3.INFORMATION_SCHEMA.TABLES`
  WHERE table_name = 'v3_flow_export_claim' AND table_type = 'BASE TABLE') = 1
  AS 'flow export claim table is absent';

ASSERT (SELECT COUNT(*)
  FROM `pacific-plating-282708.sap_integration_v3.INFORMATION_SCHEMA.TABLES`
  WHERE table_name = 'vw_v3_flow_export_lifecycle' AND table_type = 'VIEW') = 1
  AS 'flow export lifecycle view is absent';

ASSERT (SELECT COUNT(*)
  FROM `pacific-plating-282708.sap_integration_v3.v3_flow_export_claim`) = 0
  AS 'definition deployment unexpectedly created a flow export claim';

ASSERT (SELECT COUNT(*)
  FROM `pacific-plating-282708.sap_integration_v3.vw_v3_flow_export_lifecycle`) = 0
  AS 'definition deployment unexpectedly created lifecycle runtime rows';

SELECT routine_name, routine_type,
  TO_HEX(SHA256(routine_definition)) AS routine_definition_sha256
FROM `pacific-plating-282708.sap_integration_v3.INFORMATION_SCHEMA.ROUTINES`
WHERE routine_name IN (
  'sp_export_v3_scenario3_archive',
  'sp_mark_v3_flow_exact_delivery',
  'sp_register_v3_scenario1_lifecycle')
ORDER BY routine_name;

SELECT
  (SELECT COUNT(*)
    FROM `pacific-plating-282708.sap_integration_v3.v3_flow_export_claim`) AS claim_rows,
  (SELECT COUNT(*)
    FROM `pacific-plating-282708.sap_integration_v3.vw_v3_flow_export_lifecycle`)
    AS lifecycle_rows;

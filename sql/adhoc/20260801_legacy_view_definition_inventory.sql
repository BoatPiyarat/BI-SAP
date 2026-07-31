-- Governance inventory: live definitions for legacy datasets represented under sql/production
-- and sql/sap_view. Metadata only; no object mutation.
SELECT 'sap_view' AS table_schema, table_name, view_definition
FROM `pacific-plating-282708.sap_view.INFORMATION_SCHEMA.VIEWS`
UNION ALL
SELECT 'sap_data_engineer', table_name, view_definition
FROM `pacific-plating-282708.sap_data_engineer.INFORMATION_SCHEMA.VIEWS`
UNION ALL
SELECT 'sap_integration_v2', table_name, view_definition
FROM `pacific-plating-282708.sap_integration_v2.INFORMATION_SCHEMA.VIEWS`
ORDER BY table_schema, table_name;

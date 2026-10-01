SELECT CURRENT_TIMESTAMP() checked_at_utc,routine_catalog,routine_schema,routine_name,routine_type,routine_definition FROM `pacific-plating-282708.sap_integration_v3.INFORMATION_SCHEMA.ROUTINES`
UNION ALL
SELECT CURRENT_TIMESTAMP() checked_at_utc,routine_catalog,routine_schema,routine_name,routine_type,routine_definition FROM `pacific-plating-282708.sap_integration_v2.INFORMATION_SCHEMA.ROUTINES`
UNION ALL
SELECT CURRENT_TIMESTAMP() checked_at_utc,routine_catalog,routine_schema,routine_name,routine_type,routine_definition FROM `pacific-plating-282708.sap_data_engineer.INFORMATION_SCHEMA.ROUTINES`
UNION ALL
SELECT CURRENT_TIMESTAMP() checked_at_utc,routine_catalog,routine_schema,routine_name,routine_type,routine_definition FROM `pacific-plating-282708.sap_view.INFORMATION_SCHEMA.ROUTINES`
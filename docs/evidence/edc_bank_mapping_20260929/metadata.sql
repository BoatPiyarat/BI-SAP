SELECT CURRENT_TIMESTAMP() checked_at_utc,table_catalog,table_schema,table_name,view_definition FROM `pacific-plating-282708.sap_view.INFORMATION_SCHEMA.VIEWS`
UNION ALL
SELECT CURRENT_TIMESTAMP() checked_at_utc,table_catalog,table_schema,table_name,view_definition FROM `pacific-plating-282708.sap_data_engineer.INFORMATION_SCHEMA.VIEWS`
UNION ALL
SELECT CURRENT_TIMESTAMP() checked_at_utc,table_catalog,table_schema,table_name,view_definition FROM `pacific-plating-282708.sap_integration_v2.INFORMATION_SCHEMA.VIEWS`
UNION ALL
SELECT CURRENT_TIMESTAMP() checked_at_utc,table_catalog,table_schema,table_name,view_definition FROM `pacific-plating-282708.sap_integration_v3.INFORMATION_SCHEMA.VIEWS`
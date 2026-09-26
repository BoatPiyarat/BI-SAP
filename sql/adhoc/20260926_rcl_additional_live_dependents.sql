SELECT CURRENT_TIMESTAMP() AS checked_at_utc,table_catalog,table_schema,table_name,view_definition
FROM `pacific-plating-282708.region-asia-southeast1.INFORMATION_SCHEMA.VIEWS`
WHERE CONTAINS_SUBSTR(view_definition,'sap_dashboard_carepay_installment')
 OR (table_schema='sap_integration_v2' AND table_name IN ('RCL 05_newpayment','RCL 05_paid by period'))
 OR (table_schema='sap_data_engineer' AND table_name='sap_dashboard_carepay_installment');
SELECT CURRENT_TIMESTAMP() AS checked_at_utc,routine_catalog,routine_schema,routine_name,routine_type,
 TO_HEX(SHA256(routine_definition)) AS definition_sha256,
 REGEXP_EXTRACT_ALL(routine_definition,r'(?i).{0,100}sap_dashboard_carepay_installment.{0,100}') AS dashboard_references
FROM `pacific-plating-282708.region-asia-southeast1.INFORMATION_SCHEMA.ROUTINES`
WHERE CONTAINS_SUBSTR(routine_definition,'sap_dashboard_carepay_installment');
SELECT column_name,data_type FROM `pacific-plating-282708.careos.INFORMATION_SCHEMA.COLUMNS`
WHERE table_name='carepay_transactions' AND (CONTAINS_SUBSTR(column_name,'payment') OR column_name IN ('id','type'));

-- READ ONLY reviewer verification query (Claude Code, RQ-20260825-1536).
SELECT column_name, ordinal_position
FROM `pacific-plating-282708.sap_data_engineer.INFORMATION_SCHEMA.COLUMNS`
WHERE table_name = 'sap_dashboard_carepay_installment'
ORDER BY ordinal_position
LIMIT 6;

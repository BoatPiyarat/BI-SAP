-- READ ONLY reviewer verification query (Claude Code, RQ-20260824-1756).
-- Confirms sap_period_cutoff_calendar (DDL 075, still BLOCKed) is not deployed.
SELECT table_name
FROM `pacific-plating-282708.sap_integration_v3.INFORMATION_SCHEMA.TABLES`
WHERE table_name='sap_period_cutoff_calendar';

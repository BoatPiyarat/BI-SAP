-- READ ONLY reviewer verification query (Claude Code, RQ-20260824-1333).
-- Confirms v3_unit5_payload_identity's creation predates the DDL 058 deploy job
-- (06:31:28 UTC 2026-08-24), i.e. CREATE TABLE IF NOT EXISTS was genuinely a no-op skip.
SELECT
  table_name,
  UNIX_MILLIS(creation_time) AS creation_time_millis,
  creation_time
FROM `pacific-plating-282708.sap_integration_v3.INFORMATION_SCHEMA.TABLES`
WHERE table_name = 'v3_unit5_payload_identity';

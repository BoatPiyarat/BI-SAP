-- READ ONLY reviewer verification query (Claude Code, RQ-20260824-2358).
-- Metadata-only read of the live view's current definition. No mutation.
SELECT
  table_name,
  TO_HEX(SHA256(view_definition)) AS view_definition_sha256,
  LENGTH(view_definition) AS view_definition_length
FROM `pacific-plating-282708.sap_data_engineer.INFORMATION_SCHEMA.VIEWS`
WHERE table_name = 'sap_dashboard_carepay_installment';

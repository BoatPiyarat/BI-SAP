-- READ ONLY reviewer verification query (Claude Code, RQ-20260824-1333).
-- Metadata-only read of the live routine body/timestamp after DDL 058 deployment. No mutation.
SELECT
  routine_name,
  UNIX_MILLIS(last_altered) AS last_altered_millis,
  last_altered,
  STRPOS(routine_definition, "WHEN 'paid' THEN 'Paid'") > 0 AS has_paid_mapping,
  STRPOS(routine_definition, "WHEN 'pending' THEN 'Pending'") > 0 AS has_pending_mapping,
  STRPOS(routine_definition,
    "TransactionStatus NOT IN ('Paid','Pending') OR TransactionStatus IS NULL") > 0
    AS has_exact_status_assert,
  LENGTH(routine_definition) AS body_length
FROM `pacific-plating-282708.sap_integration_v3.INFORMATION_SCHEMA.ROUTINES`
WHERE routine_name = 'sp_build_v3_newpayment_shadow';

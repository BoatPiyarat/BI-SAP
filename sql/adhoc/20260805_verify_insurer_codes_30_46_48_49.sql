-- Read-only evidence for Boat's instruction to disposition insurer codes 30/46/48/49
-- from SAP_LIVE_FULL rows with a valid positive DocEntry.

WITH targets AS (
  SELECT code
  FROM UNNEST(['30', '46', '48', '49']) AS code
),
live AS (
  SELECT
    COALESCE(
      REGEXP_EXTRACT(TRIM(U_InsurerCode), r'/(.+)$'),
      REGEXP_EXTRACT(TRIM(U_InsurerCode), r'^[^-]+-(.+)$'),
      TRIM(U_InsurerCode)
    ) AS insurer_code,
    SAFE_CAST(DocEntry AS INT64) AS doc_entry,
    NULLIF(TRIM(TransactionStatus), '') AS transaction_status
  FROM `pacific-plating-282708.sap_integration_v2.SAP_LIVE_FULL`
  WHERE NULLIF(TRIM(U_InsurerCode), '') IS NOT NULL
),
master AS (
  SELECT
    insurer_code,
    COUNT(*) AS master_rows,
    ARRAY_TO_STRING(ARRAY_AGG(DISTINCT source IGNORE NULLS ORDER BY source), ',') AS sources,
    MIN(added_at) AS first_added_at,
    MAX(added_at) AS last_added_at
  FROM `pacific-plating-282708.sap_integration_v3.sap_insurer_master`
  WHERE insurer_code IN (SELECT code FROM targets)
  GROUP BY insurer_code
)
SELECT
  t.code AS insurer_code,
  COUNTIF(l.doc_entry > 0) AS accepted_live_rows,
  COUNT(DISTINCT IF(l.doc_entry > 0, l.doc_entry, NULL)) AS accepted_doc_entries,
  ARRAY_TO_STRING(
    ARRAY_AGG(
      DISTINCT IF(l.doc_entry > 0, l.transaction_status, NULL)
      IGNORE NULLS ORDER BY IF(l.doc_entry > 0, l.transaction_status, NULL)
    ),
    ','
  ) AS accepted_transaction_statuses,
  IFNULL(ANY_VALUE(m.master_rows), 0) AS master_rows,
  ANY_VALUE(m.sources) AS master_sources,
  ANY_VALUE(m.first_added_at) AS first_added_at,
  ANY_VALUE(m.last_added_at) AS last_added_at,
  COUNTIF(l.doc_entry > 0) > 0 AND IFNULL(ANY_VALUE(m.master_rows), 0) > 0
    AS passed_live_and_registered
FROM targets t
LEFT JOIN live l
  ON l.insurer_code = t.code
LEFT JOIN master m
  ON m.insurer_code = t.code
GROUP BY t.code
ORDER BY t.code;

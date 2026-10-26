-- Read-only deployment-history trace for Root Cause 8 legacy source views.

SELECT
  creation_time,
  user_email,
  job_id,
  statement_type,
  REGEXP_CONTAINS(query, r'RCL-Omise QR Prompt Pay-Health') AS has_health_mapping,
  REGEXP_CONTAINS(query, r'RCL-Omise QR Prompt Pay-BAY') AS has_bay_mapping,
  CASE
    WHEN REGEXP_CONTAINS(query, r'(?i)sap_dashboard_carepay_installment') THEN 'sap_dashboard_carepay_installment'
    WHEN REGEXP_CONTAINS(query, r'(?i)RCL_HEALTH') THEN 'RCL_HEALTH'
    ELSE 'OTHER'
  END AS object_name
FROM `pacific-plating-282708.region-asia-southeast1.INFORMATION_SCHEMA.JOBS_BY_PROJECT`
WHERE creation_time BETWEEN TIMESTAMP '2026-08-20 00:00:00+00' AND TIMESTAMP '2026-09-03 00:00:00+00'
  AND statement_type = 'CREATE_VIEW'
  AND (
    REGEXP_CONTAINS(query, r'(?i)CREATE\s+OR\s+REPLACE\s+VIEW[^;]*sap_dashboard_carepay_installment')
    OR REGEXP_CONTAINS(query, r'(?i)CREATE\s+OR\s+REPLACE\s+VIEW[^;]*RCL_HEALTH')
  )
ORDER BY creation_time;

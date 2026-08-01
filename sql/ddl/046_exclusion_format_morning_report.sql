-- E1-E3/F1-F3 morning report surface (source only; Class A review required before deploy).
-- EXCLUDED rows, validation failures, and real backlog are separate sections by design.
-- The view contains no raw InsuredID, name, PolicyNo, or other PII in its examples.

CREATE OR REPLACE VIEW `pacific-plating-282708.sap_integration_v3.v_exclusion_format_morning_report` AS
WITH exclusion_summary AS (
  SELECT
    'EXCLUSION' AS report_section,
    rule_code AS metric,
    rule_code,
    COUNT(*) AS record_count,
    COUNT(DISTINCT order_item) AS order_count,
    CAST(NULL AS INT64) AS distinct_value_count,
    CAST(NULL AS STRING) AS value_list,
    CAST(NULL AS STRING) AS examples
  FROM `pacific-plating-282708.sap_integration_v3.sap_excluded_records`
  GROUP BY rule_code
),
insurer_signal AS (
  SELECT
    'EXCLUSION_SIGNAL', 'INSURER_NOT_IN_MASTER_CODES', 'INSURER_NOT_IN_MASTER',
    COUNT(*) AS record_count,
    COUNT(DISTINCT x.order_item) AS order_count,
    COUNT(DISTINCT COALESCE(REGEXP_EXTRACT(TRIM(d.insurer_code), r'/(.+)$'),
      REGEXP_EXTRACT(TRIM(d.insurer_code), r'^[^-]+-(.+)$'), TRIM(d.insurer_code))) AS distinct_value_count,
    STRING_AGG(DISTINCT IFNULL(
      COALESCE(REGEXP_EXTRACT(TRIM(d.insurer_code), r'/(.+)$'),
        REGEXP_EXTRACT(TRIM(d.insurer_code), r'^[^-]+-(.+)$'), TRIM(d.insurer_code)), '<NULL>'
    ), ', ' ORDER BY IFNULL(
      COALESCE(REGEXP_EXTRACT(TRIM(d.insurer_code), r'/(.+)$'),
        REGEXP_EXTRACT(TRIM(d.insurer_code), r'^[^-]+-(.+)$'), TRIM(d.insurer_code)), '<NULL>'
    )) AS value_list,
    CAST(NULL AS STRING) AS examples
  FROM `pacific-plating-282708.sap_integration_v3.sap_excluded_records` x
  LEFT JOIN `pacific-plating-282708.sap_integration_v3.stg_order_dim` d USING (order_item)
  WHERE x.rule_code = 'INSURER_NOT_IN_MASTER'
),
validation_summary AS (
  SELECT
    'VALIDATION', check_name, CAST(NULL AS STRING), COUNT(*), COUNT(DISTINCT order_item),
    CAST(NULL AS INT64), CAST(NULL AS STRING),
    ARRAY_TO_STRING(ARRAY_AGG(DISTINCT CONCAT(order_item, ': ', detail) ORDER BY CONCAT(order_item, ': ', detail) LIMIT 5), ' | ')
  FROM `pacific-plating-282708.sap_integration_v3.sap_validation_error`
  WHERE check_name IN ('POLICYNO_TOO_LONG', 'DATE_FORMAT_INVALID')
  GROUP BY check_name
),
f1_by_flow AS (
  SELECT
    'FORMAT_AUDIT', 'F1_INSUREDID_MISSING_BY_FLOW', CAST(NULL AS STRING),
    COUNTIF(NULLIF(TRIM(d.insured_id), '') IS NULL) AS record_count,
    COUNT(DISTINCT IF(NULLIF(TRIM(d.insured_id), '') IS NULL, e.order_item, NULL)) AS order_count,
    CAST(NULL AS INT64),
    STRING_AGG(DISTINCT IF(NULLIF(TRIM(d.insured_id), '') IS NULL, e.flow, NULL), ', '
      ORDER BY IF(NULLIF(TRIM(d.insured_id), '') IS NULL, e.flow, NULL)) AS value_list,
    CAST(NULL AS STRING)
  FROM `pacific-plating-282708.sap_integration_v3.expected_state` e
  LEFT JOIN `pacific-plating-282708.sap_integration_v3.stg_order_dim` d USING (order_item)
),
backlog AS (
  SELECT
    'BACKLOG', 'MISSING_NO_ROW_IN_SAP', CAST(NULL AS STRING), COUNT(*),
    COUNT(DISTINCT order_item), CAST(NULL AS INT64), CAST(NULL AS STRING), CAST(NULL AS STRING)
  FROM `pacific-plating-282708.sap_integration_v3.delta_export`
  WHERE delta_type = 'MISSING_NO_ROW_IN_SAP'
)
SELECT *, CURRENT_TIMESTAMP() AS report_generated_at FROM exclusion_summary
UNION ALL SELECT *, CURRENT_TIMESTAMP() FROM insurer_signal
UNION ALL SELECT *, CURRENT_TIMESTAMP() FROM validation_summary
UNION ALL SELECT *, CURRENT_TIMESTAMP() FROM f1_by_flow
UNION ALL SELECT *, CURRENT_TIMESTAMP() FROM backlog;

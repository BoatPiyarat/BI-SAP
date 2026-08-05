-- Read-only verification for DDL 074 fixtures.
-- Replace the token in memory before passing this query to scripts/bq_safe_query.sh.
-- Never commit a real nonce into this file.

DECLARE p_nonce STRING DEFAULT '__REPLACE_14_DIGIT_NONCE__';
ASSERT REGEXP_CONTAINS(p_nonce, r'^[0-9]{14}$')
  AS 'replace the rehearsal nonce token with the exact 14-digit seed value';

CREATE TEMP TABLE _cases AS
SELECT 'ACK' AS case_name,
  CONCAT('99', p_nonce, '01') AS log_id,
  CONCAT('SYNTH-POSTIMPORT-', p_nonce, '-ACK') AS export_run_id,
  'ACKNOWLEDGED' AS expected_row_outcome,
  'SUCCEEDED' AS expected_outbox_status,
  'ACKNOWLEDGED' AS expected_manifest_status
UNION ALL
SELECT 'REJECT',
  CONCAT('99', p_nonce, '02'),
  CONCAT('SYNTH-POSTIMPORT-', p_nonce, '-REJECT'),
  'REJECTED_BY_SAP',
  'SUCCEEDED',
  'REJECTED'
UNION ALL
SELECT 'RESIDUAL',
  CONCAT('99', p_nonce, '03'),
  CONCAT('SYNTH-POSTIMPORT-', p_nonce, '-RESIDUAL'),
  'PENDING_ACK',
  'HUMAN_ACTION',
  'DELIVERED';

CREATE TEMP TABLE _verification AS
WITH
outbox AS (
  SELECT log_id, export_run_id, request_status, workflow_execution_name, attempt_count,
    last_error_template
  FROM `pacific-plating-282708.sap_integration_v3.v3_post_import_refresh_outbox`
  WHERE DATE(requested_at) >= DATE_SUB(CURRENT_DATE('Asia/Bangkok'), INTERVAL 2 DAY)
    AND log_id IN (SELECT log_id FROM _cases)
),
row_result AS (
  SELECT log_id, export_run_id, outcome, exact_error_detail_count, child_pipeline_run_id
  FROM `pacific-plating-282708.sap_integration_v3.v3_post_import_row_reconciliation`
  WHERE DATE(reconciled_at) >= DATE_SUB(CURRENT_DATE('Asia/Bangkok'), INTERVAL 2 DAY)
    AND log_id IN (SELECT log_id FROM _cases)
),
archive AS (
  SELECT export_run_id, sap_log_id, sap_result_status, acknowledged_at
  FROM `pacific-plating-282708.sap_integration_v3.export_archive`
  WHERE DATE(exported_at) >= DATE_SUB(CURRENT_DATE('Asia/Bangkok'), INTERVAL 2 DAY)
    AND export_run_id IN (SELECT export_run_id FROM _cases)
),
sap_manifest AS (
  SELECT export_run_id, delivery_status
  FROM `pacific-plating-282708.sap_integration_v3.sap_delivery_manifest_v3`
  WHERE DATE(recorded_at) >= DATE_SUB(CURRENT_DATE('Asia/Bangkok'), INTERVAL 2 DAY)
    AND export_run_id IN (SELECT export_run_id FROM _cases)
),
file_manifest AS (
  SELECT export_run_id, delivery_status
  FROM `pacific-plating-282708.sap_integration_v3.export_file_manifest`
  WHERE export_run_id IN (SELECT export_run_id FROM _cases)
)
SELECT
  c.case_name,
  c.log_id,
  c.export_run_id,
  o.request_status AS outbox_status,
  o.workflow_execution_name,
  o.attempt_count,
  o.last_error_template,
  r.outcome AS row_outcome,
  r.exact_error_detail_count,
  r.child_pipeline_run_id,
  a.sap_log_id AS archive_log_id,
  a.sap_result_status AS archive_result_status,
  a.acknowledged_at AS archive_acknowledged_at,
  sm.delivery_status AS sap_manifest_status,
  fm.delivery_status AS file_manifest_status,
  o.request_status = c.expected_outbox_status
    AND r.outcome = c.expected_row_outcome
    AND sm.delivery_status = c.expected_manifest_status
    AND fm.delivery_status = c.expected_manifest_status
    AND a.sap_log_id = c.log_id
    AND CASE c.case_name
      WHEN 'ACK' THEN a.sap_result_status = 'ACKNOWLEDGED'
        AND a.acknowledged_at IS NOT NULL
      WHEN 'REJECT' THEN a.sap_result_status = 'REJECTED'
        AND a.acknowledged_at IS NULL
      ELSE a.sap_result_status IS NULL
        AND a.acknowledged_at IS NULL
    END AS expected_final_state
FROM _cases c
LEFT JOIN outbox o USING(log_id, export_run_id)
LEFT JOIN row_result r USING(log_id, export_run_id)
LEFT JOIN archive a USING(export_run_id)
LEFT JOIN sap_manifest sm USING(export_run_id)
LEFT JOIN file_manifest fm USING(export_run_id);

ASSERT (SELECT COUNT(*) FROM _verification) = 3
  AS 'rehearsal verification must return exactly ACK, REJECT, and RESIDUAL';
ASSERT (SELECT COUNTIF(expected_final_state IS TRUE) FROM _verification) = 3
  AS 'one or more rehearsal cases is missing, duplicated, or not in its exact expected state';

SELECT *
FROM _verification
ORDER BY case_name;

DECLARE v_run_id STRING DEFAULT 'V3NIGHTLY-2026-08-25T22:21:31-manual';

SELECT 'pipeline_log' AS evidence,
  COUNTIF(step='UNIT1_COMPLETE' AND status='SUCCESS') AS unit1_success,
  COUNTIF(status='FAILED') AS failed_log_rows,
  STRING_AGG(CONCAT(step,':',status),', ' ORDER BY started_at) AS detail
FROM `pacific-plating-282708.sap_integration_v3.pipeline_run_log`
WHERE run_id=v_run_id;

SELECT 'unit_summaries' AS evidence,
  (SELECT COUNT(*) FROM `pacific-plating-282708.sap_integration_v3.v3_unit2_summary`
   WHERE pipeline_run_id=v_run_id) AS unit2_summary_rows,
  (SELECT COUNT(*) FROM `pacific-plating-282708.sap_integration_v3.v3_unit3_run_summary`
   WHERE pipeline_run_id=v_run_id) AS unit3_summary_rows,
  (SELECT COUNT(*) FROM `pacific-plating-282708.sap_integration_v3.v3_notification_run_summary`
   WHERE pipeline_run_id=v_run_id) AS unit4_summary_rows,
  (SELECT COUNT(*) FROM `pacific-plating-282708.sap_integration_v3.v3_unit5_payload_identity`
   WHERE pipeline_run_id=v_run_id) AS unit5_identity_rows,
  (SELECT COUNT(*)
   FROM `pacific-plating-282708.sap_integration_v3.export_archive` a
   JOIN `pacific-plating-282708.sap_integration_v3.v3_unit5_payload_identity` i
     ON i.order_item=a.order_item AND i.period=a.period AND i.charge_id=a.charge_id
   WHERE i.pipeline_run_id=v_run_id) AS archive_rows;

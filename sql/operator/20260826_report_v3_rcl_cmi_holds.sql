DECLARE p_run_id STRING DEFAULT 'V3NIGHTLY-2026-08-26T13:23:38-e830fff2';

SELECT AS STRUCT
  (SELECT AS STRUCT *
   FROM `pacific-plating-282708.sap_integration_v3.v3_rcl_cmi_event_summary`
   WHERE pipeline_run_id = p_run_id) AS run_summary,
  ARRAY(
    SELECT AS STRUCT hold_code, COUNT(*) AS event_count
    FROM `pacific-plating-282708.sap_integration_v3.v3_rcl_cmi_event_hold`
    WHERE pipeline_run_id = p_run_id
    GROUP BY hold_code ORDER BY hold_code
  ) AS hold_distribution;

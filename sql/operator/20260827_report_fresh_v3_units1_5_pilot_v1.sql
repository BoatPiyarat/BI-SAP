-- READ ONLY. Post-run disposition for the exact fresh delivery-disabled Units 1-5 execution.
-- Supply --parameter=run_id::V3NIGHTLY-... through scripts/bq_safe_query.sh.

DECLARE v_run_id STRING DEFAULT @run_id;

ASSERT NULLIF(TRIM(v_run_id), '') IS NOT NULL AS 'run_id parameter is required';

WITH facts AS (
  SELECT
    (SELECT COUNTIF(step = 'UNIT1_COMPLETE' AND status = 'SUCCESS')
      FROM `pacific-plating-282708.sap_integration_v3.pipeline_run_log`
      WHERE run_id = v_run_id) AS unit1_success_count,
    (SELECT COUNTIF(step = 'UNITS_2_5_ARCHIVE' AND status = 'SUCCESS')
      FROM `pacific-plating-282708.sap_integration_v3.pipeline_run_log`
      WHERE run_id = v_run_id) AS units2_5_success_count,
    (SELECT COUNTIF(status = 'FAILED')
      FROM `pacific-plating-282708.sap_integration_v3.pipeline_run_log`
      WHERE run_id = v_run_id) AS failed_log_count,
    (SELECT COUNT(*)
      FROM `pacific-plating-282708.sap_integration_v3.v3_unit2_summary`
      WHERE pipeline_run_id = v_run_id) AS unit2_summary_rows,
    (SELECT ANY_VALUE(status)
      FROM `pacific-plating-282708.sap_integration_v3.v3_unit2_magnitude_run`
      WHERE pipeline_run_id = v_run_id) AS magnitude_status,
    (SELECT COUNT(*)
      FROM `pacific-plating-282708.sap_integration_v3.v3_unit2_magnitude_run`
      WHERE pipeline_run_id = v_run_id) AS magnitude_run_rows,
    (SELECT ANY_VALUE(config_id)
      FROM `pacific-plating-282708.sap_integration_v3.v3_unit2_magnitude_run`
      WHERE pipeline_run_id = v_run_id) AS magnitude_config_id,
    (SELECT ANY_VALUE(compared_cells)
      FROM `pacific-plating-282708.sap_integration_v3.v3_unit2_magnitude_run`
      WHERE pipeline_run_id = v_run_id) AS compared_cells,
    (SELECT ANY_VALUE(breached_cells)
      FROM `pacific-plating-282708.sap_integration_v3.v3_unit2_magnitude_run`
      WHERE pipeline_run_id = v_run_id) AS breached_cells,
    (SELECT COUNT(*)
      FROM `pacific-plating-282708.sap_integration_v3.v3_unit2_magnitude_result`
      WHERE pipeline_run_id = v_run_id) AS magnitude_result_cells,
    (SELECT IFNULL(SUM(blocker_count), 0)
      FROM `pacific-plating-282708.sap_integration_v3.v3_automation_gate_result`
      WHERE pipeline_run_id = v_run_id) AS automation_blockers,
    (SELECT COUNT(DISTINCT a.export_run_id)
      FROM `pacific-plating-282708.sap_integration_v3.export_archive` a
      JOIN `pacific-plating-282708.sap_integration_v3.v3_unit5_payload_identity` i
        ON i.order_item = a.order_item AND i.period = a.period
       AND i.charge_id = a.charge_id AND i.payload_hash = a.payload_hash
      WHERE i.pipeline_run_id = v_run_id) AS archive_run_count,
    (SELECT COUNT(*)
      FROM `pacific-plating-282708.sap_integration_v3.export_archive` a
      JOIN `pacific-plating-282708.sap_integration_v3.v3_unit5_payload_identity` i
        ON i.order_item = a.order_item AND i.period = a.period
       AND i.charge_id = a.charge_id AND i.payload_hash = a.payload_hash
      WHERE i.pipeline_run_id = v_run_id
        AND a.delivery_status IN ('DELIVERED', 'PICKED_UP', 'ACKNOWLEDGED'))
      AS production_delivery_rows
)
SELECT
  v_run_id AS pipeline_run_id,
  facts.*,
  CASE
    WHEN magnitude_run_rows = 1 AND magnitude_status = 'HELD_MAGNITUDE_REVIEW'
      THEN 'HELD_MAGNITUDE_REVIEW'
    WHEN unit1_success_count = 1 AND units2_5_success_count = 1
      AND failed_log_count = 0 AND magnitude_run_rows = 1 AND magnitude_status = 'PASS'
      AND magnitude_config_id = 'UNIT2-PILOT-20260827-V1'
      AND breached_cells = 0 AND magnitude_result_cells = compared_cells
      AND automation_blockers = 0
      AND production_delivery_rows = 0 THEN 'PASS_DELIVERY_DISABLED'
    ELSE 'FAILED_OR_INCOMPLETE_REVIEW_REQUIRED'
  END AS final_disposition
FROM facts;

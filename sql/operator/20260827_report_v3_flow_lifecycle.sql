-- READ ONLY. Exact export-to-SAP lifecycle for every flow registered by DDL 100.
SELECT
  flow_key, evidence_run_id, approval_id, export_run_id, export_contract,
  released_identity_count, payload_row_count, payload_set_hash, claim_state,
  production_uri, production_generation, production_file_name, sap_file_name,
  file_sha256, delivery_status, pickup_rows, successful_pickup_rows,
  duplicate_pickup_key_rows, pickup_statuses, import_header_rows,
  duplicate_log_id_rows, terminal_import_rows, terminal_log_ids,
  reconciled_rows, acknowledged_rows, rejected_rows, pending_rows, lifecycle_state
FROM `pacific-plating-282708.sap_integration_v3.vw_v3_flow_export_lifecycle`
ORDER BY requested_at DESC, flow_key, export_run_id;

-- Class A / fail-closed. CreditShell dependency gate only; no 56-column ready payload.
-- A replacement remains held until one human-approved old/new item map exists and every old
-- SAP period has exact row-level ACK for `Cancelled (Change order / Rejected)`. Even after those
-- dependencies pass, the unresolved accepted CreditShell literal remains a named hold.

CREATE TABLE IF NOT EXISTS
  `pacific-plating-282708.sap_integration_v3.v3_change_order_item_map` (
    old_order_id STRING NOT NULL,
    new_order_id STRING NOT NULL,
    old_order_item STRING NOT NULL,
    new_order_item STRING,
    decision_status STRING NOT NULL,
    approved_by STRING,
    approved_at TIMESTAMP,
    evidence_reference STRING NOT NULL,
    recorded_at TIMESTAMP NOT NULL
  )
CLUSTER BY new_order_id, new_order_item, decision_status;

CREATE TABLE IF NOT EXISTS
  `pacific-plating-282708.sap_integration_v3.v3_creditshell_dependency_hold` (
    run_id STRING NOT NULL,
    new_order_id STRING,
    new_order_item STRING,
    old_order_id STRING,
    old_order_item STRING,
    router_decision STRING NOT NULL,
    hold_code STRING NOT NULL,
    approved_map_count INT64 NOT NULL,
    old_sap_period_count INT64 NOT NULL,
    acknowledged_cancel_period_count INT64 NOT NULL,
    cancel_export_run_id STRING,
    cancel_log_id STRING,
    classified_at TIMESTAMP NOT NULL
  )
CLUSTER BY run_id, hold_code, new_order_item;

CREATE TABLE IF NOT EXISTS
  `pacific-plating-282708.sap_integration_v3.v3_creditshell_dependency_summary` (
    run_id STRING NOT NULL,
    router_item_count INT64 NOT NULL,
    classified_item_count INT64 NOT NULL,
    fully_acknowledged_dependency_count INT64 NOT NULL,
    interface_row_count INT64 NOT NULL,
    gate_status STRING NOT NULL,
    built_at TIMESTAMP NOT NULL
  )
CLUSTER BY run_id, gate_status;

CREATE OR REPLACE PROCEDURE
  `pacific-plating-282708.sap_integration_v3.sp_build_v3_creditshell_dependency_holds`(
    p_run_id STRING
  )
BEGIN
  ASSERT NULLIF(TRIM(p_run_id), '') IS NOT NULL AS 'run_id is required';
  ASSERT NOT EXISTS (
    SELECT 1
    FROM `pacific-plating-282708.sap_integration_v3.v3_creditshell_dependency_summary`
    WHERE run_id = p_run_id
  ) AS 'run_id already published';

  CREATE TEMP TABLE _router AS
  SELECT
    order_id AS new_order_id,
    order_item AS new_order_item,
    old_human_id AS old_order_id,
    routing_decision
  FROM `pacific-plating-282708.sap_integration_v3.vw_creditshell_flow_classification`;

  ASSERT NOT EXISTS (
    SELECT new_order_id, new_order_item
    FROM _router
    GROUP BY 1, 2
    HAVING COUNT(*) != 1
  ) AS 'CreditShell router grain is not unique';

  CREATE TEMP TABLE _map AS
  SELECT
    new_order_id,
    new_order_item,
    COUNT(*) AS approved_map_count,
    ANY_VALUE(old_order_id HAVING MAX recorded_at) AS old_order_id,
    ANY_VALUE(old_order_item HAVING MAX recorded_at) AS old_order_item
  FROM `pacific-plating-282708.sap_integration_v3.v3_change_order_item_map`
  WHERE decision_status = 'APPROVED'
    AND NULLIF(TRIM(approved_by), '') IS NOT NULL
    AND approved_at IS NOT NULL
    AND NULLIF(TRIM(evidence_reference), '') IS NOT NULL
  GROUP BY new_order_id, new_order_item;

  CREATE TEMP TABLE _old_spine AS
  SELECT
    m.new_order_id,
    m.new_order_item,
    ANY_VALUE(m.old_order_id) AS old_order_id,
    ANY_VALUE(m.old_order_item) AS old_order_item,
    COUNT(s.U_OrderItem) AS old_sap_period_count,
    COUNT(DISTINCT SAFE_CAST(s.U_Period AS INT64)) AS old_sap_distinct_period_count,
    COUNT(DISTINCT SAFE_CAST(s.TotalPeriods AS INT64)) AS old_total_period_versions,
    MAX(SAFE_CAST(s.TotalPeriods AS INT64)) AS old_total_periods
    ,MIN(SAFE_CAST(s.U_Period AS INT64)) AS old_min_period
    ,MAX(SAFE_CAST(s.U_Period AS INT64)) AS old_max_period
  FROM _map AS m
  LEFT JOIN `pacific-plating-282708.sap_integration_v3.sap_mirror_state` AS s
    ON s.U_OrderItem = m.old_order_item
  GROUP BY m.new_order_id, m.new_order_item;

  CREATE TEMP TABLE _manifest_header_raw AS
  SELECT
    d.export_run_id,
    d.sap_file_name,
    h.log_id,
    d.production_generation,
    d.file_sha256
  FROM `pacific-plating-282708.sap_integration_v3.sap_delivery_manifest_v3` AS d
  JOIN `pacific-plating-282708.sap_integration_v3.sap_import_result_header_v3` AS h
    ON h.file_name = d.sap_file_name
  WHERE d.delivery_status = 'ACKNOWLEDGED'
    AND NULLIF(TRIM(d.production_generation), '') IS NOT NULL
    AND NULLIF(TRIM(d.file_sha256), '') IS NOT NULL
    AND h.company_db = 'RCB_LIVE_DB'
    AND h.attachment_parse_status = 'PARSED'
    AND NULLIF(TRIM(h.txt_gcs_uri), '') IS NOT NULL
    AND LOWER(h.status) IN ('success', 'success with error');

  CREATE TEMP TABLE _manifest_header AS
  SELECT export_run_id, log_id, production_generation, file_sha256
  FROM _manifest_header_raw
  QUALIFY COUNT(*) OVER (PARTITION BY sap_file_name) = 1
    AND COUNT(*) OVER (PARTITION BY export_run_id, log_id) = 1;

  CREATE TEMP TABLE _ack_candidate AS
  SELECT
    m.new_order_id,
    m.new_order_item,
    r.export_run_id,
    r.log_id,
    COUNT(*) AS acknowledged_cancel_period_count,
    COUNT(DISTINCT r.period) AS acknowledged_distinct_period_count,
    MIN(r.period) AS acknowledged_min_period,
    MAX(r.period) AS acknowledged_max_period,
    COUNT(DISTINCT r.child_pipeline_run_id) AS child_run_count,
    COUNT(DISTINCT r.payload_hash) AS payload_hash_count
  FROM _map AS m
  JOIN `pacific-plating-282708.sap_integration_v3.v3_post_import_row_reconciliation` AS r
    ON r.order_item = m.old_order_item
  JOIN _manifest_header AS h
    ON h.export_run_id = r.export_run_id
    AND h.log_id = r.log_id
  WHERE r.outcome = 'ACKNOWLEDGED'
    AND r.expected_status = 'Cancelled (Change order / Rejected)'
    AND NULLIF(TRIM(r.payload_hash), '') IS NOT NULL
  GROUP BY m.new_order_id, m.new_order_item, r.export_run_id, r.log_id;

  CREATE TEMP TABLE _cancel_ack AS
  SELECT
    c.new_order_id,
    c.new_order_item,
    COUNT(*) AS exact_ack_candidate_count,
    ANY_VALUE(c.acknowledged_cancel_period_count) AS acknowledged_cancel_period_count,
    ANY_VALUE(c.export_run_id) AS cancel_export_run_id,
    ANY_VALUE(c.log_id) AS cancel_log_id
  FROM _ack_candidate AS c
  JOIN _old_spine AS s USING (new_order_id, new_order_item)
  WHERE c.acknowledged_cancel_period_count = s.old_total_periods
    AND c.acknowledged_distinct_period_count = s.old_total_periods
    AND c.acknowledged_min_period = 1
    AND c.acknowledged_max_period = s.old_total_periods
    AND c.child_run_count = 1
    AND c.payload_hash_count = s.old_total_periods
  GROUP BY c.new_order_id, c.new_order_item;

  CREATE TEMP TABLE _classified AS
  SELECT
    p_run_id AS run_id,
    r.new_order_id,
    r.new_order_item,
    COALESCE(m.old_order_id, r.old_order_id) AS old_order_id,
    m.old_order_item,
    COALESCE(r.routing_decision, '<NULL>') AS router_decision,
    CASE
      WHEN NULLIF(TRIM(r.new_order_id), '') IS NULL
        OR NULLIF(TRIM(r.old_order_id), '') IS NULL
        OR NULLIF(TRIM(r.routing_decision), '') IS NULL
        THEN 'HOLD_CREDITSHELL_ROUTER_IDENTITY_INVALID'
      WHEN NULLIF(TRIM(r.new_order_item), '') IS NULL
        THEN 'HOLD_CREDITSHELL_ROUTER_ITEM_MISSING'
      WHEN STARTS_WITH(r.routing_decision, 'HOLD_') THEN r.routing_decision
      WHEN IFNULL(m.approved_map_count, 0) = 0 THEN 'HOLD_CHANGE_ORDER_ITEM_MAP_REQUIRED'
      WHEN m.approved_map_count != 1 THEN 'HOLD_CHANGE_ORDER_ITEM_MAP_AMBIGUOUS'
      WHEN m.old_order_id IS DISTINCT FROM r.old_order_id
        THEN 'HOLD_CHANGE_ORDER_MAP_LINK_MISMATCH'
      WHEN IFNULL(s.old_sap_period_count, 0) = 0 THEN 'HOLD_OLD_ITEM_NOT_IN_SAP'
      WHEN s.old_total_period_versions != 1
        OR s.old_total_periods IS NULL
        OR s.old_min_period != 1
        OR s.old_max_period != s.old_total_periods
        OR s.old_sap_period_count != s.old_total_periods
        OR s.old_sap_distinct_period_count != s.old_total_periods
        THEN 'HOLD_OLD_SAP_SPINE_INVALID'
      WHEN IFNULL(a.exact_ack_candidate_count, 0) = 0
        THEN 'HOLD_CANCEL_ROW_ACK_INCOMPLETE'
      WHEN a.exact_ack_candidate_count != 1
        THEN 'HOLD_CANCEL_ACK_EVIDENCE_AMBIGUOUS'
      ELSE 'HOLD_CREDITSHELL_LITERAL_APPROVAL_REQUIRED'
    END AS hold_code,
    IFNULL(m.approved_map_count, 0) AS approved_map_count,
    IFNULL(s.old_sap_period_count, 0) AS old_sap_period_count,
    IFNULL(a.acknowledged_cancel_period_count, 0) AS acknowledged_cancel_period_count,
    IF(a.exact_ack_candidate_count = 1, a.cancel_export_run_id, NULL) AS cancel_export_run_id,
    IF(a.exact_ack_candidate_count = 1, a.cancel_log_id, NULL) AS cancel_log_id,
    CURRENT_TIMESTAMP() AS classified_at
  FROM _router AS r
  LEFT JOIN _map AS m USING (new_order_id, new_order_item)
  LEFT JOIN _old_spine AS s USING (new_order_id, new_order_item)
  LEFT JOIN _cancel_ack AS a USING (new_order_id, new_order_item);

  ASSERT (SELECT COUNT(*) FROM _classified) = (SELECT COUNT(*) FROM _router)
    AS 'CreditShell dependency population was not conserved';
  ASSERT NOT EXISTS (SELECT 1 FROM _classified WHERE hold_code IS NULL)
    AS 'CreditShell dependency classifier produced a NULL outcome';

  BEGIN TRANSACTION;
    MERGE `pacific-plating-282708.sap_integration_v3.v3_creditshell_dependency_summary` AS target
    USING (
      SELECT
        p_run_id AS run_id,
        COUNT(*) AS router_item_count,
        COUNT(*) AS classified_item_count,
        COUNTIF(hold_code = 'HOLD_CREDITSHELL_LITERAL_APPROVAL_REQUIRED')
          AS fully_acknowledged_dependency_count,
        0 AS interface_row_count,
        'HOLD_ONLY_ZERO_INTERFACE_ROWS' AS gate_status,
        CURRENT_TIMESTAMP() AS built_at
      FROM _classified
    ) AS source
    ON target.run_id = source.run_id
    WHEN NOT MATCHED THEN INSERT ROW;
    ASSERT @@row_count = 1 AS 'run_id claim failed or already exists';

    INSERT INTO `pacific-plating-282708.sap_integration_v3.v3_creditshell_dependency_hold`
    SELECT * FROM _classified;
    ASSERT @@row_count = (SELECT COUNT(*) FROM _classified)
      AS 'CreditShell hold insert cardinality mismatch';

    ASSERT (
      SELECT router_item_count = classified_item_count AND interface_row_count = 0
      FROM `pacific-plating-282708.sap_integration_v3.v3_creditshell_dependency_summary`
      WHERE run_id = p_run_id
    ) AS 'CreditShell published conservation failed';

    ASSERT (
      SELECT COUNT(*)
      FROM `pacific-plating-282708.sap_integration_v3.v3_creditshell_dependency_hold`
      WHERE run_id = p_run_id
    ) = (SELECT COUNT(*) FROM _classified)
      AS 'CreditShell published hold detail count mismatch';
  COMMIT TRANSACTION;
END;

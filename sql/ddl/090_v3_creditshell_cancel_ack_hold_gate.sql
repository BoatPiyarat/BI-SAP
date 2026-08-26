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
    new_order_id STRING NOT NULL,
    new_order_item STRING,
    old_order_id STRING,
    old_order_item STRING,
    router_decision STRING NOT NULL,
    hold_code STRING NOT NULL,
    approved_map_count INT64 NOT NULL,
    old_sap_period_count INT64 NOT NULL,
    acknowledged_cancel_period_count INT64 NOT NULL,
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
  FROM _map AS m
  LEFT JOIN `pacific-plating-282708.sap_integration_v3.sap_mirror_state` AS s
    ON s.U_OrderItem = m.old_order_item
  GROUP BY m.new_order_id, m.new_order_item;

  CREATE TEMP TABLE _cancel_ack AS
  SELECT
    m.new_order_id,
    m.new_order_item,
    COUNT(DISTINCT IF(
      r.outcome = 'ACKNOWLEDGED'
      AND r.expected_status = 'Cancelled (Change order / Rejected)',
      r.period,
      NULL
    )) AS acknowledged_cancel_period_count
  FROM _map AS m
  LEFT JOIN `pacific-plating-282708.sap_integration_v3.v3_post_import_row_reconciliation` AS r
    ON r.order_item = m.old_order_item
  GROUP BY m.new_order_id, m.new_order_item;

  CREATE TEMP TABLE _classified AS
  SELECT
    p_run_id AS run_id,
    r.new_order_id,
    r.new_order_item,
    COALESCE(m.old_order_id, r.old_order_id) AS old_order_id,
    m.old_order_item,
    r.routing_decision AS router_decision,
    CASE
      WHEN STARTS_WITH(r.routing_decision, 'HOLD_') THEN r.routing_decision
      WHEN IFNULL(m.approved_map_count, 0) = 0 THEN 'HOLD_CHANGE_ORDER_ITEM_MAP_REQUIRED'
      WHEN m.approved_map_count != 1 THEN 'HOLD_CHANGE_ORDER_ITEM_MAP_AMBIGUOUS'
      WHEN m.old_order_id != r.old_order_id THEN 'HOLD_CHANGE_ORDER_MAP_LINK_MISMATCH'
      WHEN IFNULL(s.old_sap_period_count, 0) = 0 THEN 'HOLD_OLD_ITEM_NOT_IN_SAP'
      WHEN s.old_total_period_versions != 1
        OR s.old_total_periods IS NULL
        OR s.old_sap_period_count != s.old_total_periods
        OR s.old_sap_distinct_period_count != s.old_total_periods
        THEN 'HOLD_OLD_SAP_SPINE_INVALID'
      WHEN IFNULL(a.acknowledged_cancel_period_count, 0) != s.old_total_periods
        THEN 'HOLD_CANCEL_ROW_ACK_INCOMPLETE'
      ELSE 'HOLD_CREDITSHELL_LITERAL_APPROVAL_REQUIRED'
    END AS hold_code,
    IFNULL(m.approved_map_count, 0) AS approved_map_count,
    IFNULL(s.old_sap_period_count, 0) AS old_sap_period_count,
    IFNULL(a.acknowledged_cancel_period_count, 0) AS acknowledged_cancel_period_count,
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

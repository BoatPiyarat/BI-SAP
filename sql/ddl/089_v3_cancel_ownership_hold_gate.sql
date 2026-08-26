-- Class A / fail-closed. Reusable cancellation ownership classifier.
-- This routine publishes HOLD/REPORT evidence only. It creates no 56-column ready object,
-- writes no GCS object, calls no SAP component, and activates no scheduler.

CREATE TABLE IF NOT EXISTS `pacific-plating-282708.sap_integration_v3.v3_cancel_ownership_hold` (
  run_id STRING NOT NULL,
  order_id STRING,
  order_item STRING NOT NULL,
  ownership_lane STRING NOT NULL,
  hold_code STRING NOT NULL,
  sap_period_rows INT64 NOT NULL,
  sap_distinct_periods INT64 NOT NULL,
  sap_total_periods INT64,
  linked_old_order_count INT64 NOT NULL,
  detail STRING NOT NULL,
  classified_at TIMESTAMP NOT NULL
)
CLUSTER BY run_id, ownership_lane, hold_code, order_item;

CREATE TABLE IF NOT EXISTS `pacific-plating-282708.sap_integration_v3.v3_cancel_ownership_summary` (
  run_id STRING NOT NULL,
  cancelled_item_count INT64 NOT NULL,
  linked_change_order_count INT64 NOT NULL,
  unlinked_plain_cancel_count INT64 NOT NULL,
  classified_item_count INT64 NOT NULL,
  interface_row_count INT64 NOT NULL,
  gate_status STRING NOT NULL,
  built_at TIMESTAMP NOT NULL
)
CLUSTER BY run_id, gate_status;

CREATE OR REPLACE PROCEDURE `pacific-plating-282708.sap_integration_v3.sp_build_v3_cancel_ownership_hold`(
  p_run_id STRING
)
BEGIN
  ASSERT p_run_id IS NOT NULL AND TRIM(p_run_id) != '' AS 'run_id is required';
  ASSERT NOT EXISTS (
    SELECT 1
    FROM `pacific-plating-282708.sap_integration_v3.v3_cancel_ownership_summary`
    WHERE run_id = p_run_id
  ) AS 'run_id already published';

  CREATE TEMP TABLE _cancelled_items AS
  SELECT
    order_id,
    order_item
  FROM `pacific-plating-282708.sap_integration_v3.stg_order_dim`
  WHERE is_cancelled_effective IS TRUE;

  ASSERT NOT EXISTS (
    SELECT order_item FROM _cancelled_items GROUP BY order_item HAVING COUNT(*) != 1
  ) AS 'cancelled CareOS order_item is not unique';

  CREATE TEMP TABLE _links AS
  SELECT
    old_human_id AS old_order_id,
    COUNT(DISTINCT current_human_id) AS linked_old_order_count
  FROM `pacific-plating-282708.careos.cancelled_change_orders`
  WHERE old_human_id IS NOT NULL
    AND current_human_id IS NOT NULL
  GROUP BY old_order_id;

  CREATE TEMP TABLE _sap AS
  SELECT
    c.order_item,
    COUNT(m.U_OrderItem) AS sap_period_rows,
    COUNT(DISTINCT SAFE_CAST(m.U_Period AS INT64)) AS sap_distinct_periods,
    COUNT(DISTINCT SAFE_CAST(m.TotalPeriods AS INT64)) AS sap_total_period_versions,
    MAX(SAFE_CAST(m.TotalPeriods AS INT64)) AS sap_total_periods,
    MIN(SAFE_CAST(m.U_Period AS INT64)) AS sap_min_period,
    MAX(SAFE_CAST(m.U_Period AS INT64)) AS sap_max_period,
    COUNTIF(STARTS_WITH(COALESCE(m.TransactionStatus, ''), 'Cancelled')) AS terminal_rows,
    COUNTIF(
      m.U_OrderItem IS NOT NULL
      AND LOWER(COALESCE(m.TransactionStatus, '')) NOT IN ('paid', 'pending')
    ) AS unsupported_status_rows,
    COUNTIF(
      LOWER(COALESCE(m.TransactionStatus, '')) = 'paid'
      AND NULLIF(TRIM(m.U_InvoiceNo), '') IS NULL
    ) AS paid_missing_invoice_rows
  FROM _cancelled_items AS c
  LEFT JOIN `pacific-plating-282708.sap_integration_v3.sap_mirror_state` AS m
    ON m.U_OrderItem = c.order_item
  GROUP BY c.order_item;

  CREATE TEMP TABLE _classified AS
  SELECT
    p_run_id AS run_id,
    c.order_id,
    c.order_item,
    IF(IFNULL(l.linked_old_order_count, 0) > 0, 'LINKED_CHANGE_ORDER', 'UNLINKED_PLAIN_CANCEL')
      AS ownership_lane,
    CASE
      WHEN IFNULL(l.linked_old_order_count, 0) > 1 THEN 'HOLD_CHANGE_ORDER_LINK_AMBIGUOUS'
      WHEN IFNULL(l.linked_old_order_count, 0) = 1 THEN 'HOLD_CHANGE_ORDER_SEPARATE_FLOW'
      WHEN s.sap_period_rows = 0 THEN 'HOLD_PLAIN_CANCEL_NOT_IN_SAP'
      WHEN s.terminal_rows > 0 THEN 'HOLD_PLAIN_CANCEL_ALREADY_TERMINAL'
      WHEN s.unsupported_status_rows > 0 THEN 'HOLD_PLAIN_CANCEL_SAP_STATUS'
      WHEN s.paid_missing_invoice_rows > 0 THEN 'HOLD_PLAIN_CANCEL_PAID_INVOICE_MISSING'
      WHEN s.sap_total_period_versions != 1
        OR s.sap_total_periods IS NULL
        OR s.sap_min_period != 1
        OR s.sap_max_period != s.sap_total_periods
        OR s.sap_period_rows != s.sap_total_periods
        OR s.sap_distinct_periods != s.sap_total_periods
        THEN 'HOLD_PLAIN_CANCEL_SPINE_INVALID'
      ELSE 'HOLD_PLAIN_CANCEL_AWAITING_SCENARIO_APPROVAL'
    END AS hold_code,
    s.sap_period_rows,
    s.sap_distinct_periods,
    s.sap_total_periods,
    IFNULL(l.linked_old_order_count, 0) AS linked_old_order_count,
    CASE
      WHEN IFNULL(l.linked_old_order_count, 0) > 0
        THEN 'Linked old order is isolated from plain cancellation; no payload is released.'
      ELSE 'Unlinked plain cancellation is classified for human review; no payload is released.'
    END AS detail,
    CURRENT_TIMESTAMP() AS classified_at
  FROM _cancelled_items AS c
  LEFT JOIN _links AS l ON l.old_order_id = c.order_id
  JOIN _sap AS s USING (order_item);

  ASSERT (SELECT COUNT(*) FROM _classified) = (SELECT COUNT(*) FROM _cancelled_items)
    AS 'cancelled population was not conserved';
  ASSERT NOT EXISTS (
    SELECT order_item FROM _classified GROUP BY order_item HAVING COUNT(*) != 1
  ) AS 'classifier produced duplicate order_item rows';

  BEGIN TRANSACTION;
    MERGE `pacific-plating-282708.sap_integration_v3.v3_cancel_ownership_summary` AS target
    USING (
      SELECT
        p_run_id AS run_id,
        COUNT(*) AS cancelled_item_count,
        COUNTIF(ownership_lane = 'LINKED_CHANGE_ORDER') AS linked_change_order_count,
        COUNTIF(ownership_lane = 'UNLINKED_PLAIN_CANCEL') AS unlinked_plain_cancel_count,
        COUNT(*) AS classified_item_count,
        0 AS interface_row_count,
        'HOLD_ONLY_ZERO_INTERFACE_ROWS' AS gate_status,
        CURRENT_TIMESTAMP() AS built_at
      FROM _classified
    ) AS source
    ON target.run_id = source.run_id
    WHEN NOT MATCHED THEN INSERT ROW;

    ASSERT @@row_count = 1 AS 'run_id claim failed or already exists';

    INSERT INTO `pacific-plating-282708.sap_integration_v3.v3_cancel_ownership_hold`
    SELECT * FROM _classified;

    ASSERT @@row_count = (SELECT COUNT(*) FROM _classified)
      AS 'hold insert cardinality mismatch';

    ASSERT (
      SELECT classified_item_count = cancelled_item_count
        AND linked_change_order_count + unlinked_plain_cancel_count = cancelled_item_count
        AND interface_row_count = 0
      FROM `pacific-plating-282708.sap_integration_v3.v3_cancel_ownership_summary`
      WHERE run_id = p_run_id
    ) AS 'published hold-only conservation failed';

    ASSERT (
      SELECT COUNT(*)
      FROM `pacific-plating-282708.sap_integration_v3.v3_cancel_ownership_hold`
      WHERE run_id = p_run_id
    ) = (SELECT COUNT(*) FROM _classified) AS 'published hold detail count mismatch';
  COMMIT TRANSACTION;
END;

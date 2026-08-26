-- Class A / fail-closed. Linked change-order cancellation 56-column preparation.
-- Old-item cancellation does not require a replacement-item map, but release remains blocked on
-- Aware/FA approval. This artifact emits zero interface rows and performs no external mutation.

CREATE OR REPLACE VIEW
  `pacific-plating-282708.sap_integration_v3.vw_v3_change_order_cancel_payload_source` AS
SELECT * REPLACE ('Cancelled (Change order / Rejected)' AS TransactionStatus)
FROM `pacific-plating-282708.sap_integration_v3.vw_v3_plain_cancel_payload_source`;

CREATE TABLE IF NOT EXISTS
  `pacific-plating-282708.sap_integration_v3.v3_change_order_cancel_payload_hold` (
    ownership_run_id STRING NOT NULL,
    old_order_id STRING,
    old_order_item STRING NOT NULL,
    hold_code STRING NOT NULL,
    payload_row_count INT64 NOT NULL,
    payload_set_hash STRING NOT NULL,
    linked_new_order_count INT64 NOT NULL,
    paid_transition_required_rows INT64 NOT NULL,
    classified_at TIMESTAMP NOT NULL
  )
CLUSTER BY ownership_run_id, hold_code, old_order_item;

CREATE TABLE IF NOT EXISTS
  `pacific-plating-282708.sap_integration_v3.v3_change_order_cancel_payload_summary` (
    ownership_run_id STRING NOT NULL,
    input_item_count INT64 NOT NULL,
    classified_item_count INT64 NOT NULL,
    payload_row_count INT64 NOT NULL,
    structurally_ready_held_item_count INT64 NOT NULL,
    interface_row_count INT64 NOT NULL,
    gate_status STRING NOT NULL,
    built_at TIMESTAMP NOT NULL
  )
CLUSTER BY ownership_run_id, gate_status;

CREATE OR REPLACE PROCEDURE
  `pacific-plating-282708.sap_integration_v3.sp_build_v3_change_order_cancel_payload_holds`(
    p_ownership_run_id STRING
  )
BEGIN
  ASSERT NULLIF(TRIM(p_ownership_run_id), '') IS NOT NULL AS 'ownership_run_id is required';
  ASSERT (SELECT COUNT(*)
    FROM `pacific-plating-282708.sap_integration_v3.v3_cancel_ownership_summary`
    WHERE run_id = p_ownership_run_id AND gate_status = 'HOLD_ONLY_ZERO_INTERFACE_ROWS') = 1
    AS 'change-order preparation requires exactly one hold-only ownership summary';
  ASSERT NOT EXISTS (SELECT 1
    FROM `pacific-plating-282708.sap_integration_v3.v3_change_order_cancel_payload_summary`
    WHERE ownership_run_id = p_ownership_run_id) AS 'ownership_run_id already published';
  ASSERT (SELECT COUNT(*)
    FROM `pacific-plating-282708.sap_integration_v3.INFORMATION_SCHEMA.COLUMNS`
    WHERE table_name = 'vw_v3_change_order_cancel_payload_source') = 56
    AS 'change-order cancel source must have exactly 56 columns';
  ASSERT (SELECT COUNT(*) FROM (
    SELECT ordinal_position, column_name, data_type
    FROM `pacific-plating-282708.sap_integration_v3.INFORMATION_SCHEMA.COLUMNS`
    WHERE table_name = 'vw_v3_change_order_cancel_payload_source'
    EXCEPT DISTINCT
    SELECT ordinal_position, column_name, data_type
    FROM `pacific-plating-282708.sap_integration_v3.INFORMATION_SCHEMA.COLUMNS`
    WHERE table_name = 'v3_unit5_newpayment_delivery_ready')) = 0
    AND (SELECT COUNT(*) FROM (
    SELECT ordinal_position, column_name, data_type
    FROM `pacific-plating-282708.sap_integration_v3.INFORMATION_SCHEMA.COLUMNS`
    WHERE table_name = 'v3_unit5_newpayment_delivery_ready'
    EXCEPT DISTINCT
    SELECT ordinal_position, column_name, data_type
    FROM `pacific-plating-282708.sap_integration_v3.INFORMATION_SCHEMA.COLUMNS`
    WHERE table_name = 'vw_v3_change_order_cancel_payload_source')) = 0
    AS 'change-order cancel source differs from reviewed 56-column contract';

  CREATE TEMP TABLE _item AS
  SELECT order_id AS old_order_id, order_item AS old_order_item
  FROM `pacific-plating-282708.sap_integration_v3.v3_cancel_ownership_hold`
  WHERE run_id = p_ownership_run_id
    AND ownership_lane = 'LINKED_CHANGE_ORDER'
    AND hold_code = 'HOLD_CHANGE_ORDER_SEPARATE_FLOW';

  ASSERT NOT EXISTS (
    SELECT old_order_item FROM _item GROUP BY old_order_item HAVING COUNT(*) != 1
  ) AS 'change-order ownership input is duplicated';

  CREATE TEMP TABLE _link_shape AS
  SELECT item.old_order_item,
    COUNT(DISTINCT link.current_human_id) AS linked_new_order_count
  FROM _item AS item
  LEFT JOIN `pacific-plating-282708.careos.cancelled_change_orders` AS link
    ON link.old_human_id = item.old_order_id AND link.current_human_id IS NOT NULL
  GROUP BY item.old_order_item;

  CREATE TEMP TABLE _paid_period AS
  SELECT order_item, period, COUNT(*) AS payment_event_rows
  FROM `pacific-plating-282708.sap_integration_v3.stg_payment_events`
  GROUP BY order_item, period;

  CREATE TEMP TABLE _mirror_shape AS
  SELECT
    item.old_order_item,
    COUNT(mirror.U_OrderItem) AS mirror_rows,
    COUNT(DISTINCT mirror.U_Period) AS period_count,
    MIN(mirror.U_Period) AS min_period,
    MAX(mirror.U_Period) AS max_period,
    COUNT(DISTINCT mirror.TotalPeriods) AS total_period_versions,
    MAX(mirror.TotalPeriods) AS total_periods,
    COUNTIF(LOWER(COALESCE(mirror.TransactionStatus, '')) NOT IN ('paid', 'pending'))
      AS invalid_predecessor_rows,
    COUNTIF(mirror.U_Period = 1 AND LOWER(mirror.TransactionStatus) = 'paid')
      AS paid_first_period_rows,
    COUNTIF(EXISTS (
      SELECT 1 FROM UNNEST([
        STRUCT('GrossPremium' AS field_name, mirror.GrossPremium AS field_value),
        STRUCT('StampDuty', mirror.StampDuty), STRUCT('VAT', mirror.VAT),
        STRUCT('TotalPremium', mirror.TotalPremium), STRUCT('WHT', mirror.WHT),
        STRUCT('TotalEIR', mirror.TotalEIR), STRUCT('TotalSBT', mirror.TotalSBT),
        STRUCT('ProcessingFee', mirror.U_ProcessingFee),
        STRUCT('ProcessingFeeVat', mirror.U_ProcessingFeeVat),
        STRUCT('ShippingFee', mirror.U_ShippingFee),
        STRUCT('ShippingFeeVat', mirror.U_ShippingFeeVat),
        STRUCT('TotalAmount', mirror.U_TotalAmount), STRUCT('Discount', mirror.U_Discount),
        STRUCT('ExpectedReceived', COALESCE(mirror.ExpectedReceived, 0)),
        STRUCT('ActualReceived', COALESCE(mirror.U_ActualReceived, 0)),
        STRUCT('InterestThisPeriod', mirror.U_InterestThisPeriod),
        STRUCT('PrincipleThisPeriod', mirror.U_PrincipleThisPeriod),
        STRUCT('InterestEIRThisPeriod', mirror.U_InterestEIRThisPeriod),
        STRUCT('PrincipleEIRThisPeriod', mirror.U_PrincipleEIRThisPeriod),
        STRUCT('PendingPayment', mirror.PendingPayment),
        STRUCT('RefundAmountBeforeFee', mirror.RefundAmountBeforeFee),
        STRUCT('RefundAmountAfterFee', mirror.RefundAmountAfterFee)
      ]) AS numeric_field
      WHERE numeric_field.field_value IS NULL
        OR IS_NAN(numeric_field.field_value) OR IS_INF(numeric_field.field_value)
        OR ROUND(numeric_field.field_value, 2) != numeric_field.field_value
    )) AS invalid_numeric_source_rows,
    COUNTIF(LOWER(mirror.TransactionStatus) = 'pending'
      AND paid.payment_event_rows > 0) AS paid_transition_required_rows
  FROM _item AS item
  LEFT JOIN `pacific-plating-282708.sap_integration_v3.sap_mirror_state` AS mirror
    ON mirror.U_OrderItem = item.old_order_item
  LEFT JOIN _paid_period AS paid
    ON paid.order_item = mirror.U_OrderItem AND paid.period = mirror.U_Period
  GROUP BY item.old_order_item;

  CREATE TEMP TABLE _payload_shape AS
  SELECT
    item.old_order_item,
    COUNT(payload.OrderItem) AS payload_row_count,
    COUNTIF(REGEXP_CONTAINS(TO_JSON_STRING(payload), r':null|:"NULL"')) AS null_value_rows,
    COUNTIF(LENGTH(IFNULL(payload.OrderDate, '')) != 8
      OR SAFE.PARSE_DATE('%d%m%Y', payload.OrderDate) IS NULL
      OR LENGTH(IFNULL(payload.PolicyDate, '')) != 8
      OR SAFE.PARSE_DATE('%d%m%Y', payload.PolicyDate) IS NULL
      OR LENGTH(IFNULL(payload.ExpectedDate, '')) != 8
      OR SAFE.PARSE_DATE('%d%m%Y', payload.ExpectedDate) IS NULL
      OR LENGTH(IFNULL(payload.BatchRunDate, '')) != 8
      OR SAFE.PARSE_DATE('%d%m%Y', payload.BatchRunDate) IS NULL
      OR (payload.PaymentDate != '' AND (LENGTH(payload.PaymentDate) != 8
        OR SAFE.PARSE_DATE('%d%m%Y', payload.PaymentDate) IS NULL))) AS invalid_date_rows,
    COUNTIF(payload.TransactionStatus != 'Cancelled (Change order / Rejected)')
      AS invalid_target_status_rows,
    COUNTIF(
      NULLIF(TRIM(payload.CompanyDB), '') IS NULL
      OR NULLIF(TRIM(payload.OrderID), '') IS NULL
      OR NULLIF(TRIM(payload.OrderItem), '') IS NULL
      OR NULLIF(TRIM(payload.InsurerCode), '') IS NULL
      OR NULLIF(TRIM(payload.FirstName), '') IS NULL
      OR NULLIF(TRIM(payload.InsuranceGroup), '') IS NULL
      OR NULLIF(TRIM(payload.InsuranceProduct), '') IS NULL
      OR NULLIF(TRIM(payload.ProductType), '') IS NULL
      OR NULLIF(TRIM(payload.PolicyType), '') IS NULL
      OR NULLIF(TRIM(payload.PolicyDate), '') IS NULL
      OR NULLIF(TRIM(payload.PolicyNo), '') IS NULL
      OR NULLIF(TRIM(payload.ExpectedDate), '') IS NULL
      OR NULLIF(TRIM(payload.BillingAddress), '') IS NULL
      OR NULLIF(TRIM(payload.BatchRunDate), '') IS NULL
      OR UPPER(TRIM(payload.CompanyDB)) = 'NULL'
      OR UPPER(TRIM(payload.OrderID)) = 'NULL'
      OR UPPER(TRIM(payload.OrderItem)) = 'NULL'
      OR UPPER(TRIM(payload.InsurerCode)) = 'NULL'
      OR UPPER(TRIM(payload.FirstName)) = 'NULL'
      OR UPPER(TRIM(payload.InsuranceGroup)) = 'NULL'
      OR UPPER(TRIM(payload.InsuranceProduct)) = 'NULL'
      OR UPPER(TRIM(payload.ProductType)) = 'NULL'
      OR UPPER(TRIM(payload.PolicyType)) = 'NULL'
      OR UPPER(TRIM(payload.PolicyDate)) = 'NULL'
      OR UPPER(TRIM(payload.PolicyNo)) = 'NULL'
      OR UPPER(TRIM(payload.ExpectedDate)) = 'NULL'
      OR UPPER(TRIM(payload.BillingAddress)) = 'NULL'
      OR UPPER(TRIM(payload.BatchRunDate)) = 'NULL'
      OR (payload.PaymentDate != '' AND UPPER(TRIM(payload.PaymentDate)) = 'NULL')
      OR (payload.InvoiceNo != '' AND UPPER(TRIM(payload.InvoiceNo)) = 'NULL')
      OR (payload.PaymentMethod != '' AND UPPER(TRIM(payload.PaymentMethod)) = 'NULL')
      OR (payload.PaymentChannel != '' AND UPPER(TRIM(payload.PaymentChannel)) = 'NULL')
      OR (LOWER(mirror.TransactionStatus) = 'paid' AND (
        NULLIF(TRIM(payload.InvoiceNo), '') IS NULL
        OR NULLIF(TRIM(payload.PaymentDate), '') IS NULL
        OR NULLIF(TRIM(payload.PaymentMethod), '') IS NULL
        OR NULLIF(TRIM(payload.PaymentChannel), '') IS NULL))
    ) AS invalid_required_rows,
    TO_HEX(SHA256(COALESCE(STRING_AGG(TO_HEX(SHA256(TO_JSON_STRING(payload))), ''
      ORDER BY SAFE_CAST(payload.Period AS INT64), TO_JSON_STRING(payload)), '<EMPTY>')))
      AS payload_set_hash
  FROM _item AS item
  LEFT JOIN `pacific-plating-282708.sap_integration_v3.vw_v3_change_order_cancel_payload_source`
    AS payload ON payload.OrderItem = item.old_order_item
  LEFT JOIN `pacific-plating-282708.sap_integration_v3.sap_mirror_state` AS mirror
    ON mirror.U_OrderItem = payload.OrderItem AND mirror.U_Period = SAFE_CAST(payload.Period AS INT64)
  GROUP BY item.old_order_item;

  CREATE TEMP TABLE _classified AS
  SELECT
    p_ownership_run_id AS ownership_run_id,
    item.old_order_id,
    item.old_order_item,
    CASE
      WHEN link.linked_new_order_count != 1 THEN 'HOLD_CHANGE_ORDER_LINK_AMBIGUOUS'
      WHEN mirror.mirror_rows = 0 THEN 'HOLD_CHANGE_ORDER_MIRROR_MISSING'
      WHEN mirror.total_period_versions != 1 OR mirror.total_periods IS NULL
        OR mirror.min_period != 1 OR mirror.max_period != mirror.total_periods
        OR mirror.period_count != mirror.total_periods OR mirror.mirror_rows != mirror.total_periods
        THEN 'HOLD_CHANGE_ORDER_SPINE_INVALID'
      WHEN mirror.invalid_predecessor_rows > 0 THEN 'HOLD_CHANGE_ORDER_PREDECESSOR_STATUS_INVALID'
      WHEN mirror.paid_first_period_rows != 1 THEN 'HOLD_CHANGE_ORDER_FIRST_PERIOD_NOT_PAID'
      WHEN mirror.invalid_numeric_source_rows > 0 THEN 'HOLD_CHANGE_ORDER_NUMERIC_SOURCE_INVALID'
      WHEN mirror.paid_transition_required_rows > 0
        THEN 'HOLD_CHANGE_ORDER_PAID_TRANSITION_REQUIRED'
      WHEN payload.payload_row_count != mirror.mirror_rows
        THEN 'HOLD_CHANGE_ORDER_PAYLOAD_CARDINALITY'
      WHEN payload.null_value_rows > 0 OR payload.invalid_required_rows > 0
        THEN 'HOLD_CHANGE_ORDER_REQUIRED_VALUE_INVALID'
      WHEN payload.invalid_date_rows > 0 THEN 'HOLD_CHANGE_ORDER_DATE_INVALID'
      WHEN payload.invalid_target_status_rows > 0 THEN 'HOLD_CHANGE_ORDER_STATUS_INVALID'
      ELSE 'HOLD_CHANGE_ORDER_AWARE_FA_APPROVAL_REQUIRED'
    END AS hold_code,
    payload.payload_row_count,
    payload.payload_set_hash,
    link.linked_new_order_count,
    mirror.paid_transition_required_rows,
    CURRENT_TIMESTAMP() AS classified_at
  FROM _item AS item
  JOIN _link_shape AS link USING (old_order_item)
  JOIN _mirror_shape AS mirror USING (old_order_item)
  JOIN _payload_shape AS payload USING (old_order_item);

  ASSERT (SELECT COUNT(*) FROM _classified) = (SELECT COUNT(*) FROM _item)
    AS 'change-order item population was not conserved';
  ASSERT NOT EXISTS (SELECT 1 FROM _classified WHERE hold_code IS NULL)
    AS 'change-order classifier produced a NULL hold';

  BEGIN TRANSACTION;
    MERGE `pacific-plating-282708.sap_integration_v3.v3_change_order_cancel_payload_summary`
      AS target
    USING (
      SELECT p_ownership_run_id AS ownership_run_id,
        COUNT(*) AS input_item_count, COUNT(*) AS classified_item_count,
        COALESCE(SUM(payload_row_count), 0) AS payload_row_count,
        COUNTIF(hold_code = 'HOLD_CHANGE_ORDER_AWARE_FA_APPROVAL_REQUIRED')
          AS structurally_ready_held_item_count,
        0 AS interface_row_count, 'HOLD_ONLY_ZERO_INTERFACE_ROWS' AS gate_status,
        CURRENT_TIMESTAMP() AS built_at
      FROM _classified
    ) AS source
    ON target.ownership_run_id = source.ownership_run_id
    WHEN NOT MATCHED THEN INSERT ROW;
    ASSERT @@row_count = 1 AS 'change-order summary claim failed';

    INSERT INTO `pacific-plating-282708.sap_integration_v3.v3_change_order_cancel_payload_hold`
    SELECT * FROM _classified;
    ASSERT @@row_count = (SELECT COUNT(*) FROM _classified)
      AS 'change-order hold insertion was not conserved';
    ASSERT (SELECT input_item_count = classified_item_count AND interface_row_count = 0
      FROM `pacific-plating-282708.sap_integration_v3.v3_change_order_cancel_payload_summary`
      WHERE ownership_run_id = p_ownership_run_id)
      AS 'change-order published summary conservation failed';
  COMMIT TRANSACTION;
END;

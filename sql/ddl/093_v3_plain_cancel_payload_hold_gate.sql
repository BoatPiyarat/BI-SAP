-- Class A / fail-closed. Reusable unlinked plain-cancellation 56-column preparation.
-- This artifact publishes hold/report evidence only. It emits zero interface rows and performs
-- no GCS, scheduler, SAP, delivery-ledger, or ACK mutation.

CREATE OR REPLACE VIEW
  `pacific-plating-282708.sap_integration_v3.vw_v3_plain_cancel_payload_source` AS
SELECT
  CAST(CompanyDB AS STRING) AS CompanyDB,
  CAST(U_OrderID AS STRING) AS OrderID,
  CAST(U_OrderItem AS STRING) AS OrderItem,
  COALESCE(CAST(U_InvoiceNo AS STRING), '') AS InvoiceNo,
  CAST(OrderDate AS STRING) AS OrderDate,
  CAST(U_InsuredID AS STRING) AS InsuredID,
  CAST(U_Title AS STRING) AS Title,
  CAST(U_FirstName AS STRING) AS FirstName,
  CAST(U_LastName AS STRING) AS LastName,
  CAST(U_InsurerCode AS STRING) AS InsurerCode,
  CAST(U_InsuranceGroup AS STRING) AS InsuranceGroup,
  CAST(U_InsuranceType AS STRING) AS InsuranceType,
  CAST(U_InsuranceProduct AS STRING) AS InsuranceProduct,
  CAST(U_ProductType AS STRING) AS ProductType,
  CAST(U_PolicyType AS STRING) AS PolicyType,
  CAST(U_Endorse AS STRING) AS Endorse,
  CAST(PolicyDate AS STRING) AS PolicyDate,
  CAST(U_PolicyNo AS STRING) AS PolicyNo,
  CAST(EndorsementNo AS STRING) AS EndorsementNo,
  CAST(U_ChassisNo AS STRING) AS ChassisNo,
  CAST(U_LicensePlate AS STRING) AS LicensePlate,
  FORMAT('%.2f', COALESCE(GrossPremium, 0)) AS GrossPremium,
  FORMAT('%.2f', COALESCE(StampDuty, 0)) AS StampDuty,
  FORMAT('%.2f', COALESCE(VAT, 0)) AS VAT,
  FORMAT('%.2f', COALESCE(TotalPremium, 0)) AS TotalPremium,
  FORMAT('%.2f', COALESCE(WHT, 0)) AS WHT,
  FORMAT('%.2f', COALESCE(TotalEIR, 0)) AS TotalEIR,
  FORMAT('%.2f', COALESCE(TotalSBT, 0)) AS TotalSBT,
  FORMAT('%.2f', COALESCE(U_ProcessingFee, 0)) AS ProcessingFee,
  FORMAT('%.2f', COALESCE(U_ProcessingFeeVat, 0)) AS ProcessingFeeVat,
  FORMAT('%.2f', COALESCE(U_ShippingFee, 0)) AS ShippingFee,
  FORMAT('%.2f', COALESCE(U_ShippingFeeVat, 0)) AS ShippingFeeVat,
  FORMAT('%.2f', COALESCE(U_TotalAmount, 0)) AS TotalAmount,
  FORMAT('%.2f', COALESCE(U_Discount, 0)) AS Discount,
  'Cancelled' AS TransactionStatus,
  CAST(U_SubmissionStatus AS STRING) AS SubmissionStatus,
  CAST(U_ApprovalStatus AS STRING) AS ApprovalStatus,
  CAST(U_PaymentStatus AS STRING) AS PaymentStatus,
  FORMAT('%.2f', COALESCE(ExpectedReceived, 0)) AS ExpectedReceived,
  FORMAT('%.2f', COALESCE(U_ActualReceived, 0)) AS ActualReceived,
  FORMAT('%.2f', COALESCE(U_InterestThisPeriod, 0)) AS InterestThisPeriod,
  FORMAT('%.2f', COALESCE(U_PrincipleThisPeriod, 0)) AS PrincipleThisPeriod,
  FORMAT('%.2f', COALESCE(U_InterestEIRThisPeriod, 0)) AS InterestEIRThisPeriod,
  FORMAT('%.2f', COALESCE(U_PrincipleEIRThisPeriod, 0)) AS PrincipleEIRThisPeriod,
  COALESCE(CAST(PaymentDate AS STRING), '') AS PaymentDate,
  CAST(U_Period AS STRING) AS Period,
  CAST(TotalPeriods AS STRING) AS TotalPeriods,
  FORMAT('%.2f', COALESCE(PendingPayment, 0)) AS PendingPayment,
  IF(LOWER(TransactionStatus) = 'pending', '', COALESCE(CAST(PaymentMethod AS STRING), ''))
    AS PaymentMethod,
  IF(LOWER(TransactionStatus) = 'pending', '', COALESCE(CAST(PaymentChannel AS STRING), ''))
    AS PaymentChannel,
  COALESCE(NULLIF(TRIM(CAST(ExpectedDate AS STRING)), ''),
    NULLIF(TRIM(CAST(PaymentDate AS STRING)), ''),
    NULLIF(TRIM(CAST(BatchRunDate AS STRING)), ''), '') AS ExpectedDate,
  CAST(RefOrder AS STRING) AS RefOrder,
  FORMAT('%.2f', COALESCE(RefundAmountBeforeFee, 0)) AS RefundAmountBeforeFee,
  FORMAT('%.2f', COALESCE(RefundAmountAfterFee, 0)) AS RefundAmountAfterFee,
  CAST(BillingAddress AS STRING) AS BillingAddress,
  CAST(BatchRunDate AS STRING) AS BatchRunDate
FROM `pacific-plating-282708.sap_integration_v3.sap_mirror_state`;

CREATE TABLE IF NOT EXISTS
  `pacific-plating-282708.sap_integration_v3.v3_plain_cancel_payload_hold` (
    ownership_run_id STRING NOT NULL,
    order_item STRING NOT NULL,
    hold_code STRING NOT NULL,
    payload_row_count INT64 NOT NULL,
    payload_set_hash STRING NOT NULL,
    paid_transition_required_rows INT64 NOT NULL,
    multi_document_rows INT64 NOT NULL,
    classified_at TIMESTAMP NOT NULL
  )
CLUSTER BY ownership_run_id, hold_code, order_item;

CREATE TABLE IF NOT EXISTS
  `pacific-plating-282708.sap_integration_v3.v3_plain_cancel_payload_summary` (
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
  `pacific-plating-282708.sap_integration_v3.sp_build_v3_plain_cancel_payload_holds`(
    p_ownership_run_id STRING
  )
BEGIN
  ASSERT NULLIF(TRIM(p_ownership_run_id), '') IS NOT NULL AS 'ownership_run_id is required';
  ASSERT (SELECT COUNT(*)
    FROM `pacific-plating-282708.sap_integration_v3.v3_cancel_ownership_summary`
    WHERE run_id = p_ownership_run_id AND gate_status = 'HOLD_ONLY_ZERO_INTERFACE_ROWS') = 1
    AS 'plain cancel preparation requires exactly one hold-only ownership summary';
  ASSERT NOT EXISTS (SELECT 1
    FROM `pacific-plating-282708.sap_integration_v3.v3_plain_cancel_payload_summary`
    WHERE ownership_run_id = p_ownership_run_id) AS 'ownership_run_id already published';
  ASSERT (SELECT COUNT(*)
    FROM `pacific-plating-282708.sap_integration_v3.INFORMATION_SCHEMA.COLUMNS`
    WHERE table_name = 'vw_v3_plain_cancel_payload_source') = 56
    AS 'plain cancel source must have exactly 56 columns';
  ASSERT (SELECT COUNT(*) FROM (
    SELECT ordinal_position, column_name, data_type
    FROM `pacific-plating-282708.sap_integration_v3.INFORMATION_SCHEMA.COLUMNS`
    WHERE table_name = 'vw_v3_plain_cancel_payload_source'
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
    WHERE table_name = 'vw_v3_plain_cancel_payload_source')) = 0
    AS 'plain cancel source differs from reviewed 56-column contract';

  CREATE TEMP TABLE _item AS
  SELECT order_item
  FROM `pacific-plating-282708.sap_integration_v3.v3_cancel_ownership_hold`
  WHERE run_id = p_ownership_run_id
    AND ownership_lane = 'UNLINKED_PLAIN_CANCEL'
    AND hold_code = 'HOLD_PLAIN_CANCEL_AWAITING_SCENARIO_APPROVAL';

  ASSERT NOT EXISTS (SELECT order_item FROM _item GROUP BY order_item HAVING COUNT(*) != 1)
    AS 'plain cancel ownership input is duplicated';

  CREATE TEMP TABLE _paid_period AS
  SELECT order_item, period, COUNT(*) AS payment_event_rows
  FROM `pacific-plating-282708.sap_integration_v3.stg_payment_events`
  GROUP BY order_item, period;

  CREATE TEMP TABLE _mirror_shape AS
  SELECT
    item.order_item,
    COUNT(mirror.U_OrderItem) AS mirror_rows,
    COUNT(DISTINCT mirror.U_Period) AS period_count,
    MIN(mirror.U_Period) AS min_period,
    MAX(mirror.U_Period) AS max_period,
    COUNT(DISTINCT mirror.TotalPeriods) AS total_period_versions,
    MAX(mirror.TotalPeriods) AS total_periods,
    COUNTIF(LOWER(COALESCE(mirror.TransactionStatus, '')) NOT IN ('paid', 'pending'))
      AS invalid_predecessor_rows,
    COUNTIF(mirror.docs_considered > 1) AS multi_document_rows,
    COUNTIF(LOWER(mirror.TransactionStatus) = 'pending'
      AND paid.payment_event_rows > 0) AS paid_transition_required_rows
  FROM _item AS item
  LEFT JOIN `pacific-plating-282708.sap_integration_v3.sap_mirror_state` AS mirror
    ON mirror.U_OrderItem = item.order_item
  LEFT JOIN _paid_period AS paid
    ON paid.order_item = mirror.U_OrderItem AND paid.period = mirror.U_Period
  GROUP BY item.order_item;

  CREATE TEMP TABLE _payload_shape AS
  SELECT
    item.order_item,
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
    COUNTIF(payload.TransactionStatus != 'Cancelled') AS invalid_target_status_rows,
    TO_HEX(SHA256(COALESCE(STRING_AGG(TO_HEX(SHA256(TO_JSON_STRING(payload))), ''
      ORDER BY SAFE_CAST(payload.Period AS INT64), TO_JSON_STRING(payload)), '<EMPTY>')))
      AS payload_set_hash
  FROM _item AS item
  LEFT JOIN `pacific-plating-282708.sap_integration_v3.vw_v3_plain_cancel_payload_source` AS payload
    ON payload.OrderItem = item.order_item
  GROUP BY item.order_item;

  CREATE TEMP TABLE _classified AS
  SELECT
    p_ownership_run_id AS ownership_run_id,
    item.order_item,
    CASE
      WHEN mirror.mirror_rows = 0 THEN 'HOLD_PLAIN_CANCEL_MIRROR_MISSING'
      WHEN mirror.total_period_versions != 1 OR mirror.total_periods IS NULL
        OR mirror.min_period != 1 OR mirror.max_period != mirror.total_periods
        OR mirror.period_count != mirror.total_periods OR mirror.mirror_rows != mirror.total_periods
        THEN 'HOLD_PLAIN_CANCEL_SPINE_INVALID'
      WHEN mirror.invalid_predecessor_rows > 0 THEN 'HOLD_PLAIN_CANCEL_PREDECESSOR_STATUS_INVALID'
      WHEN mirror.paid_transition_required_rows > 0
        THEN 'HOLD_PLAIN_CANCEL_PAID_TRANSITION_REQUIRED'
      WHEN payload.payload_row_count != mirror.mirror_rows
        THEN 'HOLD_PLAIN_CANCEL_PAYLOAD_CARDINALITY'
      WHEN payload.null_value_rows > 0 THEN 'HOLD_PLAIN_CANCEL_REQUIRED_VALUE_INVALID'
      WHEN payload.invalid_date_rows > 0 THEN 'HOLD_PLAIN_CANCEL_DATE_INVALID'
      WHEN payload.invalid_target_status_rows > 0 THEN 'HOLD_PLAIN_CANCEL_STATUS_INVALID'
      ELSE 'HOLD_PLAIN_CANCEL_FA_BATCH_APPROVAL_REQUIRED'
    END AS hold_code,
    payload.payload_row_count,
    payload.payload_set_hash,
    mirror.paid_transition_required_rows,
    mirror.multi_document_rows,
    CURRENT_TIMESTAMP() AS classified_at
  FROM _item AS item
  JOIN _mirror_shape AS mirror USING (order_item)
  JOIN _payload_shape AS payload USING (order_item);

  ASSERT (SELECT COUNT(*) FROM _classified) = (SELECT COUNT(*) FROM _item)
    AS 'plain cancel item population was not conserved';
  ASSERT NOT EXISTS (SELECT 1 FROM _classified WHERE hold_code IS NULL)
    AS 'plain cancel classifier produced a NULL hold';

  BEGIN TRANSACTION;
    MERGE `pacific-plating-282708.sap_integration_v3.v3_plain_cancel_payload_summary` AS target
    USING (
      SELECT p_ownership_run_id AS ownership_run_id,
        COUNT(*) AS input_item_count, COUNT(*) AS classified_item_count,
        COALESCE(SUM(payload_row_count), 0) AS payload_row_count,
        COUNTIF(hold_code = 'HOLD_PLAIN_CANCEL_FA_BATCH_APPROVAL_REQUIRED')
          AS structurally_ready_held_item_count,
        0 AS interface_row_count, 'HOLD_ONLY_ZERO_INTERFACE_ROWS' AS gate_status,
        CURRENT_TIMESTAMP() AS built_at
      FROM _classified
    ) AS source
    ON target.ownership_run_id = source.ownership_run_id
    WHEN NOT MATCHED THEN INSERT ROW;
    ASSERT @@row_count = 1 AS 'plain cancel summary claim failed';

    INSERT INTO `pacific-plating-282708.sap_integration_v3.v3_plain_cancel_payload_hold`
    SELECT * FROM _classified;
    ASSERT @@row_count = (SELECT COUNT(*) FROM _classified)
      AS 'plain cancel hold insertion was not conserved';
    ASSERT (SELECT input_item_count = classified_item_count AND interface_row_count = 0
      FROM `pacific-plating-282708.sap_integration_v3.v3_plain_cancel_payload_summary`
      WHERE ownership_run_id = p_ownership_run_id)
      AS 'plain cancel published summary conservation failed';
  COMMIT TRANSACTION;
END;

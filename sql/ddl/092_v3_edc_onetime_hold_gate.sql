-- Class A / fail-closed. CREDIT_CARD_INSTALLMENT is owned by ONETIME/EDC and exactly period 1/1.
-- The current business-approved bank mapping is limited to EDC/KASIKORN -> RCB-EDC-KBANK.
-- All events remain hold-only until scenario numbering and release activation are approved.

CREATE OR REPLACE VIEW
  `pacific-plating-282708.sap_integration_v3.vw_v3_edc_onetime_payload_source` AS
WITH event_identity AS (
  SELECT DISTINCT
    event.order_item,
    event.period,
    `pacific-plating-282708.sap_integration_v3.fn_invoice_no`(event.third_party_id) AS invoice_no
  FROM `pacific-plating-282708.sap_integration_v3.stg_payment_events` AS event
  WHERE event.payment_option = 'CREDIT_CARD_INSTALLMENT'
)
SELECT
  CAST(src.CompanyDB AS STRING) AS CompanyDB, CAST(src.OrderID AS STRING) AS OrderID,
  CAST(src.OrderItem AS STRING) AS OrderItem, CAST(src.InvoiceNo AS STRING) AS InvoiceNo,
  CAST(src.OrderDate AS STRING) AS OrderDate, CAST(src.InsuredID AS STRING) AS InsuredID,
  CAST(src.Title AS STRING) AS Title, CAST(src.FirstName AS STRING) AS FirstName,
  CAST(src.LastName AS STRING) AS LastName, CAST(src.InsurerCode AS STRING) AS InsurerCode,
  CAST(src.InsuranceGroup AS STRING) AS InsuranceGroup,
  CAST(src.InsuranceType AS STRING) AS InsuranceType,
  CAST(src.InsuranceProduct AS STRING) AS InsuranceProduct,
  CAST(src.ProductType AS STRING) AS ProductType, CAST(src.PolicyType AS STRING) AS PolicyType,
  CAST(src.Endorse AS STRING) AS Endorse, CAST(src.PolicyDate AS STRING) AS PolicyDate,
  CAST(src.PolicyNo AS STRING) AS PolicyNo, CAST(src.EndorsementNo AS STRING) AS EndorsementNo,
  CAST(src.ChassisNo AS STRING) AS ChassisNo, CAST(src.LicensePlate AS STRING) AS LicensePlate,
  CAST(src.GrossPremium AS STRING) AS GrossPremium, CAST(src.StampDuty AS STRING) AS StampDuty,
  CAST(src.VAT AS STRING) AS VAT, CAST(src.TotalPremium AS STRING) AS TotalPremium,
  CAST(src.WHT AS STRING) AS WHT, CAST(src.TotalEIR AS STRING) AS TotalEIR,
  CAST(src.TotalSBT AS STRING) AS TotalSBT, CAST(src.ProcessingFee AS STRING) AS ProcessingFee,
  CAST(src.ProcessingFeeVat AS STRING) AS ProcessingFeeVat,
  CAST(src.ShippingFee AS STRING) AS ShippingFee,
  CAST(src.ShippingFeeVat AS STRING) AS ShippingFeeVat,
  CAST(src.TotalAmount AS STRING) AS TotalAmount, CAST(src.Discount AS STRING) AS Discount,
  CAST(src.TransactionStatus AS STRING) AS TransactionStatus,
  CAST(src.SubmissionStatus AS STRING) AS SubmissionStatus,
  CAST(src.ApprovalStatus AS STRING) AS ApprovalStatus,
  CAST(src.PaymentStatus AS STRING) AS PaymentStatus,
  CAST(src.ExpectedReceived AS STRING) AS ExpectedReceived,
  CAST(src.ActualReceived AS STRING) AS ActualReceived,
  CAST(src.InterestThisPeriod AS STRING) AS InterestThisPeriod,
  CAST(src.PrincipleThisPeriod AS STRING) AS PrincipleThisPeriod,
  CAST(src.InterestEIRThisPeriod AS STRING) AS InterestEIRThisPeriod,
  CAST(src.PrincipleEIRThisPeriod AS STRING) AS PrincipleEIRThisPeriod,
  CAST(src.PaymentDate AS STRING) AS PaymentDate, CAST(src.Period AS STRING) AS Period,
  CAST(src.TotalPeriods AS STRING) AS TotalPeriods,
  CAST(src.PendingPayment AS STRING) AS PendingPayment,
  CAST(src.PaymentMethod AS STRING) AS PaymentMethod,
  CAST(src.PaymentChannel AS STRING) AS PaymentChannel,
  CAST(src.ExpectedDate AS STRING) AS ExpectedDate, CAST(src.RefOrder AS STRING) AS RefOrder,
  CAST(src.RefundAmountBeforeFee AS STRING) AS RefundAmountBeforeFee,
  CAST(src.RefundAmountAfterFee AS STRING) AS RefundAmountAfterFee,
  CAST(src.BillingAddress AS STRING) AS BillingAddress,
  CAST(src.BatchRunDate AS STRING) AS BatchRunDate
FROM `pacific-plating-282708.sap_integration_v3.vw_onetime_payload_source` AS src
JOIN event_identity AS event
  ON event.order_item = src.OrderItem
  AND event.period = SAFE_CAST(src.Period AS INT64)
  AND event.invoice_no IS NOT DISTINCT FROM src.InvoiceNo;

CREATE TABLE IF NOT EXISTS
  `pacific-plating-282708.sap_integration_v3.v3_edc_onetime_event_hold` (
    pipeline_run_id STRING NOT NULL,
    order_id STRING,
    order_item STRING,
    period INT64,
    charge_id STRING,
    invoice_no STRING,
    payment_method_source STRING,
    payment_channel_source STRING,
    product_scope STRING,
    sap_payment_method STRING,
    sap_payment_channel STRING,
    unit2_outcome STRING NOT NULL,
    hold_code STRING NOT NULL,
    exact_payload_rows INT64 NOT NULL,
    mapping_rows INT64 NOT NULL,
    classified_at TIMESTAMP NOT NULL
  )
CLUSTER BY pipeline_run_id, hold_code, order_item;

CREATE TABLE IF NOT EXISTS
  `pacific-plating-282708.sap_integration_v3.v3_edc_onetime_event_summary` (
    pipeline_run_id STRING NOT NULL,
    event_count INT64 NOT NULL,
    classified_count INT64 NOT NULL,
    acknowledged_count INT64 NOT NULL,
    kbank_structurally_ready_count INT64 NOT NULL,
    unapproved_bank_or_method_count INT64 NOT NULL,
    interface_row_count INT64 NOT NULL,
    gate_status STRING NOT NULL,
    built_at TIMESTAMP NOT NULL
  )
CLUSTER BY pipeline_run_id, gate_status;

CREATE OR REPLACE PROCEDURE
  `pacific-plating-282708.sap_integration_v3.sp_build_v3_edc_onetime_holds`(
    p_pipeline_run_id STRING
  )
BEGIN
  ASSERT NULLIF(TRIM(p_pipeline_run_id), '') IS NOT NULL AS 'pipeline_run_id is required';
  ASSERT (SELECT COUNT(*)
    FROM `pacific-plating-282708.sap_integration_v3.pipeline_run_log`
    WHERE run_id = p_pipeline_run_id AND step = 'UNIT1_COMPLETE' AND status = 'SUCCESS') = 1
    AS 'EDC gate requires exactly one successful Unit 1 row';
  ASSERT NOT EXISTS (
    SELECT 1 FROM `pacific-plating-282708.sap_integration_v3.v3_edc_onetime_event_summary`
    WHERE pipeline_run_id = p_pipeline_run_id
  ) AS 'pipeline_run_id already published';
  ASSERT (SELECT COUNT(*) FROM `pacific-plating-282708.sap_integration_v3.INFORMATION_SCHEMA.COLUMNS`
    WHERE table_name = 'vw_v3_edc_onetime_payload_source') = 56
    AS 'EDC source must have exactly 56 columns';
  ASSERT (SELECT COUNT(*) FROM (
    SELECT ordinal_position, column_name, data_type
    FROM `pacific-plating-282708.sap_integration_v3.INFORMATION_SCHEMA.COLUMNS`
    WHERE table_name = 'vw_v3_edc_onetime_payload_source'
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
    WHERE table_name = 'vw_v3_edc_onetime_payload_source')) = 0
    AS 'EDC source names/types/ordinals differ from reviewed 56-column contract';

  CREATE TEMP TABLE _staged_shape AS
  SELECT
    charge_id,
    COUNT(*) AS staged_rows,
    COUNTIF(payment_option = 'CREDIT_CARD_INSTALLMENT') AS cci_rows,
    COUNT(DISTINCT payment_option) AS payment_option_count,
    ANY_VALUE(payment_option HAVING MIN payment_option) AS payment_option,
    ANY_VALUE(payment_method_source HAVING MIN payment_method_source) AS payment_method_source,
    ANY_VALUE(payment_channel_source HAVING MIN payment_channel_source) AS payment_channel_source
  FROM `pacific-plating-282708.sap_integration_v3.stg_payment_events`
  GROUP BY charge_id;

  CREATE TEMP TABLE _item_shape AS
  SELECT
    human_id AS order_item,
    COUNT(*) AS item_rows,
    COUNT(DISTINCT product) AS product_count,
    ANY_VALUE(product HAVING MIN product) AS item_product
  FROM `pacific-plating-282708.careos.careos_order_items`
  GROUP BY human_id;

  CREATE TEMP TABLE _event AS
  SELECT
    unit2.*,
    staged.staged_rows,
    staged.cci_rows,
    staged.payment_option_count,
    staged.payment_option,
    staged.payment_method_source,
    staged.payment_channel_source,
    item.item_rows,
    item.product_count,
    IF(item.item_product = 'products/car-insurance', 'MOTOR', 'NONMOTOR') AS product_scope,
    COUNT(*) OVER (PARTITION BY unit2.order_item, unit2.period, unit2.charge_id, unit2.invoice_no)
      AS event_identity_rows,
    COUNT(*) OVER (PARTITION BY unit2.charge_id) AS charge_rows
  FROM `pacific-plating-282708.sap_integration_v3.v3_unit2_event_shadow` AS unit2
  LEFT JOIN _staged_shape AS staged
    ON staged.charge_id IS NOT DISTINCT FROM unit2.charge_id
  LEFT JOIN _item_shape AS item
    ON item.order_item IS NOT DISTINCT FROM unit2.order_item
  WHERE unit2.pipeline_run_id = p_pipeline_run_id
    AND unit2.flow = 'ONETIME'
    AND staged.cci_rows > 0;

  CREATE TEMP TABLE _schedule_shape AS
  SELECT
    event.charge_id,
    COUNT(schedule.order_item) AS schedule_rows,
    COUNTIF(schedule.flow = 'ONETIME' AND schedule.total_periods = 1
      AND schedule.period = 1 AND schedule.payment_option = 'CREDIT_CARD_INSTALLMENT')
      AS exact_schedule_rows
  FROM _event AS event
  LEFT JOIN `pacific-plating-282708.sap_integration_v3.stg_schedule` AS schedule
    ON schedule.order_item IS NOT DISTINCT FROM event.order_item
    AND schedule.order_id IS NOT DISTINCT FROM event.order_id
    AND schedule.period IS NOT DISTINCT FROM event.period
  GROUP BY event.charge_id;

  CREATE TEMP TABLE _payload_shape AS
  SELECT
    event.charge_id,
    COUNT(payload.OrderItem) AS payload_rows,
    COUNTIF(SAFE_CAST(payload.Period AS INT64) = 1
      AND SAFE_CAST(payload.TotalPeriods AS INT64) = 1
      AND payload.InvoiceNo IS NOT DISTINCT FROM event.invoice_no) AS exact_payload_rows
  FROM _event AS event
  LEFT JOIN `pacific-plating-282708.sap_integration_v3.vw_v3_edc_onetime_payload_source` AS payload
    ON payload.OrderItem IS NOT DISTINCT FROM event.order_item
    AND SAFE_CAST(payload.Period AS INT64) IS NOT DISTINCT FROM event.period
  GROUP BY event.charge_id;

  CREATE TEMP TABLE _mapping_shape AS
  SELECT
    event.charge_id,
    COUNT(map.mapping_id) AS mapping_rows,
    ANY_VALUE(map.sap_payment_method HAVING MIN map.mapping_id) AS sap_payment_method,
    ANY_VALUE(map.sap_payment_channel HAVING MIN map.mapping_id) AS sap_payment_channel
  FROM _event AS event
  LEFT JOIN `pacific-plating-282708.sap_integration_v3.payment_mapping_registry` AS map
    ON map.approval_state = 'APPROVED' AND map.flow = 'ONETIME'
    AND map.product_scope = event.product_scope AND map.is_credit_shell = FALSE
    AND map.payment_source_type = 'CREDIT_CARD_INSTALLMENT'
    AND map.payment_method_source = IFNULL(event.payment_method_source, '')
    AND map.payment_channel_source = IFNULL(event.payment_channel_source, '')
    AND DATE(event.charge_time) >= map.effective_start
    AND DATE(event.charge_time) < IFNULL(map.effective_end, DATE '9999-12-31')
  GROUP BY event.charge_id;

  CREATE TEMP TABLE _shape AS
  SELECT event.*, schedule.schedule_rows, schedule.exact_schedule_rows,
    payload.payload_rows, payload.exact_payload_rows, mapping.mapping_rows,
    mapping.sap_payment_method, mapping.sap_payment_channel
  FROM _event AS event
  JOIN _schedule_shape AS schedule
    ON schedule.charge_id IS NOT DISTINCT FROM event.charge_id
  JOIN _payload_shape AS payload
    ON payload.charge_id IS NOT DISTINCT FROM event.charge_id
  JOIN _mapping_shape AS mapping
    ON mapping.charge_id IS NOT DISTINCT FROM event.charge_id;

  CREATE TEMP TABLE _classified AS
  SELECT
    pipeline_run_id, order_id, order_item, period, charge_id, invoice_no,
    payment_method_source, payment_channel_source, product_scope,
    sap_payment_method, sap_payment_channel,
    COALESCE(outcome, '<NULL>') AS unit2_outcome,
    CASE
      WHEN outcome IS NULL THEN 'HOLD_EDC_UNIT2_OUTCOME_NULL'
      WHEN event_identity_rows != 1 OR charge_rows != 1
        THEN 'HOLD_EDC_DUPLICATE_OR_CONFLICTING_EVENT'
      WHEN staged_rows != 1 OR cci_rows != 1 OR payment_option_count != 1
        THEN 'HOLD_EDC_STAGED_EVENT_CARDINALITY'
      WHEN outcome = 'ACKNOWLEDGED' THEN 'NOT_ACTIONABLE_ALREADY_ACKNOWLEDGED'
      WHEN outcome != 'READY_CREATE_OR_PAYMENT' THEN CONCAT('HOLD_UNIT2_', outcome)
      WHEN NULLIF(TRIM(order_id), '') IS NULL OR NULLIF(TRIM(order_item), '') IS NULL
        OR period IS NULL OR NULLIF(TRIM(charge_id), '') IS NULL
        OR NULLIF(TRIM(invoice_no), '') IS NULL THEN 'HOLD_EDC_EVENT_IDENTITY_INVALID'
      WHEN item_rows IS DISTINCT FROM 1 OR product_count IS DISTINCT FROM 1
        THEN 'HOLD_EDC_PRODUCT_SCOPE_AMBIGUOUS'
      WHEN schedule_rows != 1 OR exact_schedule_rows != 1 THEN 'HOLD_EDC_ONETIME_ROUTE_INVALID'
      WHEN exact_payload_rows = 0 THEN 'HOLD_EDC_56_SOURCE_MISSING'
      WHEN exact_payload_rows != 1 THEN 'HOLD_EDC_56_SOURCE_AMBIGUOUS'
      WHEN product_scope != 'MOTOR' THEN 'HOLD_EDC_PRODUCT_SCOPE_MAPPING_REQUIRED'
      WHEN payment_method_source = 'EDC' AND payment_channel_source = 'KASIKORN'
        AND mapping_rows != 1 THEN 'HOLD_EDC_KBANK_REGISTRY_INVALID'
      WHEN payment_method_source IS DISTINCT FROM 'EDC'
        OR payment_channel_source IS DISTINCT FROM 'KASIKORN'
        THEN 'HOLD_EDC_BANK_OR_METHOD_APPROVAL_REQUIRED'
      WHEN sap_payment_method IS DISTINCT FROM 'EDC EDC'
        OR sap_payment_channel IS DISTINCT FROM 'RCB-EDC-KBANK'
        THEN 'HOLD_EDC_KBANK_LITERAL_INVALID'
      ELSE 'HOLD_EDC_SCENARIO_RELEASE_APPROVAL_REQUIRED'
    END AS hold_code,
    exact_payload_rows,
    mapping_rows,
    CURRENT_TIMESTAMP() AS classified_at
  FROM _shape;

  ASSERT (SELECT COUNT(*) FROM _classified) = (SELECT COUNT(*) FROM _event)
    AS 'EDC event population was not conserved';
  ASSERT NOT EXISTS (SELECT 1 FROM _classified WHERE hold_code IS NULL)
    AS 'EDC classifier produced a NULL hold';

  BEGIN TRANSACTION;
    MERGE `pacific-plating-282708.sap_integration_v3.v3_edc_onetime_event_summary` AS target
    USING (
      SELECT p_pipeline_run_id AS pipeline_run_id, COUNT(*) AS event_count,
        COUNT(*) AS classified_count,
        COUNTIF(hold_code = 'NOT_ACTIONABLE_ALREADY_ACKNOWLEDGED') AS acknowledged_count,
        COUNTIF(hold_code = 'HOLD_EDC_SCENARIO_RELEASE_APPROVAL_REQUIRED')
          AS kbank_structurally_ready_count,
        COUNTIF(hold_code = 'HOLD_EDC_BANK_OR_METHOD_APPROVAL_REQUIRED')
          AS unapproved_bank_or_method_count,
        0 AS interface_row_count, 'HOLD_ONLY_ZERO_INTERFACE_ROWS' AS gate_status,
        CURRENT_TIMESTAMP() AS built_at
      FROM _classified
    ) AS source
    ON target.pipeline_run_id = source.pipeline_run_id
    WHEN NOT MATCHED THEN INSERT ROW;
    ASSERT @@row_count = 1 AS 'EDC run claim failed or already exists';

    INSERT INTO `pacific-plating-282708.sap_integration_v3.v3_edc_onetime_event_hold`
    SELECT * FROM _classified;
    ASSERT @@row_count = (SELECT COUNT(*) FROM _classified)
      AS 'EDC hold insert cardinality mismatch';
    ASSERT (SELECT COUNT(*)
      FROM `pacific-plating-282708.sap_integration_v3.v3_edc_onetime_event_hold`
      WHERE pipeline_run_id = p_pipeline_run_id) = (SELECT COUNT(*) FROM _classified)
      AS 'EDC published detail count differs from classified population';
    ASSERT (SELECT event_count = classified_count AND interface_row_count = 0
      FROM `pacific-plating-282708.sap_integration_v3.v3_edc_onetime_event_summary`
      WHERE pipeline_run_id = p_pipeline_run_id) AS 'EDC published conservation failed';
  COMMIT TRANSACTION;
END;

-- Class A / fail-closed. One-period compulsory RCL/CMI preparation gate.
-- This routine classifies every Unit-2 RCL_CMI payment event but emits no interface payload.
-- A structurally valid event remains held until its SAP payment mapping/business scenario is
-- approved. No GCS, SAP, or scheduler action exists in this artifact.

CREATE OR REPLACE VIEW
  `pacific-plating-282708.sap_integration_v3.vw_v3_rcl_cmi_payload_source` AS
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
FROM `pacific-plating-282708.sap_data_engineer.sap_dashboard_carepay_installment` AS src
JOIN `pacific-plating-282708.sap_integration_v3.stg_schedule` AS schedule
  ON schedule.order_item = src.OrderItem
  AND schedule.period = SAFE_CAST(src.Period AS INT64)
WHERE schedule.flow = 'RCL_CMI';

CREATE TABLE IF NOT EXISTS
  `pacific-plating-282708.sap_integration_v3.v3_rcl_cmi_event_hold` (
    pipeline_run_id STRING NOT NULL,
    order_id STRING,
    order_item STRING,
    period INT64,
    charge_id STRING NOT NULL,
    invoice_no STRING,
    unit2_outcome STRING NOT NULL,
    hold_code STRING NOT NULL,
    source_payload_rows INT64 NOT NULL,
    classified_at TIMESTAMP NOT NULL
  )
CLUSTER BY pipeline_run_id, hold_code, order_item;

CREATE TABLE IF NOT EXISTS
  `pacific-plating-282708.sap_integration_v3.v3_rcl_cmi_event_summary` (
    pipeline_run_id STRING NOT NULL,
    event_count INT64 NOT NULL,
    classified_count INT64 NOT NULL,
    acknowledged_count INT64 NOT NULL,
    structurally_ready_but_mapping_held_count INT64 NOT NULL,
    interface_row_count INT64 NOT NULL,
    gate_status STRING NOT NULL,
    built_at TIMESTAMP NOT NULL
  )
CLUSTER BY pipeline_run_id, gate_status;

CREATE OR REPLACE PROCEDURE
  `pacific-plating-282708.sap_integration_v3.sp_build_v3_rcl_cmi_holds`(
    p_pipeline_run_id STRING
  )
BEGIN
  ASSERT NULLIF(TRIM(p_pipeline_run_id), '') IS NOT NULL AS 'pipeline_run_id is required';
  ASSERT (SELECT COUNT(*)
    FROM `pacific-plating-282708.sap_integration_v3.pipeline_run_log`
    WHERE run_id = p_pipeline_run_id AND step = 'UNIT1_COMPLETE' AND status = 'SUCCESS') = 1
    AS 'RCL_CMI gate requires exactly one successful Unit 1 row';
  ASSERT NOT EXISTS (
    SELECT 1
    FROM `pacific-plating-282708.sap_integration_v3.v3_rcl_cmi_event_summary`
    WHERE pipeline_run_id = p_pipeline_run_id
  ) AS 'pipeline_run_id already published';
  ASSERT (SELECT COUNT(*)
    FROM `pacific-plating-282708.sap_integration_v3.INFORMATION_SCHEMA.COLUMNS`
    WHERE table_name = 'vw_v3_rcl_cmi_payload_source') = 56
    AS 'RCL_CMI source must have exactly 56 columns';
  ASSERT (SELECT COUNT(*) FROM (
    SELECT ordinal_position, column_name, data_type
    FROM `pacific-plating-282708.sap_integration_v3.INFORMATION_SCHEMA.COLUMNS`
    WHERE table_name = 'vw_v3_rcl_cmi_payload_source'
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
    WHERE table_name = 'vw_v3_rcl_cmi_payload_source')) = 0
    AS 'RCL_CMI source names/types/ordinals differ from the reviewed 56-column contract';

  CREATE TEMP TABLE _event AS
  SELECT
    e.*,
    COUNT(*) OVER (PARTITION BY order_item, period, charge_id, invoice_no)
      AS event_identity_rows,
    COUNT(*) OVER (PARTITION BY charge_id) AS charge_rows
  FROM `pacific-plating-282708.sap_integration_v3.v3_unit2_event_shadow` AS e
  WHERE pipeline_run_id = p_pipeline_run_id AND flow = 'RCL_CMI';

  CREATE TEMP TABLE _schedule_shape AS
  SELECT
    e.charge_id,
    COUNT(s.order_item) AS schedule_rows,
    COUNTIF(s.flow = 'RCL_CMI' AND s.period = 1 AND s.total_periods = 1
      AND s.payment_option = 'RABBIT_CARE_INSTALLMENT'
      AND s.motor_item_type = 'MOTOR_TYPE_COMPULSORY') AS exact_schedule_rows
  FROM _event AS e
  LEFT JOIN `pacific-plating-282708.sap_integration_v3.stg_schedule` AS s
    ON s.order_item = e.order_item AND s.order_id = e.order_id AND s.period = e.period
  GROUP BY e.charge_id;

  CREATE TEMP TABLE _raw_shape AS
  SELECT
    e.charge_id,
    COUNT(c.id) AS raw_charge_rows,
    ANY_VALUE(c.service_provider HAVING MIN c.service_provider) AS service_provider
  FROM _event AS e
  LEFT JOIN `pacific-plating-282708.careos.carepay_charges` AS c ON c.id = e.charge_id
  GROUP BY e.charge_id;

  CREATE TEMP TABLE _source_shape AS
  SELECT
    e.charge_id,
    COUNT(o.OrderItem) AS source_payload_rows,
    COUNTIF(o.InvoiceNo IS NOT DISTINCT FROM e.invoice_no
      AND SAFE_CAST(o.Period AS INT64) = 1
      AND SAFE_CAST(o.TotalPeriods AS INT64) = 1) AS exact_source_payload_rows
  FROM _event AS e
  LEFT JOIN `pacific-plating-282708.sap_integration_v3.vw_v3_rcl_cmi_payload_source` AS o
    ON o.OrderItem = e.order_item AND SAFE_CAST(o.Period AS INT64) = e.period
  GROUP BY e.charge_id;

  CREATE TEMP TABLE _shape AS
  SELECT
    e.*,
    s.schedule_rows,
    s.exact_schedule_rows,
    r.raw_charge_rows,
    r.service_provider,
    o.source_payload_rows,
    o.exact_source_payload_rows
  FROM _event AS e
  JOIN _schedule_shape AS s USING (charge_id)
  JOIN _raw_shape AS r USING (charge_id)
  JOIN _source_shape AS o USING (charge_id);

  CREATE TEMP TABLE _classified AS
  SELECT
    pipeline_run_id,
    order_id,
    order_item,
    period,
    charge_id,
    invoice_no,
    COALESCE(outcome, '<NULL>') AS unit2_outcome,
    CASE
      WHEN outcome IS NULL THEN 'HOLD_CMI_UNIT2_OUTCOME_NULL'
      WHEN event_identity_rows != 1 OR charge_rows != 1
        THEN 'HOLD_CMI_DUPLICATE_OR_CONFLICTING_EVENT'
      WHEN outcome = 'ACKNOWLEDGED' THEN 'NOT_ACTIONABLE_ALREADY_ACKNOWLEDGED'
      WHEN outcome != 'READY_CREATE_OR_PAYMENT' THEN CONCAT('HOLD_UNIT2_', outcome)
      WHEN NULLIF(TRIM(order_id), '') IS NULL OR NULLIF(TRIM(order_item), '') IS NULL
        OR period IS NULL OR NULLIF(TRIM(charge_id), '') IS NULL
        OR NULLIF(TRIM(invoice_no), '') IS NULL THEN 'HOLD_CMI_EVENT_IDENTITY_INVALID'
      WHEN schedule_rows != 1 OR exact_schedule_rows != 1 THEN 'HOLD_CMI_ONE_PERIOD_ROUTE_INVALID'
      WHEN raw_charge_rows != 1 THEN 'HOLD_CMI_RAW_CHARGE_CARDINALITY'
      WHEN service_provider IS DISTINCT FROM 'RABBIT_LENDING'
        THEN 'HOLD_CMI_SERVICE_PROVIDER_INVALID'
      WHEN exact_source_payload_rows = 0
        THEN 'HOLD_CMI_56_SOURCE_MISSING'
      WHEN exact_source_payload_rows != 1
        THEN 'HOLD_CMI_56_SOURCE_AMBIGUOUS'
      ELSE 'HOLD_CMI_PAYMENT_MAPPING_APPROVAL_REQUIRED'
    END AS hold_code,
    exact_source_payload_rows AS source_payload_rows,
    CURRENT_TIMESTAMP() AS classified_at
  FROM _shape;

  ASSERT (SELECT COUNT(*) FROM _classified) = (SELECT COUNT(*) FROM _event)
    AS 'RCL_CMI event population was not conserved';
  ASSERT NOT EXISTS (SELECT 1 FROM _classified WHERE hold_code IS NULL)
    AS 'RCL_CMI classifier produced a NULL outcome';

  BEGIN TRANSACTION;
    MERGE `pacific-plating-282708.sap_integration_v3.v3_rcl_cmi_event_summary` AS target
    USING (
      SELECT
        p_pipeline_run_id AS pipeline_run_id,
        COUNT(*) AS event_count,
        COUNT(*) AS classified_count,
        COUNTIF(hold_code = 'NOT_ACTIONABLE_ALREADY_ACKNOWLEDGED') AS acknowledged_count,
        COUNTIF(hold_code = 'HOLD_CMI_PAYMENT_MAPPING_APPROVAL_REQUIRED')
          AS structurally_ready_but_mapping_held_count,
        0 AS interface_row_count,
        'HOLD_ONLY_ZERO_INTERFACE_ROWS' AS gate_status,
        CURRENT_TIMESTAMP() AS built_at
      FROM _classified
    ) AS source
    ON target.pipeline_run_id = source.pipeline_run_id
    WHEN NOT MATCHED THEN INSERT ROW;
    ASSERT @@row_count = 1 AS 'RCL_CMI run claim failed or already exists';

    INSERT INTO `pacific-plating-282708.sap_integration_v3.v3_rcl_cmi_event_hold`
    SELECT * FROM _classified;
    ASSERT @@row_count = (SELECT COUNT(*) FROM _classified)
      AS 'RCL_CMI hold insert cardinality mismatch';

    ASSERT (
      SELECT event_count = classified_count AND interface_row_count = 0
      FROM `pacific-plating-282708.sap_integration_v3.v3_rcl_cmi_event_summary`
      WHERE pipeline_run_id = p_pipeline_run_id
    ) AS 'RCL_CMI published conservation failed';
  COMMIT TRANSACTION;
END;

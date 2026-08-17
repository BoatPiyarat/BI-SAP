-- Source only / Class A. Mo 1-15 Aug RCL recovery adapter.
-- Builds a 56-column shadow-ready table only; no GCS or SAP write.

CREATE TABLE IF NOT EXISTS `pacific-plating-282708.sap_integration_v3.mo_rcl_recovery_scope` (
  request_id STRING NOT NULL,
  order_id STRING NOT NULL,
  reported_period INT64 NOT NULL,
  requested_by STRING NOT NULL,
  source_note STRING NOT NULL,
  captured_at TIMESTAMP NOT NULL
)
CLUSTER BY request_id, order_id;

CREATE TABLE IF NOT EXISTS `pacific-plating-282708.sap_integration_v3.mo_rcl_recovery_hold` (
  request_id STRING NOT NULL,
  order_id STRING,
  reported_period INT64,
  order_item STRING,
  hold_reason STRING NOT NULL,
  detail STRING NOT NULL,
  detected_at TIMESTAMP NOT NULL
)
CLUSTER BY request_id, hold_reason, order_id;

CREATE OR REPLACE PROCEDURE `pacific-plating-282708.sap_integration_v3.sp_seed_mo_rcl_recovery_scope`(
  p_request_id STRING,
  p_pairs ARRAY<STRUCT<order_id STRING, period INT64>>,
  p_requested_by STRING,
  p_source_note STRING
)
BEGIN
  ASSERT NULLIF(TRIM(p_request_id), '') IS NOT NULL AS 'request_id is required';
  ASSERT ARRAY_LENGTH(IFNULL(p_pairs, [])) > 0 AS 'at least one OrderID/Period pair is required';
  ASSERT NULLIF(TRIM(p_requested_by), '') IS NOT NULL AS 'requested_by is required';
  ASSERT NULLIF(TRIM(p_source_note), '') IS NOT NULL AS 'source_note is required';
  ASSERT (SELECT COUNT(*) FROM UNNEST(p_pairs)
    WHERE NULLIF(TRIM(order_id), '') IS NULL OR period IS NULL OR period < 1) = 0
    AS 'scope contains blank OrderID or invalid Period';
  ASSERT (SELECT COUNT(*) FROM (
    SELECT order_id, period, COUNT(*) n FROM UNNEST(p_pairs)
    GROUP BY order_id, period HAVING n != 1)) = 0 AS 'scope contains duplicate pairs';

  DELETE FROM `pacific-plating-282708.sap_integration_v3.mo_rcl_recovery_scope`
  WHERE request_id = p_request_id;
  INSERT INTO `pacific-plating-282708.sap_integration_v3.mo_rcl_recovery_scope`
  SELECT p_request_id, TRIM(order_id), period, TRIM(p_requested_by), TRIM(p_source_note),
    CURRENT_TIMESTAMP()
  FROM UNNEST(p_pairs);
END;

CREATE OR REPLACE PROCEDURE `pacific-plating-282708.sap_integration_v3.sp_build_mo_rcl_recovery_shadow`(
  p_request_id STRING
)
BEGIN
  ASSERT NULLIF(TRIM(p_request_id), '') IS NOT NULL AS 'request_id is required';
  ASSERT (SELECT COUNT(*)
    FROM `pacific-plating-282708.sap_integration_v3.mo_rcl_recovery_scope`
    WHERE request_id = p_request_id) > 0 AS 'request has no seeded scope';

  CREATE TEMP TABLE _mapped AS
  SELECT sc.order_id, sc.reported_period, pe.order_item,
    COUNT(DISTINCT pe.charge_id) AS charge_count,
    COUNT(DISTINCT pe.order_item) OVER (PARTITION BY sc.order_id, sc.reported_period) AS item_count,
    STRING_AGG(DISTINCT sch.flow, ',' ORDER BY sch.flow) AS flows
  FROM `pacific-plating-282708.sap_integration_v3.mo_rcl_recovery_scope` sc
  LEFT JOIN `pacific-plating-282708.sap_integration_v3.stg_payment_events` pe
    ON pe.order_id = sc.order_id AND pe.period = sc.reported_period
  LEFT JOIN `pacific-plating-282708.sap_integration_v3.stg_schedule` sch
    ON sch.order_item = pe.order_item AND sch.period = pe.period
  WHERE sc.request_id = p_request_id
  GROUP BY sc.order_id, sc.reported_period, pe.order_item;

  DELETE FROM `pacific-plating-282708.sap_integration_v3.mo_rcl_recovery_hold`
  WHERE request_id = p_request_id;
  INSERT INTO `pacific-plating-282708.sap_integration_v3.mo_rcl_recovery_hold`
  SELECT p_request_id, order_id, reported_period, order_item,
    CASE
      WHEN order_item IS NULL THEN 'NO_EVENT_ITEM_MAPPING'
      WHEN item_count != 1 THEN 'AMBIGUOUS_EVENT_ITEM_MAPPING'
      WHEN flows IS NULL THEN 'UNKNOWN_FLOW'
      WHEN flows != 'RCL' THEN 'NON_RCL_FLOW'
      ELSE 'UNEXPECTED_MAPPING_HOLD'
    END,
    FORMAT('item_count=%d; flows=%s; charge_count=%d', item_count, IFNULL(flows, 'NULL'), charge_count),
    CURRENT_TIMESTAMP()
  FROM _mapped
  WHERE order_item IS NULL OR item_count != 1 OR flows IS NULL OR flows != 'RCL';

  CREATE TEMP TABLE _accepted_items AS
  SELECT DISTINCT order_item
  FROM _mapped
  WHERE order_item IS NOT NULL AND item_count = 1 AND flows = 'RCL';

  CREATE TEMP TABLE _candidate AS
  SELECT
    CAST(CompanyDB AS STRING) CompanyDB, CAST(OrderID AS STRING) OrderID,
    CAST(OrderItem AS STRING) OrderItem, CAST(IFNULL(InvoiceNo, '') AS STRING) InvoiceNo,
    CAST(OrderDate AS STRING) OrderDate, CAST(InsuredID AS STRING) InsuredID,
    CAST(Title AS STRING) Title, CAST(FirstName AS STRING) FirstName,
    CAST(LastName AS STRING) LastName, CAST(InsurerCode AS STRING) InsurerCode,
    CAST(InsuranceGroup AS STRING) InsuranceGroup, CAST(InsuranceType AS STRING) InsuranceType,
    CAST(InsuranceProduct AS STRING) InsuranceProduct, CAST(ProductType AS STRING) ProductType,
    CAST(PolicyType AS STRING) PolicyType, CAST(Endorse AS STRING) Endorse,
    CAST(PolicyDate AS STRING) PolicyDate, CAST(PolicyNo AS STRING) PolicyNo,
    CAST(EndorsementNo AS STRING) EndorsementNo, CAST(ChassisNo AS STRING) ChassisNo,
    CAST(LicensePlate AS STRING) LicensePlate, SAFE_CAST(GrossPremium AS FLOAT64) GrossPremium,
    SAFE_CAST(StampDuty AS FLOAT64) StampDuty, SAFE_CAST(VAT AS FLOAT64) VAT,
    SAFE_CAST(TotalPremium AS FLOAT64) TotalPremium, SAFE_CAST(WHT AS FLOAT64) WHT,
    SAFE_CAST(TotalEIR AS FLOAT64) TotalEIR, SAFE_CAST(TotalSBT AS FLOAT64) TotalSBT,
    SAFE_CAST(ProcessingFee AS FLOAT64) ProcessingFee,
    SAFE_CAST(ProcessingFeeVat AS FLOAT64) ProcessingFeeVat,
    SAFE_CAST(ShippingFee AS FLOAT64) ShippingFee,
    SAFE_CAST(ShippingFeeVat AS FLOAT64) ShippingFeeVat,
    SAFE_CAST(TotalAmount AS FLOAT64) TotalAmount, SAFE_CAST(Discount AS FLOAT64) Discount,
    CASE
      WHEN TransactionStatus IN ('Paid', 'paid', 'FOLLOWUP_STATUS_PAID', 'SUCCESSFUL') THEN 'Paid'
      WHEN TransactionStatus IN ('Pending', 'pending', 'FOLLOWUP_STATUS_PENDING', 'PENDING') THEN 'Pending'
      ELSE CAST(TransactionStatus AS STRING)
    END TransactionStatus,
    CAST(SubmissionStatus AS STRING) SubmissionStatus,
    CAST(ApprovalStatus AS STRING) ApprovalStatus, CAST(PaymentStatus AS STRING) PaymentStatus,
    SAFE_CAST(ExpectedReceived AS FLOAT64) ExpectedReceived,
    SAFE_CAST(ActualReceived AS FLOAT64) ActualReceived,
    SAFE_CAST(InterestThisPeriod AS FLOAT64) InterestThisPeriod,
    SAFE_CAST(PrincipleThisPeriod AS FLOAT64) PrincipleThisPeriod,
    SAFE_CAST(InterestEIRThisPeriod AS FLOAT64) InterestEIRThisPeriod,
    SAFE_CAST(PrincipleEIRThisPeriod AS FLOAT64) PrincipleEIRThisPeriod,
    CAST(IFNULL(PaymentDate, '') AS STRING) PaymentDate,
    SAFE_CAST(Period AS INT64) Period, SAFE_CAST(TotalPeriods AS INT64) TotalPeriods,
    SAFE_CAST(PendingPayment AS FLOAT64) PendingPayment,
    CAST(PaymentMethod AS STRING) PaymentMethod, CAST(PaymentChannel AS STRING) PaymentChannel,
    CAST(ExpectedDate AS STRING) ExpectedDate, CAST(RefOrder AS STRING) RefOrder,
    SAFE_CAST(RefundAmountBeforeFee AS FLOAT64) RefundAmountBeforeFee,
    SAFE_CAST(RefundAmountAfterFee AS FLOAT64) RefundAmountAfterFee,
    CAST(BillingAddress AS STRING) BillingAddress,
    FORMAT_DATE('%d%m%Y', CURRENT_DATE('Asia/Bangkok')) BatchRunDate
  FROM `pacific-plating-282708.sap_data_engineer.sap_dashboard_carepay_installment` src
  JOIN _accepted_items accepted ON accepted.order_item = src.OrderItem;

  CREATE TEMP TABLE _item_gate AS
  SELECT OrderItem,
    COUNT(*) AS row_count, COUNT(DISTINCT Period) AS period_count,
    MIN(Period) AS first_period, MAX(Period) AS last_period,
    COUNT(DISTINCT TotalPeriods) AS total_versions, MAX(TotalPeriods) AS total_periods,
    COUNTIF(TransactionStatus NOT IN ('Paid', 'Pending')) AS bad_status_rows,
    COUNTIF(PaymentChannel LIKE '%RCB%') AS rcb_rows,
    COUNTIF(REGEXP_CONTAINS(TO_JSON_STRING(c), r':null(?:,|})')) AS sql_null_rows,
    COUNTIF(REGEXP_CONTAINS(UPPER(TO_JSON_STRING(c)), r'"NULL"')) AS literal_null_rows,
    COUNTIF(LENGTH(IFNULL(PolicyNo, '')) > 50) AS long_policy_rows,
    COUNTIF(TransactionStatus = 'Paid' AND (
      NULLIF(TRIM(InvoiceNo), '') IS NULL OR NULLIF(PaymentDate, '') IS NULL
      OR NULLIF(TRIM(PaymentMethod), '') IS NULL OR NULLIF(TRIM(PaymentChannel), '') IS NULL))
      AS paid_incomplete_rows,
    COUNTIF(TransactionStatus = 'Pending' AND PaymentDate != '') AS pending_payment_date_rows
  FROM _candidate c
  GROUP BY OrderItem;

  INSERT INTO `pacific-plating-282708.sap_integration_v3.mo_rcl_recovery_hold`
  SELECT p_request_id, d.order_id, CAST(NULL AS INT64), g.OrderItem,
    CASE
      WHEN g.total_versions != 1 OR g.total_periods IS NULL OR g.total_periods < 1
        OR g.first_period != 1 OR g.last_period != g.total_periods
        OR g.row_count != g.total_periods OR g.period_count != g.total_periods
        THEN 'INCOMPLETE_PERIOD_SPINE'
      WHEN g.bad_status_rows > 0 THEN 'INVALID_STATUS'
      WHEN g.rcb_rows > 0 THEN 'RCL_RCB_MIX'
      WHEN g.sql_null_rows > 0 THEN 'SQL_NULL_VALUE'
      WHEN g.literal_null_rows > 0 THEN 'LITERAL_NULL_VALUE'
      WHEN g.long_policy_rows > 0 THEN 'POLICYNO_TOO_LONG'
      WHEN g.paid_incomplete_rows > 0 THEN 'PAID_REQUIRED_VALUE_MISSING'
      WHEN g.pending_payment_date_rows > 0 THEN 'PENDING_HAS_PAYMENT_DATE'
      ELSE 'UNEXPECTED_ITEM_GATE_HOLD'
    END,
    FORMAT('rows=%d; periods=%d; first=%d; last=%d; total=%d; statuses=%d; rcb=%d; sql_null=%d; literal_null=%d; policy=%d; paid_missing=%d; pending_date=%d',
      g.row_count, g.period_count, IFNULL(g.first_period, -1), IFNULL(g.last_period, -1),
      IFNULL(g.total_periods, -1), g.bad_status_rows, g.rcb_rows, g.sql_null_rows,
      g.literal_null_rows, g.long_policy_rows, g.paid_incomplete_rows, g.pending_payment_date_rows),
    CURRENT_TIMESTAMP()
  FROM _item_gate g
  LEFT JOIN `pacific-plating-282708.sap_integration_v3.stg_order_dim` d
    ON d.order_item = g.OrderItem
  WHERE g.total_versions != 1 OR g.total_periods IS NULL OR g.total_periods < 1
    OR g.first_period != 1 OR g.last_period != g.total_periods
    OR g.row_count != g.total_periods OR g.period_count != g.total_periods
    OR g.bad_status_rows > 0 OR g.rcb_rows > 0 OR g.sql_null_rows > 0
    OR g.literal_null_rows > 0 OR g.long_policy_rows > 0 OR g.paid_incomplete_rows > 0
    OR g.pending_payment_date_rows > 0;

  CREATE OR REPLACE TABLE `pacific-plating-282708.sap_integration_v3.mo_rcl_recovery_ready` AS
  SELECT c.*
  FROM _candidate c
  WHERE NOT EXISTS (
    SELECT 1 FROM `pacific-plating-282708.sap_integration_v3.mo_rcl_recovery_hold` h
    WHERE h.request_id = p_request_id AND h.order_item = c.OrderItem);

  ASSERT (SELECT COUNT(*)
    FROM `pacific-plating-282708.sap_integration_v3.INFORMATION_SCHEMA.COLUMNS`
    WHERE table_name = 'mo_rcl_recovery_ready') = 56 AS 'ready payload must have 56 columns';
  ASSERT (SELECT COUNT(*) FROM `pacific-plating-282708.sap_integration_v3.mo_rcl_recovery_ready`
    WHERE TransactionStatus NOT IN ('Paid', 'Pending') OR PaymentChannel LIKE '%RCB%'
      OR REGEXP_CONTAINS(TO_JSON_STRING(
        `pacific-plating-282708.sap_integration_v3.mo_rcl_recovery_ready`), r':null(?:,|})')
      OR REGEXP_CONTAINS(UPPER(TO_JSON_STRING(
        `pacific-plating-282708.sap_integration_v3.mo_rcl_recovery_ready`)), r'"NULL"')) = 0
    AS 'ready payload violates status, RCL/RCB, or NULL gate';
  ASSERT (SELECT COUNT(*) FROM (
    SELECT OrderItem, COUNT(*) rows_n, COUNT(DISTINCT Period) periods_n,
      MIN(Period) first_period, MAX(Period) last_period, MAX(TotalPeriods) total_n,
      COUNT(DISTINCT TotalPeriods) total_versions
    FROM `pacific-plating-282708.sap_integration_v3.mo_rcl_recovery_ready`
    GROUP BY OrderItem
    HAVING total_versions != 1 OR first_period != 1 OR last_period != total_n
      OR rows_n != total_n OR periods_n != total_n)) = 0
    AS 'ready payload contains an incomplete period spine';
END;

-- Class A / fail-closed. Additional-payment versus correction intent dependency gate.
-- The two intents can share the same ExpectedReceived=0 adjustment shape. No row is releasable
-- without one exact human-approved durable marker. This routine emits zero interface rows.

CREATE OR REPLACE VIEW
  `pacific-plating-282708.sap_integration_v3.vw_v3_payment_adjustment_payload_source` AS
SELECT * EXCEPT (pipeline_run_id, snapshotted_at)
FROM `pacific-plating-282708.sap_integration_v3.v3_unit5_newpayment_run_snapshot`
WHERE SAFE_CAST(ExpectedReceived AS NUMERIC) = 0
  AND SAFE_CAST(ActualReceived AS NUMERIC) != 0;

CREATE TABLE IF NOT EXISTS
  `pacific-plating-282708.sap_integration_v3.v3_payment_adjustment_intent_registry` (
    pipeline_run_id STRING NOT NULL,
    order_item STRING NOT NULL,
    period INT64 NOT NULL,
    charge_id STRING NOT NULL,
    intent STRING NOT NULL,
    decision_status STRING NOT NULL,
    approved_by STRING,
    approved_at TIMESTAMP,
    evidence_reference STRING NOT NULL,
    recorded_at TIMESTAMP NOT NULL
  )
CLUSTER BY pipeline_run_id, order_item, period, charge_id;

CREATE TABLE IF NOT EXISTS
  `pacific-plating-282708.sap_integration_v3.v3_payment_adjustment_intent_hold` (
    pipeline_run_id STRING NOT NULL,
    order_item STRING,
    period INT64,
    candidate_ordinal INT64 NOT NULL,
    charge_id STRING,
    invoice_no STRING,
    hold_code STRING NOT NULL,
    approved_marker_count INT64 NOT NULL,
    approved_intent STRING,
    payload_hash STRING NOT NULL,
    classified_at TIMESTAMP NOT NULL
  )
CLUSTER BY pipeline_run_id, hold_code, order_item;

CREATE TABLE IF NOT EXISTS
  `pacific-plating-282708.sap_integration_v3.v3_payment_adjustment_intent_summary` (
    pipeline_run_id STRING NOT NULL,
    candidate_payload_count INT64 NOT NULL,
    classified_payload_count INT64 NOT NULL,
    additional_payment_marker_count INT64 NOT NULL,
    correction_marker_count INT64 NOT NULL,
    interface_row_count INT64 NOT NULL,
    gate_status STRING NOT NULL,
    built_at TIMESTAMP NOT NULL
  )
CLUSTER BY pipeline_run_id, gate_status;

CREATE OR REPLACE PROCEDURE
  `pacific-plating-282708.sap_integration_v3.sp_build_v3_payment_adjustment_intent_holds`(
    p_pipeline_run_id STRING
  )
BEGIN
  ASSERT NULLIF(TRIM(p_pipeline_run_id), '') IS NOT NULL AS 'pipeline_run_id is required';
  ASSERT (SELECT COUNT(*)
    FROM `pacific-plating-282708.sap_integration_v3.pipeline_run_log`
    WHERE run_id = p_pipeline_run_id AND step = 'UNIT1_COMPLETE' AND status = 'SUCCESS') = 1
    AS 'adjustment intent gate requires exactly one successful Unit 1 row';
  ASSERT (SELECT COUNT(*)
    FROM `pacific-plating-282708.sap_integration_v3.v3_unit5_newpayment_snapshot_manifest`
    WHERE pipeline_run_id = p_pipeline_run_id) = 1
    AS 'adjustment intent gate requires one immutable Unit 5 manifest';
  ASSERT NOT EXISTS (SELECT 1
    FROM `pacific-plating-282708.sap_integration_v3.v3_payment_adjustment_intent_summary`
    WHERE pipeline_run_id = p_pipeline_run_id) AS 'pipeline_run_id already published';
  ASSERT (SELECT COUNT(*)
    FROM `pacific-plating-282708.sap_integration_v3.INFORMATION_SCHEMA.COLUMNS`
    WHERE table_name = 'vw_v3_payment_adjustment_payload_source') = 56
    AS 'adjustment source must have exactly 56 columns';
  ASSERT (SELECT COUNT(*) FROM (
    SELECT ordinal_position, column_name, data_type
    FROM `pacific-plating-282708.sap_integration_v3.INFORMATION_SCHEMA.COLUMNS`
    WHERE table_name = 'vw_v3_payment_adjustment_payload_source'
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
    WHERE table_name = 'vw_v3_payment_adjustment_payload_source')) = 0
    AS 'adjustment source differs from reviewed 56-column contract';

  CREATE TEMP TABLE _snapshot AS
  SELECT * EXCEPT (pipeline_run_id, snapshotted_at)
  FROM `pacific-plating-282708.sap_integration_v3.v3_unit5_newpayment_run_snapshot`
  WHERE pipeline_run_id = p_pipeline_run_id;

  ASSERT (SELECT COUNT(*) FROM _snapshot) = (SELECT row_count
    FROM `pacific-plating-282708.sap_integration_v3.v3_unit5_newpayment_snapshot_manifest`
    WHERE pipeline_run_id = p_pipeline_run_id)
    AS 'adjustment source rows differ from immutable manifest';
  ASSERT TO_HEX(SHA256(COALESCE((SELECT STRING_AGG(
    TO_HEX(SHA256(TO_JSON_STRING(payload))), ''
    ORDER BY payload.OrderItem, SAFE_CAST(payload.Period AS INT64), payload.InvoiceNo,
      TO_JSON_STRING(payload)) FROM _snapshot AS payload), '<EMPTY>'))) = (SELECT payload_set_hash
    FROM `pacific-plating-282708.sap_integration_v3.v3_unit5_newpayment_snapshot_manifest`
    WHERE pipeline_run_id = p_pipeline_run_id)
    AS 'adjustment source hash differs from immutable manifest';

  CREATE TEMP TABLE _candidate AS
  SELECT payload.*,
    TO_HEX(SHA256(TO_JSON_STRING(payload))) AS candidate_payload_hash,
    ROW_NUMBER() OVER (ORDER BY payload.OrderItem, SAFE_CAST(payload.Period AS INT64),
      payload.InvoiceNo, TO_JSON_STRING(payload)) AS candidate_ordinal,
    COUNT(*) OVER (PARTITION BY payload.OrderItem, SAFE_CAST(payload.Period AS INT64),
      payload.InvoiceNo, TO_HEX(SHA256(TO_JSON_STRING(payload)))) AS candidate_identity_rows
  FROM _snapshot AS payload
  WHERE SAFE_CAST(payload.ExpectedReceived AS NUMERIC) = 0
    AND SAFE_CAST(payload.ActualReceived AS NUMERIC) != 0;

  CREATE TEMP TABLE _mirror_shape AS
  SELECT
    candidate.order_item, candidate.period,
    COUNT(mirror.U_OrderItem) AS mirror_rows
  FROM (SELECT DISTINCT OrderItem AS order_item, SAFE_CAST(Period AS INT64) AS period
    FROM _candidate) AS candidate
  LEFT JOIN `pacific-plating-282708.sap_integration_v3.sap_mirror_state` AS mirror
    ON mirror.U_OrderItem = candidate.order_item AND mirror.U_Period = candidate.period
  GROUP BY order_item, period;

  CREATE TEMP TABLE _identity_shape AS
  SELECT pipeline_run_id, order_item, period, invoice_no, payload_hash,
    COUNT(identity.charge_id) AS identity_rows,
    COUNT(DISTINCT identity.charge_id) AS charge_id_count,
    ANY_VALUE(identity.charge_id HAVING MIN identity.charge_id) AS charge_id
  FROM `pacific-plating-282708.sap_integration_v3.v3_unit5_payload_identity` AS identity
  WHERE pipeline_run_id = p_pipeline_run_id AND file_role = 'NEWPAYMENT'
  GROUP BY pipeline_run_id, order_item, period, invoice_no, payload_hash;

  CREATE TEMP TABLE _marker AS
  SELECT
    pipeline_run_id, order_item, period, charge_id,
    COUNT(*) AS approved_marker_count,
    COUNT(DISTINCT intent) AS approved_intent_count,
    ANY_VALUE(intent HAVING MAX recorded_at) AS approved_intent
  FROM `pacific-plating-282708.sap_integration_v3.v3_payment_adjustment_intent_registry`
  WHERE pipeline_run_id = p_pipeline_run_id
    AND decision_status = 'APPROVED'
    AND intent IN ('ADDITIONAL_PAYMENT', 'CORRECTION')
    AND NULLIF(TRIM(approved_by), '') IS NOT NULL
    AND approved_at IS NOT NULL
    AND NULLIF(TRIM(evidence_reference), '') IS NOT NULL
  GROUP BY pipeline_run_id, order_item, period, charge_id;

  CREATE TEMP TABLE _classified AS
  SELECT
    p_pipeline_run_id AS pipeline_run_id,
    candidate.OrderItem AS order_item,
    SAFE_CAST(candidate.Period AS INT64) AS period,
    candidate.candidate_ordinal,
    identity.charge_id,
    candidate.InvoiceNo AS invoice_no,
    CASE
      WHEN SAFE_CAST(candidate.Period AS INT64) IS NULL
        OR NULLIF(TRIM(candidate.OrderItem), '') IS NULL
        OR NULLIF(TRIM(candidate.InvoiceNo), '') IS NULL
        OR UPPER(TRIM(candidate.InvoiceNo)) = 'NULL'
        THEN 'HOLD_ADJUSTMENT_PAYLOAD_IDENTITY_INVALID'
      WHEN candidate.candidate_identity_rows != 1
        THEN 'HOLD_ADJUSTMENT_DUPLICATE_PHYSICAL_PAYLOAD'
      WHEN mirror.mirror_rows = 0 THEN 'HOLD_ADJUSTMENT_SAP_PERIOD_MISSING'
      WHEN mirror.mirror_rows != 1 THEN 'HOLD_ADJUSTMENT_SAP_PERIOD_AMBIGUOUS'
      WHEN IFNULL(identity.identity_rows, 0) = 0 THEN 'HOLD_ADJUSTMENT_EVENT_IDENTITY_MISSING'
      WHEN identity.identity_rows != 1 OR identity.charge_id_count != 1
        THEN 'HOLD_ADJUSTMENT_EVENT_IDENTITY_AMBIGUOUS'
      WHEN IFNULL(marker.approved_marker_count, 0) = 0
        THEN 'HOLD_ADJUSTMENT_INTENT_MARKER_REQUIRED'
      WHEN marker.approved_marker_count != 1 OR marker.approved_intent_count != 1
        THEN 'HOLD_ADJUSTMENT_INTENT_MARKER_AMBIGUOUS'
      ELSE 'HOLD_ADJUSTMENT_RELEASE_APPROVAL_REQUIRED'
    END AS hold_code,
    IFNULL(marker.approved_marker_count, 0) AS approved_marker_count,
    marker.approved_intent,
    candidate.candidate_payload_hash AS payload_hash,
    CURRENT_TIMESTAMP() AS classified_at
  FROM _candidate AS candidate
  JOIN _mirror_shape AS mirror
    ON mirror.order_item = candidate.OrderItem
    AND mirror.period = SAFE_CAST(candidate.Period AS INT64)
  LEFT JOIN _identity_shape AS identity
    ON identity.pipeline_run_id = p_pipeline_run_id
    AND identity.order_item = candidate.OrderItem
    AND identity.period = SAFE_CAST(candidate.Period AS INT64)
    AND identity.invoice_no IS NOT DISTINCT FROM candidate.InvoiceNo
    AND identity.payload_hash = candidate.candidate_payload_hash
  LEFT JOIN _marker AS marker
    ON marker.pipeline_run_id = p_pipeline_run_id
    AND marker.order_item = candidate.OrderItem
    AND marker.period = SAFE_CAST(candidate.Period AS INT64)
    AND marker.charge_id = identity.charge_id;

  ASSERT (SELECT COUNT(*) FROM _classified) = (SELECT COUNT(*) FROM _candidate)
    AS 'adjustment payload population was not conserved';
  ASSERT NOT EXISTS (SELECT 1 FROM _classified WHERE hold_code IS NULL)
    AS 'adjustment classifier produced a NULL hold';

  BEGIN TRANSACTION;
    MERGE `pacific-plating-282708.sap_integration_v3.v3_payment_adjustment_intent_summary`
      AS target
    USING (
      SELECT p_pipeline_run_id AS pipeline_run_id,
        COUNT(*) AS candidate_payload_count, COUNT(*) AS classified_payload_count,
        COUNTIF(approved_intent = 'ADDITIONAL_PAYMENT') AS additional_payment_marker_count,
        COUNTIF(approved_intent = 'CORRECTION') AS correction_marker_count,
        0 AS interface_row_count, 'HOLD_ONLY_ZERO_INTERFACE_ROWS' AS gate_status,
        CURRENT_TIMESTAMP() AS built_at
      FROM _classified
    ) AS source
    ON target.pipeline_run_id = source.pipeline_run_id
    WHEN NOT MATCHED THEN INSERT ROW;
    ASSERT @@row_count = 1 AS 'adjustment summary claim failed';

    INSERT INTO `pacific-plating-282708.sap_integration_v3.v3_payment_adjustment_intent_hold`
    SELECT * FROM _classified;
    ASSERT @@row_count = (SELECT COUNT(*) FROM _classified)
      AS 'adjustment hold insertion was not conserved';
    ASSERT (SELECT candidate_payload_count = classified_payload_count AND interface_row_count = 0
      FROM `pacific-plating-282708.sap_integration_v3.v3_payment_adjustment_intent_summary`
      WHERE pipeline_run_id = p_pipeline_run_id)
      AS 'adjustment published summary conservation failed';
  COMMIT TRANSACTION;
END;

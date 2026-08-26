-- Class A. Unit 5 balance quarantine and immutable post-balance per-run snapshot.
-- All run evidence is staged, atomically claimed, and published in one transaction.

CREATE TABLE IF NOT EXISTS `pacific-plating-282708.sap_integration_v3.v3_unit5_balance_hold` (
  pipeline_run_id STRING NOT NULL,order_item STRING NOT NULL,period INT64 NOT NULL,
  charge_id STRING NOT NULL,invoice_no STRING NOT NULL,expected_received NUMERIC NOT NULL,
  actual_received NUMERIC NOT NULL,difference NUMERIC NOT NULL,hold_code STRING NOT NULL,
  hold_reason STRING NOT NULL,detected_at TIMESTAMP NOT NULL)
PARTITION BY DATE(detected_at) CLUSTER BY pipeline_run_id,order_item,period;

CREATE OR REPLACE PROCEDURE
  `pacific-plating-282708.sap_integration_v3.sp_build_v3_newpayment_delivery_ready`(
    p_pipeline_run_id STRING)
BEGIN
  ASSERT NULLIF(TRIM(p_pipeline_run_id),'') IS NOT NULL
    AS 'Unit 5 balance quarantine requires pipeline_run_id';
  CREATE TABLE IF NOT EXISTS
    `pacific-plating-282708.sap_integration_v3.v3_unit5_newpayment_delivery_ready` AS
  SELECT * FROM `pacific-plating-282708.sap_integration_v3.v3_unit5_newpayment_ready` WHERE FALSE;
  CREATE TABLE IF NOT EXISTS
    `pacific-plating-282708.sap_integration_v3.v3_unit5_newpayment_run_snapshot` AS
  SELECT CAST(NULL AS STRING) pipeline_run_id,p.*,CAST(NULL AS TIMESTAMP) snapshotted_at
  FROM `pacific-plating-282708.sap_integration_v3.v3_unit5_newpayment_ready` p WHERE FALSE;
  CREATE TABLE IF NOT EXISTS
    `pacific-plating-282708.sap_integration_v3.v3_unit5_newpayment_snapshot_manifest` (
      pipeline_run_id STRING NOT NULL,row_count INT64 NOT NULL,payload_set_hash STRING NOT NULL,
      completed_at TIMESTAMP NOT NULL)
  PARTITION BY DATE(completed_at) CLUSTER BY pipeline_run_id;
  ASSERT (SELECT COUNT(*)
    FROM `pacific-plating-282708.sap_integration_v3.v3_unit5_newpayment_snapshot_manifest`
    WHERE pipeline_run_id=p_pipeline_run_id)=0
    AS 'Immutable post-balance Unit 5 snapshot manifest already exists; refusing replay';
  ASSERT (SELECT COUNT(*)
    FROM `pacific-plating-282708.sap_integration_v3.v3_unit5_newpayment_run_snapshot`
    WHERE pipeline_run_id=p_pipeline_run_id)=0
    AS 'Orphan Unit 5 snapshot rows exist without manifest; refusing overwrite';
  ASSERT (SELECT COUNT(*)
    FROM `pacific-plating-282708.sap_integration_v3.v3_unit5_newpayment_run_state`
    WHERE pipeline_run_id=p_pipeline_run_id AND state='BUILDING')=1
    AS 'Unit 5 sealer requires exactly one BUILDING producer state';
  ASSERT (SELECT AS STRUCT COUNT(*) row_count,
      TO_HEX(SHA256(COALESCE(STRING_AGG(TO_HEX(SHA256(TO_JSON_STRING(p))),''
        ORDER BY p.OrderItem,SAFE_CAST(p.Period AS INT64),p.InvoiceNo,TO_JSON_STRING(p)),
        '<EMPTY>'))) set_hash
    FROM `pacific-plating-282708.sap_integration_v3.v3_unit5_newpayment_ready` p)
    = (SELECT AS STRUCT producer_row_count,producer_set_hash
      FROM `pacific-plating-282708.sap_integration_v3.v3_unit5_newpayment_run_state`
      WHERE pipeline_run_id=p_pipeline_run_id AND state='BUILDING')
    AS 'Mutable Unit 5 producer payload differs from claimed BUILDING version';
  ASSERT (SELECT COUNT(*) FROM `pacific-plating-282708.sap_integration_v3.v3_unit5_payload_identity`
    WHERE pipeline_run_id=p_pipeline_run_id AND file_role='NEWPAYMENT')=
    (SELECT COUNT(*) FROM `pacific-plating-282708.sap_integration_v3.v3_unit5_payload_identity` i
      WHERE i.pipeline_run_id=p_pipeline_run_id AND i.file_role='NEWPAYMENT'
        AND EXISTS (SELECT 1
          FROM `pacific-plating-282708.sap_integration_v3.v3_unit5_newpayment_ready` p
          WHERE i.order_item=p.OrderItem AND i.period=SAFE_CAST(p.Period AS INT64)
            AND i.invoice_no=p.InvoiceNo))
    AS 'Unit 5 balance quarantine requires exact candidate-to-identity conservation';

  CREATE TEMP TABLE _period_identity_count AS
  SELECT order_item,period,COUNT(*) identity_count
  FROM `pacific-plating-282708.sap_integration_v3.v3_unit5_payload_identity`
  WHERE pipeline_run_id=p_pipeline_run_id AND file_role='NEWPAYMENT' GROUP BY order_item,period;
  CREATE TEMP TABLE _payload_one AS
  SELECT * EXCEPT(_identity_rank) FROM (
    SELECT p.*,ROW_NUMBER() OVER (PARTITION BY p.OrderItem,SAFE_CAST(p.Period AS INT64),p.InvoiceNo
      ORDER BY TO_JSON_STRING(p)) _identity_rank
    FROM `pacific-plating-282708.sap_integration_v3.v3_unit5_newpayment_ready` p)
  WHERE _identity_rank=1;
  CREATE TEMP TABLE _payload_duplicate_item AS
  SELECT DISTINCT OrderItem order_item FROM (
    SELECT OrderItem,SAFE_CAST(Period AS INT64) period,COUNT(*) payload_count
    FROM `pacific-plating-282708.sap_integration_v3.v3_unit5_newpayment_ready`
    GROUP BY 1,2 HAVING payload_count>1);

  CREATE TEMP TABLE _hold AS
  SELECT p_pipeline_run_id pipeline_run_id,p.OrderItem order_item,
    SAFE_CAST(p.Period AS INT64) period,i.charge_id,p.InvoiceNo invoice_no,
    SAFE_CAST(p.ExpectedReceived AS NUMERIC) expected_received,
    SAFE_CAST(p.ActualReceived AS NUMERIC) actual_received,
    SAFE_CAST(p.ActualReceived AS NUMERIC)-SAFE_CAST(p.ExpectedReceived AS NUMERIC) difference,
    IF(c.identity_count>1 OR di.order_item IS NOT NULL,
      'HOLD_MULTIPLE_PAYMENT_EVENTS_SAME_PERIOD','HOLD_RECEIPT_BALANCE_MISMATCH') hold_code,
    IF(c.identity_count>1 OR di.order_item IS NOT NULL,
      'More than one payment identity or physical payload row resolves to the item-period',
      'Absolute ActualReceived minus ExpectedReceived exceeds THB 10') hold_reason,
    CURRENT_TIMESTAMP() detected_at
  FROM `pacific-plating-282708.sap_integration_v3.v3_unit5_payload_identity` i
  JOIN _period_identity_count c ON c.order_item=i.order_item AND c.period=i.period
  LEFT JOIN _payload_duplicate_item di ON di.order_item=i.order_item
  JOIN _payload_one p ON p.OrderItem=i.order_item AND SAFE_CAST(p.Period AS INT64)=i.period
    AND p.InvoiceNo=i.invoice_no
  WHERE i.pipeline_run_id=p_pipeline_run_id AND i.file_role='NEWPAYMENT'
    AND (c.identity_count>1 OR di.order_item IS NOT NULL
      OR ABS(SAFE_CAST(p.ActualReceived AS NUMERIC)-SAFE_CAST(p.ExpectedReceived AS NUMERIC))>10);
  ASSERT (SELECT COUNT(*) FROM (SELECT order_item,period,charge_id,COUNT(*) n FROM _hold
    GROUP BY 1,2,3 HAVING n!=1))=0 AS 'Unit 5 staged balance hold identity is not unique';

  CREATE TEMP TABLE _delivery AS
  SELECT p.* FROM `pacific-plating-282708.sap_integration_v3.v3_unit5_newpayment_ready` p
  WHERE NOT EXISTS (SELECT 1 FROM _hold h WHERE h.order_item=p.OrderItem);
  ASSERT (SELECT COUNT(*) FROM (
    SELECT OrderItem,COUNT(*) row_n,COUNT(DISTINCT SAFE_CAST(Period AS INT64)) period_n,
      MIN(SAFE_CAST(Period AS INT64)) first_period,MAX(SAFE_CAST(Period AS INT64)) last_period,
      COUNT(DISTINCT SAFE_CAST(TotalPeriods AS INT64)) total_value_n,
      MAX(SAFE_CAST(TotalPeriods AS INT64)) total_n
    FROM _delivery GROUP BY OrderItem HAVING total_value_n!=1 OR first_period!=1
      OR last_period!=total_n OR period_n!=total_n OR row_n!=total_n))=0
    AS 'Delivery-ready RCL item has incomplete or duplicate period spine';
  ASSERT (SELECT COUNT(*) FROM `pacific-plating-282708.sap_integration_v3.v3_unit5_payload_identity`
    WHERE pipeline_run_id=p_pipeline_run_id AND file_role='NEWPAYMENT'
      AND order_item NOT IN (SELECT DISTINCT order_item FROM _hold))=
    (SELECT COUNT(*) FROM `pacific-plating-282708.sap_integration_v3.v3_unit5_payload_identity` i
      WHERE i.pipeline_run_id=p_pipeline_run_id AND i.file_role='NEWPAYMENT'
        AND EXISTS (SELECT 1 FROM _delivery d WHERE d.OrderItem=i.order_item
          AND SAFE_CAST(d.Period AS INT64)=i.period AND d.InvoiceNo=i.invoice_no))
    AS 'Released event identities do not conserve against staged delivery spine';
  ASSERT (SELECT COUNT(*) FROM _delivery d
    WHERE ABS(SAFE_CAST(d.ActualReceived AS NUMERIC)-SAFE_CAST(d.ExpectedReceived AS NUMERIC))>10
      AND EXISTS (SELECT 1
        FROM `pacific-plating-282708.sap_integration_v3.v3_unit5_payload_identity` i
        WHERE i.pipeline_run_id=p_pipeline_run_id AND i.file_role='NEWPAYMENT'
          AND i.order_item=d.OrderItem AND i.period=SAFE_CAST(d.Period AS INT64)
          AND i.invoice_no=d.InvoiceNo))=0
    AS 'Staged delivery target still contains receipt-balance mismatch';
  CREATE TEMP TABLE _manifest AS
  SELECT p_pipeline_run_id pipeline_run_id,COUNT(*) row_count,
    TO_HEX(SHA256(COALESCE(STRING_AGG(TO_HEX(SHA256(TO_JSON_STRING(d))),''
      ORDER BY d.OrderItem,SAFE_CAST(d.Period AS INT64),d.InvoiceNo,TO_JSON_STRING(d)),
      '<EMPTY>'))) payload_set_hash,CURRENT_TIMESTAMP() completed_at FROM _delivery d;
  CREATE TEMP TABLE _hold_notification AS
  WITH event_one AS (
    SELECT pipeline_run_id,order_item,period,charge_id,ANY_VALUE(order_id) order_id,
      ANY_VALUE(charge_amount) charge_amount,COUNT(*) event_rows
    FROM `pacific-plating-282708.sap_integration_v3.v3_unit2_event_shadow`
    WHERE pipeline_run_id=p_pipeline_run_id GROUP BY 1,2,3,4)
  SELECT h.pipeline_run_id,'VALIDATION_HOLD' notification_type,'PAYMENT_EVENT' grain,
    h.order_item,e.order_id,h.period,h.charge_id,e.charge_amount,h.hold_code reason_code,
    CONCAT(h.hold_reason,'; expected=',CAST(h.expected_received AS STRING),'; actual=',
      CAST(h.actual_received AS STRING),'; difference=',CAST(h.difference AS STRING)) reason_detail,
    CURRENT_TIMESTAMP() detected_at
  FROM _hold h JOIN event_one e USING(pipeline_run_id,order_item,period,charge_id)
  WHERE e.event_rows=1;
  ASSERT (SELECT COUNT(*) FROM _hold_notification)=(SELECT COUNT(*) FROM _hold)
    AS 'Every Unit 5 balance hold requires exactly one notification source event';
  ASSERT (SELECT COUNT(*) FROM (
    SELECT ordinal_position,column_name,data_type
    FROM `pacific-plating-282708.sap_integration_v3.INFORMATION_SCHEMA.COLUMNS`
    WHERE table_name='v3_unit5_newpayment_delivery_ready'
    EXCEPT DISTINCT
    SELECT ordinal_position,column_name,data_type
    FROM `pacific-plating-282708.sap_integration_v3.INFORMATION_SCHEMA.COLUMNS`
    WHERE table_name='v3_unit5_newpayment_ready'))=0
    AND (SELECT COUNT(*) FROM (
    SELECT ordinal_position,column_name,data_type
    FROM `pacific-plating-282708.sap_integration_v3.INFORMATION_SCHEMA.COLUMNS`
    WHERE table_name='v3_unit5_newpayment_ready'
    EXCEPT DISTINCT
    SELECT ordinal_position,column_name,data_type
    FROM `pacific-plating-282708.sap_integration_v3.INFORMATION_SCHEMA.COLUMNS`
    WHERE table_name='v3_unit5_newpayment_delivery_ready'))=0
    AS 'Unit 5 delivery-ready schema differs from exact reviewed 56-column contract';

  BEGIN TRANSACTION;
  UPDATE `pacific-plating-282708.sap_integration_v3.v3_unit5_newpayment_run_state`
  SET state='SEALED',updated_at=CURRENT_TIMESTAMP()
  WHERE pipeline_run_id=p_pipeline_run_id AND state='BUILDING'
    AND producer_row_count=(SELECT COUNT(*)
      FROM `pacific-plating-282708.sap_integration_v3.v3_unit5_newpayment_ready`)
    AND producer_set_hash=(SELECT TO_HEX(SHA256(COALESCE(STRING_AGG(
      TO_HEX(SHA256(TO_JSON_STRING(p))),'' ORDER BY p.OrderItem,SAFE_CAST(p.Period AS INT64),
      p.InvoiceNo,TO_JSON_STRING(p)),'<EMPTY>')))
      FROM `pacific-plating-282708.sap_integration_v3.v3_unit5_newpayment_ready` p);
  ASSERT @@row_count=1 AS 'Unit 5 BUILDING version changed before atomic seal';
  MERGE `pacific-plating-282708.sap_integration_v3.v3_unit5_newpayment_snapshot_manifest` t
  USING _manifest s ON t.pipeline_run_id=s.pipeline_run_id
  WHEN NOT MATCHED THEN INSERT ROW;
  ASSERT @@row_count=1 AS 'Unit 5 immutable snapshot manifest claim failed';
  DELETE FROM `pacific-plating-282708.sap_integration_v3.v3_unit5_balance_hold`
  WHERE pipeline_run_id=p_pipeline_run_id;
  INSERT INTO `pacific-plating-282708.sap_integration_v3.v3_unit5_balance_hold` SELECT * FROM _hold;
  ASSERT @@row_count=(SELECT COUNT(*) FROM _hold) AS 'Unit 5 balance hold publication failed';
  DELETE FROM `pacific-plating-282708.sap_integration_v3.v3_notification_item`
  WHERE pipeline_run_id=p_pipeline_run_id AND reason_code IN
    ('HOLD_RECEIPT_BALANCE_MISMATCH','HOLD_MULTIPLE_PAYMENT_EVENTS_SAME_PERIOD');
  INSERT INTO `pacific-plating-282708.sap_integration_v3.v3_notification_item`
  SELECT * FROM _hold_notification;
  ASSERT @@row_count=(SELECT COUNT(*) FROM _hold)
    AS 'Unit 5 balance hold notification conservation failed';
  DELETE FROM `pacific-plating-282708.sap_integration_v3.v3_unit5_newpayment_delivery_ready`
  WHERE TRUE;
  INSERT INTO `pacific-plating-282708.sap_integration_v3.v3_unit5_newpayment_delivery_ready`
  SELECT * FROM _delivery;
  ASSERT @@row_count=(SELECT COUNT(*) FROM _delivery) AS 'Delivery-ready publication failed';
  INSERT INTO `pacific-plating-282708.sap_integration_v3.v3_unit5_newpayment_run_snapshot`
  SELECT p_pipeline_run_id,d.*,CURRENT_TIMESTAMP() FROM _delivery d;
  ASSERT @@row_count=(SELECT COUNT(*) FROM _delivery) AS 'Run snapshot publication failed';
  COMMIT TRANSACTION;
END;

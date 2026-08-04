-- Class A / production tables. Unit 5 balance quarantine before delivery.
-- Boat rule: a materially different installment ActualReceived vs ExpectedReceived must be held
-- for human investigation, never corrected or silently delivered. The existing reconciliation
-- contract uses +/- THB 10 per order/item-period; this procedure applies that same boundary.

CREATE TABLE IF NOT EXISTS `pacific-plating-282708.sap_integration_v3.v3_unit5_balance_hold` (
  pipeline_run_id STRING NOT NULL,
  order_item STRING NOT NULL,
  period INT64 NOT NULL,
  charge_id STRING NOT NULL,
  invoice_no STRING NOT NULL,
  expected_received NUMERIC NOT NULL,
  actual_received NUMERIC NOT NULL,
  difference NUMERIC NOT NULL,
  hold_code STRING NOT NULL,
  hold_reason STRING NOT NULL,
  detected_at TIMESTAMP NOT NULL
)
PARTITION BY DATE(detected_at)
CLUSTER BY pipeline_run_id,order_item,period;

CREATE OR REPLACE PROCEDURE `pacific-plating-282708.sap_integration_v3.sp_build_v3_newpayment_delivery_ready`(
  p_pipeline_run_id STRING
)
BEGIN
  ASSERT NULLIF(TRIM(p_pipeline_run_id),'') IS NOT NULL
    AS 'Unit 5 balance quarantine requires pipeline_run_id';
  ASSERT (SELECT COUNT(*) FROM `pacific-plating-282708.sap_integration_v3.v3_unit5_payload_identity`
    WHERE pipeline_run_id=p_pipeline_run_id AND file_role='NEWPAYMENT')=
    (SELECT COUNT(*) FROM `pacific-plating-282708.sap_integration_v3.v3_unit5_newpayment_ready` p
      WHERE EXISTS (SELECT 1
        FROM `pacific-plating-282708.sap_integration_v3.v3_unit5_payload_identity` i
        WHERE i.pipeline_run_id=p_pipeline_run_id AND i.file_role='NEWPAYMENT'
          AND i.order_item=p.OrderItem AND i.period=SAFE_CAST(p.Period AS INT64)
          AND i.invoice_no=p.InvoiceNo))
    AS 'Unit 5 balance quarantine requires exact candidate-to-identity conservation';

  DELETE FROM `pacific-plating-282708.sap_integration_v3.v3_unit5_balance_hold`
  WHERE pipeline_run_id=p_pipeline_run_id;

  INSERT INTO `pacific-plating-282708.sap_integration_v3.v3_unit5_balance_hold`
  SELECT p_pipeline_run_id,p.OrderItem,SAFE_CAST(p.Period AS INT64),i.charge_id,p.InvoiceNo,
    SAFE_CAST(p.ExpectedReceived AS NUMERIC),SAFE_CAST(p.ActualReceived AS NUMERIC),
    SAFE_CAST(p.ActualReceived AS NUMERIC)-SAFE_CAST(p.ExpectedReceived AS NUMERIC),
    'HOLD_RECEIPT_BALANCE_MISMATCH',
    'Absolute ActualReceived minus ExpectedReceived exceeds THB 10 for one item-period',
    CURRENT_TIMESTAMP()
  FROM `pacific-plating-282708.sap_integration_v3.v3_unit5_newpayment_ready` p
  JOIN `pacific-plating-282708.sap_integration_v3.v3_unit5_payload_identity` i
    ON i.pipeline_run_id=p_pipeline_run_id AND i.file_role='NEWPAYMENT'
   AND i.order_item=p.OrderItem AND i.period=SAFE_CAST(p.Period AS INT64)
   AND i.invoice_no=p.InvoiceNo
  WHERE ABS(SAFE_CAST(p.ActualReceived AS NUMERIC)-SAFE_CAST(p.ExpectedReceived AS NUMERIC))>10;

  ASSERT (SELECT COUNT(*) FROM (
    SELECT order_item,period,charge_id,COUNT(*) n
    FROM `pacific-plating-282708.sap_integration_v3.v3_unit5_balance_hold`
    WHERE pipeline_run_id=p_pipeline_run_id GROUP BY 1,2,3 HAVING n!=1))=0
    AS 'Unit 5 balance hold identity is not unique';

  DELETE FROM `pacific-plating-282708.sap_integration_v3.v3_notification_item`
  WHERE pipeline_run_id=p_pipeline_run_id
    AND reason_code='HOLD_RECEIPT_BALANCE_MISMATCH';

  INSERT INTO `pacific-plating-282708.sap_integration_v3.v3_notification_item`
  SELECT h.pipeline_run_id,'VALIDATION_HOLD','PAYMENT_EVENT',h.order_item,u.order_id,h.period,
    h.charge_id,u.charge_amount,h.hold_code,
    CONCAT(h.hold_reason,'; expected=',CAST(h.expected_received AS STRING),
      '; actual=',CAST(h.actual_received AS STRING),'; difference=',CAST(h.difference AS STRING)),
    CURRENT_TIMESTAMP()
  FROM `pacific-plating-282708.sap_integration_v3.v3_unit5_balance_hold` h
  JOIN `pacific-plating-282708.sap_integration_v3.v3_unit2_event_shadow` u
    ON u.pipeline_run_id=h.pipeline_run_id AND u.order_item=h.order_item
   AND u.period=h.period AND u.charge_id=h.charge_id
  WHERE h.pipeline_run_id=p_pipeline_run_id;

  CREATE OR REPLACE TABLE `pacific-plating-282708.sap_integration_v3.v3_unit5_newpayment_delivery_ready` AS
  SELECT p.*
  FROM `pacific-plating-282708.sap_integration_v3.v3_unit5_newpayment_ready` p
  WHERE NOT EXISTS (
    SELECT 1 FROM `pacific-plating-282708.sap_integration_v3.v3_unit5_balance_hold` h
    WHERE h.pipeline_run_id=p_pipeline_run_id AND h.order_item=p.OrderItem);

  ASSERT (SELECT COUNT(*) FROM (
    SELECT OrderItem,COUNT(DISTINCT SAFE_CAST(Period AS INT64)) period_n,
      MIN(SAFE_CAST(Period AS INT64)) first_period,MAX(SAFE_CAST(Period AS INT64)) last_period,
      COUNT(DISTINCT SAFE_CAST(TotalPeriods AS INT64)) total_value_n,
      MAX(SAFE_CAST(TotalPeriods AS INT64)) total_n
    FROM `pacific-plating-282708.sap_integration_v3.v3_unit5_newpayment_delivery_ready`
    GROUP BY OrderItem
    HAVING total_value_n!=1 OR first_period!=1 OR last_period!=total_n OR period_n!=total_n))=0
    AS 'Delivery-ready RCL item has an incomplete period spine';
  ASSERT (SELECT COUNT(*) FROM `pacific-plating-282708.sap_integration_v3.v3_unit5_payload_identity`
    WHERE pipeline_run_id=p_pipeline_run_id AND file_role='NEWPAYMENT'
      AND order_item NOT IN (SELECT DISTINCT order_item
        FROM `pacific-plating-282708.sap_integration_v3.v3_unit5_balance_hold`
        WHERE pipeline_run_id=p_pipeline_run_id))=
    (SELECT COUNT(*) FROM `pacific-plating-282708.sap_integration_v3.v3_unit5_payload_identity` i
      WHERE i.pipeline_run_id=p_pipeline_run_id AND i.file_role='NEWPAYMENT'
        AND EXISTS (SELECT 1
          FROM `pacific-plating-282708.sap_integration_v3.v3_unit5_newpayment_delivery_ready` d
          WHERE d.OrderItem=i.order_item AND SAFE_CAST(d.Period AS INT64)=i.period
            AND d.InvoiceNo=i.invoice_no))
    AS 'Released event identities do not conserve against expanded delivery spine';
  ASSERT (SELECT COUNT(*) FROM `pacific-plating-282708.sap_integration_v3.INFORMATION_SCHEMA.COLUMNS`
    WHERE table_name='v3_unit5_newpayment_delivery_ready')=56
    AS 'Delivery-ready NEWPAYMENT must retain exactly 56 columns';
  ASSERT (SELECT COUNT(*) FROM `pacific-plating-282708.sap_integration_v3.v3_unit5_newpayment_delivery_ready`
    WHERE ABS(SAFE_CAST(ActualReceived AS NUMERIC)-SAFE_CAST(ExpectedReceived AS NUMERIC))>10
      AND EXISTS (SELECT 1
        FROM `pacific-plating-282708.sap_integration_v3.v3_unit5_payload_identity` i
        WHERE i.pipeline_run_id=p_pipeline_run_id AND i.file_role='NEWPAYMENT'
          AND i.order_item=OrderItem AND i.period=SAFE_CAST(Period AS INT64)
          AND i.invoice_no=InvoiceNo))=0
    AS 'Delivery-ready target payment event still contains receipt-balance mismatch';
END;

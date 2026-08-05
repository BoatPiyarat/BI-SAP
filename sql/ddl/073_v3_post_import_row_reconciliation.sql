-- SOURCE ONLY / Class A. Exact delivered-row reconciliation after the child Unit 1 refresh.
-- This procedure writes BigQuery evidence and ACK/reject state only. It does not write GCS,
-- deliver a file, call SAP, start a workflow, or infer success from the file-level result alone.

CREATE TABLE IF NOT EXISTS
  `pacific-plating-282708.sap_integration_v3.v3_post_import_row_reconciliation` (
    log_id STRING NOT NULL,
    export_run_id STRING NOT NULL,
    child_pipeline_run_id STRING NOT NULL,
    order_item STRING NOT NULL,
    period INT64 NOT NULL,
    charge_id STRING NOT NULL,
    payload_hash STRING NOT NULL,
    expected_invoice_no STRING,
    expected_status STRING NOT NULL,
    outcome STRING NOT NULL,
    exact_error_detail_count INT64 NOT NULL,
    mirror_docentry INT64,
    reconciled_at TIMESTAMP NOT NULL
  )
PARTITION BY DATE(reconciled_at)
CLUSTER BY log_id, export_run_id, outcome, order_item
OPTIONS (
  description = 'Exact-identity latest post-import result after an independently completed Unit 1 mirror refresh'
);

CREATE OR REPLACE PROCEDURE
  `pacific-plating-282708.sap_integration_v3.sp_reconcile_v3_post_import_rows`(
    p_child_pipeline_run_id STRING,
    p_log_id STRING,
    p_export_run_id STRING,
    p_sap_file_name STRING
  )
BEGIN
  DECLARE v_rows INT64;
  DECLARE v_acknowledged INT64;
  DECLARE v_rejected INT64;
  DECLARE v_pending INT64;
  DECLARE v_manifest_status STRING;

  ASSERT NULLIF(TRIM(p_child_pipeline_run_id),'') IS NOT NULL
    AS 'child pipeline run ID is required';
  ASSERT NULLIF(TRIM(p_log_id),'') IS NOT NULL AS 'SAP LogID is required';
  ASSERT NULLIF(TRIM(p_export_run_id),'') IS NOT NULL AS 'export run ID is required';
  ASSERT NULLIF(TRIM(p_sap_file_name),'') IS NOT NULL AS 'SAP filename is required';
  ASSERT (SELECT COUNT(*)
    FROM `pacific-plating-282708.sap_integration_v3.pipeline_run_log`
    WHERE run_id=p_child_pipeline_run_id AND step='UNIT1_COMPLETE' AND status='SUCCESS')=1
    AS 'row reconciliation requires exactly one successful child UNIT1_COMPLETE';
  ASSERT (SELECT COUNT(*)
    FROM `pacific-plating-282708.sap_integration_v3.v3_post_import_refresh_outbox`
    WHERE log_id=p_log_id AND export_run_id=p_export_run_id AND sap_file_name=p_sap_file_name
      AND request_status='STARTED')=1
    AS 'row reconciliation must bind one STARTED outbox row';
  ASSERT (SELECT COUNT(*)
    FROM `pacific-plating-282708.sap_integration_v3.sap_import_result_header_v3`
    WHERE log_id=p_log_id AND file_name=p_sap_file_name AND company_db='RCB_LIVE_DB'
      AND attachment_parse_status='PARSED' AND NULLIF(txt_gcs_uri,'') IS NOT NULL
      AND LOWER(status) IN ('success','success with error'))=1
    AS 'one parsed terminal LIVE import header must match LogID and SAP filename';
  ASSERT (SELECT COUNT(*)
    FROM `pacific-plating-282708.sap_integration_v3.sap_delivery_manifest_v3`
    WHERE export_run_id=p_export_run_id AND sap_file_name=p_sap_file_name
      AND delivery_status IN ('DELIVERED','PICKED_UP','ACKNOWLEDGED','PARTIAL_REJECT','REJECTED'))=1
    AS 'one delivered manifest must match export run and SAP filename';
  ASSERT (SELECT COUNT(*) FROM (
    SELECT detail_seq
    FROM `pacific-plating-282708.sap_integration_v3.sap_import_error_detail_v3`
    WHERE log_id=p_log_id GROUP BY detail_seq HAVING COUNT(*)!=1))=0
    AS 'SAP error-detail logical key is duplicated';

  CREATE TEMP TABLE _archive AS
  SELECT export_run_id,order_item,period,charge_id,payload_hash,payload_json
  FROM `pacific-plating-282708.sap_integration_v3.export_archive`
  WHERE export_run_id=p_export_run_id AND delivery_status IN ('DELIVERED','PICKED_UP');

  SET v_rows=(SELECT COUNT(*) FROM _archive);
  ASSERT v_rows>0 AS 'delivered export run has no archive identities';
  ASSERT (SELECT COUNT(*) FROM (
    SELECT order_item,period,charge_id,payload_hash
    FROM _archive GROUP BY 1,2,3,4 HAVING COUNT(*)!=1))=0
    AS 'delivered export identity is duplicated';
  ASSERT (SELECT data_row_count
    FROM `pacific-plating-282708.sap_integration_v3.sap_delivery_manifest_v3`
    WHERE export_run_id=p_export_run_id AND sap_file_name=p_sap_file_name)=v_rows
    AS 'delivery manifest row count does not conserve against archive identities';
  ASSERT (SELECT COUNT(*) FROM _archive
    WHERE NULLIF(payload_hash,'') IS NULL
      OR NULLIF(JSON_VALUE(payload_json,'$.TransactionStatus'),'') IS NULL)=0
    AS 'archive identity lacks payload hash or expected SAP status';

  CREATE TEMP TABLE _exact_errors AS
  SELECT order_item,period,COUNT(*) AS exact_error_detail_count
  FROM `pacific-plating-282708.sap_integration_v3.sap_import_error_detail_v3`
  WHERE log_id=p_log_id AND error_class='ROW_LEVEL'
    AND NULLIF(order_item,'') IS NOT NULL AND period IS NOT NULL
  GROUP BY order_item,period;

  CREATE TEMP TABLE _mirror_match AS
  SELECT a.order_item,a.period,a.charge_id,a.payload_hash,m.DocEntry AS mirror_docentry
  FROM _archive a
  JOIN `pacific-plating-282708.sap_integration_v3.sap_mirror_doc` m
    ON m.U_OrderItem=a.order_item AND SAFE_CAST(m.U_Period AS INT64)=a.period
   AND IFNULL(m.U_InvoiceNo,'')=IFNULL(JSON_VALUE(a.payload_json,'$.InvoiceNo'),'')
   AND LOWER(m.TransactionStatus)=LOWER(JSON_VALUE(a.payload_json,'$.TransactionStatus'))
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY a.order_item,a.period,a.charge_id,a.payload_hash
    ORDER BY m.UpdateDate DESC,m.UpdateTime DESC,m.DocEntry DESC)=1;

  CREATE TEMP TABLE _result AS
  SELECT p_log_id AS log_id,p_export_run_id AS export_run_id,
    p_child_pipeline_run_id AS child_pipeline_run_id,
    a.order_item,a.period,a.charge_id,a.payload_hash,
    JSON_VALUE(a.payload_json,'$.InvoiceNo') AS expected_invoice_no,
    JSON_VALUE(a.payload_json,'$.TransactionStatus') AS expected_status,
    CASE
      WHEN IFNULL(e.exact_error_detail_count,0)>0 THEN 'REJECTED_BY_SAP'
      WHEN m.mirror_docentry IS NOT NULL THEN 'ACKNOWLEDGED'
      ELSE 'PENDING_ACK'
    END AS outcome,
    IFNULL(e.exact_error_detail_count,0) AS exact_error_detail_count,
    m.mirror_docentry,CURRENT_TIMESTAMP() AS reconciled_at
  FROM _archive a
  LEFT JOIN _exact_errors e USING(order_item,period)
  LEFT JOIN _mirror_match m USING(order_item,period,charge_id,payload_hash);

  SET v_acknowledged=(SELECT COUNT(*) FROM _result WHERE outcome='ACKNOWLEDGED');
  SET v_rejected=(SELECT COUNT(*) FROM _result WHERE outcome='REJECTED_BY_SAP');
  SET v_pending=(SELECT COUNT(*) FROM _result WHERE outcome='PENDING_ACK');
  ASSERT v_rows=v_acknowledged+v_rejected+v_pending
    AS 'post-import row outcome conservation failed';
  ASSERT (SELECT COUNT(*) FROM _result WHERE outcome IS NULL)=0
    AS 'post-import result contains a NULL outcome';

  SET v_manifest_status=CASE
    WHEN v_pending>0 THEN 'DELIVERED'
    WHEN v_acknowledged=v_rows THEN 'ACKNOWLEDGED'
    WHEN v_rejected=v_rows THEN 'REJECTED'
    ELSE 'PARTIAL_REJECT' END;

  BEGIN TRANSACTION;
  DELETE FROM
    `pacific-plating-282708.sap_integration_v3.v3_post_import_row_reconciliation`
  WHERE log_id=p_log_id AND export_run_id=p_export_run_id;
  INSERT INTO
    `pacific-plating-282708.sap_integration_v3.v3_post_import_row_reconciliation`
  SELECT * FROM _result;
  ASSERT @@row_count=v_rows AS 'not every delivered identity received reconciliation evidence';

  UPDATE `pacific-plating-282708.sap_integration_v3.export_archive` a
  SET sap_log_id=p_log_id,
      sap_result_status=(
        SELECT CASE r.outcome
          WHEN 'ACKNOWLEDGED' THEN 'ACKNOWLEDGED'
          WHEN 'REJECTED_BY_SAP' THEN 'REJECTED'
          ELSE NULL END
        FROM _result r
        WHERE r.order_item=a.order_item AND r.period=a.period AND r.charge_id=a.charge_id
          AND r.payload_hash=a.payload_hash),
      acknowledged_at=(
        SELECT IF(r.outcome='ACKNOWLEDGED',IFNULL(a.acknowledged_at,CURRENT_TIMESTAMP()),NULL)
        FROM _result r
        WHERE r.order_item=a.order_item AND r.period=a.period AND r.charge_id=a.charge_id
          AND r.payload_hash=a.payload_hash)
  WHERE export_run_id=p_export_run_id AND delivery_status IN ('DELIVERED','PICKED_UP');
  ASSERT @@row_count=v_rows AS 'not every delivered archive row received its exact result';

  UPDATE `pacific-plating-282708.sap_integration_v3.sap_delivery_manifest_v3`
  SET delivery_status=v_manifest_status
  WHERE export_run_id=p_export_run_id AND sap_file_name=p_sap_file_name
    AND delivery_status IN ('DELIVERED','PICKED_UP','ACKNOWLEDGED','PARTIAL_REJECT','REJECTED');
  ASSERT @@row_count=1 AS 'SAP delivery manifest terminal transition failed';

  UPDATE `pacific-plating-282708.sap_integration_v3.export_file_manifest`
  SET delivery_status=v_manifest_status
  WHERE export_run_id=p_export_run_id
    AND delivery_status IN ('DELIVERED','PICKED_UP','ACKNOWLEDGED','PARTIAL_REJECT','REJECTED');
  ASSERT @@row_count=1 AS 'export file manifest terminal transition failed';
  COMMIT TRANSACTION;

  SELECT v_rows AS total_rows,v_acknowledged AS acknowledged_rows,
    v_rejected AS rejected_rows,v_pending AS pending_rows,
    v_manifest_status AS manifest_status;
END;

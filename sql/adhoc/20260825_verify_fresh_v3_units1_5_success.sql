DECLARE target_run_id STRING DEFAULT 'V3NIGHTLY-2026-08-25T14:32:37-0ce16d45';

ASSERT (SELECT COUNT(*) FROM `pacific-plating-282708.sap_integration_v3.pipeline_run_log`
  WHERE run_id=target_run_id AND step='UNIT1_COMPLETE' AND status='SUCCESS')=1
  AS 'Fresh run lacks exactly one successful Unit 1 completion';
ASSERT (SELECT COUNT(*) FROM `pacific-plating-282708.sap_integration_v3.pipeline_run_log`
  WHERE run_id=target_run_id AND step='UNITS_2_5_ARCHIVE' AND status='SUCCESS')=1
  AS 'Fresh run lacks exactly one successful Units 2-5 archive completion';
ASSERT (SELECT COUNT(*) FROM `pacific-plating-282708.sap_integration_v3.pipeline_run_log`
  WHERE run_id=target_run_id AND status='FAILED')=0
  AS 'Fresh run contains a failed step';

ASSERT (SELECT COUNT(*) FROM (
  SELECT OrderItem,SAFE_CAST(Period AS INT64),COUNT(*) n
  FROM `pacific-plating-282708.sap_integration_v3.v3_unit5_newpayment_delivery_ready`
  GROUP BY 1,2 HAVING n>1))=0
  AS 'Fresh delivery-ready artifact contains duplicate item-periods';
ASSERT (SELECT COUNT(*) FROM (
  SELECT OrderItem,COUNT(*) row_n,COUNT(DISTINCT SAFE_CAST(Period AS INT64)) period_n,
    MAX(SAFE_CAST(TotalPeriods AS INT64)) total_n
  FROM `pacific-plating-282708.sap_integration_v3.v3_unit5_newpayment_delivery_ready`
  GROUP BY OrderItem HAVING row_n!=total_n OR period_n!=total_n))=0
  AS 'Fresh delivery-ready artifact contains incomplete item spines';
ASSERT (SELECT COUNT(*) FROM `pacific-plating-282708.sap_integration_v3.INFORMATION_SCHEMA.COLUMNS`
  WHERE table_name='v3_unit5_newpayment_delivery_ready')=56
  AS 'Fresh delivery-ready artifact is not the 56-column contract';

CREATE TEMP TABLE fresh_archive AS
SELECT a.*
FROM `pacific-plating-282708.sap_integration_v3.export_archive` a
WHERE a.export_run_id IN (
  SELECT DISTINCT a2.export_run_id
  FROM `pacific-plating-282708.sap_integration_v3.v3_unit5_payload_identity` i
  JOIN `pacific-plating-282708.sap_integration_v3.export_archive` a2
    ON a2.order_item=i.order_item AND a2.period=i.period AND a2.charge_id=i.charge_id
  WHERE i.pipeline_run_id=target_run_id AND i.file_role='NEWPAYMENT'
    AND a2.exported_at>=TIMESTAMP '2026-08-25 14:32:37+00');

ASSERT (SELECT COUNT(DISTINCT export_run_id) FROM fresh_archive)=1
  AS 'Fresh run does not resolve to exactly one archive run';
ASSERT (SELECT COUNT(DISTINCT delivery_status) FROM fresh_archive)=1
  AND (SELECT ANY_VALUE(delivery_status) FROM fresh_archive)='ARCHIVED_PENDING_OBJECT_METADATA'
  AS 'Fresh archive is not archive-only pending metadata';
ASSERT (SELECT COUNT(*) FROM fresh_archive
  WHERE gcs_uri IS NOT NULL OR sap_log_id IS NOT NULL OR acknowledged_at IS NOT NULL)=0
  AS 'Fresh archive has unexpected production or SAP evidence';
ASSERT (SELECT COUNT(*) FROM fresh_archive)=
  (SELECT COUNT(*) FROM `pacific-plating-282708.sap_integration_v3.v3_unit5_payload_identity` i
    WHERE i.pipeline_run_id=target_run_id AND i.file_role='NEWPAYMENT'
      AND NOT EXISTS (SELECT 1
        FROM `pacific-plating-282708.sap_integration_v3.v3_unit5_balance_hold` h
        WHERE h.pipeline_run_id=target_run_id AND h.order_item=i.order_item))
  AS 'Fresh archive ledger does not conserve released identities';

SELECT target_run_id AS pipeline_run_id,
  (SELECT COUNT(*) FROM `pacific-plating-282708.sap_integration_v3.v3_unit5_payload_identity`
    WHERE pipeline_run_id=target_run_id AND file_role='NEWPAYMENT') AS current_identities,
  (SELECT COUNT(*) FROM `pacific-plating-282708.sap_integration_v3.v3_unit5_balance_hold`
    WHERE pipeline_run_id=target_run_id) AS held_identities,
  (SELECT COUNT(*) FROM `pacific-plating-282708.sap_integration_v3.v3_unit5_newpayment_delivery_ready`) AS delivery_rows,
  (SELECT COUNT(DISTINCT OrderItem) FROM `pacific-plating-282708.sap_integration_v3.v3_unit5_newpayment_delivery_ready`) AS delivery_items,
  (SELECT COUNT(*) FROM `pacific-plating-282708.sap_integration_v3.v3_unit5_newpayment_delivery_ready`
    WHERE SAFE.PARSE_DATE('%d%m%Y',PaymentDate) BETWEEN DATE '2026-08-01' AND DATE '2026-08-31') AS august_paid_rows;

SELECT export_run_id,ANY_VALUE(file_name) AS file_name,ANY_VALUE(archive_uri) AS archive_uri,
  ANY_VALUE(delivery_status) AS delivery_status,COUNT(*) AS ledger_identities,
  COUNT(DISTINCT order_item) AS ledger_items,MIN(exported_at) AS exported_at
FROM fresh_archive GROUP BY export_run_id;

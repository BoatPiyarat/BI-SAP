DECLARE target_run_id STRING DEFAULT 'V3NIGHTLY-2026-08-25T11:17:18-ca7ee9e7';

ASSERT (SELECT COUNT(*)
  FROM `pacific-plating-282708.sap_integration_v3.v3_unit5_balance_hold`
  WHERE pipeline_run_id=target_run_id
    AND order_item='L78597123-V1'
    AND hold_code='HOLD_MULTIPLE_PAYMENT_EVENTS_SAME_PERIOD')=1
  AS 'Expected production-shaped duplicate item is not held exactly once';

ASSERT (SELECT COUNT(*) FROM (
  SELECT OrderItem,SAFE_CAST(Period AS INT64),COUNT(*) n
  FROM `pacific-plating-282708.sap_integration_v3.v3_unit5_newpayment_delivery_ready`
  GROUP BY 1,2 HAVING n>1))=0
  AS 'Delivery-ready artifact still contains a duplicate item-period';

ASSERT (SELECT COUNT(*) FROM (
  SELECT OrderItem,COUNT(*) row_n,COUNT(DISTINCT SAFE_CAST(Period AS INT64)) period_n,
    MIN(SAFE_CAST(Period AS INT64)) first_period,MAX(SAFE_CAST(Period AS INT64)) last_period,
    COUNT(DISTINCT SAFE_CAST(TotalPeriods AS INT64)) total_value_n,
    MAX(SAFE_CAST(TotalPeriods AS INT64)) total_n
  FROM `pacific-plating-282708.sap_integration_v3.v3_unit5_newpayment_delivery_ready`
  GROUP BY OrderItem
  HAVING total_value_n!=1 OR first_period!=1 OR last_period!=total_n
    OR period_n!=total_n OR row_n!=total_n))=0
  AS 'Delivery-ready artifact contains an incomplete item spine';

ASSERT (SELECT COUNT(*)
  FROM `pacific-plating-282708.sap_integration_v3.v3_unit5_newpayment_delivery_ready`
  WHERE OrderItem='L78597123-V1')=0
  AS 'Held item remains in delivery-ready artifact';

SELECT
  (SELECT COUNT(*) FROM `pacific-plating-282708.sap_integration_v3.v3_unit5_newpayment_delivery_ready`) AS delivery_rows,
  (SELECT COUNT(DISTINCT OrderItem) FROM `pacific-plating-282708.sap_integration_v3.v3_unit5_newpayment_delivery_ready`) AS delivery_items,
  (SELECT COUNT(*) FROM `pacific-plating-282708.sap_integration_v3.v3_unit5_payload_identity`
    WHERE pipeline_run_id=target_run_id AND file_role='NEWPAYMENT') AS current_identities,
  (SELECT COUNT(*) FROM `pacific-plating-282708.sap_integration_v3.v3_unit5_balance_hold`
    WHERE pipeline_run_id=target_run_id) AS held_identities,
  (SELECT COUNT(*) FROM `pacific-plating-282708.sap_integration_v3.v3_unit5_newpayment_delivery_ready`
    WHERE SAFE.PARSE_DATE('%d%m%Y',PaymentDate) BETWEEN DATE '2026-08-01' AND DATE '2026-08-31') AS august_paid_rows,
  (SELECT COUNT(*) FROM `pacific-plating-282708.sap_integration_v3.INFORMATION_SCHEMA.COLUMNS`
    WHERE table_name='v3_unit5_newpayment_delivery_ready') AS column_count;

SELECT a.export_run_id,a.delivery_status,COUNT(*) AS overlapping_identities,
  ANY_VALUE(a.file_name) AS file_name,ANY_VALUE(a.archive_uri) AS archive_uri,
  ANY_VALUE(a.object_generation) AS object_generation,ANY_VALUE(a.file_sha256) AS file_sha256,
  MIN(a.exported_at) AS first_exported_at,MAX(a.exported_at) AS last_exported_at
FROM `pacific-plating-282708.sap_integration_v3.v3_unit5_payload_identity` i
JOIN `pacific-plating-282708.sap_integration_v3.export_archive` a
  ON a.order_item=i.order_item AND a.period=i.period AND a.charge_id=i.charge_id
WHERE i.pipeline_run_id=target_run_id AND i.file_role='NEWPAYMENT'
  AND a.delivery_status IN ('PREPARED_ARCHIVE','ARCHIVED_PENDING_OBJECT_METADATA',
    'ARCHIVED_PENDING_DELIVERY','DELIVERED','PICKED_UP','ACKNOWLEDGED')
GROUP BY a.export_run_id,a.delivery_status
ORDER BY first_exported_at;

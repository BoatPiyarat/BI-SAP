DECLARE v_run_id STRING DEFAULT 'V3NIGHTLY-2026-08-25T22:21:31-manual';

WITH identity AS (
  SELECT i.*,
    EXISTS (SELECT 1
      FROM `pacific-plating-282708.sap_integration_v3.v3_unit5_balance_hold` h
      WHERE h.pipeline_run_id=i.pipeline_run_id AND h.order_item=i.order_item) AS is_held,
    EXISTS (SELECT 1
      FROM `pacific-plating-282708.sap_integration_v3.export_archive` a
      WHERE a.order_item=i.order_item AND a.period=i.period AND a.charge_id=i.charge_id
        AND a.delivery_status IN ('PREPARED_ARCHIVE','ARCHIVED_PENDING_OBJECT_METADATA',
          'ARCHIVED_PENDING_DELIVERY','DELIVERED','PICKED_UP','ACKNOWLEDGED')) AS has_active_archive
  FROM `pacific-plating-282708.sap_integration_v3.v3_unit5_payload_identity` i
  WHERE i.pipeline_run_id=v_run_id AND i.file_role='NEWPAYMENT'
)
SELECT
  v_run_id AS pipeline_run_id,
  COUNT(*) AS identity_count,
  COUNTIF(is_held) AS held_identity_count,
  COUNTIF(NOT is_held) AS released_identity_count,
  COUNTIF(NOT is_held AND has_active_archive) AS released_already_archived_count,
  COUNTIF(NOT is_held AND NOT has_active_archive) AS released_net_new_count,
  (SELECT COUNT(*)
   FROM `pacific-plating-282708.sap_integration_v3.v3_unit5_newpayment_delivery_ready`)
    AS delivery_row_count
FROM identity;

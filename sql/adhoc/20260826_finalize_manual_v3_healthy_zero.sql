DECLARE v_run_id STRING DEFAULT 'V3NIGHTLY-2026-08-25T22:21:31-manual';

ASSERT (SELECT COUNT(*)
  FROM `pacific-plating-282708.sap_integration_v3.pipeline_run_log`
  WHERE run_id=v_run_id AND step='UNIT1_COMPLETE' AND status='SUCCESS')=1
  AS 'finalization requires exactly one successful Unit 1 row';

ASSERT (SELECT COUNT(*)
  FROM `pacific-plating-282708.sap_integration_v3.pipeline_run_log`
  WHERE run_id=v_run_id AND step='UNITS_2_5_ARCHIVE')=0
  AS 'Units 2-5 terminal row already exists';

ASSERT (SELECT COUNT(*)
  FROM `pacific-plating-282708.sap_integration_v3.v3_unit5_payload_identity`
  WHERE pipeline_run_id=v_run_id AND file_role='NEWPAYMENT')=4
  AS 'finalization identity count drifted from verified value 4';

ASSERT (SELECT COUNT(*)
  FROM `pacific-plating-282708.sap_integration_v3.v3_unit5_payload_identity` i
  WHERE i.pipeline_run_id=v_run_id AND i.file_role='NEWPAYMENT'
    AND NOT EXISTS (SELECT 1
      FROM `pacific-plating-282708.sap_integration_v3.v3_unit5_balance_hold` h
      WHERE h.pipeline_run_id=i.pipeline_run_id AND h.order_item=i.order_item)
    AND NOT EXISTS (SELECT 1
      FROM `pacific-plating-282708.sap_integration_v3.export_archive` a
      WHERE a.order_item=i.order_item AND a.period=i.period AND a.charge_id=i.charge_id
        AND a.delivery_status IN ('PREPARED_ARCHIVE','ARCHIVED_PENDING_OBJECT_METADATA',
          'ARCHIVED_PENDING_DELIVERY','DELIVERED','PICKED_UP','ACKNOWLEDGED')))=0
  AS 'healthy-zero finalization found a released net-new identity';

INSERT INTO `pacific-plating-282708.sap_integration_v3.pipeline_run_log`
  (run_id,run_type,step,scope,rows_in,rows_out,started_at,ended_at,status,error_message)
VALUES
  (v_run_id,'NIGHTLY','UNITS_2_5_ARCHIVE','NIGHTLY:manual-post-fresh-sap',4,0,
   CURRENT_TIMESTAMP(),CURRENT_TIMESTAMP(),'SUCCESS',
   'manual resume completed; identity_count=4; held=3; released=1; released_already_archived=1; released_net_new=0; delivery_rows=6; healthy-zero no archive object created');

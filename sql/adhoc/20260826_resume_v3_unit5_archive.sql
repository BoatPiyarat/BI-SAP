DECLARE v_run_id STRING DEFAULT 'V3NIGHTLY-2026-08-25T22:21:31-manual';

ASSERT (SELECT COUNT(*)
  FROM `pacific-plating-282708.sap_integration_v3.v3_unit5_payload_identity`
  WHERE pipeline_run_id=v_run_id)>0 AS 'resume requires Unit 5 payload identities';

ASSERT (SELECT COUNT(*)
  FROM `pacific-plating-282708.sap_integration_v3.v3_unit5_newpayment_delivery_ready`)>0
  AS 'resume requires non-empty delivery-ready payload';

CALL `pacific-plating-282708.sap_integration_v3.sp_export_v3_daily_newpayment_archive`(v_run_id);

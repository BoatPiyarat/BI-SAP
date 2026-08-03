-- Class A. Nightly Unit 2-5 wrapper called only after the same run logged UNIT1_COMPLETE.
-- A healthy zero-delivery night is successful: classification/notification/gates still run,
-- but no archive object is created. Production exact-byte promotion remains outside this wrapper.

CREATE OR REPLACE PROCEDURE `pacific-plating-282708.sap_integration_v3.sp_run_v3_units2_5`(
  p_pipeline_run_id STRING
)
BEGIN
  ASSERT NULLIF(TRIM(p_pipeline_run_id),'') IS NOT NULL
    AS 'Units 2-5 wrapper requires pipeline_run_id';
  ASSERT (SELECT COUNT(*) FROM `pacific-plating-282708.sap_integration_v3.pipeline_run_log`
    WHERE run_id=p_pipeline_run_id AND step='UNIT1_COMPLETE' AND status='SUCCESS')=1
    AS 'Units 2-5 wrapper requires exactly one successful UNIT1_COMPLETE for the same run';

  CALL `pacific-plating-282708.sap_integration_v3.sp_build_v3_unit2_shadow`(p_pipeline_run_id);
  CALL `pacific-plating-282708.sap_integration_v3.sp_evaluate_v3_unit2_magnitude`(
    p_pipeline_run_id);
  CALL `pacific-plating-282708.sap_integration_v3.sp_build_v3_unit3_mapping_holds`(p_pipeline_run_id);
  CALL `pacific-plating-282708.sap_integration_v3.sp_build_v3_notification_quarantine`(p_pipeline_run_id);
  CALL `pacific-plating-282708.sap_integration_v3.sp_evaluate_v3_automation_gate`(p_pipeline_run_id);
  CALL `pacific-plating-282708.sap_integration_v3.sp_build_v3_newpayment_shadow`(p_pipeline_run_id);

  -- Always rebuild delivery-ready, including 0 rows, so a healthy-zero night cannot leave the
  -- previous night's payload looking current.
  CALL `pacific-plating-282708.sap_integration_v3.sp_build_v3_newpayment_delivery_ready`(
    p_pipeline_run_id);
  IF (SELECT COUNT(*)
    FROM `pacific-plating-282708.sap_integration_v3.v3_unit5_newpayment_delivery_ready`)>0 THEN
    CALL `pacific-plating-282708.sap_integration_v3.sp_export_v3_daily_newpayment_archive`(
      p_pipeline_run_id);
  END IF;
END;

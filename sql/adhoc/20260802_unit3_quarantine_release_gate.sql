-- Production verification for the latest evidenced Unit 2 run as of 2026-08-02 20:44 ICT.
-- No export, GCS write, scheduler mutation, or SAP mutation.
CALL `pacific-plating-282708.sap_integration_v3.sp_build_v3_unit3_mapping_holds`(
  'V3NIGHTLY-2026-08-02T09:02:26-b36e1712'
);
CALL `pacific-plating-282708.sap_integration_v3.sp_build_v3_notification_quarantine`(
  'V3NIGHTLY-2026-08-02T09:02:26-b36e1712'
);
CALL `pacific-plating-282708.sap_integration_v3.sp_evaluate_v3_automation_gate`(
  'V3NIGHTLY-2026-08-02T09:02:26-b36e1712'
);

-- Red/green reproduction for the reported interface-list gap.
-- RED: OrderItem is absent from SAP_LIVE_FULL and every current legacy sap_view.
-- GREEN: at least one SAP or interface row exists.
-- Read-only; no deployment or data mutation.

WITH evidence AS (
  SELECT 'SAP_LIVE_FULL' AS object_name, 'SAP' AS evidence_layer, COUNT(*) AS row_count
  FROM `pacific-plating-282708.sap_integration_v2.SAP_LIVE_FULL`
  WHERE U_OrderItem = 'L80570468-1'

  UNION ALL SELECT 'RCB_Motor_process_create', 'INTERFACE', COUNT(*)
  FROM `pacific-plating-282708.sap_view.RCB_Motor_process_create`
  WHERE OrderItem = 'L80570468-1'
  UNION ALL SELECT 'RCB_Motor_process_2_cancel_new', 'INTERFACE', COUNT(*)
  FROM `pacific-plating-282708.sap_view.RCB_Motor_process_2_cancel_new`
  WHERE OrderItem = 'L80570468-1'
  UNION ALL SELECT 'RCB_Motor_process_3_change', 'INTERFACE', COUNT(*)
  FROM `pacific-plating-282708.sap_view.RCB_Motor_process_3_change`
  WHERE OrderItem = 'L80570468-1'
  UNION ALL SELECT 'RCB_Motor_process_4_creditshell', 'INTERFACE', COUNT(*)
  FROM `pacific-plating-282708.sap_view.RCB_Motor_process_4_creditshell`
  WHERE OrderItem = 'L80570468-1'
  UNION ALL SELECT 'RCL_Motor_process_1_create', 'INTERFACE', COUNT(*)
  FROM `pacific-plating-282708.sap_view.RCL_Motor_process_1_create`
  WHERE OrderItem = 'L80570468-1'
  UNION ALL SELECT 'RCL_Motor_process_2_newpayment', 'INTERFACE', COUNT(*)
  FROM `pacific-plating-282708.sap_view.RCL_Motor_process_2_newpayment`
  WHERE OrderItem = 'L80570468-1'
  UNION ALL SELECT 'RCL_Motor_process_3_cancel', 'INTERFACE', COUNT(*)
  FROM `pacific-plating-282708.sap_view.RCL_Motor_process_3_cancel`
  WHERE OrderItem = 'L80570468-1'
  UNION ALL SELECT 'RCL_Motor_process_4_creditshell', 'INTERFACE', COUNT(*)
  FROM `pacific-plating-282708.sap_view.RCL_Motor_process_4_creditshell`
  WHERE OrderItem = 'L80570468-1'
  UNION ALL SELECT 'RCB_NonMotor_process_1_create', 'INTERFACE', COUNT(*)
  FROM `pacific-plating-282708.sap_view.RCB_NonMotor_process_1_create`
  WHERE OrderItem = 'L80570468-1'
  UNION ALL SELECT 'RCB_NonMotor_process_2_cancel', 'INTERFACE', COUNT(*)
  FROM `pacific-plating-282708.sap_view.RCB_NonMotor_process_2_cancel`
  WHERE OrderItem = 'L80570468-1'
  UNION ALL SELECT 'RCL_NonMotor_process_1_create', 'INTERFACE', COUNT(*)
  FROM `pacific-plating-282708.sap_view.RCL_NonMotor_process_1_create`
  WHERE OrderItem = 'L80570468-1'
  UNION ALL SELECT 'RCL_NonMotor_process_2_newpayment', 'INTERFACE', COUNT(*)
  FROM `pacific-plating-282708.sap_view.RCL_NonMotor_process_2_newpayment`
  WHERE OrderItem = 'L80570468-1'
)
SELECT
  CURRENT_TIMESTAMP() AS checked_at_utc,
  IF(SUM(row_count) = 0, 'RED_ABSENT_FROM_SAP_AND_ALL_INTERFACES', 'GREEN_FOUND') AS verdict,
  SUM(IF(evidence_layer = 'SAP', row_count, 0)) AS sap_rows,
  SUM(IF(evidence_layer = 'INTERFACE', row_count, 0)) AS interface_rows,
  ARRAY_AGG(STRUCT(object_name, evidence_layer, row_count) ORDER BY evidence_layer, object_name)
    AS object_evidence
FROM evidence;

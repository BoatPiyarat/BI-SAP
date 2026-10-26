-- Read-only trace for the one Health row not covered by the NonMotor new-payment view.

WITH
motor_row AS (
  SELECT 'RCL_Motor_process_2_newpayment' AS source_name,
    OrderID, OrderItem, CAST(Period AS STRING) AS Period,
    CAST(TotalPeriods AS STRING) AS TotalPeriods, InvoiceNo, TransactionStatus,
    CAST(ExpectedReceived AS STRING) AS ExpectedReceived,
    CAST(ActualReceived AS STRING) AS ActualReceived,
    PaymentDate, PaymentMethod, PaymentChannel, InsuranceGroup, InsuranceType
  FROM `pacific-plating-282708.sap_view.RCL_Motor_process_2_newpayment`
  WHERE OrderItem = 'L79361308-1'
),
nonmotor_row AS (
  SELECT 'RCL_NonMotor_process_2_newpayment' AS source_name,
    OrderID, OrderItem, CAST(Period AS STRING) AS Period,
    CAST(TotalPeriods AS STRING) AS TotalPeriods, InvoiceNo, TransactionStatus,
    CAST(ExpectedReceived AS STRING) AS ExpectedReceived,
    CAST(ActualReceived AS STRING) AS ActualReceived,
    PaymentDate, PaymentMethod, PaymentChannel, InsuranceGroup, InsuranceType
  FROM `pacific-plating-282708.sap_view.RCL_NonMotor_process_2_newpayment`
  WHERE OrderItem = 'L79361308-1'
),
rcl_health AS (
  SELECT 'RCL_HEALTH' AS source_name,
    OrderID, OrderItem, CAST(Period AS STRING) AS Period,
    CAST(TotalPeriods AS STRING) AS TotalPeriods, InvoiceNo, TransactionStatus,
    CAST(ExpectedReceived AS STRING) AS ExpectedReceived,
    CAST(ActualReceived AS STRING) AS ActualReceived,
    PaymentDate, PaymentMethod, PaymentChannel, InsuranceGroup, InsuranceType
  FROM `pacific-plating-282708.sap_data_engineer.RCL_HEALTH`
  WHERE OrderItem = 'L79361308-1'
),
rcl_paid AS (
  SELECT 'RCL 05_paid' AS source_name,
    OrderID, OrderItem, CAST(Period AS STRING) AS Period,
    CAST(TotalPeriods AS STRING) AS TotalPeriods, InvoiceNo, TransactionStatus,
    CAST(ExpectedReceived AS STRING) AS ExpectedReceived,
    CAST(ActualReceived AS STRING) AS ActualReceived,
    PaymentDate, PaymentMethod, PaymentChannel, InsuranceGroup, InsuranceType
  FROM `pacific-plating-282708.sap_integration_v2.RCL 05_paid`
  WHERE OrderItem = 'L79361308-1'
),
rcl_newpayment AS (
  SELECT 'RCL 05_newpayment' AS source_name,
    OrderID, OrderItem, CAST(Period AS STRING) AS Period,
    CAST(TotalPeriods AS STRING) AS TotalPeriods, InvoiceNo, TransactionStatus,
    CAST(ExpectedReceived AS STRING) AS ExpectedReceived,
    CAST(ActualReceived AS STRING) AS ActualReceived,
    PaymentDate, PaymentMethod, PaymentChannel, InsuranceGroup, InsuranceType
  FROM `pacific-plating-282708.sap_integration_v2.RCL 05_newpayment`
  WHERE OrderItem = 'L79361308-1'
),
combined_rows AS (
  SELECT * FROM motor_row
  UNION ALL SELECT * FROM nonmotor_row
  UNION ALL SELECT * FROM rcl_health
  UNION ALL SELECT * FROM rcl_paid
  UNION ALL SELECT * FROM rcl_newpayment
),
sap_rows AS (
  SELECT
    U_OrderID AS OrderID,
    U_OrderItem AS OrderItem,
    CAST(U_Period AS STRING) AS Period,
    CAST(TotalPeriods AS STRING) AS TotalPeriods,
    U_InvoiceNo AS InvoiceNo,
    TransactionStatus,
    CAST(ExpectedReceived AS STRING) AS ExpectedReceived,
    CAST(U_ActualReceived AS STRING) AS ActualReceived,
    PaymentDate,
    PaymentMethod,
    PaymentChannel,
    U_InsuranceGroup AS InsuranceGroup,
    U_InsuranceType AS InsuranceType,
    BatchRunDate,
    UpdateDate
  FROM `pacific-plating-282708.sap_integration_v2.SAP_LIVE_FULL`
  WHERE U_OrderItem = 'L79361308-1'
),
view_presence AS (
  SELECT 'RCB_Motor_process_2_cancel_new' AS view_name, COUNT(*) AS rows_found
  FROM `pacific-plating-282708.sap_view.RCB_Motor_process_2_cancel_new` WHERE OrderItem = 'L79361308-1'
  UNION ALL SELECT 'RCB_Motor_process_3_change', COUNT(*) FROM `pacific-plating-282708.sap_view.RCB_Motor_process_3_change` WHERE OrderItem = 'L79361308-1'
  UNION ALL SELECT 'RCB_Motor_process_4_creditshell', COUNT(*) FROM `pacific-plating-282708.sap_view.RCB_Motor_process_4_creditshell` WHERE OrderItem = 'L79361308-1'
  UNION ALL SELECT 'RCB_Motor_process_create', COUNT(*) FROM `pacific-plating-282708.sap_view.RCB_Motor_process_create` WHERE OrderItem = 'L79361308-1'
  UNION ALL SELECT 'RCB_NonMotor_process_1_create', COUNT(*) FROM `pacific-plating-282708.sap_view.RCB_NonMotor_process_1_create` WHERE OrderItem = 'L79361308-1'
  UNION ALL SELECT 'RCB_NonMotor_process_2_cancel', COUNT(*) FROM `pacific-plating-282708.sap_view.RCB_NonMotor_process_2_cancel` WHERE OrderItem = 'L79361308-1'
  UNION ALL SELECT 'RCL_Motor_process_1_create', COUNT(*) FROM `pacific-plating-282708.sap_view.RCL_Motor_process_1_create` WHERE OrderItem = 'L79361308-1'
  UNION ALL SELECT 'RCL_Motor_process_2_newpayment', COUNT(*) FROM `pacific-plating-282708.sap_view.RCL_Motor_process_2_newpayment` WHERE OrderItem = 'L79361308-1'
  UNION ALL SELECT 'RCL_Motor_process_3_cancel', COUNT(*) FROM `pacific-plating-282708.sap_view.RCL_Motor_process_3_cancel` WHERE OrderItem = 'L79361308-1'
  UNION ALL SELECT 'RCL_Motor_process_4_creditshell', COUNT(*) FROM `pacific-plating-282708.sap_view.RCL_Motor_process_4_creditshell` WHERE OrderItem = 'L79361308-1'
  UNION ALL SELECT 'RCL_NonMotor_process_1_create', COUNT(*) FROM `pacific-plating-282708.sap_view.RCL_NonMotor_process_1_create` WHERE OrderItem = 'L79361308-1'
  UNION ALL SELECT 'RCL_NonMotor_process_2_newpayment', COUNT(*) FROM `pacific-plating-282708.sap_view.RCL_NonMotor_process_2_newpayment` WHERE OrderItem = 'L79361308-1'
)

SELECT
  ARRAY(SELECT AS STRUCT * FROM combined_rows ORDER BY source_name, SAFE_CAST(Period AS INT64)) AS source_rows,
  ARRAY(SELECT AS STRUCT * FROM sap_rows ORDER BY SAFE_CAST(Period AS INT64), UpdateDate) AS sap_rows,
  ARRAY(SELECT AS STRUCT * FROM view_presence WHERE rows_found > 0 ORDER BY view_name) AS sap_view_presence,
  (SELECT COUNT(*) FROM `pacific-plating-282708.sap_integration_v2.RCL 05_paid by period`
   WHERE order_item = 'L79361308-1') AS paid_by_period_gate_rows;

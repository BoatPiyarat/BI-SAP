-- Source only / Class A. Builds a fail-closed July-only 56-column shadow; it does NOT write GCS.
-- Boat 2026-08-01: raw PaymentDate scope is [2026-07-01, 2026-08-01), never August; delivery
-- folder is temporarily RCB_MOTOR for all output. Deploy/run/export require separate reviewed gates.
-- Source-view BatchRunDate is execution-dated and normally tied, so the normalized content hash is
-- the effective duplicate winner. It is deterministic, not a claim that the chosen row is newest.

CREATE TABLE IF NOT EXISTS `pacific-plating-282708.sap_integration_v3.export_archive` (
  export_run_id STRING,
  order_item STRING,
  period INT64,
  charge_id STRING,
  raw_payment_date DATE,
  file_name STRING,
  gcs_uri STRING,
  archive_uri STRING,
  delivery_folder STRING,
  contract_version STRING,
  payload_hash STRING,
  payload_json STRING,
  run_type STRING,
  delivery_status STRING,
  object_generation STRING,
  file_sha256 STRING,
  uat2_status STRING,
  exported_at TIMESTAMP,
  sap_log_id STRING,
  sap_result_status STRING,
  acknowledged_at TIMESTAMP
)
PARTITION BY DATE(exported_at)
CLUSTER BY order_item, period, export_run_id;

CREATE TABLE IF NOT EXISTS `pacific-plating-282708.sap_integration_v3.export_file_manifest` (
  export_run_id STRING,
  archive_uri STRING,
  production_uri STRING,
  archive_generation STRING,
  production_generation STRING,
  sha256 STRING,
  size_bytes INT64,
  header_column_count INT64,
  data_row_count INT64,
  event_identity_count INT64,
  uat2_status STRING,
  uat2_accepted_by STRING,
  uat2_accepted_at TIMESTAMP,
  delivery_status STRING,
  recorded_at TIMESTAMP
)
CLUSTER BY export_run_id, delivery_status;

ALTER TABLE `pacific-plating-282708.sap_integration_v3.export_file_manifest`
ADD COLUMN IF NOT EXISTS event_identity_count INT64;

CREATE TABLE IF NOT EXISTS `pacific-plating-282708.sap_integration_v3.july_export_hold` (
  order_item STRING,
  period INT64,
  charge_id STRING,
  raw_payment_date DATE,
  hold_reason STRING,
  detected_at TIMESTAMP
)
PARTITION BY raw_payment_date
CLUSTER BY hold_reason, order_item;

CREATE OR REPLACE PROCEDURE `pacific-plating-282708.sap_integration_v3.sp_build_july_export_shadow`()
BEGIN
  DECLARE open_period_start DATE;
  DECLARE gap_count INT64;
  DECLARE duplicate_count INT64;
  DECLARE august_count INT64;

  ASSERT (SELECT COUNT(*) FROM `pacific-plating-282708.sap_integration_v3.sap_period_lock`
    WHERE lock_datetime > CURRENT_TIMESTAMP()) = 1
    AS 'July export requires exactly one active sap_period_lock row';

  SET open_period_start = (SELECT open_period_start
    FROM `pacific-plating-282708.sap_integration_v3.sap_period_lock`
    WHERE lock_datetime > CURRENT_TIMESTAMP());
  ASSERT open_period_start = DATE '2026-07-01'
    AS 'This release is July-only; active open_period_start must be 2026-07-01';

  CREATE TEMP TABLE _eligible_all AS
  SELECT e.*, DATE(pe.charge_time) AS raw_payment_date,
    EXISTS (SELECT 1 FROM `pacific-plating-282708.careos.cancelled_change_orders` cco
      WHERE cco.current_human_id=e.order_id) AS is_change_order
  FROM `pacific-plating-282708.sap_integration_v3.expected_state` e
  JOIN `pacific-plating-282708.sap_integration_v3.stg_payment_events` pe USING (charge_id)
  -- Direct qualification is required for this historical July close. 013 is incremental and
  -- cannot retroactively remove pre-deploy unqualified charges already present in staging.
  JOIN `pacific-plating-282708.careos.careos_orders` co ON co.human_id=e.order_id
  JOIN `pacific-plating-282708.careos.careos_order_items` coi
    ON coi.order_id=co.id AND coi.human_id=e.order_item
  JOIN `pacific-plating-282708.careos.careos_leads` cl
    ON CONCAT('leads/',cl.id)=co.lead AND cl.status='LEAD_STATUS_PURCHASED'
  LEFT JOIN `pacific-plating-282708.sap_integration_v3.export_archive` a
    ON a.charge_id=e.charge_id AND a.order_item=e.order_item AND a.period=e.period
   AND a.delivery_status IN ('DELIVERED','ACKNOWLEDGED')
  WHERE e.expected_status='Paid'
    AND DATE(pe.charge_time) >= DATE '2026-07-01'
    AND DATE(pe.charge_time) < DATE '2026-08-01'
    AND a.charge_id IS NULL;

  CREATE TEMP TABLE _payload_source AS
  SELECT * FROM (
    SELECT s.*, ROW_NUMBER() OVER (
      PARTITION BY OrderItem, SAFE_CAST(Period AS INT64)
      ORDER BY SAFE.PARSE_DATE('%d%m%Y', NULLIF(CAST(BatchRunDate AS STRING), '')) DESC,
        FARM_FINGERPRINT(TO_JSON_STRING(s)) DESC
    ) AS _rn
    FROM (
      SELECT
        CAST(CompanyDB AS STRING) CompanyDB, CAST(OrderID AS STRING) OrderID,
        CAST(OrderItem AS STRING) OrderItem, CAST(InvoiceNo AS STRING) InvoiceNo,
        CAST(OrderDate AS STRING) OrderDate, CAST(InsuredID AS STRING) InsuredID,
        CAST(Title AS STRING) Title, CAST(FirstName AS STRING) FirstName,
        CAST(LastName AS STRING) LastName, CAST(InsurerCode AS STRING) InsurerCode,
        CAST(InsuranceGroup AS STRING) InsuranceGroup, CAST(InsuranceType AS STRING) InsuranceType,
        CAST(InsuranceProduct AS STRING) InsuranceProduct, CAST(ProductType AS STRING) ProductType,
        CAST(PolicyType AS STRING) PolicyType, CAST(Endorse AS STRING) Endorse,
        CAST(PolicyDate AS STRING) PolicyDate, CAST(PolicyNo AS STRING) PolicyNo,
        CAST(EndorsementNo AS STRING) EndorsementNo, CAST(ChassisNo AS STRING) ChassisNo,
        CAST(LicensePlate AS STRING) LicensePlate, SAFE_CAST(GrossPremium AS FLOAT64) GrossPremium,
        SAFE_CAST(StampDuty AS FLOAT64) StampDuty, SAFE_CAST(VAT AS FLOAT64) VAT,
        SAFE_CAST(TotalPremium AS FLOAT64) TotalPremium, SAFE_CAST(WHT AS FLOAT64) WHT,
        SAFE_CAST(TotalEIR AS FLOAT64) TotalEIR, SAFE_CAST(TotalSBT AS FLOAT64) TotalSBT,
        SAFE_CAST(ProcessingFee AS FLOAT64) ProcessingFee,
        SAFE_CAST(ProcessingFeeVat AS FLOAT64) ProcessingFeeVat,
        SAFE_CAST(ShippingFee AS FLOAT64) ShippingFee,
        SAFE_CAST(ShippingFeeVat AS FLOAT64) ShippingFeeVat,
        SAFE_CAST(TotalAmount AS FLOAT64) TotalAmount, SAFE_CAST(Discount AS FLOAT64) Discount,
        CAST(TransactionStatus AS STRING) TransactionStatus,
        CAST(SubmissionStatus AS STRING) SubmissionStatus,
        CAST(ApprovalStatus AS STRING) ApprovalStatus, CAST(PaymentStatus AS STRING) PaymentStatus,
        SAFE_CAST(ExpectedReceived AS FLOAT64) ExpectedReceived,
        SAFE_CAST(ActualReceived AS FLOAT64) ActualReceived,
        SAFE_CAST(InterestThisPeriod AS FLOAT64) InterestThisPeriod,
        SAFE_CAST(PrincipleThisPeriod AS FLOAT64) PrincipleThisPeriod,
        SAFE_CAST(InterestEIRThisPeriod AS FLOAT64) InterestEIRThisPeriod,
        SAFE_CAST(PrincipleEIRThisPeriod AS FLOAT64) PrincipleEIRThisPeriod,
        CAST(PaymentDate AS STRING) PaymentDate, SAFE_CAST(Period AS INT64) Period,
        SAFE_CAST(TotalPeriods AS INT64) TotalPeriods, CAST(PendingPayment AS STRING) PendingPayment,
        CAST(PaymentMethod AS STRING) PaymentMethod, CAST(PaymentChannel AS STRING) PaymentChannel,
        CAST(ExpectedDate AS STRING) ExpectedDate, CAST(RefOrder AS STRING) RefOrder,
        SAFE_CAST(RefundAmountBeforeFee AS FLOAT64) RefundAmountBeforeFee,
        SAFE_CAST(RefundAmountAfterFee AS FLOAT64) RefundAmountAfterFee,
        CAST(BillingAddress AS STRING) BillingAddress, CAST(BatchRunDate AS STRING) BatchRunDate
      FROM `pacific-plating-282708.sap_integration_v3.vw_onetime_payload_source`
      UNION ALL
      SELECT
        CAST(CompanyDB AS STRING), CAST(OrderID AS STRING), CAST(OrderItem AS STRING),
        CAST(InvoiceNo AS STRING), CAST(OrderDate AS STRING), CAST(InsuredID AS STRING),
        CAST(Title AS STRING), CAST(FirstName AS STRING), CAST(LastName AS STRING),
        CAST(InsurerCode AS STRING), CAST(InsuranceGroup AS STRING), CAST(InsuranceType AS STRING),
        CAST(InsuranceProduct AS STRING), CAST(ProductType AS STRING), CAST(PolicyType AS STRING),
        CAST(Endorse AS STRING), CAST(PolicyDate AS STRING), CAST(PolicyNo AS STRING),
        CAST(EndorsementNo AS STRING), CAST(ChassisNo AS STRING), CAST(LicensePlate AS STRING),
        SAFE_CAST(GrossPremium AS FLOAT64), SAFE_CAST(StampDuty AS FLOAT64), SAFE_CAST(VAT AS FLOAT64),
        SAFE_CAST(TotalPremium AS FLOAT64), SAFE_CAST(WHT AS FLOAT64), SAFE_CAST(TotalEIR AS FLOAT64),
        SAFE_CAST(TotalSBT AS FLOAT64), SAFE_CAST(ProcessingFee AS FLOAT64),
        SAFE_CAST(ProcessingFeeVat AS FLOAT64), SAFE_CAST(ShippingFee AS FLOAT64),
        SAFE_CAST(ShippingFeeVat AS FLOAT64), SAFE_CAST(TotalAmount AS FLOAT64),
        SAFE_CAST(Discount AS FLOAT64), CAST(TransactionStatus AS STRING),
        CAST(SubmissionStatus AS STRING), CAST(ApprovalStatus AS STRING), CAST(PaymentStatus AS STRING),
        SAFE_CAST(ExpectedReceived AS FLOAT64), SAFE_CAST(ActualReceived AS FLOAT64),
        SAFE_CAST(InterestThisPeriod AS FLOAT64), SAFE_CAST(PrincipleThisPeriod AS FLOAT64),
        SAFE_CAST(InterestEIRThisPeriod AS FLOAT64), SAFE_CAST(PrincipleEIRThisPeriod AS FLOAT64),
        CAST(PaymentDate AS STRING), SAFE_CAST(Period AS INT64), SAFE_CAST(TotalPeriods AS INT64),
        CAST(PendingPayment AS STRING), CAST(PaymentMethod AS STRING), CAST(PaymentChannel AS STRING),
        CAST(ExpectedDate AS STRING), CAST(RefOrder AS STRING),
        SAFE_CAST(RefundAmountBeforeFee AS FLOAT64), SAFE_CAST(RefundAmountAfterFee AS FLOAT64),
        CAST(BillingAddress AS STRING), CAST(BatchRunDate AS STRING)
      FROM `pacific-plating-282708.sap_data_engineer.sap_dashboard_carepay_installment`
    ) s
  ) WHERE _rn=1;

  CREATE TEMP TABLE _coverage AS
  SELECT e.*,
    CASE
      WHEN e.is_change_order THEN 'CHANGE_ORDER_SEPARATE_FLOW'
      WHEN s.OrderItem IS NULL AND e.flow='RCL_CMI' THEN 'RCL_CMI_PAYLOAD_MISSING'
      WHEN s.OrderItem IS NULL THEN 'UNCLASSIFIED_PAYLOAD_GAP'
      ELSE NULL
    END AS hold_reason
  FROM _eligible_all e LEFT JOIN _payload_source s
    ON s.OrderItem=e.order_item AND SAFE_CAST(s.Period AS INT64)=e.period;

  ASSERT (SELECT COUNT(*) FROM _coverage WHERE hold_reason='UNCLASSIFIED_PAYLOAD_GAP')=0
    AS 'July eligible rows contain an unclassified 56-column payload gap';

  MERGE `pacific-plating-282708.sap_integration_v3.july_export_hold` t
  USING (SELECT order_item,period,charge_id,raw_payment_date,hold_reason FROM _coverage
    WHERE hold_reason IS NOT NULL) s
  ON t.order_item=s.order_item AND t.period=s.period AND t.charge_id=s.charge_id
     AND t.hold_reason=s.hold_reason
  WHEN MATCHED THEN UPDATE SET detected_at=CURRENT_TIMESTAMP()
  WHEN NOT MATCHED THEN INSERT
    (order_item,period,charge_id,raw_payment_date,hold_reason,detected_at)
  VALUES (s.order_item,s.period,s.charge_id,s.raw_payment_date,s.hold_reason,CURRENT_TIMESTAMP());

  CREATE TEMP TABLE _eligible AS
  SELECT * EXCEPT(is_change_order,hold_reason) FROM _coverage WHERE hold_reason IS NULL;

  ASSERT (SELECT COUNT(*) FROM _eligible)+(SELECT COUNT(*) FROM _coverage WHERE hold_reason IS NOT NULL)
    =(SELECT COUNT(*) FROM _eligible_all)
    AS 'July population conservation failed: eligible_all must equal export plus audited hold';

  SET duplicate_count = (SELECT COUNT(*) FROM (
    SELECT OrderItem, SAFE_CAST(Period AS INT64), COUNT(*) n
    FROM _payload_source GROUP BY 1,2 HAVING n>1));
  ASSERT duplicate_count=0 AS 'Deterministic source winner failed to reach one row per key';

  SET gap_count = (SELECT COUNT(*) FROM _eligible e LEFT JOIN _payload_source s
    ON s.OrderItem=e.order_item AND SAFE_CAST(s.Period AS INT64)=e.period
    WHERE s.OrderItem IS NULL);
  ASSERT gap_count=0 AS 'July eligible rows lack a verified 56-column payload source';

  CREATE TEMP TABLE _july_export_candidate AS
  SELECT
    CAST(s.CompanyDB AS STRING) CompanyDB, CAST(s.OrderID AS STRING) OrderID,
    CAST(s.OrderItem AS STRING) OrderItem, CAST(e.expected_invoice_no AS STRING) InvoiceNo,
    CAST(s.OrderDate AS STRING) OrderDate, COALESCE(NULLIF(TRIM(CAST(s.InsuredID AS STRING)),''),'-') InsuredID,
    CAST(s.Title AS STRING) Title, CAST(s.FirstName AS STRING) FirstName, CAST(s.LastName AS STRING) LastName,
    CAST(s.InsurerCode AS STRING) InsurerCode, CAST(s.InsuranceGroup AS STRING) InsuranceGroup,
    CAST(s.InsuranceType AS STRING) InsuranceType, CAST(s.InsuranceProduct AS STRING) InsuranceProduct,
    CAST(s.ProductType AS STRING) ProductType, CAST(s.PolicyType AS STRING) PolicyType,
    CAST(s.Endorse AS STRING) Endorse, CAST(s.PolicyDate AS STRING) PolicyDate,
    CAST(s.PolicyNo AS STRING) PolicyNo, CAST(s.EndorsementNo AS STRING) EndorsementNo,
    CAST(s.ChassisNo AS STRING) ChassisNo, CAST(s.LicensePlate AS STRING) LicensePlate,
    FORMAT('%.2f',SAFE_CAST(s.GrossPremium AS FLOAT64)) GrossPremium,
    FORMAT('%.2f',SAFE_CAST(s.StampDuty AS FLOAT64)) StampDuty,
    FORMAT('%.2f',SAFE_CAST(s.VAT AS FLOAT64)) VAT,
    FORMAT('%.2f',SAFE_CAST(s.TotalPremium AS FLOAT64)) TotalPremium,
    FORMAT('%.2f',SAFE_CAST(s.WHT AS FLOAT64)) WHT,
    FORMAT('%.2f',SAFE_CAST(s.TotalEIR AS FLOAT64)) TotalEIR,
    FORMAT('%.2f',SAFE_CAST(s.TotalSBT AS FLOAT64)) TotalSBT,
    FORMAT('%.2f',SAFE_CAST(s.ProcessingFee AS FLOAT64)) ProcessingFee,
    FORMAT('%.2f',SAFE_CAST(s.ProcessingFeeVat AS FLOAT64)) ProcessingFeeVat,
    FORMAT('%.2f',SAFE_CAST(s.ShippingFee AS FLOAT64)) ShippingFee,
    FORMAT('%.2f',SAFE_CAST(s.ShippingFeeVat AS FLOAT64)) ShippingFeeVat,
    FORMAT('%.2f',SAFE_CAST(s.TotalAmount AS FLOAT64)) TotalAmount,
    FORMAT('%.2f',SAFE_CAST(s.Discount AS FLOAT64)) Discount,
    'Paid' TransactionStatus, CAST(s.SubmissionStatus AS STRING) SubmissionStatus,
    CAST(s.ApprovalStatus AS STRING) ApprovalStatus, CAST(s.PaymentStatus AS STRING) PaymentStatus,
    FORMAT('%.2f',SAFE_CAST(s.ExpectedReceived AS FLOAT64)) ExpectedReceived,
    FORMAT('%.2f',SAFE_CAST(s.ActualReceived AS FLOAT64)) ActualReceived,
    FORMAT('%.2f',SAFE_CAST(s.InterestThisPeriod AS FLOAT64)) InterestThisPeriod,
    FORMAT('%.2f',SAFE_CAST(s.PrincipleThisPeriod AS FLOAT64)) PrincipleThisPeriod,
    FORMAT('%.2f',SAFE_CAST(s.InterestEIRThisPeriod AS FLOAT64)) InterestEIRThisPeriod,
    FORMAT('%.2f',SAFE_CAST(s.PrincipleEIRThisPeriod AS FLOAT64)) PrincipleEIRThisPeriod,
    FORMAT_DATE('%d%m%Y',e.expected_payment_date) PaymentDate,
    CAST(e.period AS STRING) Period, CAST(e.total_periods AS STRING) TotalPeriods,
    CAST(s.PendingPayment AS STRING) PendingPayment, CAST(s.PaymentMethod AS STRING) PaymentMethod,
    CAST(s.PaymentChannel AS STRING) PaymentChannel, CAST(s.ExpectedDate AS STRING) ExpectedDate,
    CAST(s.RefOrder AS STRING) RefOrder,
    FORMAT('%.2f',SAFE_CAST(s.RefundAmountBeforeFee AS FLOAT64)) RefundAmountBeforeFee,
    FORMAT('%.2f',SAFE_CAST(s.RefundAmountAfterFee AS FLOAT64)) RefundAmountAfterFee,
    CAST(s.BillingAddress AS STRING) BillingAddress,
    FORMAT_DATE('%d%m%Y',LAST_DAY(open_period_start)) BatchRunDate
  FROM _eligible e JOIN _payload_source s
    ON s.OrderItem=e.order_item AND SAFE_CAST(s.Period AS INT64)=e.period;

  CREATE TEMP TABLE _contract_invalid AS
  SELECT DISTINCT OrderItem,SAFE_CAST(Period AS INT64) period,'POLICYNO_TOO_LONG' hold_reason
  FROM _july_export_candidate WHERE LENGTH(PolicyNo)>50
  UNION DISTINCT
  SELECT DISTINCT OrderItem,SAFE_CAST(Period AS INT64),'PAID_COMPLETENESS'
  FROM _july_export_candidate
  WHERE NULLIF(TRIM(InvoiceNo),'') IS NULL OR NULLIF(TRIM(PaymentDate),'') IS NULL
     OR NULLIF(TRIM(PaymentMethod),'') IS NULL OR NULLIF(TRIM(PaymentChannel),'') IS NULL
  UNION DISTINCT
  SELECT DISTINCT OrderItem,SAFE_CAST(Period AS INT64),'DATE_FORMAT_INVALID'
  FROM _july_export_candidate
  UNPIVOT(date_value FOR date_column IN
    (OrderDate,PolicyDate,PaymentDate,ExpectedDate,BatchRunDate))
  WHERE NOT(IFNULL(date_value,'')='' OR
    (LENGTH(date_value)=8 AND SAFE.PARSE_DATE('%d%m%Y',date_value) IS NOT NULL));

  MERGE `pacific-plating-282708.sap_integration_v3.july_export_hold` t
  USING (
    SELECT e.order_item,e.period,e.charge_id,e.raw_payment_date,i.hold_reason
    FROM _eligible e JOIN _contract_invalid i
      ON i.OrderItem=e.order_item AND i.period=e.period
  ) s
  ON t.order_item=s.order_item AND t.period=s.period AND t.charge_id=s.charge_id
     AND t.hold_reason=s.hold_reason
  WHEN MATCHED THEN UPDATE SET detected_at=CURRENT_TIMESTAMP()
  WHEN NOT MATCHED THEN INSERT
    (order_item,period,charge_id,raw_payment_date,hold_reason,detected_at)
  VALUES (s.order_item,s.period,s.charge_id,s.raw_payment_date,s.hold_reason,CURRENT_TIMESTAMP());

  CREATE OR REPLACE TABLE `pacific-plating-282708.sap_integration_v3.july_export_ready` AS
  SELECT c.* FROM _july_export_candidate c
  WHERE NOT EXISTS (SELECT 1 FROM _contract_invalid i
    WHERE i.OrderItem=c.OrderItem AND i.period=SAFE_CAST(c.Period AS INT64));

  ASSERT (SELECT COUNT(*) FROM _eligible_all)=
    (SELECT COUNT(*) FROM `pacific-plating-282708.sap_integration_v3.july_export_ready`)+
    (SELECT COUNT(*) FROM _coverage WHERE hold_reason IS NOT NULL)+
    (SELECT COUNT(*) FROM (SELECT DISTINCT OrderItem,period FROM _contract_invalid))
    AS 'Final July conservation failed: eligible_all must equal ready plus all held keys';

  SET august_count = (SELECT COUNT(*) FROM _eligible WHERE raw_payment_date >= DATE '2026-08-01');
  ASSERT august_count=0 AS 'August raw PaymentDate leaked into July export scope';
  ASSERT (SELECT COUNT(*) FROM `pacific-plating-282708.sap_integration_v3.INFORMATION_SCHEMA.COLUMNS`
    WHERE table_name='july_export_ready')=56 AS 'SAP interface payload must contain exactly 56 columns';
  ASSERT (SELECT COUNT(*) FROM `pacific-plating-282708.sap_integration_v3.july_export_ready`
    WHERE NULLIF(TRIM(InvoiceNo),'') IS NULL OR NULLIF(TRIM(PaymentDate),'') IS NULL
       OR NULLIF(TRIM(PaymentMethod),'') IS NULL OR NULLIF(TRIM(PaymentChannel),'') IS NULL)=0
    AS 'Paid completeness failed: InvoiceNo/PaymentDate/PaymentMethod/PaymentChannel must be non-empty';
  ASSERT (SELECT COUNT(*) FROM `pacific-plating-282708.sap_integration_v3.july_export_ready`
    WHERE LENGTH(PolicyNo)>50)=0
    AS 'POLICYNO_TOO_LONG: July payload contains PolicyNo longer than 50 characters';
  ASSERT (SELECT COUNT(*) FROM (
    SELECT OrderItem, date_value
    FROM `pacific-plating-282708.sap_integration_v3.july_export_ready`
    UNPIVOT(date_value FOR date_column IN
      (OrderDate, PolicyDate, PaymentDate, ExpectedDate, BatchRunDate))
    WHERE NOT (IFNULL(date_value,'')='' OR
      (LENGTH(date_value)=8 AND SAFE.PARSE_DATE('%d%m%Y',date_value) IS NOT NULL))))=0
    AS 'DATE_FORMAT_INVALID: July payload date must be empty or valid DDMMYYYY';
  ASSERT (SELECT COUNT(*) FROM `pacific-plating-282708.sap_integration_v3.july_export_ready`
    WHERE NULLIF(TRIM(BatchRunDate),'') IS NULL
       OR SAFE.PARSE_DATE('%d%m%Y',BatchRunDate) IS NULL
       OR SAFE.PARSE_DATE('%d%m%Y',BatchRunDate)>DATE '2026-07-31')=0
    AS 'BatchRunDate must be non-empty DDMMYYYY and no later than 31072026';
END;

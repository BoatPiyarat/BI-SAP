-- Class A source: read-only preparation/gate for URGENT-REFUND-CANCEL-20260822.
-- No persistent table and no GCS write. Production export is a separate reviewed step.
DECLARE v_batch_date STRING DEFAULT FORMAT_DATE('%d%m%Y', CURRENT_DATE('Asia/Bangkok'));

CREATE TEMP TABLE _scope AS
SELECT order_item FROM UNNEST([
  'L78551615-V1','L80451154-V1','L80482628-V1',
  'L80545799-V1','L80546987-V1','L80562453-V1'
]) order_item;

CREATE TEMP TABLE _source AS
SELECT m.*
FROM `pacific-plating-282708.sap_integration_v3.sap_mirror_state` m
JOIN _scope s ON s.order_item=m.U_OrderItem;

ASSERT (SELECT COUNT(*) FROM _source)=47 AS 'expected exact 47-row full-spine source';
ASSERT (SELECT COUNT(DISTINCT U_OrderItem) FROM _source)=6 AS 'expected exact six items';
ASSERT (SELECT COUNT(*) FROM (
  SELECT U_OrderItem,COUNT(*) row_n,COUNT(DISTINCT U_Period) period_n,MIN(U_Period) min_p,
    MAX(U_Period) max_p,COUNT(DISTINCT TotalPeriods) total_versions,MAX(TotalPeriods) total_n
  FROM _source GROUP BY U_OrderItem
  HAVING row_n!=total_n OR period_n!=total_n OR min_p!=1 OR max_p!=total_n OR total_versions!=1
))=0 AS 'source is not a complete unique 1..TotalPeriods spine';
ASSERT (SELECT COUNT(*) FROM _source WHERE docs_considered!=1)=0
  AS 'multi-document winner needs Aware decision';
ASSERT (SELECT COUNT(*) FROM _source
  WHERE TransactionStatus NOT IN ('Paid','paid','Pending'))=0
  AS 'source predecessor must be Paid or Pending';
ASSERT (SELECT COUNT(*) FROM _source
  WHERE TransactionStatus IN ('Paid','paid')
    AND (NULLIF(TRIM(U_InvoiceNo),'') IS NULL OR NULLIF(TRIM(PaymentDate),'') IS NULL))=0
  AS 'Paid predecessor needs immutable InvoiceNo and PaymentDate';
ASSERT (SELECT COUNT(*)
  FROM _scope s
  LEFT JOIN `pacific-plating-282708.careos.careos_order_items` i ON i.human_id=s.order_item
  WHERE i.human_id IS NULL OR NOT (i.is_cancelled IS TRUE OR i.cancel_time IS NOT NULL))=0
  AS 'CareOS item-level cancellation changed';
ASSERT (SELECT COUNT(*)
  FROM _source m
  JOIN `pacific-plating-282708.sap_integration_v3.stg_payment_events` e
    ON e.order_item=m.U_OrderItem AND e.period=m.U_Period
   AND DATE(e.charge_time)>='2025-01-01'
  WHERE m.TransactionStatus='Pending')=0
  AS 'CareOS-paid/SAP-pending period requires Paid import and SAP ACK before cancel';
ASSERT (SELECT COUNT(*) FROM _scope s
  JOIN `pacific-plating-282708.careos.careos_order_items` i ON i.human_id=s.order_item
  JOIN `pacific-plating-282708.careos.careos_orders` o ON o.id=i.order_id
  JOIN `pacific-plating-282708.careos.cancelled_change_orders` c
    ON o.human_id IN (c.old_human_id,c.current_human_id))=0
  AS 'plain-cancel scope now intersects change-order routing';

CREATE TEMP TABLE _candidate AS
SELECT
  CompanyDB,
  U_OrderID AS OrderID,
  U_OrderItem AS OrderItem,
  COALESCE(NULLIF(U_InvoiceNo,'NULL'),'') AS InvoiceNo,
  OrderDate,
  U_InsuredID AS InsuredID,
  U_Title AS Title,
  U_FirstName AS FirstName,
  U_LastName AS LastName,
  SPLIT(U_InsurerCode,'-')[SAFE_OFFSET(1)] AS InsurerCode,
  U_InsuranceGroup AS InsuranceGroup,
  U_InsuranceType AS InsuranceType,
  U_InsuranceProduct AS InsuranceProduct,
  IF(U_ProductType='NULL','Insurance',U_ProductType) AS ProductType,
  U_PolicyType AS PolicyType,
  'N' AS Endorse,
  PolicyDate,
  U_PolicyNo AS PolicyNo,
  EndorsementNo,
  U_ChassisNo AS ChassisNo,
  U_LicensePlate AS LicensePlate,
  GrossPremium,StampDuty,VAT,TotalPremium,WHT,TotalEIR,TotalSBT,
  U_ProcessingFee AS ProcessingFee,
  U_ProcessingFeeVat AS ProcessingFeeVat,
  U_ShippingFee AS ShippingFee,
  U_ShippingFeeVat AS ShippingFeeVat,
  U_TotalAmount AS TotalAmount,
  U_Discount AS Discount,
  'Cancelled' AS TransactionStatus,
  U_SubmissionStatus AS SubmissionStatus,
  U_ApprovalStatus AS ApprovalStatus,
  U_PaymentStatus AS PaymentStatus,
  COALESCE(ExpectedReceived,0) AS ExpectedReceived,
  COALESCE(U_ActualReceived,0) AS ActualReceived,
  U_InterestThisPeriod AS InterestThisPeriod,
  U_PrincipleThisPeriod AS PrincipleThisPeriod,
  U_InterestEIRThisPeriod AS InterestEIRThisPeriod,
  U_PrincipleEIRThisPeriod AS PrincipleEIRThisPeriod,
  COALESCE(NULLIF(PaymentDate,'NULL'),'') AS PaymentDate,
  U_Period AS Period,
  TotalPeriods,
  PendingPayment,
  IF(TransactionStatus='Pending','',COALESCE(NULLIF(PaymentMethod,'NULL'),'')) AS PaymentMethod,
  IF(TransactionStatus='Pending','',COALESCE(NULLIF(PaymentChannel,'NULL'),'')) AS PaymentChannel,
  COALESCE(NULLIF(NULLIF(ExpectedDate,'NULL'),''),
    NULLIF(NULLIF(PaymentDate,'NULL'),''),v_batch_date) AS ExpectedDate,
  RefOrder,RefundAmountBeforeFee,RefundAmountAfterFee,BillingAddress,
  v_batch_date AS BatchRunDate
FROM _source;

ASSERT (SELECT COUNT(*) FROM _candidate)=47 AS 'candidate row conservation failed';
ASSERT (SELECT COUNT(*) FROM _candidate WHERE TransactionStatus!='Cancelled')=0
  AS 'plain cancel status invalid';
ASSERT (SELECT COUNT(*) FROM _candidate WHERE LENGTH(PolicyNo)>50)=0
  AS 'PolicyNo exceeds 50 characters';
ASSERT (SELECT COUNT(*) FROM _candidate
  WHERE InvoiceNo='NULL' OR PaymentDate='NULL' OR ExpectedDate IS NULL OR ExpectedDate=''
    OR SAFE.PARSE_DATE('%d%m%Y',ExpectedDate) IS NULL
    OR SAFE.PARSE_DATE('%d%m%Y',BatchRunDate) IS NULL)=0
  AS 'confirmed cancel date/NULL rules failed';

SELECT CURRENT_TIMESTAMP() checked_at,'URGENT-REFUND-CANCEL-20260822' request_id,
  COUNT(*) row_count,COUNT(DISTINCT OrderItem) item_count,
  TO_HEX(SHA256(STRING_AGG(TO_JSON_STRING(c),'\n' ORDER BY OrderItem,Period))) candidate_sha256,
  v_batch_date batch_run_date
FROM _candidate c;

SELECT CompanyDB,OrderID,OrderItem,InvoiceNo,OrderDate,InsuredID,Title,FirstName,LastName,
  InsurerCode,InsuranceGroup,InsuranceType,InsuranceProduct,ProductType,PolicyType,Endorse,
  PolicyDate,PolicyNo,EndorsementNo,ChassisNo,LicensePlate,GrossPremium,StampDuty,VAT,
  TotalPremium,WHT,TotalEIR,TotalSBT,ProcessingFee,ProcessingFeeVat,ShippingFee,ShippingFeeVat,
  TotalAmount,Discount,TransactionStatus,SubmissionStatus,ApprovalStatus,PaymentStatus,
  ExpectedReceived,ActualReceived,InterestThisPeriod,PrincipleThisPeriod,InterestEIRThisPeriod,
  PrincipleEIRThisPeriod,PaymentDate,Period,TotalPeriods,PendingPayment,PaymentMethod,
  PaymentChannel,ExpectedDate,RefOrder,RefundAmountBeforeFee,RefundAmountAfterFee,BillingAddress,
  BatchRunDate
FROM _candidate ORDER BY OrderItem,Period;

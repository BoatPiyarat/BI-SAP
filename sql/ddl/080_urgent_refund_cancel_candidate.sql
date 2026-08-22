-- SOURCE ONLY / Class A. Builds the shadow, immutable urgent-refund plain-cancel candidate for
-- the 6 items PASSed in Phase 1 (docs/tasks/TASK_URGENT_REFUND_PAID_CANCEL_20260821.md,
-- reviewed docs/reviews/2026-08-21-e5eefcd-claude.md). Does not write GCS. Does not CALL anything
-- mutating on its own — this is a plain top-to-bottom script, run once by whoever has deploy
-- authority, after its own dry-run and after this file passes Class-A review.
--
-- Scope: request_id 'URGENT-REFUND-CANCEL-20260822-PHASE2', exactly the 6 order_items:
--   L78551615-V1, L80451154-V1, L80482628-V1, L80545799-V1, L80546987-V1, L80562453-V1
-- Rule applied (Boat, 2026-08-21): CareOS item cancellation is definitive; a row is complete
-- only when SAP has the transaction Paid and subsequently Cancelled. This candidate proposes the
-- SAP-side Cancelled status for the still-open Pending tail of each item's already-Paid spine
-- (inferred rule R1, SAP_CANCEL_IMPORT_SPEC_INFERRED_v0.9.md: a cancel set must cover ALL periods
-- 1..TotalPeriods). Financial fields, InvoiceNo, and PaymentDate are mirrored verbatim from
-- sap_mirror_state, never recomputed — this deliberately avoids the unsafe legacy wide-source
-- cancel view (sql/production/RCL_02_items_cancel.sql), which re-derives premiums/fees fresh from
-- CareOS/CarePay instead of mirroring what SAP already has.
--
-- UPDATE 2026-08-22 (Boat relaying Aware, recorded in TASK_URGENT_REFUND_PAID_CANCEL_20260821.md
-- "Aware answers received"): the Q11 question this file originally could not resolve is now
-- confirmed -- for a never-paid period, preserve the existing SAP InvoiceNo and PaymentDate
-- verbatim (blank stays blank) even once status becomes Cancelled; NULL ActualReceived becomes
-- numeric 0. This file applies all three confirmed rules directly rather than gate on them.

DECLARE v_request_id STRING DEFAULT 'URGENT-REFUND-CANCEL-20260822-PHASE2';

CREATE TABLE IF NOT EXISTS `pacific-plating-282708.sap_integration_v3.urgent_refund_cancel_hold` (
  request_id STRING NOT NULL,
  order_item STRING NOT NULL,
  rule_code STRING NOT NULL,
  detail STRING NOT NULL,
  detected_at TIMESTAMP NOT NULL
)
CLUSTER BY request_id,rule_code,order_item;

CREATE TABLE IF NOT EXISTS `pacific-plating-282708.sap_integration_v3.urgent_refund_cancel_ready` (
  request_id STRING, CompanyDB STRING, OrderID STRING, OrderItem STRING, InvoiceNo STRING,
  OrderDate STRING, InsuredID STRING, Title STRING, FirstName STRING, LastName STRING,
  InsurerCode STRING, InsuranceGroup STRING, InsuranceType STRING, InsuranceProduct STRING,
  ProductType STRING, PolicyType STRING, Endorse STRING, PolicyDate STRING, PolicyNo STRING,
  EndorsementNo STRING, ChassisNo STRING, LicensePlate STRING, GrossPremium STRING,
  StampDuty STRING, VAT STRING, TotalPremium STRING, WHT STRING, TotalEIR STRING,
  TotalSBT STRING, ProcessingFee STRING, ProcessingFeeVat STRING, ShippingFee STRING,
  ShippingFeeVat STRING, TotalAmount STRING, Discount STRING, TransactionStatus STRING,
  SubmissionStatus STRING, ApprovalStatus STRING, PaymentStatus STRING, ExpectedReceived STRING,
  ActualReceived STRING, InterestThisPeriod STRING, PrincipleThisPeriod STRING,
  InterestEIRThisPeriod STRING, PrincipleEIRThisPeriod STRING, PaymentDate STRING, Period STRING,
  TotalPeriods STRING, PendingPayment STRING, PaymentMethod STRING, PaymentChannel STRING,
  ExpectedDate STRING, RefOrder STRING, RefundAmountBeforeFee STRING, RefundAmountAfterFee STRING,
  BillingAddress STRING, BatchRunDate STRING
);

CREATE TABLE IF NOT EXISTS `pacific-plating-282708.sap_integration_v3.urgent_refund_cancel_gate_manifest` (
  request_id STRING NOT NULL, row_count INT64 NOT NULL, item_count INT64 NOT NULL,
  hold_item_count INT64 NOT NULL, open_vendor_question_row_count INT64 NOT NULL,
  candidate_sha256 STRING NOT NULL, schema_sha256 STRING NOT NULL, built_at TIMESTAMP NOT NULL,
  gate_status STRING NOT NULL, gate_note STRING NOT NULL
)
CLUSTER BY request_id,gate_status;

-- ============================================================================
-- Run body starts here. Dry-run first. This is a one-time build for this exact
-- request_id; rerunning is refused if the request_id already has ready/hold rows.
-- ============================================================================

ASSERT (SELECT COUNT(*) FROM `pacific-plating-282708.sap_integration_v3.urgent_refund_cancel_ready`
  WHERE request_id=v_request_id)=0 AS 'this request_id already has ready rows';
ASSERT (SELECT COUNT(*) FROM `pacific-plating-282708.sap_integration_v3.urgent_refund_cancel_hold`
  WHERE request_id=v_request_id)=0 AS 'this request_id already has hold rows';

CREATE TEMP TABLE _scope AS
SELECT order_item FROM UNNEST([
  'L78551615-V1','L80451154-V1','L80482628-V1','L80545799-V1','L80546987-V1','L80562453-V1'
]) AS order_item;

ASSERT (SELECT COUNT(*) FROM _scope)=6 AS 'scope must be exactly the 6 reviewed Phase-1 candidates';

-- Re-derive eligibility live rather than trust the Phase-1 snapshot's freshness.
CREATE TEMP TABLE _careos AS
SELECT i.human_id AS order_item, o.human_id AS order_id,
  (i.is_cancelled IS TRUE OR i.cancel_time IS NOT NULL) AS careos_cancelled
FROM `pacific-plating-282708.careos.careos_order_items` AS i
JOIN `pacific-plating-282708.careos.careos_orders` AS o ON o.id=i.order_id
JOIN _scope AS s ON s.order_item=i.human_id;

CREATE TEMP TABLE _mirror AS
SELECT
  m.U_OrderItem AS order_item, m.CompanyDB, m.U_OrderID AS OrderID, m.OrderDate,
  m.U_InsuredID AS InsuredID, m.U_Title AS Title, m.U_FirstName AS FirstName,
  m.U_LastName AS LastName, m.U_InsurerCode AS InsurerCode,
  m.U_InsuranceGroup AS InsuranceGroup, m.U_InsuranceType AS InsuranceType,
  m.U_InsuranceProduct AS InsuranceProduct, m.U_ProductType AS ProductType,
  m.U_PolicyType AS PolicyType, m.U_Endorse AS Endorse, m.PolicyDate,
  m.U_PolicyNo AS PolicyNo, m.EndorsementNo, m.U_ChassisNo AS ChassisNo,
  m.U_LicensePlate AS LicensePlate, m.GrossPremium, m.StampDuty, m.VAT, m.TotalPremium,
  m.WHT, m.TotalEIR, m.TotalSBT, m.U_ProcessingFee AS ProcessingFee,
  m.U_ProcessingFeeVat AS ProcessingFeeVat, m.U_ShippingFee AS ShippingFee,
  m.U_ShippingFeeVat AS ShippingFeeVat, m.U_TotalAmount AS TotalAmount,
  m.U_Discount AS Discount, m.U_SubmissionStatus AS SubmissionStatus,
  m.U_ApprovalStatus AS ApprovalStatus, m.U_PaymentStatus AS PaymentStatus,
  COALESCE(m.ExpectedReceived,0) AS ExpectedReceived, COALESCE(m.U_ActualReceived,0) AS ActualReceived,
  m.U_InterestThisPeriod AS InterestThisPeriod, m.U_PrincipleThisPeriod AS PrincipleThisPeriod,
  m.U_InterestEIRThisPeriod AS InterestEIRThisPeriod,
  m.U_PrincipleEIRThisPeriod AS PrincipleEIRThisPeriod,
  COALESCE(NULLIF(TRIM(m.PaymentDate),''),'') AS PaymentDate,
  m.U_Period AS Period, m.TotalPeriods, m.PendingPayment,
  COALESCE(NULLIF(TRIM(m.U_InvoiceNo),''),'') AS InvoiceNo,
  m.ExpectedDate, m.RefOrder, m.RefundAmountBeforeFee, m.RefundAmountAfterFee,
  m.BillingAddress,
  FIRST_VALUE(NULLIF(TRIM(m.PaymentMethod),'') IGNORE NULLS)
    OVER (PARTITION BY m.U_OrderItem ORDER BY (NULLIF(TRIM(m.PaymentMethod),'') IS NULL), m.U_Period
      ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS PaymentMethod,
  FIRST_VALUE(NULLIF(TRIM(m.PaymentChannel),'') IGNORE NULLS)
    OVER (PARTITION BY m.U_OrderItem ORDER BY (NULLIF(TRIM(m.PaymentChannel),'') IS NULL), m.U_Period
      ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS PaymentChannel,
  COUNT(*) OVER (PARTITION BY m.U_OrderItem) AS sap_period_rows,
  COUNT(DISTINCT m.U_Period) OVER (PARTITION BY m.U_OrderItem) AS sap_distinct_periods,
  MIN(m.U_Period) OVER (PARTITION BY m.U_OrderItem) AS sap_min_period,
  MAX(m.U_Period) OVER (PARTITION BY m.U_OrderItem) AS sap_max_period,
  COUNT(DISTINCT m.TotalPeriods) OVER (PARTITION BY m.U_OrderItem) AS sap_total_period_values,
  COUNTIF(STARTS_WITH(m.TransactionStatus,'Cancelled')) OVER (PARTITION BY m.U_OrderItem) AS existing_cancelled_periods,
  COUNT(DISTINCT NULLIF(TRIM(m.PaymentMethod),'')) OVER (PARTITION BY m.U_OrderItem) AS distinct_payment_methods,
  COUNT(DISTINCT NULLIF(TRIM(m.PaymentChannel),'')) OVER (PARTITION BY m.U_OrderItem) AS distinct_payment_channels
FROM `pacific-plating-282708.sap_integration_v3.sap_mirror_state` AS m
JOIN _scope AS s ON s.order_item=m.U_OrderItem;

-- Item-level quarantine: hold anything that isn't exactly the confirmed clean shape.
INSERT INTO `pacific-plating-282708.sap_integration_v3.urgent_refund_cancel_hold`
  (request_id, order_item, rule_code, detail, detected_at)
SELECT v_request_id, order_item, rule_code, detail, CURRENT_TIMESTAMP()
FROM (
  SELECT s.order_item, 'CAREOS_NOT_CANCELLED' AS rule_code,
    'CareOS item is not cancelled per D1 (is_cancelled OR cancel_time)' AS detail
  FROM _scope s LEFT JOIN _careos c USING(order_item)
  WHERE COALESCE(c.careos_cancelled,FALSE)=FALSE
  UNION ALL
  SELECT DISTINCT order_item, 'ALREADY_HAS_CANCELLED_PERIOD',
    'SAP already shows at least one Cancelled period for this item; not a plain-cancel candidate'
  FROM _mirror WHERE existing_cancelled_periods>0
  UNION ALL
  SELECT DISTINCT order_item, 'SAP_SPINE_INVALID',
    'SAP period rows do not form a clean 1..TotalPeriods spine'
  FROM _mirror
  WHERE sap_total_period_values!=1 OR sap_min_period!=1
    OR sap_max_period!=CAST(TotalPeriods AS INT64)
    OR sap_period_rows!=CAST(TotalPeriods AS INT64)
    OR sap_distinct_periods!=CAST(TotalPeriods AS INT64)
  UNION ALL
  SELECT DISTINCT order_item, 'PAYMENT_CHANNEL_AMBIGUOUS',
    'more than one distinct non-blank PaymentMethod or PaymentChannel exists for this item; forward-fill is unsafe'
  FROM _mirror WHERE distinct_payment_methods>1 OR distinct_payment_channels>1
  UNION ALL
  SELECT DISTINCT order_item, 'PAYMENT_CHANNEL_MISSING',
    'no period has a non-blank PaymentMethod/PaymentChannel to forward-fill from'
  FROM _mirror WHERE PaymentMethod IS NULL OR PaymentChannel IS NULL
) h
WHERE NOT EXISTS (
  SELECT 1 FROM `pacific-plating-282708.sap_integration_v3.urgent_refund_cancel_hold` existing
  WHERE existing.request_id=v_request_id AND existing.order_item=h.order_item AND existing.rule_code=h.rule_code
);

INSERT INTO `pacific-plating-282708.sap_integration_v3.urgent_refund_cancel_ready`
SELECT
  v_request_id, CompanyDB, OrderID, order_item AS OrderItem, InvoiceNo,
  CAST(FORMAT_DATE('%d%m%Y', SAFE.PARSE_DATE('%d%m%Y',OrderDate)) AS STRING) AS OrderDate,
  InsuredID, Title, FirstName, LastName, InsurerCode, InsuranceGroup, InsuranceType,
  InsuranceProduct, ProductType, PolicyType, Endorse,
  CAST(FORMAT_DATE('%d%m%Y', SAFE.PARSE_DATE('%d%m%Y',PolicyDate)) AS STRING) AS PolicyDate,
  PolicyNo, EndorsementNo, ChassisNo, LicensePlate, GrossPremium, StampDuty, VAT, TotalPremium,
  WHT, TotalEIR, TotalSBT, ProcessingFee, ProcessingFeeVat, ShippingFee, ShippingFeeVat,
  TotalAmount, Discount,
  'Cancelled' AS TransactionStatus, -- the whole point of this candidate: cancel every period (R1)
  SubmissionStatus, ApprovalStatus, PaymentStatus, ExpectedReceived, ActualReceived,
  InterestThisPeriod, PrincipleThisPeriod, InterestEIRThisPeriod, PrincipleEIRThisPeriod,
  PaymentDate, -- mirrored verbatim, never invented; blank stays blank for never-paid periods
  Period, TotalPeriods, PendingPayment, PaymentMethod, PaymentChannel,
  -- ExpectedDate fallback chain (Aware, 2026-08-22): existing value, else PaymentDate, else
  -- BatchRunDate -- never blank.
  FORMAT_DATE('%d%m%Y', COALESCE(
    SAFE.PARSE_DATE('%d%m%Y',ExpectedDate),
    SAFE.PARSE_DATE('%d%m%Y',PaymentDate),
    CURRENT_DATE('Asia/Bangkok'))) AS ExpectedDate,
  RefOrder, RefundAmountBeforeFee, RefundAmountAfterFee, BillingAddress,
  FORMAT_DATE('%d%m%Y', CURRENT_DATE('Asia/Bangkok')) AS BatchRunDate
FROM _mirror
WHERE order_item NOT IN (
  SELECT order_item FROM `pacific-plating-282708.sap_integration_v3.urgent_refund_cancel_hold`
  WHERE request_id=v_request_id
);

-- ============================================================================
-- Gate. UPDATE 2026-08-22: Boat relayed Aware's confirmation for the two open questions this
-- gate originally distrusted -- blank PaymentDate and blank InvoiceNo on a never-paid period are
-- both confirmed mirror-verbatim-correct even once status becomes Cancelled, and NULL
-- ActualReceived is confirmed to become numeric 0 (applied above). See
-- docs/tasks/TASK_URGENT_REFUND_PAID_CANCEL_20260821.md "Aware answers received". This gate no
-- longer treats those as BLOCK conditions; it still fails closed on any other required-field NULL.
-- ============================================================================
INSERT INTO `pacific-plating-282708.sap_integration_v3.urgent_refund_cancel_gate_manifest`
SELECT
  v_request_id,
  (SELECT COUNT(*) FROM `pacific-plating-282708.sap_integration_v3.urgent_refund_cancel_ready` WHERE request_id=v_request_id),
  (SELECT COUNT(DISTINCT OrderItem) FROM `pacific-plating-282708.sap_integration_v3.urgent_refund_cancel_ready` WHERE request_id=v_request_id),
  (SELECT COUNT(DISTINCT order_item) FROM `pacific-plating-282708.sap_integration_v3.urgent_refund_cancel_hold` WHERE request_id=v_request_id),
  (SELECT COUNT(*) FROM `pacific-plating-282708.sap_integration_v3.urgent_refund_cancel_ready`
    WHERE request_id=v_request_id AND TransactionStatus='Cancelled' AND PaymentDate=''),
  TO_HEX(SHA256((SELECT STRING_AGG(TO_JSON_STRING(r),'\n' ORDER BY OrderItem,SAFE_CAST(Period AS INT64))
    FROM `pacific-plating-282708.sap_integration_v3.urgent_refund_cancel_ready` r WHERE r.request_id=v_request_id))),
  TO_HEX(SHA256((SELECT STRING_AGG(CONCAT(column_name,'|',data_type,'|',ordinal_position),'\n' ORDER BY ordinal_position)
    FROM `pacific-plating-282708.sap_integration_v3.INFORMATION_SCHEMA.COLUMNS`
    WHERE table_name='urgent_refund_cancel_ready'))),
  CURRENT_TIMESTAMP(),
  CASE
    WHEN (SELECT COUNT(*) FROM `pacific-plating-282708.sap_integration_v3.urgent_refund_cancel_ready` r
      WHERE r.request_id=v_request_id
        AND REGEXP_CONTAINS(TO_JSON_STRING((SELECT AS STRUCT r.* EXCEPT(request_id,PaymentDate,InvoiceNo))),r':null|:"NULL"'))>0
      THEN 'BLOCK_NULL_VALUE'
    WHEN (SELECT COUNT(*) FROM (
      SELECT OrderItem FROM `pacific-plating-282708.sap_integration_v3.urgent_refund_cancel_ready`
      WHERE request_id=v_request_id GROUP BY OrderItem
      HAVING COUNT(*)!=CAST(ANY_VALUE(TotalPeriods) AS INT64)
        OR COUNT(DISTINCT SAFE_CAST(Period AS INT64))!=CAST(ANY_VALUE(TotalPeriods) AS INT64)
        OR MIN(SAFE_CAST(Period AS INT64))!=1
        OR MAX(SAFE_CAST(Period AS INT64))!=CAST(ANY_VALUE(TotalPeriods) AS INT64)
        OR COUNTIF(TransactionStatus!='Cancelled')>0
    ))>0
      THEN 'BLOCK_SPINE_OR_STATUS'
    WHEN (SELECT COUNT(*) FROM `pacific-plating-282708.sap_integration_v3.urgent_refund_cancel_ready`
      WHERE request_id=v_request_id) = 0
      THEN 'BLOCK_NO_READY_ROWS'
    ELSE 'PASS'
  END,
  CASE
    WHEN (SELECT COUNT(*) FROM `pacific-plating-282708.sap_integration_v3.urgent_refund_cancel_ready` r
      WHERE r.request_id=v_request_id
        AND REGEXP_CONTAINS(TO_JSON_STRING((SELECT AS STRUCT r.* EXCEPT(request_id,PaymentDate,InvoiceNo))),r':null|:"NULL"'))>0
      THEN 'A required field other than the confirmed PaymentDate/InvoiceNo exceptions is SQL NULL or literal NULL.'
    WHEN (SELECT COUNT(*) FROM `pacific-plating-282708.sap_integration_v3.urgent_refund_cancel_ready`
      WHERE request_id=v_request_id) = 0
      THEN 'No items passed item-level quarantine; see urgent_refund_cancel_hold for reasons.'
    ELSE 'Confirmed rules applied: blank PaymentDate/InvoiceNo on never-paid periods and NULL ActualReceived->0 are all Aware-confirmed, not open questions.'
  END;

-- Report the result. This script performs no GCS write and does not by itself constitute
-- Boat's deploy OK or Aware's rule confirmation -- both remain required before any export.
SELECT * FROM `pacific-plating-282708.sap_integration_v3.urgent_refund_cancel_gate_manifest`
WHERE request_id=v_request_id;

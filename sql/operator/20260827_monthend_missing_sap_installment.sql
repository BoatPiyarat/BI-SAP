-- READ ONLY. Reusable month-end catch-up: find order_items with a genuinely new Paid
-- INSTALLMENT/RENEWAL charge (period > 1) within one calendar month that is not yet delivered to
-- SAP, then emit the FULL 1..TotalPeriods spine for every such order_item (Paid rows fully
-- populated, Pending rows blank InvoiceNo/PaymentDate/etc.) — the SAP installment interface
-- rejects any submission that is missing periods for an order_item ("PolicyStatus: is duplicated" /
-- "InvoiceNo: Cannot change InvoiceNo when status Paid,Cancelled" on LogID 21639 traced back to
-- this file previously emitting only the newly-paid period instead of the whole spine). This
-- writes nothing: no CREATE OR REPLACE TABLE, no MERGE, no GCS, no SAP action. Safe to run
-- repeatedly for any month by editing only the three DECLARE values below.
--
-- Lineage: generalizes sql/ddl/048_july_export_shadow_and_archive.sql (a July-only, hard-coded,
-- table-writing procedure) into a parameterized, side-effect-free query. Not yet Class-A reviewed
-- — treat every row here as a candidate list to eyeball before manual export, not an approved
-- population. Read docs/AGENT_REVIEW_PROTOCOL.md before relying on this for a real SAP upload; a
-- second reviewer should check this once before first use, same as any other Class-A artifact.
--
-- Scope: this file covers only the INSTALLMENT/RENEWAL (existing order, later payment periods)
-- population, sourced from `sap_data_engineer.sap_dashboard_carepay_installment`. The brand-new
-- order / first-payment population is structurally different — use the sibling file
-- sql/operator/20260827_monthend_missing_sap_onetime.sql for that. Do not merge the two FROM
-- clauses back into one query; keeping them apart is what makes each one auditable.
--
-- Excludes anything SAP already agrees with CareOS on (`sap_integration_v2.SAP_LIVE_FULL`'s own
-- TransactionStatus for that exact OrderItem+Period is something other than Pending) — the root
-- cause of LogID 21639's mass rejection was resubmitting periods SAP's own record already showed
-- as settled. A period SAP still shows Pending while CareOS shows the charge as successful is
-- exactly the gap this script exists to find, so that case stays IN, not excluded. Still not
-- Class-A reviewed; still untested against live BigQuery this session.
-- ============================================================================================
-- EDIT THESE THREE VALUES ONLY WHEN REUSING FOR A DIFFERENT MONTH
-- ============================================================================================
DECLARE v_month_start DATE DEFAULT DATE '2026-08-01';
DECLARE v_month_end_exclusive DATE DEFAULT DATE '2026-09-01';   -- first day of the FOLLOWING month
DECLARE v_batch_run_date DATE DEFAULT DATE '2026-08-31';         -- must be the last day of the month above
-- ============================================================================================

ASSERT v_month_end_exclusive > v_month_start
  AS 'v_month_end_exclusive must be after v_month_start';
ASSERT v_batch_run_date = LAST_DAY(v_month_start)
  AS 'v_batch_run_date must be the last calendar day of v_month_start\'s month';

-- Repairs "UTF-8 read as a single-byte charset (Latin-1/Windows-1252), then re-saved as UTF-8"
-- double-encoding — the classic à¸ˆà¹ˆà¸²à¸¢ mojibake seen live in Title/PaymentMethod. Reinterprets
-- each character's code point as a raw byte (valid only when every code point is <=255, i.e. the
-- string could plausibly BE mojibake) and re-decodes those bytes as UTF-8. SAFE. + COALESCE means
-- a string that is already correct Thai (real code points >255) or pure ASCII round-trips back to
-- itself unchanged instead of erroring or getting corrupted a second time.
CREATE TEMP FUNCTION fn_fix_mojibake_th(s STRING) AS (
  COALESCE(
    SAFE_CONVERT_BYTES_TO_STRING(SAFE.CODE_POINTS_TO_BYTES(TO_CODE_POINTS(s))),
    s)
);

-- The real comparison (per project knowledge, not a blanket "row exists = exclude" — that
-- previous version excluded almost every trigger row and returned an empty result, because
-- SAP_LIVE_FULL carries one row per (OrderItem, Period) regardless of whether SAP has actually
-- received payment yet): the gap that needs export is CareOS showing the charge as successful
-- while SAP's own PolicyStatus/TransactionStatus for that exact period is still 'Pending'. A row
-- is only "already synced" (safe to hold out of this run) when SAP's own status is something
-- other than Pending — i.e. SAP already agrees with CareOS. Absence from SAP_LIVE_FULL entirely
-- is NOT synced either; it still needs export.
-- `sql/production/SAP_LIVE_FULL.sql` (the live view definition on file) exposes this field as
-- `TransactionStatus` (aliased from SAP's own `U_PolicyStatus`) — using that exact name here.
CREATE TEMP TABLE _legacy_status AS
SELECT
  CAST(OrderItem AS STRING) AS order_item,
  SAFE_CAST(Period AS INT64) AS period,
  LOWER(TRIM(CAST(TransactionStatus AS STRING))) AS sap_status
FROM `pacific-plating-282708.sap_integration_v2.SAP_LIVE_FULL`
WHERE OrderItem IS NOT NULL AND Period IS NOT NULL;

-- Every Paid, non-change-order INSTALLMENT charge (period > 1) whose actual charge_time falls in
-- the target month and has not already reached a terminal delivered/acknowledged state in
-- export_archive, and is not already known-delivered via the V2/legacy path. This identifies which
-- order_items have a genuinely NEW trigger this month — it does not by itself decide what gets
-- exported (see _spine below, which emits the full period range for every triggered order_item).
CREATE TEMP TABLE _trigger_all AS
SELECT e.*, DATE(pe.charge_time) AS raw_payment_date,
  EXISTS (SELECT 1 FROM `pacific-plating-282708.careos.cancelled_change_orders` cco
    WHERE cco.current_human_id = e.order_id) AS is_change_order,
  (SELECT STRING_AGG(DISTINCT a.delivery_status ORDER BY a.delivery_status)
    FROM `pacific-plating-282708.sap_integration_v3.export_archive` a
    WHERE a.charge_id = e.charge_id AND a.order_item = e.order_item AND a.period = e.period)
    AS existing_archive_statuses,
  EXISTS (SELECT 1 FROM _legacy_status ld
    WHERE ld.order_item = e.order_item AND ld.period = e.period
      AND ld.sap_status NOT IN ('pending', '')) AS already_in_legacy
FROM `pacific-plating-282708.sap_integration_v3.expected_state` e
JOIN `pacific-plating-282708.sap_integration_v3.stg_payment_events` pe USING (charge_id)
JOIN `pacific-plating-282708.careos.careos_orders` co ON co.human_id = e.order_id
JOIN `pacific-plating-282708.careos.careos_order_items` coi
  ON coi.order_id = co.id AND coi.human_id = e.order_item
JOIN `pacific-plating-282708.careos.careos_leads` cl
  ON CONCAT('leads/', cl.id) = co.lead AND cl.status = 'LEAD_STATUS_PURCHASED'
WHERE e.expected_status = 'Paid'
  AND e.period > 1
  AND DATE(pe.charge_time) >= v_month_start
  AND DATE(pe.charge_time) < v_month_end_exclusive
  AND NOT EXISTS (
    SELECT 1 FROM `pacific-plating-282708.sap_integration_v3.export_archive` a
    WHERE a.charge_id = e.charge_id AND a.order_item = e.order_item AND a.period = e.period
      AND a.delivery_status IN ('DELIVERED', 'PICKED_UP', 'ACKNOWLEDGED'));

CREATE TEMP TABLE _trigger_coverage AS
SELECT t.*,
  CASE
    WHEN t.is_change_order THEN 'CHANGE_ORDER_SEPARATE_FLOW'
    WHEN t.already_in_legacy THEN 'ALREADY_DELIVERED_VIA_V2_LEGACY'
    WHEN t.existing_archive_statuses IS NOT NULL
      THEN CONCAT('ALREADY_IN_FLIGHT_VIA_AUTOMATED_PIPELINE:', t.existing_archive_statuses)
    ELSE NULL
  END AS hold_reason
FROM _trigger_all t;

-- The order_items with at least one genuine, un-held new trigger this month. Every period of
-- these order_items — Paid or Pending, including periods already delivered in a prior month — is
-- emitted below, because the SAP installment interface requires the complete spine on every
-- submission, not just the newly-triggering period.
CREATE TEMP TABLE _trigger_order_items AS
SELECT DISTINCT order_item FROM _trigger_coverage WHERE hold_reason IS NULL;

-- The exact 56-column installment/renewal payload source, deduplicated deterministically per key.
CREATE TEMP TABLE _payload_source AS
SELECT * EXCEPT(_rn) FROM (
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
    FROM `pacific-plating-282708.sap_data_engineer.sap_dashboard_carepay_installment`
  ) s
) WHERE _rn = 1;

-- Full 1..TotalPeriods spine for every triggered order_item: every (order_item, period) row that
-- exists in expected_state, Paid or Pending, regardless of whether that specific period is the one
-- that newly triggered this run.
CREATE TEMP TABLE _spine AS
SELECT e2.*
FROM `pacific-plating-282708.sap_integration_v3.expected_state` e2
WHERE e2.order_item IN (SELECT order_item FROM _trigger_order_items);

CREATE TEMP TABLE _coverage AS
SELECT sp.*,
  CASE
    WHEN s.OrderItem IS NULL AND sp.flow = 'RCL_CMI' THEN 'RCL_CMI_PAYLOAD_MISSING'
    WHEN s.OrderItem IS NULL THEN 'UNCLASSIFIED_PAYLOAD_GAP'
    ELSE NULL
  END AS hold_reason
FROM _spine sp LEFT JOIN _payload_source s
  ON s.OrderItem = sp.order_item AND SAFE_CAST(s.Period AS INT64) = sp.period;

CREATE TEMP TABLE _eligible AS
SELECT * EXCEPT(hold_reason) FROM _coverage WHERE hold_reason IS NULL;

ASSERT (SELECT COUNT(*) FROM _eligible) + (SELECT COUNT(*) FROM _coverage WHERE hold_reason IS NOT NULL)
  = (SELECT COUNT(*) FROM _spine)
  AS 'Population conservation failed: eligible must equal export plus held, out of the full spine';

CREATE TEMP TABLE _candidate AS
SELECT
  CAST(s.CompanyDB AS STRING) CompanyDB, CAST(s.OrderID AS STRING) OrderID,
  CAST(s.OrderItem AS STRING) OrderItem, CAST(e.expected_invoice_no AS STRING) InvoiceNo,
  CAST(s.OrderDate AS STRING) OrderDate,
  COALESCE(NULLIF(TRIM(CAST(s.InsuredID AS STRING)), ''), '-') InsuredID,
  fn_fix_mojibake_th(CAST(s.Title AS STRING)) Title, CAST(s.FirstName AS STRING) FirstName, CAST(s.LastName AS STRING) LastName,
  CAST(s.InsurerCode AS STRING) InsurerCode, CAST(s.InsuranceGroup AS STRING) InsuranceGroup,
  CAST(s.InsuranceType AS STRING) InsuranceType, CAST(s.InsuranceProduct AS STRING) InsuranceProduct,
  CAST(s.ProductType AS STRING) ProductType, CAST(s.PolicyType AS STRING) PolicyType,
  CAST(s.Endorse AS STRING) Endorse, CAST(s.PolicyDate AS STRING) PolicyDate,
  CAST(s.PolicyNo AS STRING) PolicyNo, CAST(s.EndorsementNo AS STRING) EndorsementNo,
  CAST(s.ChassisNo AS STRING) ChassisNo, CAST(s.LicensePlate AS STRING) LicensePlate,
  FORMAT('%.2f', SAFE_CAST(s.GrossPremium AS FLOAT64)) GrossPremium,
  FORMAT('%.2f', SAFE_CAST(s.StampDuty AS FLOAT64)) StampDuty,
  FORMAT('%.2f', SAFE_CAST(s.VAT AS FLOAT64)) VAT,
  FORMAT('%.2f', SAFE_CAST(s.TotalPremium AS FLOAT64)) TotalPremium,
  FORMAT('%.2f', SAFE_CAST(s.WHT AS FLOAT64)) WHT,
  FORMAT('%.2f', SAFE_CAST(s.TotalEIR AS FLOAT64)) TotalEIR,
  FORMAT('%.2f', SAFE_CAST(s.TotalSBT AS FLOAT64)) TotalSBT,
  FORMAT('%.2f', SAFE_CAST(s.ProcessingFee AS FLOAT64)) ProcessingFee,
  FORMAT('%.2f', SAFE_CAST(s.ProcessingFeeVat AS FLOAT64)) ProcessingFeeVat,
  FORMAT('%.2f', SAFE_CAST(s.ShippingFee AS FLOAT64)) ShippingFee,
  FORMAT('%.2f', SAFE_CAST(s.ShippingFeeVat AS FLOAT64)) ShippingFeeVat,
  FORMAT('%.2f', SAFE_CAST(s.TotalAmount AS FLOAT64)) TotalAmount,
  FORMAT('%.2f', SAFE_CAST(s.Discount AS FLOAT64)) Discount,
  e.expected_status TransactionStatus, CAST(s.SubmissionStatus AS STRING) SubmissionStatus,
  CAST(s.ApprovalStatus AS STRING) ApprovalStatus, CAST(s.PaymentStatus AS STRING) PaymentStatus,
  FORMAT('%.2f', SAFE_CAST(s.ExpectedReceived AS FLOAT64)) ExpectedReceived,
  FORMAT('%.2f', SAFE_CAST(s.ActualReceived AS FLOAT64)) ActualReceived,
  FORMAT('%.2f', SAFE_CAST(s.InterestThisPeriod AS FLOAT64)) InterestThisPeriod,
  FORMAT('%.2f', SAFE_CAST(s.PrincipleThisPeriod AS FLOAT64)) PrincipleThisPeriod,
  FORMAT('%.2f', SAFE_CAST(s.InterestEIRThisPeriod AS FLOAT64)) InterestEIRThisPeriod,
  FORMAT('%.2f', SAFE_CAST(s.PrincipleEIRThisPeriod AS FLOAT64)) PrincipleEIRThisPeriod,
  IF(e.expected_payment_date IS NULL, '', FORMAT_DATE('%d%m%Y', e.expected_payment_date)) PaymentDate,
  CAST(e.period AS STRING) Period, CAST(e.total_periods AS STRING) TotalPeriods,
  CAST(s.PendingPayment AS STRING) PendingPayment,
  IF(e.expected_status = 'Paid', fn_fix_mojibake_th(CAST(s.PaymentMethod AS STRING)), '') PaymentMethod,
  IF(e.expected_status = 'Paid', CAST(s.PaymentChannel AS STRING), '') PaymentChannel,
  CAST(s.ExpectedDate AS STRING) ExpectedDate,
  CAST(s.RefOrder AS STRING) RefOrder,
  FORMAT('%.2f', SAFE_CAST(s.RefundAmountBeforeFee AS FLOAT64)) RefundAmountBeforeFee,
  FORMAT('%.2f', SAFE_CAST(s.RefundAmountAfterFee AS FLOAT64)) RefundAmountAfterFee,
  CAST(s.BillingAddress AS STRING) BillingAddress,
  FORMAT_DATE('%d%m%Y', v_batch_run_date) BatchRunDate
FROM _eligible e JOIN _payload_source s
  ON s.OrderItem = e.order_item AND SAFE_CAST(s.Period AS INT64) = e.period;

-- Contract validation. PAID_COMPLETENESS only applies to Paid rows — Pending rows are supposed to
-- have blank InvoiceNo/PaymentDate/PaymentMethod/PaymentChannel, that's what makes them Pending.
CREATE TEMP TABLE _contract_invalid AS
SELECT DISTINCT OrderItem, SAFE_CAST(Period AS INT64) period, 'POLICYNO_TOO_LONG' hold_reason
FROM _candidate WHERE LENGTH(PolicyNo) > 50
UNION DISTINCT
SELECT DISTINCT OrderItem, SAFE_CAST(Period AS INT64), 'PAID_COMPLETENESS'
FROM _candidate
WHERE TransactionStatus = 'Paid'
  AND (NULLIF(TRIM(InvoiceNo), '') IS NULL OR NULLIF(TRIM(PaymentDate), '') IS NULL
   OR NULLIF(TRIM(PaymentMethod), '') IS NULL OR NULLIF(TRIM(PaymentChannel), '') IS NULL)
UNION DISTINCT
SELECT DISTINCT OrderItem, SAFE_CAST(Period AS INT64), 'DATE_FORMAT_INVALID'
FROM _candidate
UNPIVOT(date_value FOR date_column IN (OrderDate, PolicyDate, PaymentDate, ExpectedDate, BatchRunDate))
WHERE NOT (IFNULL(date_value, '') = '' OR
  (LENGTH(date_value) = 8 AND SAFE.PARSE_DATE('%d%m%Y', date_value) IS NOT NULL));

-- Spine-completeness invariant, matching the pattern already reviewed and passed in
-- sql/operator/20260825_export_fresh_v3_newpayment_interface.sql: every OrderItem in the
-- ready-to-export result must carry exactly TotalPeriods rows and TotalPeriods distinct periods.
ASSERT (SELECT COUNT(*) FROM (
  SELECT OrderItem, COUNT(*) row_n, COUNT(DISTINCT SAFE_CAST(Period AS INT64)) period_n,
    MAX(SAFE_CAST(TotalPeriods AS INT64)) total_n
  FROM _candidate c
  WHERE NOT EXISTS (
    SELECT 1 FROM _contract_invalid i
    WHERE i.OrderItem = c.OrderItem AND i.period = SAFE_CAST(c.Period AS INT64))
  GROUP BY OrderItem HAVING row_n != total_n OR period_n != total_n)) = 0
  AS 'Ready-to-export result contains incomplete period spines for at least one OrderItem';

-- ============================================================================================
-- RESULT 1 of 2: what's held and why (this answers "what's missing and blocking manual export")
-- ============================================================================================
SELECT 'HELD' AS result_set, hold_reason, COUNT(*) AS row_count,
  ARRAY_AGG(STRUCT(order_item, period) ORDER BY order_item, period LIMIT 20) AS sample_keys
FROM _trigger_coverage WHERE hold_reason IS NOT NULL
GROUP BY hold_reason
UNION ALL
SELECT 'HELD' AS result_set, hold_reason, COUNT(*) AS row_count,
  ARRAY_AGG(STRUCT(order_item, period) ORDER BY order_item, period LIMIT 20) AS sample_keys
FROM _coverage WHERE hold_reason IS NOT NULL
GROUP BY hold_reason
UNION ALL
SELECT 'HELD' AS result_set, hold_reason, COUNT(*) AS row_count,
  ARRAY_AGG(STRUCT(OrderItem AS order_item, period) ORDER BY OrderItem, period LIMIT 20) AS sample_keys
FROM _contract_invalid
GROUP BY hold_reason
ORDER BY row_count DESC;

-- ============================================================================================
-- RESULT 2 of 2: the exact 56-column payload, ready for manual CSV export (`bq query ...
-- --format=csv`). Rows failing contract validation are excluded here — they appear in RESULT 1.
-- Includes the FULL period spine (Paid and Pending) for every order_item with a genuine new
-- trigger this month, not just the newly-paid period.
-- ============================================================================================
SELECT c.*
FROM _candidate c
WHERE NOT EXISTS (
  SELECT 1 FROM _contract_invalid i
  WHERE i.OrderItem = c.OrderItem AND i.period = SAFE_CAST(c.Period AS INT64))
ORDER BY c.OrderItem, SAFE_CAST(c.Period AS INT64);

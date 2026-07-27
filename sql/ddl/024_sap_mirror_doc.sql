-- 024_sap_mirror_doc.sql
-- STEP 3 of TASK_CLEAN_SAP_MIRROR.md — sap_mirror_doc: one row per DocEntry, nothing dropped.
--
-- Same 4 source tables and same DocEntry-level resolution as
-- sap_integration_v2.SAP_LIVE_FULL (ROW_NUMBER PARTITION BY DocEntry ORDER BY
-- BatchRunDate DESC — this resolves repeat-loads of the SAME DocEntry caused by
-- the legacy loader being append-only, it does NOT collapse across DIFFERENT
-- DocEntry values, per Boat's explicit instruction: "เก็บครบ ห้าม dedup ข้าม
-- DocEntry"). The one deliberate difference from SAP_LIVE_FULL: no
-- `WHERE U_InsuranceGroup <> 'B2B'` filter in any branch — every row that
-- exists in the 4 source tables is kept. (Confirmed live 2026-07-26: all 4
-- source tables currently have 0 B2B rows anyway, so this is a no-op today,
-- but SAP_LIVE_FULL's own filter would silently start dropping them the day
-- that changes — this table won't.)
--
-- Why this exists alongside SAP_LIVE_FULL/stg_sap_state rather than replacing
-- them: FINDINGS_SAP_MIRROR_20260726.md concluded the extract->load chain
-- into SAP_LIVE is genuinely working (contra this task's original "Branch B"
-- assumption) and SAP_LIVE_FULL's DocEntry-grain dedup logic is sound — the
-- real gap is the STATE-resolution layer (see 025_sap_mirror_state.sql), not
-- ingestion. This table is the full-fidelity base the state layer resolves
-- from; it does not touch or replace sap_integration_v2 objects.
--
-- Completeness evidence for this design (docs/FINDINGS_SAP_MIRROR_20260726.md
-- addendum, 2026-07-26, no SAP DB access — verified from BigQuery + Cloud
-- Logging only):
--   - DocEntry gap analysis: 1,622,566 of 1,652,810 consecutive DocEntry pairs
--     (98.2%) are perfectly contiguous (gap=1) across the full mirror. Only
--     389 gaps >100 and 45 gaps >1000 exist, none of which line up with a
--     detected outage window — consistent with DocEntry being a private
--     auto-increment on the source @INSURANCE table (not a shared SAP-wide
--     sequence), where remaining gaps are most plausibly the already-known
--     B2B exclusion (this table no longer applies that filter) plus other
--     non-insurance-installment row types the extract's own source query
--     never selects. No evidence of a systemic hole.
--   - Log cross-check: reliable per-run "rows extracted" counts only exist in
--     Cloud Logging since ~2026-07-20 (earlier executions logged no
--     structured output — an older code revision). Every run since 07-20
--     reported `caught_up=True` including the one that absorbed a 3.75-day
--     gap (2026-07-16 13:30 -> 2026-07-20 09:13, likely an outage) in a
--     single 4-chunk, 47,888-row catch-up run with no evidence of loss. The
--     watermark file only advances on success, so failed runs (7 of ~20
--     lifetime executions, clustered around initial deploy 07-12 and the
--     07-20 fix) retry the same window rather than skipping it.
--
-- Duplicate-document forensics (same addendum) that motivated keeping this
-- layer at full DocEntry grain instead of collapsing further here:
--   - 31% of (U_OrderItem, U_Period) keys have 2+ DocEntry rows; one has 496.
--   - Two of the highest-count buckets (496 and 45 docs) turned out to be
--     `U_OrderItem = 'Invoice'` / `'SaleOrder'` — placeholder/object-type
--     values that leaked into the OrderItem column, not real orders. These
--     will need excluding at the STATE layer (see 025), not here — this
--     table intentionally keeps them, "nothing dropped" is the point of it.
--   - The remaining genuine high-duplicate items (e.g. L76956324-V1) show
--     many DocEntry rows sharing identical amounts, mostly identical
--     'Pending' status, and no InvoiceNo, clustered on a handful of specific
--     BatchRunDates rather than one new row appearing every night — i.e. NOT
--     a "re-exported every night" pattern. This looks more like an
--     extract-query fan-out artifact (or genuine duplicate schedule rows
--     already present in the source table) than distinct real SAP postings,
--     but this can't be fully confirmed without SAP DB/Aware input — flagged
--     for Aware, not resolved by picking a side here.
--
-- Idempotent: full rebuild every run (source is a few million rows, matches
-- the existing sp_refresh_sap_state.sql convention). run_scope kept for
-- calling-convention parity with the other sp_refresh_* procs.
--
-- *** BUG FOUND AND FIXED 2026-07-27 *** (while cross-checking this table against
-- stg_sap_state per Boat's ask, before collapsing stg_sap_state into a view over
-- sap_mirror_state): the per-DocEntry ROW_NUMBER below ordered by `BatchRunDate DESC`,
-- but by that point in the query `BatchRunDate` is already the DDMMYYYY STRING output
-- column (FORMAT_DATE'd from the real `U_BatchRunDate` DATE inside each UNION branch),
-- not a date. Ordering a DDMMYYYY string DESC sorts LEXICOGRAPHICALLY, not
-- chronologically — e.g. "31032026" (31 Mar) sorts ahead of "16062026" (16 Jun) because
-- '3' > '1' as the first character. This silently kept the wrong (older) row for every
-- DocEntry whose true latest BatchRunDate didn't happen to also sort highest as a string
-- — confirmed live: 44,781 (OrderItem, Period) keys where this table showed a stale
-- status (e.g. Pending) for a DocEntry that `SAP_LIVE_FULL`/`stg_sap_state` correctly
-- showed as Paid, same DocEntry, just picked from the real latest batch. Fixed by
-- parsing the string back to a date before ordering — same technique already used
-- correctly in `002_sp_refresh_sap_state.sql`/`025_sap_mirror_state.sql`'s own picking
-- rule (`SAFE.PARSE_TIMESTAMP('%d%m%Y', BatchRunDate) DESC`). Re-verified after the fix:
-- 0 status/invoice disagreements remain against stg_sap_state (see 30_SAP_CHANGELOG.md
-- 2026-07-27 entry for the full before/after numbers).

CREATE OR REPLACE PROCEDURE `pacific-plating-282708.sap_integration_v3.sp_refresh_sap_mirror_doc`(run_scope STRING)
BEGIN
  DECLARE run_id STRING DEFAULT GENERATE_UUID();
  DECLARE started TIMESTAMP DEFAULT CURRENT_TIMESTAMP();
  DECLARE row_count INT64;

  CREATE OR REPLACE TABLE `pacific-plating-282708.sap_integration_v3.sap_mirror_doc`
  CLUSTER BY U_OrderItem AS
  SELECT * EXCEPT(_rn)
  FROM (
    SELECT
      *,
      ROW_NUMBER() OVER (
        PARTITION BY DocEntry
        ORDER BY SAFE.PARSE_DATE('%d%m%Y', BatchRunDate) DESC
      ) AS _rn
    FROM (

      SELECT DISTINCT
        DocEntry,
        U_CompanyCode CompanyDB,
        U_OrderID,
        U_OrderItem,
        U_InvoiceNo,
        SAFE_CAST(FORMAT_DATE('%d%m%Y', U_OrderDate) AS STRING) AS OrderDate,
        U_InsuredID,
        U_Title,
        U_FirstName,
        U_LastName,
        U_InsurerCode,
        U_InsuranceGroup,
        U_InsuranceType,
        U_InsuranceProduct,
        U_ProductType,
        U_PolicyType,
        CAST(U_Endorse AS STRING) U_Endorse,
        SAFE_CAST(FORMAT_DATE('%d%m%Y', U_PolicyDate) AS STRING) AS PolicyDate,
        U_PolicyNo,
        SAFE_CAST(U_EndorsementNo AS STRING) AS EndorsementNo,
        U_ChassisNo,
        U_LicensePlate,
        U_GrossPremiumAmt GrossPremium,
        CAST(U_StampDutyAmt AS FLOAT64) AS StampDuty,
        SAFE_CAST(U_VATAmt AS FLOAT64) AS VAT,
        SAFE_CAST(U_TotalPremiumAmt AS FLOAT64) AS TotalPremium,
        SAFE_CAST(U_WHTAmt AS FLOAT64) AS WHT,
        SAFE_CAST(U_TotalEIRAmt AS FLOAT64) AS TotalEIR,
        SAFE_CAST(U_TotalSBTAmt AS FLOAT64) AS TotalSBT,
        SAFE_CAST(U_ProcessingFee AS FLOAT64) AS U_ProcessingFee,
        SAFE_CAST(U_ProcessingFeeVat AS FLOAT64) AS U_ProcessingFeeVat,
        SAFE_CAST(U_ShippingFee AS FLOAT64) AS U_ShippingFee,
        SAFE_CAST(U_ShippingFeeVat AS FLOAT64) AS U_ShippingFeeVat,
        SAFE_CAST(U_TotalAmount AS FLOAT64) AS U_TotalAmount,
        SAFE_CAST(U_Discount AS FLOAT64) AS U_Discount,
        U_PolicyStatus TransactionStatus,
        U_SubmissionStatus,
        U_ApprovalStatus,
        U_PaymentStatus,
        SAFE_CAST(U_ExpectedReceived AS FLOAT64) AS ExpectedReceived,
        SAFE_CAST(U_ActualReceived AS FLOAT64) AS U_ActualReceived,
        SAFE_CAST(U_InterestThisPeriod AS FLOAT64) AS U_InterestThisPeriod,
        SAFE_CAST(U_PrincipleThisPeriod AS FLOAT64) AS U_PrincipleThisPeriod,
        SAFE_CAST(U_InterestEIRThisPeriod AS FLOAT64) AS U_InterestEIRThisPeriod,
        SAFE_CAST(U_PrincipleEIRThisPeriod AS FLOAT64) AS U_PrincipleEIRThisPeriod,
        CASE WHEN U_PaymentDate = 'NULL' THEN '' ELSE CAST(FORMAT_DATE('%d%m%Y', DATE(U_PaymentDate)) AS STRING) END AS PaymentDate,
        U_Period,
        U_TotalPeriods TotalPeriods,
        U_PendingPayment PendingPayment,
        U_PaymentMethod PaymentMethod,
        U_PaymentChannel PaymentChannel,
        SAFE_CAST(FORMAT_DATE('%d%m%Y', U_ExpectedDate) AS STRING) AS ExpectedDate,
        U_RefOrder RefOrder,
        U_RefundAmt RefundAmountBeforeFee,
        U_RefundAmountAfterFee RefundAmountAfterFee,
        U_BillingAddress BillingAddress,
        SAFE_CAST(FORMAT_DATE('%d%m%Y', U_BatchRunDate) AS STRING) AS BatchRunDate
      FROM `pacific-plating-282708.sap_integration_v2.SAP_LIVE_2024`

      UNION ALL

      SELECT DISTINCT
        DocEntry,
        U_CompanyCode CompanyDB,
        U_OrderID,
        U_OrderItem,
        U_InvoiceNo,
        SAFE_CAST(FORMAT_DATE('%d%m%Y', U_OrderDate) AS STRING) AS OrderDate,
        U_InsuredID,
        U_Title,
        U_FirstName,
        U_LastName,
        U_InsurerCode,
        U_InsuranceGroup,
        U_InsuranceType,
        U_InsuranceProduct,
        U_ProductType,
        U_PolicyType,
        CAST(U_Endorse AS STRING) U_Endorse,
        SAFE_CAST(FORMAT_DATE('%d%m%Y', U_PolicyDate) AS STRING) AS PolicyDate,
        U_PolicyNo,
        SAFE_CAST(U_EndorsementNo AS STRING) AS EndorsementNo,
        U_ChassisNo,
        U_LicensePlate,
        U_GrossPremiumAmt GrossPremium,
        CAST(U_StampDutyAmt AS FLOAT64) AS StampDuty,
        SAFE_CAST(U_VATAmt AS FLOAT64) AS VAT,
        SAFE_CAST(U_TotalPremiumAmt AS FLOAT64) AS TotalPremium,
        SAFE_CAST(U_WHTAmt AS FLOAT64) AS WHT,
        SAFE_CAST(U_TotalEIRAmt AS FLOAT64) AS TotalEIR,
        SAFE_CAST(U_TotalSBTAmt AS FLOAT64) AS TotalSBT,
        SAFE_CAST(U_ProcessingFee AS FLOAT64) AS U_ProcessingFee,
        SAFE_CAST(U_ProcessingFeeVat AS FLOAT64) AS U_ProcessingFeeVat,
        SAFE_CAST(U_ShippingFee AS FLOAT64) AS U_ShippingFee,
        SAFE_CAST(U_ShippingFeeVat AS FLOAT64) AS U_ShippingFeeVat,
        SAFE_CAST(U_TotalAmount AS FLOAT64) AS U_TotalAmount,
        SAFE_CAST(U_Discount AS FLOAT64) AS U_Discount,
        U_PolicyStatus TransactionStatus,
        U_SubmissionStatus,
        U_ApprovalStatus,
        U_PaymentStatus,
        SAFE_CAST(U_ExpectedReceived AS FLOAT64) AS ExpectedReceived,
        SAFE_CAST(U_ActualReceived AS FLOAT64) AS U_ActualReceived,
        SAFE_CAST(U_InterestThisPeriod AS FLOAT64) AS U_InterestThisPeriod,
        SAFE_CAST(U_PrincipleThisPeriod AS FLOAT64) AS U_PrincipleThisPeriod,
        SAFE_CAST(U_InterestEIRThisPeriod AS FLOAT64) AS U_InterestEIRThisPeriod,
        SAFE_CAST(U_PrincipleEIRThisPeriod AS FLOAT64) AS U_PrincipleEIRThisPeriod,
        CASE WHEN U_PaymentDate = 'NULL' THEN '' ELSE CAST(FORMAT_DATE('%d%m%Y', DATE(U_PaymentDate)) AS STRING) END AS PaymentDate,
        U_Period,
        U_TotalPeriods TotalPeriods,
        U_PendingPayment PendingPayment,
        U_PaymentMethod PaymentMethod,
        U_PaymentChannel PaymentChannel,
        SAFE_CAST(FORMAT_DATE('%d%m%Y', U_ExpectedDate) AS STRING) AS ExpectedDate,
        U_RefOrder RefOrder,
        U_RefundAmt RefundAmountBeforeFee,
        U_RefundAmountAfterFee RefundAmountAfterFee,
        U_BillingAddress BillingAddress,
        SAFE_CAST(FORMAT_DATE('%d%m%Y', U_BatchRunDate) AS STRING) AS BatchRunDate
      FROM `pacific-plating-282708.sap_integration_v2.SAP_LIVE_2025`

      UNION ALL

      SELECT DISTINCT
        DocEntry,
        U_CompanyCode CompanyDB,
        U_OrderID,
        U_OrderItem,
        U_InvoiceNo,
        SAFE_CAST(FORMAT_DATE('%d%m%Y', U_OrderDate) AS STRING) AS OrderDate,
        U_InsuredID,
        U_Title,
        U_FirstName,
        U_LastName,
        U_InsurerCode,
        U_InsuranceGroup,
        U_InsuranceType,
        U_InsuranceProduct,
        U_ProductType,
        U_PolicyType,
        CAST(U_Endorse AS STRING) U_Endorse,
        SAFE_CAST(FORMAT_DATE('%d%m%Y', U_PolicyDate) AS STRING) AS PolicyDate,
        U_PolicyNo,
        SAFE_CAST(U_EndorsementNo AS STRING) AS EndorsementNo,
        U_ChassisNo,
        U_LicensePlate,
        U_GrossPremiumAmt GrossPremium,
        CAST(U_StampDutyAmt AS FLOAT64) AS StampDuty,
        SAFE_CAST(U_VATAmt AS FLOAT64) AS VAT,
        SAFE_CAST(U_TotalPremiumAmt AS FLOAT64) AS TotalPremium,
        SAFE_CAST(U_WHTAmt AS FLOAT64) AS WHT,
        SAFE_CAST(U_TotalEIRAmt AS FLOAT64) AS TotalEIR,
        SAFE_CAST(U_TotalSBTAmt AS FLOAT64) AS TotalSBT,
        SAFE_CAST(U_ProcessingFee AS FLOAT64) AS U_ProcessingFee,
        SAFE_CAST(U_ProcessingFeeVat AS FLOAT64) AS U_ProcessingFeeVat,
        SAFE_CAST(U_ShippingFee AS FLOAT64) AS U_ShippingFee,
        SAFE_CAST(U_ShippingFeeVat AS FLOAT64) AS U_ShippingFeeVat,
        SAFE_CAST(U_TotalAmount AS FLOAT64) AS U_TotalAmount,
        SAFE_CAST(U_Discount AS FLOAT64) AS U_Discount,
        U_PolicyStatus TransactionStatus,
        U_SubmissionStatus,
        U_ApprovalStatus,
        U_PaymentStatus,
        SAFE_CAST(U_ExpectedReceived AS FLOAT64) AS ExpectedReceived,
        SAFE_CAST(U_ActualReceived AS FLOAT64) AS U_ActualReceived,
        SAFE_CAST(U_InterestThisPeriod AS FLOAT64) AS U_InterestThisPeriod,
        SAFE_CAST(U_PrincipleThisPeriod AS FLOAT64) AS U_PrincipleThisPeriod,
        SAFE_CAST(U_InterestEIRThisPeriod AS FLOAT64) AS U_InterestEIRThisPeriod,
        SAFE_CAST(U_PrincipleEIRThisPeriod AS FLOAT64) AS U_PrincipleEIRThisPeriod,
        CASE WHEN U_PaymentDate = 'NULL' THEN '' ELSE CAST(FORMAT_DATE('%d%m%Y', DATE(U_PaymentDate)) AS STRING) END AS PaymentDate,
        U_Period,
        U_TotalPeriods TotalPeriods,
        U_PendingPayment PendingPayment,
        U_PaymentMethod PaymentMethod,
        U_PaymentChannel PaymentChannel,
        SAFE_CAST(FORMAT_DATE('%d%m%Y', U_ExpectedDate) AS STRING) AS ExpectedDate,
        U_RefOrder RefOrder,
        U_RefundAmt RefundAmountBeforeFee,
        U_RefundAmountAfterFee RefundAmountAfterFee,
        U_BillingAddress BillingAddress,
        SAFE_CAST(FORMAT_DATE('%d%m%Y', U_BatchRunDate) AS STRING) AS BatchRunDate
      FROM `pacific-plating-282708.sap_integration_v2.SAP_LIVE_2026`

      UNION ALL

      SELECT DISTINCT
        DocEntry,
        U_CompanyCode CompanyDB,
        U_OrderID,
        U_OrderItem,
        U_InvoiceNo,
        SAFE_CAST(FORMAT_DATE('%d%m%Y', U_OrderDate) AS STRING) AS OrderDate,
        U_InsuredID,
        U_Title,
        U_FirstName,
        U_LastName,
        U_InsurerCode,
        U_InsuranceGroup,
        U_InsuranceType,
        U_InsuranceProduct,
        U_ProductType,
        U_PolicyType,
        CAST(U_Endorse AS STRING) U_Endorse,
        SAFE_CAST(FORMAT_DATE('%d%m%Y', U_PolicyDate) AS STRING) AS PolicyDate,
        U_PolicyNo,
        SAFE_CAST(U_EndorsementNo AS STRING) AS EndorsementNo,
        U_ChassisNo,
        U_LicensePlate,
        U_GrossPremiumAmt GrossPremium,
        CAST(U_StampDutyAmt AS FLOAT64) AS StampDuty,
        SAFE_CAST(U_VATAmt AS FLOAT64) AS VAT,
        SAFE_CAST(U_TotalPremiumAmt AS FLOAT64) AS TotalPremium,
        SAFE_CAST(U_WHTAmt AS FLOAT64) AS WHT,
        SAFE_CAST(U_TotalEIRAmt AS FLOAT64) AS TotalEIR,
        SAFE_CAST(U_TotalSBTAmt AS FLOAT64) AS TotalSBT,
        SAFE_CAST(U_ProcessingFee AS FLOAT64) AS U_ProcessingFee,
        SAFE_CAST(U_ProcessingFeeVat AS FLOAT64) AS U_ProcessingFeeVat,
        SAFE_CAST(U_ShippingFee AS FLOAT64) AS U_ShippingFee,
        SAFE_CAST(U_ShippingFeeVat AS FLOAT64) AS U_ShippingFeeVat,
        SAFE_CAST(U_TotalAmount AS FLOAT64) AS U_TotalAmount,
        SAFE_CAST(U_Discount AS FLOAT64) AS U_Discount,
        U_PolicyStatus TransactionStatus,
        U_SubmissionStatus,
        U_ApprovalStatus,
        U_PaymentStatus,
        SAFE_CAST(U_ExpectedReceived AS FLOAT64) AS ExpectedReceived,
        SAFE_CAST(U_ActualReceived AS FLOAT64) AS U_ActualReceived,
        SAFE_CAST(U_InterestThisPeriod AS FLOAT64) AS U_InterestThisPeriod,
        SAFE_CAST(U_PrincipleThisPeriod AS FLOAT64) AS U_PrincipleThisPeriod,
        SAFE_CAST(U_InterestEIRThisPeriod AS FLOAT64) AS U_InterestEIRThisPeriod,
        SAFE_CAST(U_PrincipleEIRThisPeriod AS FLOAT64) AS U_PrincipleEIRThisPeriod,
        CASE WHEN U_PaymentDate = 'NULL' THEN '' ELSE CAST(FORMAT_DATE('%d%m%Y', DATE(U_PaymentDate)) AS STRING) END AS PaymentDate,
        U_Period,
        U_TotalPeriods TotalPeriods,
        U_PendingPayment PendingPayment,
        U_PaymentMethod PaymentMethod,
        U_PaymentChannel PaymentChannel,
        SAFE_CAST(FORMAT_DATE('%d%m%Y', U_ExpectedDate) AS STRING) AS ExpectedDate,
        U_RefOrder RefOrder,
        U_RefundAmt RefundAmountBeforeFee,
        U_RefundAmountAfterFee RefundAmountAfterFee,
        U_BillingAddress BillingAddress,
        SAFE_CAST(FORMAT_DATE('%d%m%Y', U_BatchRunDate) AS STRING) AS BatchRunDate
      FROM `pacific-plating-282708.sap_integration_v2.SAP_LIVE`
    )
  )
  WHERE _rn = 1;

  SET row_count = (SELECT COUNT(*) FROM `pacific-plating-282708.sap_integration_v3.sap_mirror_doc`);

  INSERT INTO `pacific-plating-282708.sap_integration_v3.pipeline_run_log`
    (run_id, run_type, step, scope, rows_in, rows_out, started_at, ended_at, status, error_message)
  VALUES (
    run_id,
    IF(STARTS_WITH(run_scope, 'ADHOC:'), 'ADHOC', 'NIGHTLY'),
    'sap_mirror_doc',
    run_scope,
    NULL,
    row_count,
    started,
    CURRENT_TIMESTAMP(),
    'SUCCESS',
    NULL
  );
END;

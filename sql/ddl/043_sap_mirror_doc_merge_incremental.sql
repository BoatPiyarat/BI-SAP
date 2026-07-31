-- 043_sap_mirror_doc_merge_incremental.sql
-- Boat priority 5 (2026-07-30), Boat-approved direction: replace sap_mirror_doc's full
-- CREATE OR REPLACE TABLE (full CTAS, rescans all of SAP_LIVE + 3 year-shards every run)
-- with an incremental MERGE. SOURCE ONLY. Nothing in this file has been deployed - the live
-- `sp_refresh_sap_mirror_doc` (024) is untouched. Requires class-A review + explicit deploy OK
-- before this replaces 024.
--
-- ============================================================================
-- ⚠️ Cost-win caveat, stated plainly rather than oversold: `SAP_LIVE` and its 3 year-shards
-- have NO partitioning and NO clustering (checked directly: `bq show` on SAP_LIVE returns no
-- timePartitioning/rangePartitioning key at all). BigQuery's columnar engine still has to
-- read the full value of every referenced column across the WHOLE table for a `WHERE
-- UpdateDate > watermark` filter - there is no block-level pruning to skip old rows. The
-- "~100x" cost win in docs/knowledge/KNOWLEDGE_ADDENDUM_20260730_v3.md §C6.4 is more
-- accurately attributed to downstream consumers reading the already-deduplicated,
-- CLUSTER-BY-U_OrderItem `sap_mirror_doc` (~1.3M rows) instead of scanning `SAP_LIVE` directly
-- (~8.3M rows and growing) - that win already exists today regardless of this file.
-- What THIS file's incremental-MERGE design actually buys, honestly stated:
--   1. Correctness fix: UpdateDate/UpdateTime are now selected and used in the tiebreak
--      (see the 297,413/297,604 investigation in docs/sessions/2026-07-30-claude.md P1 -
--      I could not reproduce that exact historical figure, but the missing-column gap it
--      described is real and is fixed here regardless).
--   2. Reduced DOWNSTREAM dedup/ROW_NUMBER computation - only rows touched since the
--      watermark need re-ranking, not the full 8.3M-row history every run.
--   3. Reduced OUTPUT/write cost - only changed DocEntries get MERGEd, not a full table
--      rewrite every run.
-- It does NOT reduce the bytes SCANNED from SAP_LIVE's un-partitioned columns to anywhere
-- near 100x on its own. If that scan cost matters enough to fix directly, the real lever is
-- adding CLUSTER BY to SAP_LIVE itself - a schema change, not a data cleanup, and arguably
-- compatible with the append-only hold (no rows touched) - but that is a separate decision,
-- not assumed or done here.
-- ============================================================================
--
-- ⚠️ SAP_LIVE append-only hold reaffirmed: nothing in this design cleans, dedupes, truncates,
-- rebuilds, or deletes any row in SAP_LIVE or its shards. This only changes how
-- `sap_integration_v3.sap_mirror_doc` (a v3 object) is refreshed.
--
-- ⚠️ Watermark boundary: the filter is strictly newer than `(last_upd_date,
-- last_upd_time)`. A source row that arrives late with exactly the already-merged DATE/HHMM pair
-- is not discoverable by this incremental path. The mandatory row-for-row comparison with a fresh
-- 024 full rebuild is the cutover gate; no claim of losslessness is made before that check passes.

-- ============================================================================
-- New control table: tracks the high-water mark actually merged, so the next run's source
-- scan can filter to only what's newer. Separate from pipeline_run_log (which times OUR
-- runs, not the SOURCE's own UpdateDate/UpdateTime).
-- ============================================================================
CREATE TABLE IF NOT EXISTS `pacific-plating-282708.sap_integration_v3.sap_mirror_doc_watermark` (
  singleton_id INT64,       -- always 1; single-row control table
  last_upd_date DATE,       -- MAX(DATE(UpdateDate)) actually merged as of the last successful run
  last_upd_time INT64,      -- MAX(UpdateTime) among rows sharing last_upd_date
  updated_at TIMESTAMP
);

-- Bootstrap row: an incremental run with no prior watermark must behave like a full run
-- (process everything), so seed with a value older than any real UpdateDate.
-- Run once, only when this table is first created - not part of the per-run procedure.
/*
INSERT INTO `pacific-plating-282708.sap_integration_v3.sap_mirror_doc_watermark`
  (singleton_id, last_upd_date, last_upd_time, updated_at)
VALUES (1, DATE '1900-01-01', 0, CURRENT_TIMESTAMP());
*/

CREATE OR REPLACE PROCEDURE `pacific-plating-282708.sap_integration_v3.sp_refresh_sap_mirror_doc_incremental`(run_scope STRING)
BEGIN
  DECLARE run_id STRING DEFAULT GENERATE_UUID();
  DECLARE started TIMESTAMP DEFAULT CURRENT_TIMESTAMP();
  DECLARE row_count INT64;
  DECLARE wm_date DATE;
  DECLARE wm_time INT64;
  DECLARE new_wm_date DATE;
  DECLARE new_wm_time INT64;

  SET (wm_date, wm_time) = (
    SELECT AS STRUCT last_upd_date, last_upd_time
    FROM `pacific-plating-282708.sap_integration_v3.sap_mirror_doc_watermark`
    WHERE singleton_id = 1
  );

  -- ==========================================================================
  -- Delta batch: only rows touched since the watermark, from the same 4 source
  -- tables as 024, same column list PLUS UpdateDate/UpdateTime (the fix).
  -- ==========================================================================
  CREATE TEMP TABLE delta AS
  WITH raw_delta AS (
    SELECT DocEntry, U_CompanyCode CompanyDB, U_OrderID, U_OrderItem, U_InvoiceNo,
      SAFE_CAST(FORMAT_DATE('%d%m%Y', U_OrderDate) AS STRING) AS OrderDate,
      U_InsuredID, U_Title, U_FirstName, U_LastName, U_InsurerCode, U_InsuranceGroup,
      U_InsuranceType, U_InsuranceProduct, U_ProductType, U_PolicyType,
      CAST(U_Endorse AS STRING) U_Endorse,
      SAFE_CAST(FORMAT_DATE('%d%m%Y', U_PolicyDate) AS STRING) AS PolicyDate,
      U_PolicyNo, SAFE_CAST(U_EndorsementNo AS STRING) AS EndorsementNo, U_ChassisNo,
      U_LicensePlate, U_GrossPremiumAmt GrossPremium, CAST(U_StampDutyAmt AS FLOAT64) AS StampDuty,
      SAFE_CAST(U_VATAmt AS FLOAT64) AS VAT, SAFE_CAST(U_TotalPremiumAmt AS FLOAT64) AS TotalPremium,
      SAFE_CAST(U_WHTAmt AS FLOAT64) AS WHT, SAFE_CAST(U_TotalEIRAmt AS FLOAT64) AS TotalEIR,
      SAFE_CAST(U_TotalSBTAmt AS FLOAT64) AS TotalSBT,
      SAFE_CAST(U_ProcessingFee AS FLOAT64) AS U_ProcessingFee,
      SAFE_CAST(U_ProcessingFeeVat AS FLOAT64) AS U_ProcessingFeeVat,
      SAFE_CAST(U_ShippingFee AS FLOAT64) AS U_ShippingFee,
      SAFE_CAST(U_ShippingFeeVat AS FLOAT64) AS U_ShippingFeeVat,
      SAFE_CAST(U_TotalAmount AS FLOAT64) AS U_TotalAmount,
      SAFE_CAST(U_Discount AS FLOAT64) AS U_Discount,
      U_PolicyStatus TransactionStatus, U_SubmissionStatus, U_ApprovalStatus, U_PaymentStatus,
      SAFE_CAST(U_ExpectedReceived AS FLOAT64) AS ExpectedReceived,
      SAFE_CAST(U_ActualReceived AS FLOAT64) AS U_ActualReceived,
      SAFE_CAST(U_InterestThisPeriod AS FLOAT64) AS U_InterestThisPeriod,
      SAFE_CAST(U_PrincipleThisPeriod AS FLOAT64) AS U_PrincipleThisPeriod,
      SAFE_CAST(U_InterestEIRThisPeriod AS FLOAT64) AS U_InterestEIRThisPeriod,
      SAFE_CAST(U_PrincipleEIRThisPeriod AS FLOAT64) AS U_PrincipleEIRThisPeriod,
      CASE WHEN U_PaymentDate = 'NULL' THEN '' ELSE CAST(FORMAT_DATE('%d%m%Y', DATE(U_PaymentDate)) AS STRING) END AS PaymentDate,
      U_Period, U_TotalPeriods TotalPeriods, U_PendingPayment PendingPayment,
      U_PaymentMethod PaymentMethod, U_PaymentChannel PaymentChannel,
      SAFE_CAST(FORMAT_DATE('%d%m%Y', U_ExpectedDate) AS STRING) AS ExpectedDate,
      U_RefOrder RefOrder, U_RefundAmt RefundAmountBeforeFee,
      U_RefundAmountAfterFee RefundAmountAfterFee, U_BillingAddress BillingAddress,
      SAFE_CAST(FORMAT_DATE('%d%m%Y', U_BatchRunDate) AS STRING) AS BatchRunDate,
      DATE(UpdateDate) AS UpdateDate, UpdateTime  -- native mirror type; recency time stays separate
    FROM `pacific-plating-282708.sap_integration_v2.SAP_LIVE_2024`
    WHERE UpdateDate > wm_date OR (UpdateDate = wm_date AND UpdateTime > wm_time)
    UNION ALL
    SELECT DocEntry, U_CompanyCode, U_OrderID, U_OrderItem, U_InvoiceNo,
      SAFE_CAST(FORMAT_DATE('%d%m%Y', U_OrderDate) AS STRING), U_InsuredID, U_Title, U_FirstName,
      U_LastName, U_InsurerCode, U_InsuranceGroup, U_InsuranceType, U_InsuranceProduct,
      U_ProductType, U_PolicyType, CAST(U_Endorse AS STRING),
      SAFE_CAST(FORMAT_DATE('%d%m%Y', U_PolicyDate) AS STRING), U_PolicyNo,
      SAFE_CAST(U_EndorsementNo AS STRING), U_ChassisNo, U_LicensePlate, U_GrossPremiumAmt,
      CAST(U_StampDutyAmt AS FLOAT64), SAFE_CAST(U_VATAmt AS FLOAT64),
      SAFE_CAST(U_TotalPremiumAmt AS FLOAT64), SAFE_CAST(U_WHTAmt AS FLOAT64),
      SAFE_CAST(U_TotalEIRAmt AS FLOAT64), SAFE_CAST(U_TotalSBTAmt AS FLOAT64),
      SAFE_CAST(U_ProcessingFee AS FLOAT64), SAFE_CAST(U_ProcessingFeeVat AS FLOAT64),
      SAFE_CAST(U_ShippingFee AS FLOAT64), SAFE_CAST(U_ShippingFeeVat AS FLOAT64),
      SAFE_CAST(U_TotalAmount AS FLOAT64), SAFE_CAST(U_Discount AS FLOAT64), U_PolicyStatus,
      U_SubmissionStatus, U_ApprovalStatus, U_PaymentStatus, SAFE_CAST(U_ExpectedReceived AS FLOAT64),
      SAFE_CAST(U_ActualReceived AS FLOAT64), SAFE_CAST(U_InterestThisPeriod AS FLOAT64),
      SAFE_CAST(U_PrincipleThisPeriod AS FLOAT64), SAFE_CAST(U_InterestEIRThisPeriod AS FLOAT64),
      SAFE_CAST(U_PrincipleEIRThisPeriod AS FLOAT64),
      CASE WHEN U_PaymentDate = 'NULL' THEN '' ELSE CAST(FORMAT_DATE('%d%m%Y', DATE(U_PaymentDate)) AS STRING) END,
      U_Period, U_TotalPeriods, U_PendingPayment, U_PaymentMethod, U_PaymentChannel,
      SAFE_CAST(FORMAT_DATE('%d%m%Y', U_ExpectedDate) AS STRING), U_RefOrder, U_RefundAmt,
      U_RefundAmountAfterFee, U_BillingAddress,
      SAFE_CAST(FORMAT_DATE('%d%m%Y', U_BatchRunDate) AS STRING), DATE(UpdateDate), UpdateTime
    FROM `pacific-plating-282708.sap_integration_v2.SAP_LIVE_2025`
    WHERE UpdateDate > wm_date OR (UpdateDate = wm_date AND UpdateTime > wm_time)
    UNION ALL
    SELECT DocEntry, U_CompanyCode, U_OrderID, U_OrderItem, U_InvoiceNo,
      SAFE_CAST(FORMAT_DATE('%d%m%Y', U_OrderDate) AS STRING), U_InsuredID, U_Title, U_FirstName,
      U_LastName, U_InsurerCode, U_InsuranceGroup, U_InsuranceType, U_InsuranceProduct,
      U_ProductType, U_PolicyType, CAST(U_Endorse AS STRING),
      SAFE_CAST(FORMAT_DATE('%d%m%Y', U_PolicyDate) AS STRING), U_PolicyNo,
      SAFE_CAST(U_EndorsementNo AS STRING), U_ChassisNo, U_LicensePlate, U_GrossPremiumAmt,
      CAST(U_StampDutyAmt AS FLOAT64), SAFE_CAST(U_VATAmt AS FLOAT64),
      SAFE_CAST(U_TotalPremiumAmt AS FLOAT64), SAFE_CAST(U_WHTAmt AS FLOAT64),
      SAFE_CAST(U_TotalEIRAmt AS FLOAT64), SAFE_CAST(U_TotalSBTAmt AS FLOAT64),
      SAFE_CAST(U_ProcessingFee AS FLOAT64), SAFE_CAST(U_ProcessingFeeVat AS FLOAT64),
      SAFE_CAST(U_ShippingFee AS FLOAT64), SAFE_CAST(U_ShippingFeeVat AS FLOAT64),
      SAFE_CAST(U_TotalAmount AS FLOAT64), SAFE_CAST(U_Discount AS FLOAT64), U_PolicyStatus,
      U_SubmissionStatus, U_ApprovalStatus, U_PaymentStatus, SAFE_CAST(U_ExpectedReceived AS FLOAT64),
      SAFE_CAST(U_ActualReceived AS FLOAT64), SAFE_CAST(U_InterestThisPeriod AS FLOAT64),
      SAFE_CAST(U_PrincipleThisPeriod AS FLOAT64), SAFE_CAST(U_InterestEIRThisPeriod AS FLOAT64),
      SAFE_CAST(U_PrincipleEIRThisPeriod AS FLOAT64),
      CASE WHEN U_PaymentDate = 'NULL' THEN '' ELSE CAST(FORMAT_DATE('%d%m%Y', DATE(U_PaymentDate)) AS STRING) END,
      U_Period, U_TotalPeriods, U_PendingPayment, U_PaymentMethod, U_PaymentChannel,
      SAFE_CAST(FORMAT_DATE('%d%m%Y', U_ExpectedDate) AS STRING), U_RefOrder, U_RefundAmt,
      U_RefundAmountAfterFee, U_BillingAddress,
      SAFE_CAST(FORMAT_DATE('%d%m%Y', U_BatchRunDate) AS STRING), DATE(UpdateDate), UpdateTime
    FROM `pacific-plating-282708.sap_integration_v2.SAP_LIVE_2026`
    WHERE UpdateDate > wm_date OR (UpdateDate = wm_date AND UpdateTime > wm_time)
    UNION ALL
    SELECT DocEntry, U_CompanyCode, U_OrderID, U_OrderItem, U_InvoiceNo,
      SAFE_CAST(FORMAT_DATE('%d%m%Y', U_OrderDate) AS STRING), U_InsuredID, U_Title, U_FirstName,
      U_LastName, U_InsurerCode, U_InsuranceGroup, U_InsuranceType, U_InsuranceProduct,
      U_ProductType, U_PolicyType, CAST(U_Endorse AS STRING),
      SAFE_CAST(FORMAT_DATE('%d%m%Y', U_PolicyDate) AS STRING), U_PolicyNo,
      SAFE_CAST(U_EndorsementNo AS STRING), U_ChassisNo, U_LicensePlate, U_GrossPremiumAmt,
      CAST(U_StampDutyAmt AS FLOAT64), SAFE_CAST(U_VATAmt AS FLOAT64),
      SAFE_CAST(U_TotalPremiumAmt AS FLOAT64), SAFE_CAST(U_WHTAmt AS FLOAT64),
      SAFE_CAST(U_TotalEIRAmt AS FLOAT64), SAFE_CAST(U_TotalSBTAmt AS FLOAT64),
      SAFE_CAST(U_ProcessingFee AS FLOAT64), SAFE_CAST(U_ProcessingFeeVat AS FLOAT64),
      SAFE_CAST(U_ShippingFee AS FLOAT64), SAFE_CAST(U_ShippingFeeVat AS FLOAT64),
      SAFE_CAST(U_TotalAmount AS FLOAT64), SAFE_CAST(U_Discount AS FLOAT64), U_PolicyStatus,
      U_SubmissionStatus, U_ApprovalStatus, U_PaymentStatus, SAFE_CAST(U_ExpectedReceived AS FLOAT64),
      SAFE_CAST(U_ActualReceived AS FLOAT64), SAFE_CAST(U_InterestThisPeriod AS FLOAT64),
      SAFE_CAST(U_PrincipleThisPeriod AS FLOAT64), SAFE_CAST(U_InterestEIRThisPeriod AS FLOAT64),
      SAFE_CAST(U_PrincipleEIRThisPeriod AS FLOAT64),
      CASE WHEN U_PaymentDate = 'NULL' THEN '' ELSE CAST(FORMAT_DATE('%d%m%Y', DATE(U_PaymentDate)) AS STRING) END,
      U_Period, U_TotalPeriods, U_PendingPayment, U_PaymentMethod, U_PaymentChannel,
      SAFE_CAST(FORMAT_DATE('%d%m%Y', U_ExpectedDate) AS STRING), U_RefOrder, U_RefundAmt,
      U_RefundAmountAfterFee, U_BillingAddress,
      SAFE_CAST(FORMAT_DATE('%d%m%Y', U_BatchRunDate) AS STRING), DATE(UpdateDate), UpdateTime
    FROM `pacific-plating-282708.sap_integration_v2.SAP_LIVE`
    WHERE UpdateDate > wm_date OR (UpdateDate = wm_date AND UpdateTime > wm_time)
  )
  -- Per-DocEntry pick within the delta batch itself: same RULE-03 rule as 024.
  SELECT * EXCEPT(_rn)
  FROM (
    SELECT *,
      ROW_NUMBER() OVER (
        PARTITION BY DocEntry
        ORDER BY UpdateDate DESC, UpdateTime DESC, DocEntry DESC
      ) AS _rn
    FROM raw_delta
  )
  WHERE _rn = 1;

  -- ==========================================================================
  -- MERGE: every DocEntry in `delta` is, by construction of the watermark filter,
  -- strictly newer than anything currently in sap_mirror_doc for that DocEntry -
  -- so a match is always safe to overwrite outright, no extra recency comparison needed.
  -- ==========================================================================
  MERGE `pacific-plating-282708.sap_integration_v3.sap_mirror_doc` T
  USING delta D
  ON T.DocEntry = D.DocEntry
  WHEN MATCHED THEN UPDATE SET
    CompanyDB = D.CompanyDB, U_OrderID = D.U_OrderID, U_OrderItem = D.U_OrderItem,
    U_InvoiceNo = D.U_InvoiceNo, OrderDate = D.OrderDate, U_InsuredID = D.U_InsuredID,
    U_Title = D.U_Title, U_FirstName = D.U_FirstName, U_LastName = D.U_LastName,
    U_InsurerCode = D.U_InsurerCode, U_InsuranceGroup = D.U_InsuranceGroup,
    U_InsuranceType = D.U_InsuranceType, U_InsuranceProduct = D.U_InsuranceProduct,
    U_ProductType = D.U_ProductType, U_PolicyType = D.U_PolicyType, U_Endorse = D.U_Endorse,
    PolicyDate = D.PolicyDate, U_PolicyNo = D.U_PolicyNo, EndorsementNo = D.EndorsementNo,
    U_ChassisNo = D.U_ChassisNo, U_LicensePlate = D.U_LicensePlate, GrossPremium = D.GrossPremium,
    StampDuty = D.StampDuty, VAT = D.VAT, TotalPremium = D.TotalPremium, WHT = D.WHT,
    TotalEIR = D.TotalEIR, TotalSBT = D.TotalSBT, U_ProcessingFee = D.U_ProcessingFee,
    U_ProcessingFeeVat = D.U_ProcessingFeeVat, U_ShippingFee = D.U_ShippingFee,
    U_ShippingFeeVat = D.U_ShippingFeeVat, U_TotalAmount = D.U_TotalAmount,
    U_Discount = D.U_Discount, TransactionStatus = D.TransactionStatus,
    U_SubmissionStatus = D.U_SubmissionStatus, U_ApprovalStatus = D.U_ApprovalStatus,
    U_PaymentStatus = D.U_PaymentStatus, ExpectedReceived = D.ExpectedReceived,
    U_ActualReceived = D.U_ActualReceived, U_InterestThisPeriod = D.U_InterestThisPeriod,
    U_PrincipleThisPeriod = D.U_PrincipleThisPeriod,
    U_InterestEIRThisPeriod = D.U_InterestEIRThisPeriod,
    U_PrincipleEIRThisPeriod = D.U_PrincipleEIRThisPeriod, PaymentDate = D.PaymentDate,
    U_Period = D.U_Period, TotalPeriods = D.TotalPeriods, PendingPayment = D.PendingPayment,
    PaymentMethod = D.PaymentMethod, PaymentChannel = D.PaymentChannel,
    ExpectedDate = D.ExpectedDate, RefOrder = D.RefOrder,
    RefundAmountBeforeFee = D.RefundAmountBeforeFee,
    RefundAmountAfterFee = D.RefundAmountAfterFee, BillingAddress = D.BillingAddress,
    BatchRunDate = D.BatchRunDate, UpdateDate = D.UpdateDate, UpdateTime = D.UpdateTime
  WHEN NOT MATCHED THEN INSERT (
    DocEntry, CompanyDB, U_OrderID, U_OrderItem, U_InvoiceNo, OrderDate, U_InsuredID, U_Title,
    U_FirstName, U_LastName, U_InsurerCode, U_InsuranceGroup, U_InsuranceType, U_InsuranceProduct,
    U_ProductType, U_PolicyType, U_Endorse, PolicyDate, U_PolicyNo, EndorsementNo, U_ChassisNo,
    U_LicensePlate, GrossPremium, StampDuty, VAT, TotalPremium, WHT, TotalEIR, TotalSBT,
    U_ProcessingFee, U_ProcessingFeeVat, U_ShippingFee, U_ShippingFeeVat, U_TotalAmount,
    U_Discount, TransactionStatus, U_SubmissionStatus, U_ApprovalStatus, U_PaymentStatus,
    ExpectedReceived, U_ActualReceived, U_InterestThisPeriod, U_PrincipleThisPeriod,
    U_InterestEIRThisPeriod, U_PrincipleEIRThisPeriod, PaymentDate, U_Period, TotalPeriods,
    PendingPayment, PaymentMethod, PaymentChannel, ExpectedDate, RefOrder,
    RefundAmountBeforeFee, RefundAmountAfterFee, BillingAddress, BatchRunDate, UpdateDate, UpdateTime
  ) VALUES (
    D.DocEntry, D.CompanyDB, D.U_OrderID, D.U_OrderItem, D.U_InvoiceNo, D.OrderDate,
    D.U_InsuredID, D.U_Title, D.U_FirstName, D.U_LastName, D.U_InsurerCode, D.U_InsuranceGroup,
    D.U_InsuranceType, D.U_InsuranceProduct, D.U_ProductType, D.U_PolicyType, D.U_Endorse,
    D.PolicyDate, D.U_PolicyNo, D.EndorsementNo, D.U_ChassisNo, D.U_LicensePlate,
    D.GrossPremium, D.StampDuty, D.VAT, D.TotalPremium, D.WHT, D.TotalEIR, D.TotalSBT,
    D.U_ProcessingFee, D.U_ProcessingFeeVat, D.U_ShippingFee, D.U_ShippingFeeVat,
    D.U_TotalAmount, D.U_Discount, D.TransactionStatus, D.U_SubmissionStatus, D.U_ApprovalStatus,
    D.U_PaymentStatus, D.ExpectedReceived, D.U_ActualReceived, D.U_InterestThisPeriod,
    D.U_PrincipleThisPeriod, D.U_InterestEIRThisPeriod, D.U_PrincipleEIRThisPeriod,
    D.PaymentDate, D.U_Period, D.TotalPeriods, D.PendingPayment, D.PaymentMethod,
    D.PaymentChannel, D.ExpectedDate, D.RefOrder, D.RefundAmountBeforeFee,
    D.RefundAmountAfterFee, D.BillingAddress, D.BatchRunDate, D.UpdateDate, D.UpdateTime
  );

  SET row_count = (SELECT COUNT(*) FROM delta);

  IF row_count > 0 THEN
    SET (new_wm_date, new_wm_time) = (
      SELECT AS STRUCT UpdateDate, MAX(UpdateTime) AS UpdateTime
      FROM delta
      WHERE UpdateDate = (SELECT MAX(UpdateDate) FROM delta)
      GROUP BY UpdateDate
    );

    UPDATE `pacific-plating-282708.sap_integration_v3.sap_mirror_doc_watermark`
    SET last_upd_date = new_wm_date, last_upd_time = new_wm_time, updated_at = CURRENT_TIMESTAMP()
    WHERE singleton_id = 1;
  END IF;

  INSERT INTO `pacific-plating-282708.sap_integration_v3.pipeline_run_log`
    (run_id, run_type, step, scope, rows_in, rows_out, started_at, ended_at, status, error_message)
  VALUES (
    run_id,
    IF(STARTS_WITH(run_scope, 'ADHOC:'), 'ADHOC', 'NIGHTLY'),
    'sap_mirror_doc_incremental',
    run_scope,
    NULL,
    row_count,
    started,
    CURRENT_TIMESTAMP(),
    'SUCCESS',
    NULL
  );
END;

-- ============================================================================
-- Cutover plan (not executed): 1) create sap_mirror_doc_watermark, seed with a bootstrap
-- row older than any real UpdateDate; 2) run this new procedure once as a full catch-up
-- (watermark starts at 1900-01-01, so the first run processes everything, same cost as
-- today's full CTAS, one time); 3) diff sap_mirror_doc's content against a fresh run of
-- the existing 024 CTAS logic - must match row-for-row before swapping the nightly chain
-- to call this procedure instead of 024's; 4) only then repoint 008/014/020's scheduled
-- chain. None of steps 1-4 done here - source only, awaiting class-A review.
-- ============================================================================

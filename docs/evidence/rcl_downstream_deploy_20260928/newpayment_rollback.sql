CREATE OR REPLACE VIEW `pacific-plating-282708.sap_integration_v2.RCL 05_newpayment` AS
-- RCL 05_newpayment -- FIXED & TUNED VERSION

-- Fixed & tuned: 2026-08-28 (Boat review)

-- Changes:

--  1. FIX (dead code / perf): removed the `sap` CTE (a full transform of

--     all of SAP_LIVE_FULL) and the `cancelled` CTE -- neither was

--     referenced anywhere in the final SELECT (only `newpayment` and

--     `interface` were used). That was a full-table scan+transform paid

--     for nothing.

--  2. FIX (correctness, confirmed with Boat -- same root cause suspected

--     for Chain 3 / DDL 043): replaced the MAX(Period)-per-OrderItem

--     "watermark" with a genuine PER-PERIOD existence check. The old logic

--     (`careos_installment > MAX(paid period)`) assumed periods are paid

--     strictly in sequence with no gaps -- if period 2 was skipped but

--     period 3 got marked Paid, period 2 would be wrongly treated as

--     "already covered" forever and never surface as missing/new. The new

--     logic checks, for each exact (OrderItem, Period) pair CareOS says

--     should exist, whether THAT SPECIFIC period is already Paid in SAP --

--     no assumption of contiguous sequence.

-- ============================================================

-- RCL 05_newpayment -- FIXED & TUNED VERSION

-- Fixed & tuned: 2026-08-28 (Boat review)

-- Redeployed 2026-08-29: previous live definition under this name was

-- actually the 13-col `RCL 05_paid by period` logic (careos_orders join) --

-- wrong definition, root cause of UNION ALL column-count mismatch in

-- 06_02. This corrects it to the intended 56-col, schema-matched-to-

-- RCL-05_paid definition.



-- RCL 05_newpayment -- FIXED & TUNED VERSION

-- Redeployed 2026-08-29 (Boat review): previous live definition under

-- this name was actually the 13-col `RCL 05_paid by period` logic --

-- wrong definition, root cause of UNION ALL column-count mismatch

-- (56 vs 13) in 06_02. Corrected to the intended 56-col definition,

-- schema-matched to RCL 05_paid via sap_dashboard_carepay_installment.

-- Also explicitly casts RefundAmountBeforeFee/AfterFee to FLOAT64

-- (source has them as INT64; RCL 05_paid has them as FLOAT64 --

-- BigQuery would implicit-coerce in UNION ALL, but made explicit here

-- to avoid relying on that behavior silently).

WITH

  sap_paid_periods AS (

    -- exact per-(OrderItem, Period) existence check -- NOT a MAX watermark, NOT an all-period fan-out

    SELECT DISTINCT

      U_OrderItem AS order_item,

      SAFE_CAST(U_Period AS INT64) AS period

    FROM `pacific-plating-282708.sap_integration_v2.SAP_LIVE_FULL`

    WHERE TransactionStatus IN ('Paid', 'paid')

  ),



  interface AS (

    SELECT

      * REPLACE (

        CAST(RefundAmountBeforeFee AS FLOAT64) AS RefundAmountBeforeFee,

        CAST(RefundAmountAfterFee AS FLOAT64) AS RefundAmountAfterFee

      ),

      SAFE_CAST(Period AS INT64) AS careos_installment

    FROM `pacific-plating-282708.sap_data_engineer.sap_dashboard_carepay_installment`

  )



SELECT DISTINCT

  interface.* EXCEPT(careos_installment)

FROM interface

WHERE

  interface.careos_installment IS NOT NULL

  AND NOT EXISTS (

    SELECT 1

    FROM sap_paid_periods p

    WHERE p.order_item = interface.OrderItem

      AND p.period = interface.careos_installment

  )



ORDER BY interface.OrderItem, careos_installment;

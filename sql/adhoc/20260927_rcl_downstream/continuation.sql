CREATE TEMP TABLE candidate_gate AS -- 2026-09-27 downstream candidate; SELECT only, NOT DEPLOYED.
-- 2026-09-26 same-period payment correction. Source only; not deployed.
-- RCL 05_paid by period -- FIXED & CREATED 2026-08-29 (Boat review)
-- Previously this logic lived (mislabeled) under `RCL 05_newpayment`.
-- Bug fixed here: original version joined `sap` to `charges` (ALL periods
-- ever paid) instead of `charges_ranking` (latest period only), then
-- relied on DISTINCT to collapse -- this let orders where an OLD period
-- was still missing from SAP mask the fact that the LATEST period was
-- already Paid+Paid, producing false "qualified" rows
-- (e.g. "1/10 CareOS paid, SAP paid" wrongly surfaced).
-- Fix: NOT EXISTS check scoped to charges_ranking.installment_number
-- (the actual latest period) plus OrderItem-level join key (was OrderID-only).
WITH charges AS (
  SELECT *
  FROM `pacific-plating-282708.careos.carepay_charges`
  WHERE status = 'SUCCESSFUL'
),

charges_ranking AS (
  SELECT *,
    ROW_NUMBER() OVER (PARTITION BY transaction_id ORDER BY installment_number DESC, update_time DESC, create_time DESC, id DESC) AS rank
  FROM charges
  QUALIFY rank = 1
),

sap_paid_periods AS (
  -- exact per-(OrderItem, Period) existence check -- NOT a MAX watermark, NOT an all-period fan-out
  SELECT DISTINCT
    U_OrderItem AS order_item,
    SAFE_CAST(U_Period AS INT64) AS period
  FROM `pacific-plating-282708._script7c6faf4dc1f287623ae26f66d20de48b274328dd.evidence_sap`
  WHERE TransactionStatus IN ('Paid', 'paid')
)
,
outstanding_receipt_items AS (
  -- Any recent unsent receipt can reopen an item, even if a later period is Paid.
  SELECT DISTINCT OrderItem
  FROM `pacific-plating-282708._script7c6faf4dc1f287623ae26f66d20de48b274328dd.candidate_newpayment` n
  JOIN `pacific-plating-282708.careos.careos_order_items` oi ON oi.human_id = n.OrderItem
  JOIN `pacific-plating-282708.careos.careos_orders` o ON o.id = oi.order_id
  JOIN (
    SELECT transaction_id, installment_number, third_party_id, update_time,
      ROW_NUMBER() OVER (PARTITION BY transaction_id, installment_number ORDER BY create_time, id) AS source_charge_rank
    FROM `pacific-plating-282708.careos.carepay_charges`
    WHERE status='SUCCESSFUL' AND service_provider='RABBIT_LENDING'
  ) c
    ON o.payment = CONCAT('transactions/', c.transaction_id)
    AND c.installment_number = SAFE_CAST(n.Period AS INT64)
    AND n.InvoiceNo = CASE WHEN c.installment_number = 1
      THEN CONCAT('2_', IF(c.source_charge_rank=1, COALESCE(c.third_party_id,oi.human_id),c.third_party_id)) ELSE IF(c.source_charge_rank=1,COALESCE(c.third_party_id,oi.human_id),c.third_party_id) END
    AND c.source_charge_rank >= 1
  WHERE ActualReceived > 0
    AND LOWER(TRIM(TransactionStatus)) = 'paid'
    AND NULLIF(TRIM(InvoiceNo), '') IS NOT NULL
    AND UPPER(TRIM(InvoiceNo)) != 'NULL'
    AND DATE(c.update_time)
      BETWEEN DATE_TRUNC(DATE_SUB(CURRENT_DATE(), INTERVAL 2 MONTH), MONTH)
      AND CURRENT_DATE()
)

SELECT DISTINCT
  orders.human_id,
  oi.human_id AS order_item,
  orders.create_time AS order_create_time,
  orders.update_time AS order_update_time,
  orders.is_fully_paid,
  orders.is_cancelled,
  transactions.payment_option,
  charges_ranking.installment_number,
  orders.cancel_time,
  charges_ranking.update_time AS charges_update_time,
  CASE
    WHEN orders.create_time < '2024-03-28' THEN 'icollection'
    ELSE 'carepay'
  END AS sql_view_using,
  orders.product,
  oi.motor_item_type AS InsuranceType
FROM `pacific-plating-282708.careos.careos_orders` AS orders
LEFT JOIN `pacific-plating-282708.careos.careos_order_items` AS oi
  ON orders.id = oi.order_id
LEFT JOIN `pacific-plating-282708.careos.carepay_transactions` AS transactions
  ON CONCAT('transactions/', transactions.id) = orders.payment
LEFT JOIN charges_ranking
  ON charges_ranking.transaction_id = transactions.id
LEFT JOIN outstanding_receipt_items AS outstanding
  ON outstanding.OrderItem = oi.human_id
WHERE 1=1
  AND charges_ranking.installment_number IS NOT NULL
  AND (
    DATE(charges_ranking.update_time)
      BETWEEN DATE_TRUNC(DATE_SUB(CURRENT_DATE(), INTERVAL 2 MONTH), MONTH)
      AND CURRENT_DATE()
    OR outstanding.OrderItem IS NOT NULL
  )
  AND transactions.payment_option = 'RABBIT_CARE_INSTALLMENT'
  AND (
    NOT EXISTS (
      SELECT 1
      FROM sap_paid_periods p
      WHERE p.order_item = oi.human_id
        AND p.period = charges_ranking.installment_number
    )
    OR outstanding.OrderItem IS NOT NULL
  )
ORDER BY orders.create_time ASC;
CREATE TEMP TABLE candidate_wrapper AS -- 2026-09-27 downstream candidate; SELECT only, NOT DEPLOYED.
-- Full source-only legacy root-fix proposal for:
--   pacific-plating-282708.sap_view.RCL_Motor_process_2_newpayment
--
-- Root fixes:
--   1. Route only products/car-insurance into this Motor interface.
--   2. Exclude an OrderItem when the canonical CareOS item is cancelled. This keeps the
--      whole cancelled schedule out of new-payment instead of mixing current pending rows
--      with historical SAP Paid rows removed by RCL 05_paid.
--   3. Preserve legitimate same-period additional-payment rows. ExpectedReceived = 0 rows
--      are deduplicated by InvoiceNo (or their existing deterministic fallback), while a
--      normal scheduled row remains one row per OrderItem/Period.
--
-- SELECT only: this file does not replace or deploy the legacy view.

WITH
  interface AS (
    SELECT *
    FROM `pacific-plating-282708._script7c6faf4dc1f287623ae26f66d20de48b274328dd.evidence_paid`

    UNION ALL

    SELECT *
    FROM `pacific-plating-282708._script7c6faf4dc1f287623ae26f66d20de48b274328dd.candidate_newpayment`
  ),

  eligible_newpayment_items AS (
    SELECT DISTINCT
      paid_by_period.order_item
    FROM candidate_gate AS paid_by_period
    JOIN `pacific-plating-282708.careos.careos_order_items` AS order_item
      ON order_item.human_id = paid_by_period.order_item
    WHERE paid_by_period.product = 'products/car-insurance'
      AND paid_by_period.InsuranceType != 'MOTOR_TYPE_COMPULSORY'
      AND order_item.is_cancelled IS NOT TRUE
      AND order_item.cancel_time IS NULL
  ),

  source AS (
    SELECT DISTINCT
      interface.*
    FROM interface
    JOIN eligible_newpayment_items
      ON eligible_newpayment_items.order_item = interface.OrderItem
    WHERE TRUE -- Payment recency belongs to the receipt gate, not order creation year.
      -- Fail closed against RCB/RCL and NonMotor routing leakage.
      AND interface.InsuranceGroup = 'Motor'
      AND interface.InsuranceType != 'MOTOR_TYPE_COMPULSORY'
  ),

  classified AS (
    SELECT
      source.*,
      CASE
        WHEN COALESCE(source.ExpectedReceived, 0) = 0
          AND COALESCE(source.ActualReceived, 0) > 0
        THEN 1
        ELSE 0
      END AS is_additional_payment,
      ROW_NUMBER() OVER (
        PARTITION BY
          source.OrderItem,
          source.Period,
          CASE
            WHEN COALESCE(source.ExpectedReceived, 0) = 0
              AND COALESCE(source.ActualReceived, 0) > 0
            THEN COALESCE(
              NULLIF(source.InvoiceNo, ''),
              CONCAT(
                'additional_',
                CAST(source.ActualReceived AS STRING),
                '_',
                COALESCE(source.PaymentDate, '')
              )
            )
            ELSE 'normal_period_row'
          END
        ORDER BY
          CASE
            WHEN source.InvoiceNo IS NOT NULL
              AND source.InvoiceNo NOT IN ('', 'null', 'NULL')
            THEN 1 ELSE 2
          END,
          CASE
            WHEN source.PolicyNo IS NOT NULL
              AND source.PolicyNo NOT IN ('', 'null', 'NULL')
            THEN 1 ELSE 2
          END,
          CASE
            WHEN source.PaymentDate IS NOT NULL
              AND source.PaymentDate NOT IN ('', 'null', 'NULL')
            THEN 1 ELSE 2
          END,
          SAFE.PARSE_DATE('%d%m%Y', source.PaymentDate) DESC,
          TO_JSON_STRING(source) DESC
      ) AS rn
    FROM source
  )

SELECT
  * EXCEPT (is_additional_payment, rn)
FROM classified
WHERE rn = 1
ORDER BY OrderID, OrderItem, Period;
CREATE TEMP TABLE receipt_lineage AS -- 2026-09-27 downstream candidate; SELECT only, NOT DEPLOYED.
-- 2026-09-26 same-period payment correction. Source only; not deployed.
-- SELECT-only replacement for sap_integration_v2.RCL 05_newpayment.
-- Ordinary periods keep the existing paid-period exclusion.
-- Additional payments use immutable event identity, including the established
-- raw/2_ invoice alias for installment 1. No SAP values are rewritten.
WITH
  sap_paid_periods AS (
    SELECT DISTINCT U_OrderItem AS order_item, SAFE_CAST(U_Period AS INT64) AS period
    FROM `pacific-plating-282708._script7c6faf4dc1f287623ae26f66d20de48b274328dd.evidence_sap`
    WHERE TransactionStatus IN ('Paid', 'paid')
  ),
  sap_terminal_events AS (
    SELECT DISTINCT U_OrderItem AS order_item, SAFE_CAST(U_Period AS INT64) AS period,
      U_InvoiceNo AS invoice_no
    FROM `pacific-plating-282708._script7c6faf4dc1f287623ae26f66d20de48b274328dd.evidence_sap`
    WHERE LOWER(TRIM(TransactionStatus)) IN
      ('paid', 'cancelled', 'cancelled (change order / rejected)')
      AND NULLIF(TRIM(U_InvoiceNo), '') IS NOT NULL
      AND UPPER(TRIM(U_InvoiceNo)) != 'NULL'
  ),
  source_receipts AS (
    SELECT id, transaction_id, installment_number, third_party_id, create_time, update_time,
      ROW_NUMBER() OVER (PARTITION BY transaction_id, installment_number ORDER BY create_time, id) AS source_charge_rank,
      COUNT(*) OVER (PARTITION BY id) AS charge_id_rows,
      COUNT(*) OVER (PARTITION BY transaction_id, installment_number, third_party_id) AS invoice_rows,
      COUNT(*) OVER (PARTITION BY transaction_id, installment_number, create_time) AS timestamp_rows
    FROM `pacific-plating-282708.careos.carepay_charges`
    WHERE status = 'SUCCESSFUL' AND service_provider = 'RABBIT_LENDING'
  ),
  source_receipt_events AS (
    -- Preserve rank lineage even when additional-receipt eligibility fails.
    -- The fallback mirrors dashboard identity ONLY for classification; it is
    -- never accepted as a new additional receipt's invoice identity.
    SELECT oi.human_id AS order_item, c.installment_number AS period,
      CASE WHEN c.installment_number = 1 AND oi.motor_item_type='MOTOR_TYPE_COMPULSORY'
        THEN CONCAT('2_',c.third_party_id)
        WHEN c.installment_number = 1 THEN CONCAT('2_', COALESCE(c.third_party_id, oi.human_id))
        ELSE COALESCE(c.third_party_id, oi.human_id) END AS invoice_no,
      MIN(c.update_time) AS raw_update_time,
      CASE WHEN COUNT(*) = 1 THEN MIN(c.source_charge_rank) END AS source_charge_rank,
      COUNT(*) AS source_event_rows,
      COUNT(*) = 1 AND COUNTIF(
        NULLIF(TRIM(c.id), '') IS NULL
        OR NULLIF(TRIM(c.third_party_id), '') IS NULL
        OR UPPER(TRIM(c.third_party_id)) = 'NULL'
        OR c.charge_id_rows != 1 OR c.invoice_rows != 1 OR c.timestamp_rows != 1
      ) = 0 AS additional_identity_valid
    FROM source_receipts c
    JOIN `pacific-plating-282708.careos.careos_orders` o
      ON o.payment = CONCAT('transactions/', c.transaction_id)
    JOIN `pacific-plating-282708.careos.careos_order_items` oi
      ON oi.order_id = o.id
    WHERE NULLIF(TRIM(oi.human_id), '') IS NOT NULL
      AND (COALESCE(oi.motor_item_type,'') != 'MOTOR_TYPE_COMPULSORY' OR c.source_charge_rank=1)
    GROUP BY order_item, period, invoice_no
  ),
  interface AS (
    SELECT
      d.CompanyDB,
      d.OrderID,
      d.OrderItem,
      d.InvoiceNo,
      d.OrderDate,
      d.InsuredID,
      d.Title,
      d.FirstName,
      d.LastName,
      d.InsurerCode,
      d.InsuranceGroup,
      d.InsuranceType,
      d.InsuranceProduct,
      d.ProductType,
      d.PolicyType,
      d.Endorse,
      d.PolicyDate,
      d.PolicyNo,
      d.EndorsementNo,
      d.ChassisNo,
      d.LicensePlate,
      d.GrossPremium,
      d.StampDuty,
      d.VAT,
      d.TotalPremium,
      d.WHT,
      d.TotalEIR,
      d.TotalSBT,
      d.ProcessingFee,
      d.ProcessingFeeVat,
      d.ShippingFee,
      d.ShippingFeeVat,
      d.TotalAmount,
      d.Discount,
      d.TransactionStatus,
      d.SubmissionStatus,
      d.ApprovalStatus,
      d.PaymentStatus,
      d.ExpectedReceived,
      d.ActualReceived,
      d.InterestThisPeriod,
      d.PrincipleThisPeriod,
      d.InterestEIRThisPeriod,
      d.PrincipleEIRThisPeriod,
      d.PaymentDate,
      d.Period,
      d.TotalPeriods,
      d.PendingPayment,
      d.PaymentMethod,
      d.PaymentChannel,
      d.ExpectedDate,
      d.RefOrder,
      CAST(d.RefundAmountBeforeFee AS FLOAT64) AS RefundAmountBeforeFee,
      CAST(d.RefundAmountAfterFee AS FLOAT64) AS RefundAmountAfterFee,
      d.BillingAddress,
      d.BatchRunDate,
      SAFE_CAST(d.Period AS INT64) AS careos_installment,
      v.raw_update_time, v.source_charge_rank, v.source_event_rows, v.additional_identity_valid,
      COALESCE(ExpectedReceived = 0, FALSE)
        AND COALESCE(ActualReceived, 0) > 0
        AND LOWER(TRIM(COALESCE(TransactionStatus, ''))) = 'paid'
        AS has_additional_shape
    FROM `pacific-plating-282708._script7c6faf4dc1f287623ae26f66d20de48b274328dd.live_dashboard` d
    LEFT JOIN source_receipt_events v ON v.order_item=d.OrderItem
      AND v.period=SAFE_CAST(d.Period AS INT64) AND v.invoice_no IS NOT DISTINCT FROM d.InvoiceNo
  )
SELECT OrderItem,Period,InvoiceNo,raw_update_time,source_charge_rank FROM interface;
CREATE TEMP TABLE added AS SELECT c.* FROM candidate_wrapper c WHERE TO_JSON_STRING(c) NOT IN (SELECT TO_JSON_STRING(b) FROM `pacific-plating-282708._script7c6faf4dc1f287623ae26f66d20de48b274328dd.baseline_wrapper` b);
SELECT CURRENT_TIMESTAMP() AS checked_at_utc,
(SELECT COUNT(*) FROM `pacific-plating-282708._script7c6faf4dc1f287623ae26f66d20de48b274328dd.baseline_wrapper`) AS baseline_rows,
(SELECT COUNT(*) FROM candidate_wrapper) AS candidate_rows,
(SELECT COUNT(*) FROM (SELECT TO_JSON_STRING(b) FROM `pacific-plating-282708._script7c6faf4dc1f287623ae26f66d20de48b274328dd.baseline_wrapper` b EXCEPT DISTINCT SELECT TO_JSON_STRING(c) FROM candidate_wrapper c)) AS removed_wrapper_payloads,
(SELECT COUNT(*) FROM (SELECT TO_JSON_STRING(b) FROM `pacific-plating-282708._script7c6faf4dc1f287623ae26f66d20de48b274328dd.baseline_newpayment` b EXCEPT DISTINCT SELECT TO_JSON_STRING(c) FROM `pacific-plating-282708._script7c6faf4dc1f287623ae26f66d20de48b274328dd.candidate_newpayment` c)) AS removed_newpayment_payloads,
(SELECT COUNT(*) FROM (SELECT TO_JSON_STRING(c) FROM candidate_wrapper c EXCEPT DISTINCT SELECT TO_JSON_STRING(b) FROM `pacific-plating-282708._script7c6faf4dc1f287623ae26f66d20de48b274328dd.baseline_wrapper` b)) AS added_wrapper_payloads,
(SELECT COUNT(*) FROM (SELECT OrderItem,Period,InvoiceNo FROM candidate_wrapper GROUP BY 1,2,3 HAVING COUNT(*)>1)) AS duplicate_event_keys,
(SELECT COUNT(*) FROM (SELECT OrderItem FROM candidate_wrapper GROUP BY OrderItem HAVING COUNT(DISTINCT Period)!=MAX(TotalPeriods) OR MIN(Period)!=1 OR MAX(Period)!=MAX(TotalPeriods))) AS incomplete_spines,
ARRAY(SELECT AS STRUCT OrderID,OrderItem,Period,InvoiceNo,ExpectedReceived,ActualReceived,PrincipleThisPeriod,PrincipleEIRThisPeriod,TransactionStatus FROM candidate_wrapper WHERE OrderID IN ('L80570054','L79109956') ORDER BY OrderItem,Period,InvoiceNo) AS target_rows,
ARRAY(SELECT AS STRUCT rule_code,COUNT(*) AS row_count FROM `pacific-plating-282708._script7c6faf4dc1f287623ae26f66d20de48b274328dd.lineage_diagnostics` GROUP BY rule_code) AS diagnostic_groups;
SELECT CURRENT_TIMESTAMP() AS checked_at_utc,
ARRAY(SELECT AS STRUCT c.TransactionStatus,l.source_charge_rank,
DATE(l.raw_update_time)<DATE_TRUNC(DATE_SUB(CURRENT_DATE(),INTERVAL 2 MONTH),MONTH) AS older_than_window,
SAFE.PARSE_DATE('%d%m%Y',c.OrderDate)<DATE '2026-01-01' AS old_order,
COUNT(*) AS row_count,ROUND(SUM(c.ActualReceived),2) AS actual_sum
FROM added c LEFT JOIN receipt_lineage l ON l.OrderItem=c.OrderItem AND l.Period=c.Period AND l.InvoiceNo IS NOT DISTINCT FROM c.InvoiceNo
GROUP BY 1,2,3,4) AS added_distribution,
ARRAY(SELECT AS STRUCT c.OrderItem,c.Period,c.InvoiceNo,c.ActualReceived,l.raw_update_time,l.source_charge_rank
FROM added c JOIN receipt_lineage l ON l.OrderItem=c.OrderItem AND l.Period=c.Period AND l.InvoiceNo IS NOT DISTINCT FROM c.InvoiceNo
WHERE LOWER(c.TransactionStatus)='paid' AND DATE(l.raw_update_time)<DATE_TRUNC(DATE_SUB(CURRENT_DATE(),INTERVAL 2 MONTH),MONTH)) AS older_paid_exposure;

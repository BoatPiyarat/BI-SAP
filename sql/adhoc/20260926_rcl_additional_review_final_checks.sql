CREATE TEMP TABLE candidate_newpayment AS -- 2026-09-26 same-period payment correction. Source only; not deployed.
-- SELECT-only replacement for sap_integration_v2.RCL 05_newpayment.
-- Ordinary periods keep the existing paid-period exclusion.
-- Additional payments use immutable event identity, including the established
-- raw/2_ invoice alias for installment 1. No SAP values are rewritten.
WITH
  sap_paid_periods AS (
    SELECT DISTINCT U_OrderItem AS order_item, SAFE_CAST(U_Period AS INT64) AS period
    FROM `pacific-plating-282708._scriptb14b3a9ebead07d9ecd3b3177c5b3bbe7a0379aa.evidence_sap`
    WHERE TransactionStatus IN ('Paid', 'paid')
  ),
  sap_terminal_events AS (
    SELECT DISTINCT U_OrderItem AS order_item, SAFE_CAST(U_Period AS INT64) AS period,
      U_InvoiceNo AS invoice_no
    FROM `pacific-plating-282708._scriptb14b3a9ebead07d9ecd3b3177c5b3bbe7a0379aa.evidence_sap`
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
      v.source_charge_rank, v.source_event_rows, v.additional_identity_valid,
      COALESCE(ExpectedReceived = 0, FALSE)
        AND COALESCE(ActualReceived, 0) > 0
        AND LOWER(TRIM(COALESCE(TransactionStatus, ''))) = 'paid'
        AS has_additional_shape
    FROM `pacific-plating-282708._scriptb14b3a9ebead07d9ecd3b3177c5b3bbe7a0379aa.candidate_dashboard` d
    LEFT JOIN source_receipt_events v ON v.order_item=d.OrderItem
      AND v.period=SAFE_CAST(d.Period AS INT64) AND v.invoice_no IS NOT DISTINCT FROM d.InvoiceNo
  )
SELECT DISTINCT
  interface.CompanyDB,
  interface.OrderID,
  interface.OrderItem,
  interface.InvoiceNo,
  interface.OrderDate,
  interface.InsuredID,
  interface.Title,
  interface.FirstName,
  interface.LastName,
  interface.InsurerCode,
  interface.InsuranceGroup,
  interface.InsuranceType,
  interface.InsuranceProduct,
  interface.ProductType,
  interface.PolicyType,
  interface.Endorse,
  interface.PolicyDate,
  interface.PolicyNo,
  interface.EndorsementNo,
  interface.ChassisNo,
  interface.LicensePlate,
  interface.GrossPremium,
  interface.StampDuty,
  interface.VAT,
  interface.TotalPremium,
  interface.WHT,
  interface.TotalEIR,
  interface.TotalSBT,
  interface.ProcessingFee,
  interface.ProcessingFeeVat,
  interface.ShippingFee,
  interface.ShippingFeeVat,
  interface.TotalAmount,
  interface.Discount,
  interface.TransactionStatus,
  interface.SubmissionStatus,
  interface.ApprovalStatus,
  interface.PaymentStatus,
  interface.ExpectedReceived,
  interface.ActualReceived,
  interface.InterestThisPeriod,
  interface.PrincipleThisPeriod,
  interface.InterestEIRThisPeriod,
  interface.PrincipleEIRThisPeriod,
  interface.PaymentDate,
  interface.Period,
  interface.TotalPeriods,
  interface.PendingPayment,
  interface.PaymentMethod,
  interface.PaymentChannel,
  interface.ExpectedDate,
  interface.RefOrder,
  interface.RefundAmountBeforeFee,
  interface.RefundAmountAfterFee,
  interface.BillingAddress,
  interface.BatchRunDate
FROM interface
WHERE interface.careos_installment IS NOT NULL
  AND (
    (
      (
        interface.source_charge_rank = 1
        OR (interface.source_event_rows IS NULL AND COALESCE(interface.ActualReceived, 0) = 0)
      )
      AND NOT EXISTS (
        SELECT 1 FROM sap_paid_periods p
        WHERE p.order_item = interface.OrderItem
          AND p.period = interface.careos_installment
      )
    )
    OR (
      interface.source_charge_rank > 1
      AND interface.has_additional_shape
      AND interface.additional_identity_valid
      AND NULLIF(TRIM(interface.InvoiceNo), '') IS NOT NULL
      AND UPPER(TRIM(interface.InvoiceNo)) != 'NULL'
      AND NOT EXISTS (
        SELECT 1 FROM sap_terminal_events e
        WHERE e.order_item = interface.OrderItem
          AND e.period = interface.careos_installment
          AND (
            e.invoice_no = interface.InvoiceNo
            OR (
              interface.careos_installment = 1
              AND STARTS_WITH(interface.InvoiceNo, '2_')
              AND e.invoice_no = SUBSTR(interface.InvoiceNo, 3)
            )
          )
      )
    )
  )
ORDER BY interface.OrderItem, interface.Period
;
CREATE TEMP TABLE candidate_gate AS -- 2026-09-26 same-period payment correction. Source only; not deployed.
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
    ROW_NUMBER() OVER (PARTITION BY transaction_id ORDER BY installment_number DESC) AS rank
  FROM charges
  QUALIFY rank = 1
),

sap_paid_periods AS (
  -- exact per-(OrderItem, Period) existence check -- NOT a MAX watermark, NOT an all-period fan-out
  SELECT DISTINCT
    U_OrderItem AS order_item,
    SAFE_CAST(U_Period AS INT64) AS period
  FROM `pacific-plating-282708._scriptb14b3a9ebead07d9ecd3b3177c5b3bbe7a0379aa.evidence_sap`
  WHERE TransactionStatus IN ('Paid', 'paid')
)
,
additional_items AS (
  -- Only genuinely unsent additional events can reopen an already-paid item.
  SELECT DISTINCT OrderItem
  FROM candidate_newpayment n
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
      THEN CONCAT('2_', c.third_party_id) ELSE c.third_party_id END
    AND c.source_charge_rank > 1
  WHERE ExpectedReceived = 0
    AND ActualReceived > 0
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
LEFT JOIN additional_items AS additional
  ON additional.OrderItem = oi.human_id
WHERE 1=1
  AND charges_ranking.installment_number IS NOT NULL
  AND (
    DATE(charges_ranking.update_time)
      BETWEEN DATE_TRUNC(DATE_SUB(CURRENT_DATE(), INTERVAL 2 MONTH), MONTH)
      AND CURRENT_DATE()
    OR additional.OrderItem IS NOT NULL
  )
  AND transactions.payment_option = 'RABBIT_CARE_INSTALLMENT'
  AND (
    NOT EXISTS (
      SELECT 1
      FROM sap_paid_periods p
      WHERE p.order_item = oi.human_id
        AND p.period = charges_ranking.installment_number
    )
    OR additional.OrderItem IS NOT NULL
  )
ORDER BY orders.create_time ASC;
CREATE TEMP TABLE candidate_wrapper AS -- Full source-only legacy root-fix proposal for:
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
    FROM `pacific-plating-282708._scriptb14b3a9ebead07d9ecd3b3177c5b3bbe7a0379aa.evidence_paid`

    UNION ALL

    SELECT *
    FROM candidate_newpayment
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
    WHERE SAFE.PARSE_DATE('%d%m%Y', interface.OrderDate) >= DATE '2026-01-01'
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
          source.PaymentDate DESC
      ) AS rn
    FROM source
  )

SELECT
  * EXCEPT (is_additional_payment, rn)
FROM classified
WHERE rn = 1
ORDER BY OrderID, OrderItem, Period;
SELECT CURRENT_TIMESTAMP() AS checked_at_utc,
 (SELECT COUNT(*) FROM candidate_wrapper) AS candidate_rows,
 (SELECT COUNT(DISTINCT OrderItem) FROM candidate_wrapper) AS candidate_items,
 (SELECT COUNT(*) FROM candidate_wrapper WHERE ExpectedReceived=0 AND ActualReceived>0) AS additional_rows,
 (SELECT COUNT(*) FROM (SELECT OrderItem,Period,InvoiceNo FROM candidate_wrapper GROUP BY 1,2,3 HAVING COUNT(*)>1)) AS duplicate_event_keys,
 (SELECT COUNT(*) FROM (SELECT OrderItem FROM candidate_wrapper GROUP BY OrderItem HAVING MIN(SAFE_CAST(Period AS INT64))!=1 OR MAX(SAFE_CAST(Period AS INT64))!=MAX(SAFE_CAST(TotalPeriods AS INT64)) OR COUNT(DISTINCT SAFE_CAST(Period AS INT64))!=MAX(SAFE_CAST(TotalPeriods AS INT64)) OR COUNT(DISTINCT TotalPeriods)!=1)) AS incomplete_spines,
 (SELECT COUNT(*) FROM (SELECT OrderItem,Period FROM candidate_wrapper GROUP BY 1,2 HAVING COUNTIF(COALESCE(ExpectedReceived,0)!=0)>1)) AS repeated_expected_periods,
 (SELECT COUNT(*) FROM candidate_wrapper WHERE ExpectedReceived=0 AND ActualReceived>0 AND (NULLIF(TRIM(InvoiceNo),'') IS NULL OR UPPER(TRIM(InvoiceNo))='NULL')) AS blank_additional_invoices,
 (SELECT COUNT(*) FROM (SELECT OrderItem,Period,InvoiceNo,TransactionStatus,ExpectedReceived,ActualReceived,PaymentDate,PaymentMethod,PaymentChannel FROM `pacific-plating-282708._scriptb14b3a9ebead07d9ecd3b3177c5b3bbe7a0379aa.baseline_wrapper` EXCEPT DISTINCT SELECT OrderItem,Period,InvoiceNo,TransactionStatus,ExpectedReceived,ActualReceived,PaymentDate,PaymentMethod,PaymentChannel FROM candidate_wrapper)) AS existing_rows_removed_or_changed,
 ARRAY(SELECT AS STRUCT TransactionStatus,COUNT(*) AS row_count FROM candidate_wrapper GROUP BY TransactionStatus) AS status_distribution;


SELECT CURRENT_TIMESTAMP() AS checked_at_utc,
 (SELECT COUNT(*) FROM (SELECT TO_JSON_STRING(b) FROM `pacific-plating-282708._scriptb14b3a9ebead07d9ecd3b3177c5b3bbe7a0379aa.baseline_wrapper` b EXCEPT DISTINCT SELECT TO_JSON_STRING(c) FROM candidate_wrapper c)) AS full_payload_old_rows_removed,
 (SELECT COUNT(*) FROM (SELECT TO_JSON_STRING(b) FROM `pacific-plating-282708._scriptb14b3a9ebead07d9ecd3b3177c5b3bbe7a0379aa.baseline_dashboard` b EXCEPT DISTINCT SELECT TO_JSON_STRING(c) FROM `pacific-plating-282708._scriptb14b3a9ebead07d9ecd3b3177c5b3bbe7a0379aa.candidate_dashboard` c)) AS dashboard_old_rows_removed;

CREATE TEMP TABLE added_wrapper_rows AS
SELECT c.* FROM candidate_wrapper c WHERE NOT EXISTS (
 SELECT 1 FROM `pacific-plating-282708._scriptb14b3a9ebead07d9ecd3b3177c5b3bbe7a0379aa.baseline_wrapper` b WHERE TO_JSON_STRING(b)=TO_JSON_STRING(c));
SELECT CURRENT_TIMESTAMP() AS checked_at_utc,TransactionStatus,
 CASE WHEN ExpectedReceived=0 AND ActualReceived>0 THEN 'additional_shape' ELSE 'normal_spine' END AS row_kind,
 COUNT(*) AS row_count,COUNT(DISTINCT OrderItem) AS items,ROUND(SUM(ActualReceived),2) AS actual_thb
FROM added_wrapper_rows GROUP BY 2,3;
SELECT CURRENT_TIMESTAMP() AS checked_at_utc, OrderID,OrderItem,Period,InvoiceNo,ExpectedReceived,ActualReceived
FROM candidate_wrapper WHERE OrderID IN ('L80570054','L79109956') ORDER BY OrderItem,Period,InvoiceNo;
CREATE TEMP TABLE population_links AS
SELECT c.transaction_id,c.installment_number,c.source_charge_rank,
 COUNT(DISTINCT oi.human_id) AS item_count,
 COUNTIF(oi.product='products/car-insurance' AND COALESCE(oi.motor_item_type,'')!='MOTOR_TYPE_COMPULSORY') AS motor_voluntary_links,
 COUNTIF(oi.motor_item_type='MOTOR_TYPE_COMPULSORY') AS compulsory_links,
 COUNTIF(oi.product!='products/car-insurance') AS nonmotor_links,
 COUNTIF(s.U_OrderItem IS NOT NULL) AS sap_links,
 COUNTIF(w.OrderItem IS NOT NULL) AS candidate_links,
 COUNTIF(d.OrderItem IS NOT NULL) AS dashboard_links
FROM `pacific-plating-282708._script46ab18514cd926b622b3c7ad4e224e5f9fa65717.population_a` c
LEFT JOIN `pacific-plating-282708.careos.careos_orders` o ON o.payment=CONCAT('transactions/',c.transaction_id)
LEFT JOIN `pacific-plating-282708.careos.careos_order_items` oi ON oi.order_id=o.id
LEFT JOIN `pacific-plating-282708._script46ab18514cd926b622b3c7ad4e224e5f9fa65717.sap_receipts` s ON s.U_OrderItem=oi.human_id AND s.period=c.installment_number
 AND s.U_InvoiceNo IN (c.third_party_id,IF(c.installment_number=1,CONCAT('2_',c.third_party_id),c.third_party_id))
LEFT JOIN candidate_wrapper w ON w.OrderItem=oi.human_id AND SAFE_CAST(w.Period AS INT64)=c.installment_number
 AND w.InvoiceNo=IF(c.installment_number=1,CONCAT('2_',c.third_party_id),c.third_party_id)
LEFT JOIN `pacific-plating-282708._scriptb14b3a9ebead07d9ecd3b3177c5b3bbe7a0379aa.candidate_dashboard` d ON d.OrderItem=oi.human_id AND SAFE_CAST(d.Period AS INT64)=c.installment_number
 AND d.InvoiceNo=IF(c.installment_number=1,CONCAT('2_',c.third_party_id),c.third_party_id)
GROUP BY 1,2,3;
CREATE TEMP TABLE population_ledger AS
SELECT c.id AS charge_id,c.transaction_id,c.installment_number AS period,c.source_charge_rank,c.third_party_id,
 ROUND(c.amount/100,2) AS charge_amount_thb,FORMAT_TIMESTAMP('%Y-%m',c.create_time) AS charge_month,
 c.payment_method, l.item_count,l.sap_links,l.candidate_links,l.dashboard_links,
 CONCAT(IF(l.motor_voluntary_links>0,'MOTOR_VOLUNTARY;',''),IF(l.compulsory_links>0,'COMPULSORY;',''),IF(l.nonmotor_links>0,'NONMOTOR;','')) AS products,
 c.source_charge_rank>1 AND l.compulsory_links>0 AS additional_with_compulsory_item,
 DATE(c.update_time)<DATE_TRUNC(DATE_SUB(CURRENT_DATE(),INTERVAL 2 MONTH),MONTH) AS older_than_window,
 CASE
 WHEN NULLIF(TRIM(c.id),'') IS NULL OR c.charge_id_rows>1 THEN 'HOLD_INVALID_OR_DUPLICATE_CHARGE_ID'
 WHEN NULLIF(TRIM(c.third_party_id),'') IS NULL OR UPPER(TRIM(c.third_party_id))='NULL' THEN 'HOLD_MISSING_INVOICE'
 WHEN c.invoice_rows>1 THEN 'HOLD_COLLIDING_INVOICE'
 WHEN l.sap_links>0 THEN 'SAP_IDENTITY_PRESENT'
 WHEN l.candidate_links>0 THEN 'LEGACY_CANDIDATE_PRESENT'
 WHEN c.timestamp_rows>1 THEN 'HOLD_TIED_SOURCE_TIME'
 WHEN l.item_count=0 THEN 'HOLD_NO_ORDER_ITEM'
 WHEN DATE(c.update_time)<DATE_TRUNC(DATE_SUB(CURRENT_DATE(),INTERVAL 2 MONTH),MONTH) THEN 'HOLD_OUTSIDE_RECENCY_WINDOW'
 WHEN l.dashboard_links=0 THEN 'HOLD_OUTSIDE_DASHBOARD_SCOPE'
 ELSE 'HOLD_NOT_ROUTED_BY_LEGACY' END AS disposition
FROM `pacific-plating-282708._script46ab18514cd926b622b3c7ad4e224e5f9fa65717.population_a` c JOIN population_links l USING(transaction_id,installment_number,source_charge_rank);
SELECT CURRENT_TIMESTAMP() AS checked_at_utc,
 (SELECT COUNT(*) FROM `pacific-plating-282708._script46ab18514cd926b622b3c7ad4e224e5f9fa65717.population_a`) AS population_rows,
 (SELECT COUNT(*) FROM population_ledger) AS ledger_rows,
 (SELECT COUNT(*) FROM population_ledger WHERE disposition IS NULL) AS unclassified_rows,
 (SELECT COUNT(*) FROM population_ledger WHERE older_than_window) AS historical_rows,
 (SELECT COUNT(*) FROM population_ledger WHERE additional_with_compulsory_item) AS additional_compulsory_linked_rows,
 (SELECT COUNT(*) FROM population_ledger WHERE disposition LIKE 'HOLD_%') AS requires_hold_rows;
SELECT CURRENT_TIMESTAMP() AS checked_at_utc,products,IF(source_charge_rank=1,'first','additional') AS charge_kind,
 IF(period=1,'period_1','period_2_plus') AS period_group,charge_month,payment_method,disposition,
 COUNT(*) AS charge_rows,ROUND(SUM(charge_amount_thb),2) AS charge_amount_thb
FROM population_ledger GROUP BY 2,3,4,5,6,7 ORDER BY 2,3,4,5,6,7;
SELECT CURRENT_TIMESTAMP() AS checked_at_utc,COUNT(*) AS additional_shape_without_raw_rank
FROM added_wrapper_rows w WHERE w.ExpectedReceived=0 AND w.ActualReceived>0 AND NOT EXISTS (
 SELECT 1 FROM `pacific-plating-282708._script46ab18514cd926b622b3c7ad4e224e5f9fa65717.ranked_charges` c JOIN `pacific-plating-282708.careos.careos_orders` o ON o.payment=CONCAT('transactions/',c.transaction_id)
 JOIN `pacific-plating-282708.careos.careos_order_items` oi ON oi.order_id=o.id
 WHERE oi.human_id=w.OrderItem AND c.installment_number=SAFE_CAST(w.Period AS INT64)
 AND w.InvoiceNo=IF(c.installment_number=1,CONCAT('2_',c.third_party_id),c.third_party_id) AND c.source_charge_rank>1);
CREATE TEMP TABLE create_baseline AS -- Full source-only legacy root-fix proposal for:
--   pacific-plating-282708.sap_view.RCL_Motor_process_1_create
--
-- Root cause:
--   sap_dashboard_carepay_installment correctly emits an RCL compulsory M1 as one
--   Period/TotalPeriods 1/1 row. The legacy wrapper then discards it because its
--   final QUALIFY requires every OrderItem to have more than one row and
--   TotalPeriods > 1. That schedule rule is valid for voluntary V1, but not M1.
--
-- Surgical fix:
--   * Allow compulsory M1 through only as Period/TotalPeriods 1/1.
--   * Keep the original multi-row and TotalPeriods > 1 gate for all voluntary rows.
--   * Require RABBIT_CARE_INSTALLMENT plus at least one SUCCESSFUL
--     RABBIT_LENDING charge before any row can enter this RCL interface.
--   * Admit V1 only as an all-or-nothing complete 1..TotalPeriods spine with
--     non-NULL ExpectedReceived, ActualReceived, and ExpectedDate.
--   * Preserve all existing SAP, change-order, year, insurer, and Test exclusions.
--
-- SELECT only: this file does not replace or deploy the live legacy view.

WITH
  eligible_rcl_items AS (
    SELECT DISTINCT order_items.human_id AS OrderItem
    FROM `pacific-plating-282708.careos.careos_orders` AS orders
    JOIN `pacific-plating-282708.careos.careos_order_items` AS order_items
      ON order_items.order_id = orders.id
    JOIN `pacific-plating-282708.careos.carepay_transactions` AS transactions
      ON CONCAT('transactions/', transactions.id) = orders.payment
     AND transactions.payment_option = 'RABBIT_CARE_INSTALLMENT'
    WHERE EXISTS (
      SELECT 1
      FROM `pacific-plating-282708.careos.carepay_charges` AS charges
      WHERE charges.transaction_id = transactions.id
        AND charges.status = 'SUCCESSFUL'
        AND charges.service_provider = 'RABBIT_LENDING'
    )
  ),

  interface AS (
    SELECT dashboard.*
    FROM `pacific-plating-282708._scriptb14b3a9ebead07d9ecd3b3177c5b3bbe7a0379aa.baseline_dashboard` AS dashboard
    JOIN eligible_rcl_items USING (OrderItem)
  ),

  filtered AS (
    SELECT interface.*
    FROM interface
    WHERE interface.OrderItem NOT IN (
      SELECT U_OrderItem
      FROM `pacific-plating-282708._scriptb14b3a9ebead07d9ecd3b3177c5b3bbe7a0379aa.evidence_sap`
    )
      AND interface.OrderID NOT IN (
        SELECT current_human_id
        FROM `pacific-plating-282708.careos.cancelled_change_orders`
      )
      AND interface.OrderDate NOT LIKE '%2023%'
      AND interface.OrderDate NOT LIKE '%2024%'
      AND interface.InsurerCode NOT IN ('45', '49')
      AND LOWER(TRIM(COALESCE(interface.FirstName, ''))) != 'test'
      AND LOWER(TRIM(COALESCE(interface.LastName, ''))) != 'test'
  ),

  spine_metrics AS (
    SELECT
      OrderItem,
      COUNT(*) AS row_count,
      COUNT(DISTINCT SAFE_CAST(Period AS INT64)) AS distinct_periods,
      MIN(SAFE_CAST(Period AS INT64)) AS min_period,
      MAX(SAFE_CAST(Period AS INT64)) AS max_period,
      COUNT(DISTINCT SAFE_CAST(TotalPeriods AS INT64)) AS total_period_versions,
      MAX(SAFE_CAST(TotalPeriods AS INT64)) AS total_periods,
      COUNTIF(SAFE_CAST(ExpectedReceived AS FLOAT64) IS NULL) AS null_expected_rows,
      COUNTIF(SAFE_CAST(ActualReceived AS FLOAT64) IS NULL) AS null_actual_rows,
      COUNTIF(
        NULLIF(TRIM(COALESCE(ExpectedDate, '')), '') IS NULL
      ) AS blank_expected_date_rows
    FROM filtered
    GROUP BY OrderItem
  )

SELECT
  filtered.*
FROM filtered
JOIN spine_metrics USING (OrderItem)
WHERE
  (
    filtered.InsuranceType = 'MOTOR_TYPE_COMPULSORY'
    AND SAFE_CAST(filtered.Period AS INT64) = 1
    AND SAFE_CAST(filtered.TotalPeriods AS INT64) = 1
    AND SAFE_CAST(filtered.ExpectedReceived AS FLOAT64) IS NOT NULL
    AND SAFE_CAST(filtered.ActualReceived AS FLOAT64) IS NOT NULL
    AND NULLIF(TRIM(COALESCE(filtered.ExpectedDate, '')), '') IS NOT NULL
  )
  OR (
    COALESCE(filtered.InsuranceType, '') != 'MOTOR_TYPE_COMPULSORY'
    AND spine_metrics.row_count > 1
    AND spine_metrics.total_periods > 1
    AND spine_metrics.total_period_versions = 1
    AND spine_metrics.min_period = 1
    AND spine_metrics.max_period = spine_metrics.total_periods
    AND spine_metrics.distinct_periods = spine_metrics.total_periods
    AND spine_metrics.null_expected_rows = 0
    AND spine_metrics.null_actual_rows = 0
    AND spine_metrics.blank_expected_date_rows = 0
  )
ORDER BY
  filtered.OrderItem,
  filtered.Period;
CREATE TEMP TABLE create_candidate AS -- Full source-only legacy root-fix proposal for:
--   pacific-plating-282708.sap_view.RCL_Motor_process_1_create
--
-- Root cause:
--   sap_dashboard_carepay_installment correctly emits an RCL compulsory M1 as one
--   Period/TotalPeriods 1/1 row. The legacy wrapper then discards it because its
--   final QUALIFY requires every OrderItem to have more than one row and
--   TotalPeriods > 1. That schedule rule is valid for voluntary V1, but not M1.
--
-- Surgical fix:
--   * Allow compulsory M1 through only as Period/TotalPeriods 1/1.
--   * Keep the original multi-row and TotalPeriods > 1 gate for all voluntary rows.
--   * Require RABBIT_CARE_INSTALLMENT plus at least one SUCCESSFUL
--     RABBIT_LENDING charge before any row can enter this RCL interface.
--   * Admit V1 only as an all-or-nothing complete 1..TotalPeriods spine with
--     non-NULL ExpectedReceived, ActualReceived, and ExpectedDate.
--   * Preserve all existing SAP, change-order, year, insurer, and Test exclusions.
--
-- SELECT only: this file does not replace or deploy the live legacy view.

WITH
  eligible_rcl_items AS (
    SELECT DISTINCT order_items.human_id AS OrderItem
    FROM `pacific-plating-282708.careos.careos_orders` AS orders
    JOIN `pacific-plating-282708.careos.careos_order_items` AS order_items
      ON order_items.order_id = orders.id
    JOIN `pacific-plating-282708.careos.carepay_transactions` AS transactions
      ON CONCAT('transactions/', transactions.id) = orders.payment
     AND transactions.payment_option = 'RABBIT_CARE_INSTALLMENT'
    WHERE EXISTS (
      SELECT 1
      FROM `pacific-plating-282708.careos.carepay_charges` AS charges
      WHERE charges.transaction_id = transactions.id
        AND charges.status = 'SUCCESSFUL'
        AND charges.service_provider = 'RABBIT_LENDING'
    )
  ),

  interface AS (
    SELECT dashboard.*
    FROM `pacific-plating-282708._scriptb14b3a9ebead07d9ecd3b3177c5b3bbe7a0379aa.candidate_dashboard` AS dashboard
    JOIN eligible_rcl_items USING (OrderItem)
  ),

  filtered AS (
    SELECT interface.*
    FROM interface
    WHERE interface.OrderItem NOT IN (
      SELECT U_OrderItem
      FROM `pacific-plating-282708._scriptb14b3a9ebead07d9ecd3b3177c5b3bbe7a0379aa.evidence_sap`
    )
      AND interface.OrderID NOT IN (
        SELECT current_human_id
        FROM `pacific-plating-282708.careos.cancelled_change_orders`
      )
      AND interface.OrderDate NOT LIKE '%2023%'
      AND interface.OrderDate NOT LIKE '%2024%'
      AND interface.InsurerCode NOT IN ('45', '49')
      AND LOWER(TRIM(COALESCE(interface.FirstName, ''))) != 'test'
      AND LOWER(TRIM(COALESCE(interface.LastName, ''))) != 'test'
  ),

  spine_metrics AS (
    SELECT
      OrderItem,
      COUNT(*) AS row_count,
      COUNT(DISTINCT SAFE_CAST(Period AS INT64)) AS distinct_periods,
      MIN(SAFE_CAST(Period AS INT64)) AS min_period,
      MAX(SAFE_CAST(Period AS INT64)) AS max_period,
      COUNT(DISTINCT SAFE_CAST(TotalPeriods AS INT64)) AS total_period_versions,
      MAX(SAFE_CAST(TotalPeriods AS INT64)) AS total_periods,
      COUNTIF(SAFE_CAST(ExpectedReceived AS FLOAT64) IS NULL) AS null_expected_rows,
      COUNTIF(SAFE_CAST(ActualReceived AS FLOAT64) IS NULL) AS null_actual_rows,
      COUNTIF(
        NULLIF(TRIM(COALESCE(ExpectedDate, '')), '') IS NULL
      ) AS blank_expected_date_rows
    FROM filtered
    GROUP BY OrderItem
  )

SELECT
  filtered.*
FROM filtered
JOIN spine_metrics USING (OrderItem)
WHERE
  (
    filtered.InsuranceType = 'MOTOR_TYPE_COMPULSORY'
    AND SAFE_CAST(filtered.Period AS INT64) = 1
    AND SAFE_CAST(filtered.TotalPeriods AS INT64) = 1
    AND SAFE_CAST(filtered.ExpectedReceived AS FLOAT64) IS NOT NULL
    AND SAFE_CAST(filtered.ActualReceived AS FLOAT64) IS NOT NULL
    AND NULLIF(TRIM(COALESCE(filtered.ExpectedDate, '')), '') IS NOT NULL
  )
  OR (
    COALESCE(filtered.InsuranceType, '') != 'MOTOR_TYPE_COMPULSORY'
    AND spine_metrics.row_count > 1
    AND spine_metrics.total_periods > 1
    AND spine_metrics.total_period_versions = 1
    AND spine_metrics.min_period = 1
    AND spine_metrics.max_period = spine_metrics.total_periods
    AND spine_metrics.distinct_periods = spine_metrics.total_periods
    AND spine_metrics.null_expected_rows = 0
    AND spine_metrics.null_actual_rows = 0
    AND spine_metrics.blank_expected_date_rows = 0
  )
ORDER BY
  filtered.OrderItem,
  filtered.Period;
SELECT CURRENT_TIMESTAMP() AS checked_at_utc,'sap_view.RCL_Motor_process_1_create' AS dependent,
 (SELECT COUNT(*) FROM create_baseline) AS old_rows,(SELECT COUNT(*) FROM create_candidate) AS new_rows,
 (SELECT COUNT(*) FROM (SELECT TO_JSON_STRING(c) FROM create_candidate c EXCEPT DISTINCT SELECT TO_JSON_STRING(b) FROM create_baseline b)) AS added_payloads,
 (SELECT COUNT(*) FROM (SELECT TO_JSON_STRING(b) FROM create_baseline b EXCEPT DISTINCT SELECT TO_JSON_STRING(c) FROM create_candidate c)) AS removed_payloads,
 (SELECT COUNT(*) FROM (SELECT OrderItem,Period,InvoiceNo FROM create_candidate GROUP BY 1,2,3 HAVING COUNT(*)>1)) AS duplicate_event_keys;
WITH missing AS (
 SELECT TO_JSON_STRING(b) AS payload FROM `pacific-plating-282708._scriptb14b3a9ebead07d9ecd3b3177c5b3bbe7a0379aa.baseline_dashboard` b
 EXCEPT DISTINCT SELECT TO_JSON_STRING(c) FROM `pacific-plating-282708._scriptb14b3a9ebead07d9ecd3b3177c5b3bbe7a0379aa.candidate_dashboard` c
), affected AS (
 SELECT DISTINCT b.OrderItem,b.Period FROM `pacific-plating-282708._scriptb14b3a9ebead07d9ecd3b3177c5b3bbe7a0379aa.baseline_dashboard` b JOIN missing m ON m.payload=TO_JSON_STRING(b)
), facts AS (
 SELECT a.OrderItem,a.Period,COUNTIF(c.create_time=f.create_time) AS first_time_ties
 FROM affected a JOIN `pacific-plating-282708.careos.careos_order_items` oi ON oi.human_id=a.OrderItem
 JOIN `pacific-plating-282708.careos.careos_orders` o ON o.id=oi.order_id
 JOIN `pacific-plating-282708._script46ab18514cd926b622b3c7ad4e224e5f9fa65717.ranked_charges` c ON o.payment=CONCAT('transactions/',c.transaction_id) AND c.installment_number=a.Period
 JOIN `pacific-plating-282708._script46ab18514cd926b622b3c7ad4e224e5f9fa65717.ranked_charges` f ON f.transaction_id=c.transaction_id AND f.installment_number=c.installment_number AND f.source_charge_rank=1
 GROUP BY 1,2
), old_sums AS (
 SELECT OrderItem,Period,ROUND(SUM(ExpectedReceived),2) AS expected,ROUND(SUM(InterestThisPeriod),2) AS interest,ROUND(SUM(InterestEIRThisPeriod),2) AS eir
 FROM `pacific-plating-282708._scriptb14b3a9ebead07d9ecd3b3177c5b3bbe7a0379aa.baseline_dashboard` GROUP BY 1,2
), new_sums AS (
 SELECT OrderItem,Period,ROUND(SUM(ExpectedReceived),2) AS expected,ROUND(SUM(InterestThisPeriod),2) AS interest,ROUND(SUM(InterestEIRThisPeriod),2) AS eir
 FROM `pacific-plating-282708._scriptb14b3a9ebead07d9ecd3b3177c5b3bbe7a0379aa.candidate_dashboard` GROUP BY 1,2
)
SELECT CURRENT_TIMESTAMP() AS checked_at_utc,(SELECT COUNT(*) FROM affected) AS affected_item_periods,
 (SELECT COUNT(*) FROM facts WHERE first_time_ties>1) AS affected_with_tied_first_charge,
 (SELECT COUNT(*) FROM affected a JOIN old_sums o USING(OrderItem,Period) JOIN new_sums n USING(OrderItem,Period) WHERE o.expected IS DISTINCT FROM n.expected OR o.interest IS DISTINCT FROM n.interest OR o.eir IS DISTINCT FROM n.eir) AS affected_schedule_sum_changes;
SELECT CURRENT_TIMESTAMP() AS checked_at_utc,
 (SELECT COUNT(*) FROM (SELECT TO_JSON_STRING(b) FROM `pacific-plating-282708._scriptb14b3a9ebead07d9ecd3b3177c5b3bbe7a0379aa.baseline_newpayment` b EXCEPT DISTINCT SELECT TO_JSON_STRING(c) FROM candidate_newpayment c)) AS raw_newpayment_old_payloads_removed,
 (SELECT COUNT(*) FROM candidate_newpayment WHERE InsuranceType='MOTOR_TYPE_COMPULSORY' AND InvoiceNo IS NULL AND ActualReceived>0) AS preserved_compulsory_null_invoice_rows;

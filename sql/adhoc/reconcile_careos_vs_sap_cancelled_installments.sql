-- reconcile_careos_vs_sap_cancelled_installments.sql
-- Boat's rule (2026-07-25): once an order shows Paid periods then Cancelled in SAP, that's
-- final - never modify it. This query is purely a REPORT for visibility, not a fix input.
--
-- Signal used: a cancelled order's cancel-send mirrors every period to TransactionStatus =
-- 'Cancelled' (confirmed live 2026-07-25, e.g. L78210940-V1 - all 6 periods show Cancelled),
-- so current status can't tell you which periods were actually paid before cancellation.
-- U_InvoiceNo can: a period only gets a real invoice once it's actually been charged/paid,
-- so "non-empty U_InvoiceNo among Cancelled periods" = "was paid in SAP before cancellation."
--
-- Credit Shell orders (U_OrderID LIKE 'C#%') are excluded - they use a different single-invoice
-- (period-1-only) pattern by design, not one invoice per period, which would otherwise look
-- like a mass of false "missing installments."
--
-- Run this ad hoc whenever a fresh reconciliation email is needed - not scheduled/automated.

WITH sap_cancelled_orders AS (
  SELECT
    U_OrderItem,
    U_OrderID,
    MAX(TotalPeriods) AS total_periods,
    COUNTIF(IFNULL(U_InvoiceNo, '') != '') AS sap_paid_periods
  FROM `pacific-plating-282708.sap_integration_v3.stg_sap_state`
  WHERE TransactionStatus IN ('Cancelled', 'Cancelled (Change order / Rejected)')
    AND TotalPeriods > 1
    AND U_OrderID NOT LIKE 'C#%'
  GROUP BY U_OrderItem, U_OrderID
),

careos_paid AS (
  SELECT
    oi.human_id AS OrderItem,
    COUNT(DISTINCT c.installment_number) AS careos_paid_periods
  FROM `pacific-plating-282708.careos.carepay_charges` c
  JOIN `pacific-plating-282708.careos.carepay_transactions` t ON t.id = c.transaction_id
  JOIN `pacific-plating-282708.careos.careos_orders` o ON CONCAT('transactions/', t.id) = o.payment
  JOIN `pacific-plating-282708.careos.careos_order_items` oi ON oi.order_id = o.id
  WHERE c.status = 'SUCCESSFUL'
  GROUP BY oi.human_id
)

SELECT
  s.U_OrderID AS OrderID,
  s.U_OrderItem AS OrderItem,
  s.total_periods AS TotalPeriods,
  s.sap_paid_periods AS SapPaidPeriods,
  cp.careos_paid_periods AS CareosPaidPeriods,
  cp.careos_paid_periods - s.sap_paid_periods AS MissingOnSap
FROM sap_cancelled_orders s
JOIN careos_paid cp ON cp.OrderItem = s.U_OrderItem
WHERE cp.careos_paid_periods > s.sap_paid_periods
ORDER BY MissingOnSap DESC, s.U_OrderItem;

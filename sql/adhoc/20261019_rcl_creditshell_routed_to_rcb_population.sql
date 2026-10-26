-- Read-only. RCL installment CreditShell items whose first SAP appearance is on/after 2026-09-15,
-- i.e. after sap_view.RCB_Motor_process_4_creditshell was overwritten (2026-09-14 11:02 UTC) with the
-- RCL wrapper that reads `RCL 04_new order credit shell`. These items were emitted by BOTH the RCB
-- (step 04) and RCL (step 08) Motor files in the same run. SAP_LIVE_FULL CompanyDB is the constant
-- 'RCB' and cannot show which company posted; RCL posting status must be confirmed in SAP RCL.
WITH first_seen AS (
  SELECT U_OrderItem AS OrderItem, SPLIT(U_OrderItem,'-')[SAFE_OFFSET(0)] AS OrderID,
    MIN(SAFE.PARSE_DATE('%d%m%Y', BatchRunDate)) AS first_batch,
    MAX(TotalPeriods) AS TotalPeriods,
    ANY_VALUE(RefOrder) AS RefOrder,
    LOGICAL_OR(PaymentChannel = 'RCL-Credit Shell') AS has_cs,
    COUNTIF(TransactionStatus = 'Paid' AND PaymentChannel = 'RCL-Credit Shell') AS cs_paid_rows,
    ROUND(SUM(IF(TransactionStatus = 'Paid' AND PaymentChannel = 'RCL-Credit Shell', U_ActualReceived, 0)), 2) AS cs_paid_thb
  FROM `pacific-plating-282708.sap_integration_v2.SAP_LIVE_FULL`
  GROUP BY 1, 2
)
SELECT f.OrderID, f.OrderItem, f.RefOrder, f.TotalPeriods, f.first_batch, f.cs_paid_rows, f.cs_paid_thb, t.payment_option
FROM first_seen AS f
JOIN (SELECT DISTINCT current_human_id FROM `pacific-plating-282708.careos.cancelled_change_orders`) AS co
  ON co.current_human_id = f.OrderID
LEFT JOIN `pacific-plating-282708.careos.careos_orders` AS o ON o.human_id = f.OrderID
LEFT JOIN `pacific-plating-282708.careos.carepay_transactions` AS t ON o.payment = CONCAT('transactions/', t.id)
WHERE f.first_batch >= '2026-09-15' AND f.has_cs AND f.TotalPeriods > 1
ORDER BY f.first_batch, f.OrderItem;

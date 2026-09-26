WITH fixture_events AS (
 SELECT 'old-V1' AS OrderItem,1 AS Period,'2_old' AS InvoiceNo,0 AS ExpectedReceived,10 AS ActualReceived,'paid' AS TransactionStatus,FORMAT_DATE('%d%m%Y',CURRENT_DATE()) AS PaymentDate
 UNION ALL SELECT 'recent-V1',1,'2_recent',0,10,'paid',FORMAT_DATE('%d%m%Y',CURRENT_DATE())
), fixture_items AS (SELECT 'old-V1' AS human_id,'old' AS order_id UNION ALL SELECT 'recent-V1','recent'),
fixture_orders AS (SELECT 'old' AS id,'transactions/old' AS payment UNION ALL SELECT 'recent','transactions/recent'),
fixture_charges AS (
 SELECT 'old' AS transaction_id,1 AS installment_number,'old' AS third_party_id,'SUCCESSFUL' AS status,'RABBIT_LENDING' AS service_provider,TIMESTAMP(DATE_SUB(CURRENT_DATE(),INTERVAL 1 YEAR)) AS update_time
 UNION ALL SELECT 'recent',1,'recent','SUCCESSFUL','RABBIT_LENDING',CURRENT_TIMESTAMP()
), additional_items AS (
  -- Only genuinely unsent additional events can reopen an already-paid item.
  SELECT DISTINCT OrderItem
  FROM fixture_events n
  JOIN fixture_items oi ON oi.human_id = n.OrderItem
  JOIN fixture_orders o ON o.id = oi.order_id
  JOIN fixture_charges c
    ON o.payment = CONCAT('transactions/', c.transaction_id)
    AND c.installment_number = SAFE_CAST(n.Period AS INT64)
    AND n.InvoiceNo = CASE WHEN c.installment_number = 1
      THEN CONCAT('2_', c.third_party_id) ELSE c.third_party_id END
    AND c.status = 'SUCCESSFUL' AND c.service_provider = 'RABBIT_LENDING'
  WHERE ExpectedReceived = 0
    AND ActualReceived > 0
    AND LOWER(TRIM(TransactionStatus)) = 'paid'
    AND NULLIF(TRIM(InvoiceNo), '') IS NOT NULL
    AND UPPER(TRIM(InvoiceNo)) != 'NULL'
    AND DATE(c.update_time)
      BETWEEN DATE_TRUNC(DATE_SUB(CURRENT_DATE(), INTERVAL 2 MONTH), MONTH)
      AND CURRENT_DATE()
)
SELECT CURRENT_TIMESTAMP() AS checked_at_utc,
 (SELECT COUNT(*) FROM additional_items WHERE OrderItem='old-V1') AS old_clamped_event_admitted,
 (SELECT COUNT(*) FROM additional_items WHERE OrderItem='recent-V1') AS recent_event_admitted;

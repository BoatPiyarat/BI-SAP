WITH charges_fixture AS (
SELECT 'first' AS id,'first' AS transaction_id,1 AS installment_number,'first' AS third_party_id,TIMESTAMP '2026-01-01' AS create_time,CURRENT_TIMESTAMP() AS update_time,'SUCCESSFUL' AS status,'RABBIT_LENDING' AS service_provider UNION ALL
SELECT 'first-latest','first',2,'latest',CURRENT_TIMESTAMP(),CURRENT_TIMESTAMP(),'SUCCESSFUL','RABBIT_LENDING' UNION ALL
SELECT 'fallback' AS id,'fallback' AS transaction_id,1 AS installment_number,CAST(NULL AS STRING) AS third_party_id,TIMESTAMP '2026-01-01' AS create_time,CURRENT_TIMESTAMP() AS update_time,'SUCCESSFUL' AS status,'RABBIT_LENDING' AS service_provider UNION ALL
SELECT 'fallback-latest','fallback',2,'latest',CURRENT_TIMESTAMP(),CURRENT_TIMESTAMP(),'SUCCESSFUL','RABBIT_LENDING' UNION ALL
SELECT 'extra' AS id,'extra' AS transaction_id,1 AS installment_number,'extra' AS third_party_id,TIMESTAMP '2026-01-01' AS create_time,CURRENT_TIMESTAMP() AS update_time,'SUCCESSFUL' AS status,'RABBIT_LENDING' AS service_provider UNION ALL
SELECT 'extra-first','extra',1,'prior',TIMESTAMP '2025-12-01',TIMESTAMP '2025-12-01','SUCCESSFUL','RABBIT_LENDING' UNION ALL
SELECT 'extra-latest','extra',2,'latest',CURRENT_TIMESTAMP(),CURRENT_TIMESTAMP(),'SUCCESSFUL','RABBIT_LENDING' UNION ALL
SELECT 'stale' AS id,'stale' AS transaction_id,1 AS installment_number,'stale' AS third_party_id,TIMESTAMP '2026-01-01' AS create_time,TIMESTAMP '2025-01-01' AS update_time,'SUCCESSFUL' AS status,'RABBIT_LENDING' AS service_provider UNION ALL
SELECT 'stale-first','stale',1,'prior',TIMESTAMP '2025-12-01',TIMESTAMP '2025-12-01','SUCCESSFUL','RABBIT_LENDING' UNION ALL
SELECT 'stale-latest','stale',2,'latest',CURRENT_TIMESTAMP(),CURRENT_TIMESTAMP(),'SUCCESSFUL','RABBIT_LENDING' UNION ALL
SELECT 'no_event' AS id,'no_event' AS transaction_id,1 AS installment_number,'no_event' AS third_party_id,TIMESTAMP '2026-01-01' AS create_time,CURRENT_TIMESTAMP() AS update_time,'SUCCESSFUL' AS status,'RABBIT_LENDING' AS service_provider UNION ALL
SELECT 'no_event-latest','no_event',2,'latest',CURRENT_TIMESTAMP(),CURRENT_TIMESTAMP(),'SUCCESSFUL','RABBIT_LENDING'
),
orders_fixture AS (
SELECT 'first' AS id,'first' AS human_id,'transactions/first' AS payment,TIMESTAMP '2025-01-01' AS create_time,CURRENT_TIMESTAMP() AS update_time,FALSE AS is_fully_paid,FALSE AS is_cancelled,CAST(NULL AS TIMESTAMP) AS cancel_time,'products/car-insurance' AS product UNION ALL
SELECT 'fallback' AS id,'fallback' AS human_id,'transactions/fallback' AS payment,TIMESTAMP '2025-01-01' AS create_time,CURRENT_TIMESTAMP() AS update_time,FALSE AS is_fully_paid,FALSE AS is_cancelled,CAST(NULL AS TIMESTAMP) AS cancel_time,'products/car-insurance' AS product UNION ALL
SELECT 'extra' AS id,'extra' AS human_id,'transactions/extra' AS payment,TIMESTAMP '2025-01-01' AS create_time,CURRENT_TIMESTAMP() AS update_time,FALSE AS is_fully_paid,FALSE AS is_cancelled,CAST(NULL AS TIMESTAMP) AS cancel_time,'products/car-insurance' AS product UNION ALL
SELECT 'stale' AS id,'stale' AS human_id,'transactions/stale' AS payment,TIMESTAMP '2025-01-01' AS create_time,CURRENT_TIMESTAMP() AS update_time,FALSE AS is_fully_paid,FALSE AS is_cancelled,CAST(NULL AS TIMESTAMP) AS cancel_time,'products/car-insurance' AS product UNION ALL
SELECT 'no_event' AS id,'no_event' AS human_id,'transactions/no_event' AS payment,TIMESTAMP '2025-01-01' AS create_time,CURRENT_TIMESTAMP() AS update_time,FALSE AS is_fully_paid,FALSE AS is_cancelled,CAST(NULL AS TIMESTAMP) AS cancel_time,'products/car-insurance' AS product
),
items_fixture AS (
SELECT 'first' AS order_id,'first-V1' AS human_id,'MOTOR_TYPE_VOLUNTARY' AS motor_item_type UNION ALL
SELECT 'fallback' AS order_id,'fallback-V1' AS human_id,'MOTOR_TYPE_VOLUNTARY' AS motor_item_type UNION ALL
SELECT 'extra' AS order_id,'extra-V1' AS human_id,'MOTOR_TYPE_VOLUNTARY' AS motor_item_type UNION ALL
SELECT 'stale' AS order_id,'stale-V1' AS human_id,'MOTOR_TYPE_VOLUNTARY' AS motor_item_type UNION ALL
SELECT 'no_event' AS order_id,'no_event-V1' AS human_id,'MOTOR_TYPE_VOLUNTARY' AS motor_item_type
),
transactions_fixture AS (
SELECT 'first' AS id,'RABBIT_CARE_INSTALLMENT' AS payment_option UNION ALL
SELECT 'fallback' AS id,'RABBIT_CARE_INSTALLMENT' AS payment_option UNION ALL
SELECT 'extra' AS id,'RABBIT_CARE_INSTALLMENT' AS payment_option UNION ALL
SELECT 'stale' AS id,'RABBIT_CARE_INSTALLMENT' AS payment_option UNION ALL
SELECT 'no_event' AS id,'RABBIT_CARE_INSTALLMENT' AS payment_option
),
sap_fixture AS (
SELECT 'first-V1' AS U_OrderItem,2 AS U_Period,'Paid' AS TransactionStatus UNION ALL
SELECT 'fallback-V1' AS U_OrderItem,2 AS U_Period,'Paid' AS TransactionStatus UNION ALL
SELECT 'extra-V1' AS U_OrderItem,2 AS U_Period,'Paid' AS TransactionStatus UNION ALL
SELECT 'stale-V1' AS U_OrderItem,2 AS U_Period,'Paid' AS TransactionStatus UNION ALL
SELECT 'no_event-V1' AS U_OrderItem,2 AS U_Period,'Paid' AS TransactionStatus
),
new_fixture AS (
SELECT 'first-V1' AS OrderItem,1 AS Period,'2_first' AS InvoiceNo,10 AS ActualReceived,'paid' AS TransactionStatus UNION ALL
SELECT 'fallback-V1' AS OrderItem,1 AS Period,'2_fallback-V1' AS InvoiceNo,10 AS ActualReceived,'paid' AS TransactionStatus UNION ALL
SELECT 'extra-V1' AS OrderItem,1 AS Period,'2_extra' AS InvoiceNo,10 AS ActualReceived,'paid' AS TransactionStatus UNION ALL
SELECT 'stale-V1' AS OrderItem,1 AS Period,'2_stale' AS InvoiceNo,10 AS ActualReceived,'paid' AS TransactionStatus
),
actual AS (
-- 2026-09-27 downstream candidate; SELECT only, NOT DEPLOYED.
-- Receipt-aware eligibility: retain legacy latest-period path and reopen for any recent unsent receipt.
WITH charges AS (
  SELECT *
  FROM charges_fixture
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
  FROM sap_fixture
  WHERE TransactionStatus IN ('Paid', 'paid')
)
,
outstanding_receipt_items AS (
  -- Any recent unsent receipt can reopen an item, even if a later period is Paid.
  SELECT DISTINCT OrderItem
  FROM new_fixture n
  JOIN items_fixture oi ON oi.human_id = n.OrderItem
  JOIN orders_fixture o ON o.id = oi.order_id
  JOIN (
    SELECT transaction_id, installment_number, third_party_id, update_time,
      ROW_NUMBER() OVER (PARTITION BY transaction_id, installment_number ORDER BY create_time, id) AS source_charge_rank
    FROM charges_fixture
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
FROM orders_fixture AS orders
LEFT JOIN items_fixture AS oi
  ON orders.id = oi.order_id
LEFT JOIN transactions_fixture AS transactions
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
ORDER BY orders.create_time ASC
),
expected AS (SELECT 'first-V1' AS order_item,TRUE AS want UNION ALL SELECT 'fallback-V1' AS order_item,TRUE AS want UNION ALL SELECT 'extra-V1' AS order_item,TRUE AS want UNION ALL SELECT 'stale-V1' AS order_item,FALSE AS want UNION ALL SELECT 'no_event-V1' AS order_item,FALSE AS want)
SELECT order_item,want,EXISTS(SELECT 1 FROM actual a WHERE a.order_item=e.order_item) AS observed FROM expected e;

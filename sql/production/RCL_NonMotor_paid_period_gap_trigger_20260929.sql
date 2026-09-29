WITH charges AS (
  SELECT 
    transaction_id, installment_number, status, update_time,
    ROW_NUMBER() OVER (PARTITION BY transaction_id, installment_number ORDER BY update_time DESC, create_time DESC, id DESC) AS rank   
  FROM `pacific-plating-282708.careos.carepay_charges`
  WHERE status = 'SUCCESSFUL'
),

charges_ranking AS (
  SELECT transaction_id, installment_number, status, update_time FROM charges WHERE rank = 1
)
,
sap AS (  SELECT U_OrderID, U_OrderItem, U_Period, TransactionStatus, BatchRunDate
  FROM `pacific-plating-282708.sap_integration_v2.SAP_LIVE_FULL`
  WHERE LOWER(TransactionStatus) = 'paid'
   )
SELECT distinct
  orders.human_id, 
  order_item.human_id order_item,
  orders.create_time AS order_create_time, 
  orders.update_time AS order_update_time, 
  orders.is_fully_paid, 
  orders.is_cancelled,
  --order_item.underwriting_status,
  transactions.payment_option,
  charges_ranking.installment_number,
  orders.cancel_time,
  charges_ranking.update_time AS charges_update_time,
  CASE
    WHEN orders.create_time < '2024-03-28' THEN 'icollection'
    ELSE 'carepay'
  END AS sql_view_using,
  orders.product,
  --JSON_VALUE(orders.data, '$.oicCode') AS oic_code,
  --JSON_VALUE(orders.data, '$.carLicensePlate') AS LicensePlate,
  --CONCAT(JSON_VALUE(orders.data,'$.policyHolder.firstName'),' ',JSON_VALUE(orders.data,'$.policyHolder.lastName')) AS customer_name,
sap.TransactionStatus,
sap.BatchRunDate,
order_item.motor_item_type InsuranceType
FROM `pacific-plating-282708.careos.careos_orders` AS orders
LEFT JOIN `pacific-plating-282708.careos.careos_order_items` AS order_item
  ON orders.id  = order_item.order_id
LEFT JOIN `pacific-plating-282708.careos.carepay_transactions` AS transactions
  ON CONCAT('transactions/',transactions.id) = orders.payment
LEFT JOIN charges_ranking
  ON charges_ranking.transaction_id = transactions.id
LEFT JOIN sap 
  ON sap.U_OrderItem = order_item.human_id AND SAFE_CAST(sap.U_Period AS INT64) = charges_ranking.installment_number

WHERE 1=1
--AND orders.create_time BETWEEN '2025-01-01' AND '2025-12-31' 
AND charges_ranking.status = 'SUCCESSFUL'
AND charges_ranking.update_time BETWEEN '2026-01-01' AND '2026-12-31'
AND payment_option = 'RABBIT_CARE_INSTALLMENT'
AND sap.U_OrderItem IS NULL
AND order_item.human_id IS NOT NULL
AND NOT EXISTS (
  SELECT 1 FROM `pacific-plating-282708.sap_integration_v2.SAP_LIVE_FULL` terminal
  WHERE terminal.U_OrderItem = order_item.human_id
    AND (LOWER(terminal.TransactionStatus) IN ('cancelled', 'cancelled (change order / rejected)')
         OR STARTS_WITH(COALESCE(terminal.U_OrderID, ''), 'C#'))
)
--AND (charges_ranking.installment_number > 1 OR order_item.motor_item_type LIKE '%COMPU%')
AND orders.product <> 'products/car-insurance'
ORDER BY orders.create_time ASC
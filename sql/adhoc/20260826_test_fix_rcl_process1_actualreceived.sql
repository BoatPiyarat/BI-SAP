-- READ-ONLY TEST of the proposed fix to sap_view.RCL_Motor_process_1_create's ActualReceived
-- formula. Does NOT touch the live view. For a sample of the affected population, shows the real
-- charges.amount (what the fix's fallback join would use) vs. what @INSURANCE actually recorded
-- (ActualReceived=0, already confirmed separately) - proving the fix would produce the correct
-- nonzero value.
WITH o AS (
  SELECT id, human_id, payment FROM `pacific-plating-282708.careos.careos_orders`
  WHERE human_id IN (
    'L78700849','L80534340','L78547453','L78654214','L78667850','L78681874',
    'L78683857','L78718741','L78723281','L78731512','L78734195','L78751566'
  )
),
t AS (
  SELECT tr.id AS transaction_id, o.human_id
  FROM `pacific-plating-282708.careos.carepay_transactions` tr
  JOIN o ON CONCAT('transactions/', tr.id) = o.payment
)
SELECT
  t.human_id AS order_id,
  c.amount AS raw_charge_amount_satang,
  ROUND((1/100) * c.amount, 2) AS proposed_fixed_actualreceived,
  c.status
FROM t
JOIN `pacific-plating-282708.careos.carepay_charges` c
  ON c.transaction_id = t.transaction_id AND c.status = 'SUCCESSFUL'
ORDER BY t.human_id;

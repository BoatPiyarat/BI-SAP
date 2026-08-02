-- Read-only inventory of raw mapping tuples for the corrected Unit 2 READY payment events.
DECLARE target_run_id STRING DEFAULT 'V3NIGHTLY-2026-08-02T09:02:26-b36e1712';

WITH ready AS (
  SELECT u.order_item,u.order_id,u.charge_id,u.charge_amount,u.charge_time,u.flow,
    oi.product source_insurance_group,c.payment_method payment_method_source,
    c.service_provider payment_channel_source,p.payment_option payment_source_type
  FROM `pacific-plating-282708.sap_integration_v3.v3_unit2_event_shadow` u
  LEFT JOIN `pacific-plating-282708.careos.carepay_charges` c ON c.id=u.charge_id
  LEFT JOIN `pacific-plating-282708.sap_integration_v3.stg_payment_events` p USING(charge_id)
  LEFT JOIN `pacific-plating-282708.careos.careos_order_items` oi ON oi.human_id=u.order_item
  WHERE u.pipeline_run_id=target_run_id AND u.outcome='READY_CREATE_OR_PAYMENT'
)
SELECT 'INSURANCE_GROUP' registry,
  IFNULL(source_insurance_group,'<NULL>') source_1,
  IF(source_insurance_group='products/car-insurance','MOTOR','NONMOTOR') source_2,
  IF(flow='ONETIME','RCB','RCL') source_3,
  COUNT(*) records,COUNT(DISTINCT order_id) orders,SUM(charge_amount) amount,
  MIN(DATE(charge_time)) first_payment_date,MAX(DATE(charge_time)) last_payment_date
FROM ready
WHERE DATE(charge_time)>=DATE '2026-08-01'
GROUP BY 1,2,3,4
UNION ALL
SELECT 'PAYMENT',IFNULL(payment_source_type,'<NULL>'),IFNULL(payment_method_source,'<NULL>'),
  IFNULL(payment_channel_source,'<NULL>'),COUNT(*),COUNT(DISTINCT order_id),SUM(charge_amount),
  MIN(DATE(charge_time)),MAX(DATE(charge_time))
FROM ready GROUP BY 1,2,3,4
ORDER BY registry,records DESC,source_1,source_2,source_3;

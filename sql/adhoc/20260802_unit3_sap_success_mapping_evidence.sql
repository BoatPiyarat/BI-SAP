-- Read-only evidence inventory. A row is "SAP-success evidence" only when the CareOS event's
-- immutable (order_item, period, derived InvoiceNo) matches a sap_mirror_doc row with valid DocEntry.
DECLARE target_run_id STRING DEFAULT 'V3NIGHTLY-2026-08-02T09:02:26-b36e1712';

WITH ready_payment_tuple AS (
  SELECT DISTINCT u.flow,IF(oi.product='products/car-insurance','MOTOR','NONMOTOR') product_scope,
    co.current_human_id IS NOT NULL is_credit_shell,p.payment_option,c.payment_method payment_method_source,
    c.service_provider payment_channel_source
  FROM `pacific-plating-282708.sap_integration_v3.v3_unit2_event_shadow` u
  JOIN `pacific-plating-282708.sap_integration_v3.stg_payment_events` p USING(charge_id)
  JOIN `pacific-plating-282708.careos.carepay_charges` c ON c.id=u.charge_id
  LEFT JOIN `pacific-plating-282708.careos.careos_order_items` oi ON oi.human_id=u.order_item
  LEFT JOIN (SELECT DISTINCT current_human_id
    FROM `pacific-plating-282708.careos.cancelled_change_orders`) co
    ON co.current_human_id=u.order_id
  WHERE u.pipeline_run_id=target_run_id AND u.outcome='READY_CREATE_OR_PAYMENT'
), matched_payment AS (
  SELECT s.flow,IF(oi.product='products/car-insurance','MOTOR','NONMOTOR') product_scope,
    co.current_human_id IS NOT NULL is_credit_shell,p.payment_option,c.payment_method payment_method_source,
    c.service_provider payment_channel_source,m.PaymentMethod sap_payment_method,
    m.PaymentChannel sap_payment_channel,COUNT(*) evidence_rows,
    COUNT(DISTINCT m.DocEntry) evidence_docs
  FROM `pacific-plating-282708.sap_integration_v3.stg_payment_events` p
  JOIN `pacific-plating-282708.careos.carepay_charges` c ON c.id=p.charge_id
  LEFT JOIN `pacific-plating-282708.sap_integration_v3.stg_schedule` s
    USING(order_item,order_id,period)
  LEFT JOIN `pacific-plating-282708.careos.careos_order_items` oi ON oi.human_id=p.order_item
  LEFT JOIN (SELECT DISTINCT current_human_id
    FROM `pacific-plating-282708.careos.cancelled_change_orders`) co
    ON co.current_human_id=p.order_id
  JOIN `pacific-plating-282708.sap_integration_v3.sap_mirror_doc` m
    ON m.U_OrderItem=p.order_item AND m.U_Period=p.period
   AND IFNULL(m.U_InvoiceNo,'')=IFNULL(
     `pacific-plating-282708.sap_integration_v3.fn_invoice_no`(p.third_party_id),'')
   AND m.DocEntry IS NOT NULL
  WHERE EXISTS (SELECT 1 FROM ready_payment_tuple r
    WHERE r.flow=s.flow
      AND r.product_scope=IF(oi.product='products/car-insurance','MOTOR','NONMOTOR')
      AND r.is_credit_shell=(co.current_human_id IS NOT NULL)
      AND r.payment_option=p.payment_option
      AND IFNULL(r.payment_method_source,'')=IFNULL(c.payment_method,'')
      AND IFNULL(r.payment_channel_source,'')=IFNULL(c.service_provider,''))
  GROUP BY 1,2,3,4,5,6,7,8
), payment_rank AS (
  SELECT *,COUNT(*) OVER(PARTITION BY flow,product_scope,is_credit_shell,payment_option,payment_method_source,
      payment_channel_source) accepted_output_variants
  FROM matched_payment
)
SELECT 'PAYMENT' registry,FORMAT('%s|%s|credit=%t',flow,product_scope,is_credit_shell) source_scope,payment_option source_1,
  payment_method_source source_2,payment_channel_source source_3,
  sap_payment_method target_1,sap_payment_channel target_2,evidence_rows,evidence_docs,
  accepted_output_variants
FROM payment_rank
ORDER BY source_scope,source_1,source_2,source_3,evidence_rows DESC;

WITH ready_group AS (
  SELECT DISTINCT oi.product source_insurance_group,
    IF(oi.product='products/car-insurance','MOTOR','NONMOTOR') product_scope,
    IF(u.flow='ONETIME','RCB','RCL') business_unit
  FROM `pacific-plating-282708.sap_integration_v3.v3_unit2_event_shadow` u
  JOIN `pacific-plating-282708.careos.careos_order_items` oi ON oi.human_id=u.order_item
  WHERE u.pipeline_run_id=target_run_id AND u.outcome='READY_CREATE_OR_PAYMENT'
    AND DATE(u.charge_time)>=DATE '2026-08-01'
), matched_group AS (
  SELECT oi.product source_insurance_group,
    IF(oi.product='products/car-insurance','MOTOR','NONMOTOR') product_scope,
    IF(s.flow='ONETIME','RCB','RCL') business_unit,m.U_InsuranceGroup sap_insurance_group,
    COUNT(*) evidence_rows,COUNT(DISTINCT m.DocEntry) evidence_docs
  FROM `pacific-plating-282708.sap_integration_v3.sap_mirror_doc` m
  JOIN `pacific-plating-282708.careos.careos_order_items` oi ON oi.human_id=m.U_OrderItem
  LEFT JOIN `pacific-plating-282708.sap_integration_v3.stg_schedule` s
    ON s.order_item=m.U_OrderItem AND s.period=m.U_Period
  WHERE m.DocEntry IS NOT NULL AND NULLIF(TRIM(m.U_InsuranceGroup),'') IS NOT NULL
    AND EXISTS (SELECT 1 FROM ready_group r WHERE r.source_insurance_group=oi.product
      AND r.product_scope=IF(oi.product='products/car-insurance','MOTOR','NONMOTOR')
      AND r.business_unit=IF(s.flow='ONETIME','RCB','RCL'))
  GROUP BY 1,2,3,4
), group_rank AS (
  SELECT *,COUNT(*) OVER(PARTITION BY source_insurance_group,product_scope,business_unit)
    accepted_output_variants
  FROM matched_group
)
SELECT 'INSURANCE_GROUP' registry,business_unit source_scope,source_insurance_group source_1,
  product_scope source_2,CAST(NULL AS STRING) source_3,sap_insurance_group target_1,
  CAST(NULL AS STRING) target_2,evidence_rows,evidence_docs,accepted_output_variants
FROM group_rank
ORDER BY source_scope,source_1,evidence_rows DESC;

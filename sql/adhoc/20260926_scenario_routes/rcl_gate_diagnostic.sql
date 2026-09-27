WITH max_period AS (
 SELECT transaction_id,MAX(installment_number) AS last_period FROM `pacific-plating-282708._script854956d6400364d5179432334ac884bec17498b8.charges` GROUP BY transaction_id
), latest_charge AS (
 SELECT c.transaction_id,m.last_period,COUNT(*) AS tied_latest_period_charges,
 MIN(DATE(c.update_time)) AS min_latest_update_date,MAX(DATE(c.update_time)) AS max_latest_update_date
 FROM `pacific-plating-282708._script854956d6400364d5179432334ac884bec17498b8.charges` c JOIN max_period m ON m.transaction_id=c.transaction_id AND m.last_period=c.installment_number
 GROUP BY c.transaction_id,m.last_period
)
SELECT a.charge_id,a.order_item,a.installment_period,a.reason_code,a.flow,a.business_type,
 c.last_period,c.tied_latest_period_charges,c.min_latest_update_date,c.max_latest_update_date,
 EXISTS(SELECT 1 FROM `pacific-plating-282708._script854956d6400364d5179432334ac884bec17498b8.sap` s WHERE s.order_item=a.order_item AND s.period=c.last_period AND s.sap_status='paid') AS latest_period_already_paid,
 EXISTS(SELECT 1 FROM `pacific-plating-282708._script854956d6400364d5179432334ac884bec17498b8.sap` s WHERE s.order_item=a.order_item AND s.period=a.installment_period AND s.sap_status='paid') AS event_period_already_paid,
 a.payment_option,a.is_cancelled,a.is_change_order_new
FROM `pacific-plating-282708._script854956d6400364d5179432334ac884bec17498b8.audit_result` a LEFT JOIN latest_charge c USING(transaction_id)
WHERE a.event_type='PAID' AND a.reconciliation_status='MISSING_TERMINAL_SAP_EVIDENCE' AND a.flow='RCL' AND a.order_item IS NOT NULL;

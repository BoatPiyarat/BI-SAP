DECLARE target_run_id STRING DEFAULT 'V3NIGHTLY-2026-08-25T14:32:37-0ce16d45';

SELECT e.flow,e.outcome,d.PaymentMethod,d.PaymentChannel,
  COUNT(*) AS released_identities,COUNT(DISTINCT i.order_item) AS items,
  MIN(DATE(e.charge_time)) AS first_charge_date,MAX(DATE(e.charge_time)) AS last_charge_date
FROM `pacific-plating-282708.sap_integration_v3.v3_unit5_payload_identity` i
JOIN `pacific-plating-282708.sap_integration_v3.v3_unit2_event_shadow` e
  ON e.pipeline_run_id=i.pipeline_run_id AND e.order_item=i.order_item
 AND e.period=i.period AND e.charge_id=i.charge_id
JOIN `pacific-plating-282708.sap_integration_v3.v3_unit5_newpayment_delivery_ready` d
  ON d.OrderItem=i.order_item AND SAFE_CAST(d.Period AS INT64)=i.period
 AND d.InvoiceNo=i.invoice_no
WHERE i.pipeline_run_id=target_run_id AND i.file_role='NEWPAYMENT'
  AND NOT EXISTS (SELECT 1
    FROM `pacific-plating-282708.sap_integration_v3.v3_unit5_balance_hold` h
    WHERE h.pipeline_run_id=target_run_id AND h.order_item=i.order_item)
GROUP BY e.flow,e.outcome,d.PaymentMethod,d.PaymentChannel
ORDER BY e.flow,released_identities DESC,d.PaymentMethod,d.PaymentChannel;

SELECT IF(i.period=1,'RCL_FIRST_PERIOD','RCL_LATER_PERIOD') AS approved_case,
  COUNT(*) AS released_identities,COUNT(DISTINCT i.order_item) AS items
FROM `pacific-plating-282708.sap_integration_v3.v3_unit5_payload_identity` i
WHERE i.pipeline_run_id=target_run_id AND i.file_role='NEWPAYMENT'
  AND NOT EXISTS (SELECT 1
    FROM `pacific-plating-282708.sap_integration_v3.v3_unit5_balance_hold` h
    WHERE h.pipeline_run_id=target_run_id AND h.order_item=i.order_item)
GROUP BY approved_case ORDER BY approved_case;

SELECT hold_code,COUNT(*) AS held_identities,COUNT(DISTINCT order_item) AS held_items,
  STRING_AGG(DISTINCT order_item,', ' ORDER BY order_item LIMIT 20) AS sample_items
FROM `pacific-plating-282708.sap_integration_v3.v3_unit5_balance_hold`
WHERE pipeline_run_id=target_run_id
GROUP BY hold_code ORDER BY held_identities DESC;

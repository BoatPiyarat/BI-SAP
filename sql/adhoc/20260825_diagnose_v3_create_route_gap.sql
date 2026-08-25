DECLARE target_run_id STRING DEFAULT 'V3NIGHTLY-2026-08-25T14:32:37-0ce16d45';

CREATE TEMP TABLE create_event AS
SELECT e.*
FROM `pacific-plating-282708.sap_integration_v3.v3_unit2_event_shadow` e
WHERE e.pipeline_run_id=target_run_id AND e.outcome='READY_CREATE_OR_PAYMENT'
  AND NOT EXISTS (SELECT 1
    FROM `pacific-plating-282708.sap_integration_v3.sap_mirror_doc` m
    WHERE m.U_OrderItem=e.order_item);

SELECT flow,IF(period=1,'FIRST_PERIOD','LATER_PERIOD') AS period_case,
  COUNT(*) AS event_identities,COUNT(DISTINCT order_item) AS items,
  MIN(DATE(charge_time)) AS first_charge_date,MAX(DATE(charge_time)) AS last_charge_date
FROM create_event
GROUP BY flow,period_case ORDER BY flow,period_case;

SELECT e.flow,
  COUNTIF(h.order_item IS NOT NULL) AS mapping_held_identities,
  COUNTIF(h.order_item IS NULL) AS source_route_candidates,
  COUNT(DISTINCT IF(h.order_item IS NULL,e.order_item,NULL)) AS source_route_items
FROM create_event e
LEFT JOIN `pacific-plating-282708.sap_integration_v3.v3_unit3_mapping_hold` h
  ON h.pipeline_run_id=e.pipeline_run_id AND h.order_item=e.order_item
 AND h.period=e.period AND h.charge_id=e.charge_id
GROUP BY e.flow ORDER BY e.flow;

SELECT e.flow,
  COUNTIF(o.OrderItem IS NOT NULL) AS onetime_source_matches,
  COUNTIF(r.OrderItem IS NOT NULL) AS rcl_source_matches,
  COUNT(*) AS candidate_identities
FROM create_event e
LEFT JOIN `pacific-plating-282708.sap_integration_v3.vw_onetime_payload_source` o
  ON o.OrderItem=e.order_item AND SAFE_CAST(o.Period AS INT64)=e.period
 AND o.InvoiceNo=e.invoice_no
LEFT JOIN `pacific-plating-282708.sap_data_engineer.sap_dashboard_carepay_installment` r
  ON r.OrderItem=e.order_item AND SAFE_CAST(r.Period AS INT64)=e.period
 AND r.InvoiceNo=e.invoice_no
GROUP BY e.flow ORDER BY e.flow;

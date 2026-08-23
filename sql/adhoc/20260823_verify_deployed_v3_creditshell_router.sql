-- Read-only post-deploy verification for DDL 081.
WITH classified AS (
  SELECT order_id,order_item,routing_decision
  FROM `pacific-plating-282708.sap_integration_v3.vw_creditshell_flow_classification`
),
violations AS (
  SELECT order_id,order_item
  FROM `pacific-plating-282708.sap_integration_v3.vw_creditshell_routing_violation`
)
SELECT
  CURRENT_TIMESTAMP() AS checked_at,
  COUNTIF(c.routing_decision='ROUTE_RCB_CREDITSHELL') AS route_rcb_items,
  COUNTIF(c.routing_decision='ROUTE_RCL_CREDIT_SHELL') AS route_rcl_items,
  COUNTIF(STARTS_WITH(c.routing_decision,'HOLD_')) AS hold_items,
  COUNT(v.order_item) AS onetime_routed_to_rcl_violations,
  COUNTIF(c.order_item IN ('L80569331-M1','L80569331-V1','L80482368-M1','L80482368-V1')
    AND c.routing_decision='ROUTE_RCB_CREDITSHELL') AS known_case_passes
FROM classified AS c
LEFT JOIN violations AS v
  ON v.order_id=c.order_id AND v.order_item=c.order_item;

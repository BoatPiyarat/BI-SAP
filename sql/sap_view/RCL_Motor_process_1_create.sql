-- BASELINE CAPTURE 2026-07-25 -- pulled verbatim from live BigQuery view definition
-- Object: sap_view.RCL_Motor_process_1_create
-- Part of the 11 sap_view process views confirmed as real nightly production, that
-- read directly from sap_integration_v2.SAP_LIVE_FULL. Repointing to
-- sap_integration_v3.stg_sap_state (deduped, no duplicate (OrderItem,Period) rows).
-- See docs/knowledge/30_SAP_CHANGELOG.md 2026-07-25 entry.
-- NOT repointed 2026-07-25: found a real correctness risk (see 30_SAP_CHANGELOG.md) -
-- this view checks "TransactionStatus IN Paid" to mean "already settled/created in SAP", which
-- breaks once stg_sap_state dedup collapses a later Cancelled row over a historical Paid row
-- for the same period. Stays on SAP_LIVE_FULL until a semantically-correct approach is designed.

  --new CREATE order--
SELECT
  DISTINCT *
FROM
  pacific-plating-282708.sap_data_engineer.sap_dashboard_carepay_installment interface
WHERE
 interface.OrderItem NOT IN (
  SELECT
    U_OrderItem
  FROM
    `pacific-plating-282708.sap_integration_v2.SAP_LIVE_FULL`
  ) 
 AND OrderID NOT IN (
  SELECT
    current_human_id
  FROM
    `pacific-plating-282708.careos.cancelled_change_orders` )
  AND OrderID NOT IN (
    -- 45 TIP no purchase anymore
    'L78239563',
    -- 49 is for non-motor orders (Muang Thai Life Assurance PCL)
    'L77783129','L77920845','L79111183','L79127474', 'L79325579'
  )
  AND OrderDate NOT LIKE '%2023%'
  AND OrderDate NOT LIKE '%2024%'

ORDER BY
  interface.OrderItem,
  Period;

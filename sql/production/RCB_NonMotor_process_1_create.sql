-- BASELINE CAPTURE 2026-07-24 -- pulled verbatim from live BigQuery view definition
-- Object: sap_view.RCB_NonMotor_process_1_create
-- Bug: hardcoded interface.OrderDate LIKE '%2025%' silently excludes every
-- 2026-dated order from ever being proposed for SAP creation. Confirmed live:
-- 91 RCB_HEALTH orders dated 2026 are genuinely missing from SAP right now.
-- See docs/knowledge/30_SAP_CHANGELOG.md (2026-07-24 entry) for detail.

WITH
  sap AS (
  SELECT
    *
  FROM
    `pacific-plating-282708.sap_integration_v2.SAP_LIVE_FULL` ),
  interface AS (
  SELECT
    *
  FROM
    `pacific-plating-282708.sap_data_engineer.RCB_HEALTH`
  UNION ALL
  SELECT
    *
  FROM
    `pacific-plating-282708.sap_data_engineer.RCB_TRAVEL`  )
SELECT
  interface.*
FROM
  interface
LEFT JOIN
  sap
ON
  sap.U_OrderItem = interface.OrderItem
WHERE
  sap.U_OrderItem IS NULL
  -- year-hardcode fix 2026-07-24: was "AND interface.OrderDate LIKE '%2025%'",
  -- silently excluded every 2026+ order forever. The LEFT JOIN anti-join above
  -- already limits this to "not yet in SAP" rows, so no date filter is needed.
  AND interface.TransactionStatus IS NOT NULL
ORDER BY
  OrderID



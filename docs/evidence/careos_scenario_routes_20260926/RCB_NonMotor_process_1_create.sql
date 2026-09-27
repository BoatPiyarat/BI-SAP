WITH
  sap AS (
  SELECT
    *
  FROM
    `pacific-plating-282708.sap_integration_v3.stg_sap_state` ),
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

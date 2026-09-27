WITH sap AS (
  SELECT
    sap.U_OrderItem
  FROM
    `pacific-plating-282708.sap_integration_v3.stg_sap_state` AS sap
)

SELECT
  non.* REPLACE (
    CASE
      WHEN LOWER(non.TransactionStatus) = 'pending'
        THEN ''
      ELSE non.PaymentMethod
    END AS PaymentMethod,

    CASE
      WHEN LOWER(non.TransactionStatus) = 'pending'
        THEN ''
      ELSE non.PaymentChannel
    END AS PaymentChannel
  )

FROM
  `pacific-plating-282708.sap_data_engineer.RCL_HEALTH` AS non

LEFT JOIN sap
  ON sap.U_OrderItem = non.OrderItem

WHERE
  sap.U_OrderItem IS NULL
  AND non.ActualReceived IS NOT NULL
  AND LOWER(non.FirstName) <> 'test'

ORDER BY
  non.OrderItem,
  non.Period

WITH filtered AS (
  SELECT
    src.*
  FROM
    `pacific-plating-282708.sap_integration_v2.RCL 04_new order credit shell` AS src
  WHERE
    -- Required to preserve the behavior of the original NOT IN condition.
    -- Upstream currently contains OrderItem NULL rows.
    src.OrderItem IS NOT NULL

    AND NOT EXISTS (
      SELECT
        1
      FROM
        `pacific-plating-282708.sap_integration_v2.SAP_LIVE_FULL` AS sap
      WHERE
        sap.U_OrderItem = src.OrderItem
    )

    AND EXISTS (
      SELECT
        1
      FROM
        `pacific-plating-282708.careos.cancelled_change_orders` AS change_order
      WHERE
        change_order.current_human_id = src.OrderID
    )

    AND (
      src.OrderDate LIKE '%2025%'
      OR src.OrderDate LIKE '%2026%'
    )

    AND src.OrderID NOT IN (
      'L79128866', -- incorrect insurer id
      'L79217528', -- incorrect insurer id
      'L79291428'  -- incorrect insurer id
    )

    -- Malformed rows wait until the upstream transaction data is complete.
    AND src.Period IS NOT NULL
    AND src.TotalPeriods IS NOT NULL
    AND src.Period BETWEEN 1 AND src.TotalPeriods
),

ranked AS (
  SELECT
    filtered.*,

    ROW_NUMBER() OVER (
      PARTITION BY
        filtered.OrderItem,
        filtered.Period
      ORDER BY
        -- A successful payment row is the expected schedule row.
        CASE
          WHEN LOWER(filtered.TransactionStatus) = 'paid' THEN 0
          ELSE 1
        END,

        -- Earlier payment keeps ExpectedReceived.
        SAFE.PARSE_DATE(
          '%d%m%Y',
          NULLIF(filtered.PaymentDate, '')
        ) NULLS LAST,

        NULLIF(filtered.InvoiceNo, '') NULLS LAST,

        -- Stable tie-breaker without removing valid additional payments.
        FARM_FINGERPRINT(TO_JSON_STRING(filtered))
    ) AS duplicate_period_seq
  FROM
    filtered
),

fixed AS (
  SELECT
    * EXCEPT (duplicate_period_seq)

    REPLACE (
      -- Period duplication is allowed, but ExpectedReceived must not repeat.
      CASE
        WHEN duplicate_period_seq = 1
          THEN ExpectedReceived
        ELSE 0
      END AS ExpectedReceived,

      -- Pending transactions have no successful charge information.
      CASE
        WHEN LOWER(TransactionStatus) = 'pending'
          THEN ''
        ELSE IFNULL(PaymentMethod, '')
      END AS PaymentMethod,

      CASE
        WHEN LOWER(TransactionStatus) = 'pending'
          THEN ''
        ELSE IFNULL(PaymentChannel, '')
      END AS PaymentChannel
    )
  FROM
    ranked
)

SELECT DISTINCT
  *
FROM
  fixed
ORDER BY
  OrderItem,
  Period
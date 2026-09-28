-- Full source-only legacy fix proposal for:
--   pacific-plating-282708.sap_view.RCL_Motor_process_4_creditshell
--
-- Root fixes:
--   1. Split Motor and NonMotor routing after the upstream payload is normalized.
--      Motor keeps its existing channel. Health/TA successful QR payments use
--      RCL-Omise QR Prompt Pay-Health, including later CreditShell installments.
--      The carried-over first installment keeps RCL-Credit Shell because its
--      PaymentMethod is RCL-Credit Shell, not OME Omise QR Prompt Pay.
--   2. A paid PaymentDate earlier than the current month is posted as the first
--      day of the current month. A current-month paid date is preserved.
--   3. Pending InvoiceNo/payment routing remains blank.
--   4. Preserve legitimate repeated-period payment rows and keep ExpectedReceived
--      only on the first row for an OrderItem/Period.
--
-- SELECT only: this file does not replace or deploy the live legacy view.

WITH
  filtered AS (
    SELECT src.*
    FROM `pacific-plating-282708.sap_integration_v2.RCL 04_new order credit shell` AS src
    WHERE src.OrderItem IS NOT NULL
      AND NOT EXISTS (
        SELECT 1
        FROM `pacific-plating-282708.sap_integration_v2.SAP_LIVE_FULL` AS sap
        WHERE sap.U_OrderItem = src.OrderItem
      )
      AND EXISTS (
        SELECT 1
        FROM `pacific-plating-282708.careos.cancelled_change_orders` AS change_order
        WHERE change_order.current_human_id = src.OrderID
      )
      AND (
        src.OrderDate LIKE '%2025%'
        OR src.OrderDate LIKE '%2026%'
      )
      AND src.OrderID NOT IN (
        'L79128866',
        'L79217528',
        'L79291428'
      )
      AND src.Period IS NOT NULL
      AND src.TotalPeriods IS NOT NULL
      AND src.Period BETWEEN 1 AND src.TotalPeriods
  ),

  ranked AS (
    SELECT
      filtered.*,
      ROW_NUMBER() OVER (
        PARTITION BY filtered.OrderItem, filtered.Period
        ORDER BY
          CASE WHEN LOWER(filtered.TransactionStatus) = 'paid' THEN 0 ELSE 1 END,
          SAFE.PARSE_DATE('%d%m%Y', NULLIF(filtered.PaymentDate, '')) NULLS LAST,
          NULLIF(filtered.InvoiceNo, '') NULLS LAST,
          FARM_FINGERPRINT(TO_JSON_STRING(filtered))
      ) AS duplicate_period_seq
    FROM filtered
  ),

  fixed_common AS (
    SELECT
      * EXCEPT (duplicate_period_seq)
      REPLACE (
        CASE
          WHEN duplicate_period_seq = 1 THEN ExpectedReceived
          ELSE 0
        END AS ExpectedReceived,
        CASE
          WHEN LOWER(TransactionStatus) = 'pending' THEN ''
          ELSE IFNULL(PaymentMethod, '')
        END AS PaymentMethod,
        CASE
          WHEN LOWER(TransactionStatus) = 'pending' THEN ''
          ELSE IFNULL(PaymentChannel, '')
        END AS PaymentChannel
      )
    FROM ranked
  ),

  motor_rows AS (
    SELECT *
    FROM fixed_common
    WHERE InsuranceGroup = 'Motor'
  ),

  nonmotor_rows AS (
    SELECT
      * REPLACE (
        CASE
          WHEN LOWER(TransactionStatus) = 'paid'
            AND PaymentMethod = 'OME Omise QR Prompt Pay'
          THEN 'RCL-Omise QR Prompt Pay-Health'
          ELSE PaymentChannel
        END AS PaymentChannel
      )
    FROM fixed_common
    WHERE InsuranceGroup IN ('Health', 'TA')
  ),

  unclassified_rows AS (
    -- Preserve unknown legacy product labels without guessing a payment route.
    SELECT *
    FROM fixed_common
    WHERE InsuranceGroup IS NULL
       OR InsuranceGroup NOT IN ('Motor', 'Health', 'TA')
  ),

  routed AS (
    SELECT * FROM motor_rows
    UNION ALL
    SELECT * FROM nonmotor_rows
    UNION ALL
    SELECT * FROM unclassified_rows
  ),

  payment_date_fixed AS (
    SELECT
      * REPLACE (
        CASE
          WHEN LOWER(TransactionStatus) = 'pending' THEN ''
          WHEN SAFE.PARSE_DATE('%d%m%Y', NULLIF(PaymentDate, ''))
            < DATE_TRUNC(CURRENT_DATE(), MONTH)
          THEN FORMAT_DATE('%d%m%Y', DATE_TRUNC(CURRENT_DATE(), MONTH))
          ELSE IFNULL(PaymentDate, '')
        END AS PaymentDate
      )
    FROM routed
  )

SELECT DISTINCT * REPLACE (
  CASE WHEN InsuranceGroup IN ('Health', 'TA') AND LOWER(TransactionStatus) = 'paid'
         AND SAFE.PARSE_DATE('%d%m%Y', NULLIF(PaymentDate, '')) < DATE_TRUNC(CURRENT_DATE('Asia/Bangkok'), MONTH)
       THEN FORMAT_DATE('%d%m%Y', DATE_TRUNC(CURRENT_DATE('Asia/Bangkok'), MONTH))
       ELSE PaymentDate END AS PaymentDate
)
FROM payment_date_fixed
ORDER BY OrderItem, Period;

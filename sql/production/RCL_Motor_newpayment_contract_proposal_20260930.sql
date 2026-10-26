-- PROPOSAL ONLY: full SELECT for sap_view.RCL_Motor_process_2_newpayment.
-- Preserve column positions and monetary/date values of Paid rows.
-- Canonicalize known statuses and documented empty fields; unknown statuses remain held.
-- Does NOT repair missing PolicyNo, unqualified leads, mapping, amounts or other gate failures.
-- No deployment authorized or performed.
WITH
  interface AS (
    SELECT *
    FROM `pacific-plating-282708.sap_integration_v2.RCL 05_paid`

    UNION ALL

    SELECT *
    FROM `pacific-plating-282708.sap_integration_v2.RCL 05_newpayment`
  ),

  eligible_newpayment_items AS (
    SELECT DISTINCT
      paid_by_period.order_item
    FROM `pacific-plating-282708.sap_integration_v2.RCL 05_paid by period` AS paid_by_period
    JOIN `pacific-plating-282708.careos.careos_order_items` AS order_item
      ON order_item.human_id = paid_by_period.order_item
    WHERE paid_by_period.product = 'products/car-insurance'
      AND paid_by_period.InsuranceType != 'MOTOR_TYPE_COMPULSORY'
      AND order_item.is_cancelled IS NOT TRUE
      AND order_item.cancel_time IS NULL
  ),

  source AS (
    SELECT DISTINCT
      interface.*
    FROM interface
    JOIN eligible_newpayment_items
      ON eligible_newpayment_items.order_item = interface.OrderItem
    WHERE TRUE -- Payment recency belongs to the receipt gate, not order creation year.
      -- Fail closed against RCB/RCL and NonMotor routing leakage.
      AND interface.InsuranceGroup = 'Motor'
      AND interface.InsuranceType != 'MOTOR_TYPE_COMPULSORY'
  ),

  classified AS (
    SELECT
      source.*,
      CASE
        WHEN COALESCE(source.ExpectedReceived, 0) = 0
          AND COALESCE(source.ActualReceived, 0) > 0
        THEN 1
        ELSE 0
      END AS is_additional_payment,
      ROW_NUMBER() OVER (
        PARTITION BY
          source.OrderItem,
          source.Period,
          CASE
            WHEN COALESCE(source.ExpectedReceived, 0) = 0
              AND COALESCE(source.ActualReceived, 0) > 0
            THEN COALESCE(
              NULLIF(source.InvoiceNo, ''),
              CONCAT(
                'additional_',
                CAST(source.ActualReceived AS STRING),
                '_',
                COALESCE(source.PaymentDate, '')
              )
            )
            ELSE 'normal_period_row'
          END
        ORDER BY
          CASE
            WHEN source.InvoiceNo IS NOT NULL
              AND source.InvoiceNo NOT IN ('', 'null', 'NULL')
            THEN 1 ELSE 2
          END,
          CASE
            WHEN source.PolicyNo IS NOT NULL
              AND source.PolicyNo NOT IN ('', 'null', 'NULL')
            THEN 1 ELSE 2
          END,
          CASE
            WHEN source.PaymentDate IS NOT NULL
              AND source.PaymentDate NOT IN ('', 'null', 'NULL')
            THEN 1 ELSE 2
          END,
          SAFE.PARSE_DATE('%d%m%Y', source.PaymentDate) DESC,
          TO_JSON_STRING(source) DESC
      ) AS rn
    FROM source
  )

SELECT
  * EXCEPT (is_additional_payment, rn) REPLACE (
    CASE LOWER(TransactionStatus) WHEN 'paid' THEN 'Paid' WHEN 'pending' THEN 'Pending'
      ELSE TransactionStatus END AS TransactionStatus,
    CASE WHEN LOWER(TransactionStatus)='pending' THEN '' ELSE InvoiceNo END AS InvoiceNo,
    CASE WHEN LOWER(TransactionStatus)='pending' THEN '' ELSE PaymentDate END AS PaymentDate,
    IFNULL(EndorsementNo,'') AS EndorsementNo,
    IFNULL(RefOrder,'') AS RefOrder
  )
FROM classified
WHERE rn = 1
ORDER BY OrderID, OrderItem, Period
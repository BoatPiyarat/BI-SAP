-- Read-only regression of the proposed final wrapper transformation.
-- Uses the current live wrapper as the before-set because the proposal preserves
-- its filters/dedup logic and changes only type-aware channel + PaymentDate.

WITH
  live AS (
    SELECT *
    FROM `pacific-plating-282708.sap_view.RCL_Motor_process_4_creditshell`
  ),

  candidate AS (
    SELECT
      * REPLACE (
        CASE
          WHEN InsuranceGroup IN ('Health', 'TA')
            AND LOWER(TransactionStatus) = 'paid'
            AND PaymentMethod = 'OME Omise QR Prompt Pay'
          THEN 'RCL-Omise QR Prompt Pay-Health'
          ELSE PaymentChannel
        END AS PaymentChannel,
        CASE
          WHEN LOWER(TransactionStatus) = 'pending' THEN ''
          WHEN SAFE.PARSE_DATE('%d%m%Y', NULLIF(PaymentDate, ''))
            < DATE_TRUNC(CURRENT_DATE(), MONTH)
          THEN FORMAT_DATE('%d%m%Y', DATE_TRUNC(CURRENT_DATE(), MONTH))
          ELSE IFNULL(PaymentDate, '')
        END AS PaymentDate
      )
    FROM live
  )

SELECT
  CURRENT_TIMESTAMP() AS checked_at_utc,
  (SELECT COUNT(*) FROM live) AS before_rows,
  (SELECT COUNT(*) FROM candidate) AS after_rows,
  (SELECT COUNT(*) FROM live)
    - (SELECT COUNT(*) FROM candidate) AS row_count_delta,
  (
    SELECT COUNT(*)
    FROM candidate
    WHERE InsuranceGroup = 'Motor'
      AND TO_JSON_STRING((SELECT AS STRUCT candidate.* EXCEPT (PaymentDate))) NOT IN (
        SELECT TO_JSON_STRING((SELECT AS STRUCT live.* EXCEPT (PaymentDate)))
        FROM live
        WHERE live.InsuranceGroup = 'Motor'
      )
  ) AS motor_non_date_payload_changes,
  (
    SELECT COUNT(*)
    FROM candidate
    WHERE InsuranceGroup IN ('Health', 'TA')
      AND LOWER(TransactionStatus) = 'paid'
      AND PaymentMethod = 'OME Omise QR Prompt Pay'
      AND PaymentChannel != 'RCL-Omise QR Prompt Pay-Health'
  ) AS bad_nonmotor_qr_channels,
  (
    SELECT COUNT(*)
    FROM candidate
    WHERE LOWER(TransactionStatus) = 'pending'
      AND (
        COALESCE(PaymentMethod, '') != ''
        OR COALESCE(PaymentChannel, '') != ''
        OR COALESCE(PaymentDate, '') != ''
      )
  ) AS bad_pending_payment_fields,
  (
    SELECT COUNT(*)
    FROM candidate
    WHERE LOWER(TransactionStatus) = 'paid'
      AND SAFE.PARSE_DATE('%d%m%Y', NULLIF(PaymentDate, ''))
        < DATE_TRUNC(CURRENT_DATE(), MONTH)
  ) AS old_paid_payment_dates_remaining,
  (
    SELECT COUNT(*)
    FROM candidate
    WHERE OrderItem = 'L80700230-1'
      AND Period = 2
      AND PaymentMethod = 'OME Omise QR Prompt Pay'
      AND PaymentChannel = 'RCL-Omise QR Prompt Pay-Health'
      AND PaymentDate = FORMAT_DATE('%d%m%Y', DATE_TRUNC(CURRENT_DATE(), MONTH))
  ) AS target_period_2_green_rows,
  (
    SELECT COUNT(*)
    FROM candidate
    WHERE OrderItem = 'L80700230-1'
      AND Period = 1
      AND PaymentMethod = 'RCL-Credit Shell'
      AND PaymentChannel = 'RCL-Credit Shell'
      AND PaymentDate = FORMAT_DATE('%d%m%Y', DATE_TRUNC(CURRENT_DATE(), MONTH))
  ) AS target_period_1_green_rows;

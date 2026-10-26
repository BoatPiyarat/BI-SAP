-- Read-only population profile before the type-aware legacy wrapper fix.

WITH live AS (
  SELECT *
  FROM `pacific-plating-282708.sap_view.RCL_Motor_process_4_creditshell`
)
SELECT
  IF(InsuranceGroup = 'Motor', 'MOTOR', 'NONMOTOR') AS route_family,
  InsuranceGroup,
  LOWER(TransactionStatus) AS transaction_status,
  PaymentMethod,
  PaymentChannel,
  COUNT(*) AS row_count,
  COUNT(DISTINCT OrderItem) AS item_count,
  COUNTIF(
    SAFE.PARSE_DATE('%d%m%Y', NULLIF(PaymentDate, ''))
      < DATE_TRUNC(CURRENT_DATE(), MONTH)
  ) AS old_payment_date_rows
FROM live
GROUP BY 1, 2, 3, 4, 5
ORDER BY route_family, InsuranceGroup, transaction_status, row_count DESC;

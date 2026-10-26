-- Exact replay of the August 2026 Health/BAY order-period list supplied by Mo,
-- plus an all-history search for matching Health/BAY pairs outside that list.
-- Read-only; report-only investigation.

WITH reported AS (
  SELECT * FROM UNNEST([
    STRUCT('L80552297' AS OrderID, 1 AS Period),
    STRUCT('L79770471',4), STRUCT('L80637895',1), STRUCT('L79360431',6),
    STRUCT('L80474626',2), STRUCT('L80682561',1), STRUCT('L79916653',6),
    STRUCT('L80005306',5), STRUCT('L79112016',10), STRUCT('L80421605',2),
    STRUCT('L80058018',4), STRUCT('L80289855',2), STRUCT('L80191270',4),
    STRUCT('L79771462',5), STRUCT('L79905998',5), STRUCT('L80124434',4),
    STRUCT('L80482298',2), STRUCT('L78974963',6), STRUCT('L79933935',6),
    STRUCT('L79930218',6), STRUCT('L79833236',3), STRUCT('L79367200',9),
    STRUCT('L80414868',3), STRUCT('L78784479',3), STRUCT('L79157426',10),
    STRUCT('L79769363',5), STRUCT('L79072658',10), STRUCT('L79962132',5),
    STRUCT('L80322117',3), STRUCT('L80148842',4), STRUCT('L79567494',3),
    STRUCT('L80425092',2), STRUCT('L79050967',2), STRUCT('L78891178',8),
    STRUCT('L80499390',2), STRUCT('L80461823',2), STRUCT('L78877276',3),
    STRUCT('L79506226',8), STRUCT('L80475101',2), STRUCT('L79484029',7),
    STRUCT('L80497796',2), STRUCT('L80050377',4), STRUCT('L79018331',8),
    STRUCT('L80461533',2), STRUCT('L80503243',2), STRUCT('L80055150',2),
    STRUCT('L79236694',5), STRUCT('L79095915',2), STRUCT('L79637467',2),
    STRUCT('L79190417',8), STRUCT('L78508754',2), STRUCT('L79020672',10),
    STRUCT('L79671811',7), STRUCT('L80130610',2), STRUCT('L80311643',2),
    STRUCT('L80434595',2), STRUCT('L80527329',2), STRUCT('L79053441',5),
    STRUCT('L80332070',2), STRUCT('L80182217',2), STRUCT('L79350549',9),
    STRUCT('L80514586',2), STRUCT('L79206281',5), STRUCT('L80146772',4),
    STRUCT('L80148129',4), STRUCT('L79129580',10), STRUCT('L80474917',2),
    STRUCT('L80035895',2), STRUCT('L79376267',9), STRUCT('L80150332',4),
    STRUCT('L79574979',6), STRUCT('L79284599',8), STRUCT('L79499290',4),
    STRUCT('L79798691',5), STRUCT('L80180793',4), STRUCT('L80242674',3),
    STRUCT('L80159422',4), STRUCT('L79494859',7), STRUCT('L79531977',7),
    STRUCT('L80042386',5), STRUCT('L79357422',9), STRUCT('L78539880',10),
    STRUCT('L79918908',6), STRUCT('L79143469',9), STRUCT('L78939082',5),
    STRUCT('L80279754',3), STRUCT('L79473789',8), STRUCT('L79526117',8),
    STRUCT('L80353304',3), STRUCT('L80015184',4), STRUCT('L79370373',9),
    STRUCT('L79846966',3), STRUCT('L80285438',3), STRUCT('L80181806',4),
    STRUCT('L80056028',4), STRUCT('L80281946',3), STRUCT('L79218212',9),
    STRUCT('L79668776',7), STRUCT('L79933167',6), STRUCT('L79535877',2),
    STRUCT('L80329189',3), STRUCT('L80321454',2), STRUCT('L79541409',7),
    STRUCT('L80056817',4), STRUCT('L80355324',3), STRUCT('L79578195',3),
    STRUCT('L79934719',6), STRUCT('L79627259',7), STRUCT('L79451220',8),
    STRUCT('L79294002',5), STRUCT('L79025173',10), STRUCT('L79368470',9),
    STRUCT('L80500790',2), STRUCT('L79368139',9), STRUCT('L79690699',7),
    STRUCT('L79384516',7), STRUCT('L79845016',6), STRUCT('L80235572',3),
    STRUCT('L79053854',5), STRUCT('L79529308',8), STRUCT('L79845135',6),
    STRUCT('L80369931',3), STRUCT('L79925949',6), STRUCT('L79502560',8),
    STRUCT('L80325540',3), STRUCT('L80056694',3), STRUCT('L80147352',4),
    STRUCT('L79946550',6), STRUCT('L79845336',5), STRUCT('L79689312',7),
    STRUCT('L80143177',2), STRUCT('L79941568',5), STRUCT('L79133150',10),
    STRUCT('L78999301',6), STRUCT('L80022776',5), STRUCT('L79717539',3),
    STRUCT('L80332102',2), STRUCT('L79809868',6), STRUCT('L80457874',2),
    STRUCT('L80496263',2), STRUCT('L80297469',3), STRUCT('L79855846',2),
    STRUCT('L80330107',3), STRUCT('L79346186',9), STRUCT('L79846520',6),
    STRUCT('L79929307',6), STRUCT('L80296949',3), STRUCT('L79652265',7),
    STRUCT('L79019488',9)
  ])
),

all_health_bay_pairs AS (
  SELECT
    U_OrderID AS OrderID,
    U_Period AS Period,
    COUNT(*) AS sap_row_count,
    MIN(SAFE.PARSE_DATE('%d%m%Y', NULLIF(PaymentDate, ''))) AS first_payment_date,
    MAX(SAFE.PARSE_DATE('%d%m%Y', NULLIF(PaymentDate, ''))) AS last_payment_date,
    MIN(SAFE.PARSE_DATE('%d%m%Y', NULLIF(BatchRunDate, ''))) AS first_batch_date,
    MAX(SAFE.PARSE_DATE('%d%m%Y', NULLIF(BatchRunDate, ''))) AS last_batch_date,
    MIN(UpdateDate) AS first_update_date,
    MAX(UpdateDate) AS last_update_date
  FROM `pacific-plating-282708.sap_integration_v2.SAP_LIVE_FULL`
  WHERE PaymentChannel = 'RCL-Omise QR Prompt Pay-BAY'
    AND (
      U_InsuranceGroup IN ('Health', 'products/health-insurance')
      OR U_InsuranceType = 'Health'
    )
  GROUP BY OrderID, Period
),

additional_health_bay_pairs AS (
  SELECT a.*
  FROM all_health_bay_pairs a
  LEFT JOIN reported r USING (OrderID, Period)
  WHERE r.OrderID IS NULL
),

sap AS (
  SELECT
    U_OrderID AS OrderID,
    U_Period AS Period,
    ARRAY_AGG(STRUCT(
      U_OrderItem AS OrderItem,
      PaymentChannel,
      PaymentDate,
      BatchRunDate,
      UpdateDate,
      U_InvoiceNo AS InvoiceNo
    ) ORDER BY UpdateDate DESC, DocEntry DESC) AS source_rows
  FROM `pacific-plating-282708.sap_integration_v2.SAP_LIVE_FULL`
  JOIN reported r ON r.OrderID = U_OrderID AND r.Period = U_Period
  GROUP BY OrderID, Period
),

health AS (
  SELECT
    OrderID,
    Period,
    ARRAY_AGG(STRUCT(OrderItem, PaymentChannel, PaymentDate, InvoiceNo)) AS source_rows
  FROM `pacific-plating-282708.sap_data_engineer.RCL_HEALTH`
  JOIN reported USING (OrderID, Period)
  GROUP BY OrderID, Period
),

classified AS (
  SELECT
    r.*,
    IFNULL(ARRAY_LENGTH(s.source_rows), 0) AS sap_rows,
    EXISTS(SELECT 1 FROM UNNEST(s.source_rows) x
           WHERE x.PaymentChannel = 'RCL-Omise QR Prompt Pay-BAY') AS sap_has_wrong_bay,
    EXISTS(SELECT 1 FROM UNNEST(s.source_rows) x
           WHERE x.PaymentChannel = 'RCL-Omise QR Prompt Pay-Health') AS sap_has_correct_health,
    EXISTS(SELECT 1 FROM UNNEST(h.source_rows) x
           WHERE x.PaymentChannel = 'RCL-Omise QR Prompt Pay-Health') AS current_source_is_health,
    s.source_rows AS sap_detail,
    h.source_rows AS current_source_detail
  FROM reported r
  LEFT JOIN sap s USING (OrderID, Period)
  LEFT JOIN health h USING (OrderID, Period)
)

SELECT
  COUNT(*) AS reported_pairs,
  COUNT(DISTINCT CONCAT(OrderID, '#', CAST(Period AS STRING))) AS distinct_reported_pairs,
  COUNTIF(sap_rows > 0) AS found_in_sap,
  COUNTIF(sap_has_wrong_bay) AS confirmed_wrong_bay,
  COUNTIF(sap_has_correct_health) AS already_correct_health,
  COUNTIF(sap_rows = 0) AS not_found_in_sap,
  COUNTIF(current_source_is_health) AS now_correct_in_rcl_health,
  (SELECT COUNT(*) FROM all_health_bay_pairs) AS all_history_health_bay_pairs,
  (SELECT SUM(sap_row_count) FROM all_health_bay_pairs) AS all_history_health_bay_rows,
  (SELECT COUNT(*) FROM additional_health_bay_pairs) AS additional_health_bay_pairs,
  (SELECT COUNT(DISTINCT OrderID) FROM additional_health_bay_pairs) AS additional_health_bay_orders,
  (SELECT SUM(sap_row_count) FROM additional_health_bay_pairs) AS additional_health_bay_rows,
  (SELECT MIN(first_payment_date) FROM additional_health_bay_pairs) AS additional_first_payment_date,
  (SELECT MAX(last_payment_date) FROM additional_health_bay_pairs) AS additional_last_payment_date,
  (SELECT MIN(first_batch_date) FROM additional_health_bay_pairs) AS additional_first_batch_date,
  (SELECT MAX(last_batch_date) FROM additional_health_bay_pairs) AS additional_last_batch_date,
  (SELECT MIN(first_update_date) FROM additional_health_bay_pairs) AS additional_first_update_date,
  (SELECT MAX(last_update_date) FROM additional_health_bay_pairs) AS additional_last_update_date,
  (SELECT ARRAY_AGG(STRUCT(payment_month, pair_count) ORDER BY payment_month)
   FROM (
     SELECT FORMAT_DATE('%Y-%m', last_payment_date) AS payment_month, COUNT(*) AS pair_count
     FROM additional_health_bay_pairs
     GROUP BY payment_month
   )) AS additional_pairs_by_payment_month,
  ARRAY_AGG(
    IF(NOT sap_has_wrong_bay,
      STRUCT(OrderID, Period, sap_detail, current_source_detail),
      NULL
    ) IGNORE NULLS ORDER BY OrderID
  ) AS non_bay_exceptions,
  ARRAY_AGG(
    IF(NOT current_source_is_health,
      STRUCT(OrderID, Period, sap_detail, current_source_detail),
      NULL
    ) IGNORE NULLS ORDER BY OrderID
  ) AS current_source_exceptions,
  ARRAY_AGG(STRUCT(
    OrderID, Period, sap_rows, sap_has_wrong_bay, sap_has_correct_health,
    current_source_is_health, sap_detail, current_source_detail
  ) ORDER BY OrderID LIMIT 30) AS samples
FROM classified;

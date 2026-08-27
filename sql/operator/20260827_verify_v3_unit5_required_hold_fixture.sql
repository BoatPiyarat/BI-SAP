-- READ ONLY. Regression fixture for DDL 058's complete item-level pre-export quarantine.
-- Covers SQL NULL, literal NULL, Paid required blanks, status, spine, duplicate, and date failures,
-- plus zero-held and zero-released populations. It writes only temporary tables.

CREATE TEMP TABLE _candidate (
  test_case STRING,OrderItem STRING,Period STRING,TotalPeriods STRING,InvoiceNo STRING,
  TransactionStatus STRING,LastName STRING,PolicyNo STRING,PaymentDate STRING,
  PaymentMethod STRING,PaymentChannel STRING,OrderDate STRING,PolicyDate STRING,
  ExpectedDate STRING,BatchRunDate STRING
);
INSERT INTO _candidate VALUES
  ('MIXED','GOOD-V1','1','2','INV-1','Paid','Good','POL-1','01082026','RCL','RCL-QR',
    '01012026','01012026','01082026','28082026'),
  ('MIXED','GOOD-V1','2','2','','Pending','Good','POL-1','','','',
    '01012026','01012026','01092026','28082026'),
  ('MIXED','BAD-LAST-V1','1','2','INV-2','Paid',NULL,'POL-2','01082026','RCL','RCL-QR',
    '01012026','01012026','01082026','28082026'),
  ('MIXED','BAD-LAST-V1','2','2','','Pending','Known','POL-2','','','',
    '01012026','01012026','01092026','28082026'),
  ('MIXED','BAD-LITERAL-V1','1','1','INV-3','Paid','Known','NULL','01082026','RCL','RCL-QR',
    '01012026','01012026','01082026','28082026'),
  ('MIXED','BAD-PAID-BLANK-V1','1','1','','Paid','Known','POL-4','01082026','RCL','RCL-QR',
    '01012026','01012026','01082026','28082026'),
  ('MIXED','BAD-STATUS-V1','1','1','INV-5','paid','Known','POL-5','01082026','RCL','RCL-QR',
    '01012026','01012026','01082026','28082026'),
  ('MIXED','BAD-SPINE-V1','1','3','INV-6','Paid','Known','POL-6','01082026','RCL','RCL-QR',
    '01012026','01012026','01082026','28082026'),
  ('MIXED','BAD-SPINE-V1','3','3','','Pending','Known','POL-6','','','',
    '01012026','01012026','01102026','28082026'),
  ('MIXED','BAD-DATE-V1','1','1','INV-7','Paid','Known','POL-7','01082026','RCL','RCL-QR',
    '01012026','bad-date','01082026','28082026'),
  ('MIXED','BAD-DUP-V1','1','1','INV-8','Paid','Known','POL-8','01082026','RCL','RCL-QR',
    '01012026','01012026','01082026','28082026'),
  ('MIXED','BAD-DUP-V1','1','1','INV-8','Paid','Known','POL-8','01082026','RCL','RCL-QR',
    '01012026','01012026','01082026','28082026'),
  ('ZERO_HELD','ONLY-GOOD-V1','1','1','INV-Z1','Paid','Good','POL-Z1','01082026','RCL','RCL-QR',
    '01012026','01012026','01082026','28082026'),
  ('ZERO_RELEASED','ONLY-BAD-V1','1','1','INV-Z2','Paid',NULL,'POL-Z2','01082026','RCL','RCL-QR',
    '01012026','01012026','01082026','28082026');

CREATE TEMP TABLE _spine_invalid_item AS
SELECT test_case,OrderItem FROM (
  SELECT test_case,OrderItem,COUNT(DISTINCT SAFE_CAST(Period AS INT64)) period_n,
    MIN(SAFE_CAST(Period AS INT64)) first_period,MAX(SAFE_CAST(Period AS INT64)) last_period,
    COUNT(DISTINCT SAFE_CAST(TotalPeriods AS INT64)) total_value_n,
    MAX(SAFE_CAST(TotalPeriods AS INT64)) total_n
  FROM _candidate GROUP BY test_case,OrderItem)
WHERE total_value_n!=1 OR first_period!=1 OR last_period!=total_n OR period_n!=total_n;

CREATE TEMP TABLE _candidate_validation_issue AS
SELECT c.test_case,c.OrderItem order_item,SAFE_CAST(c.Period AS INT64) period,
  'SPINE_INCOMPLETE' rule_code,CAST(NULL AS STRING) field_name
FROM _candidate c JOIN _spine_invalid_item b USING(test_case,OrderItem)
UNION ALL
SELECT test_case,OrderItem,SAFE_CAST(Period AS INT64),'STATUS_INVALID','TransactionStatus'
FROM _candidate WHERE TransactionStatus NOT IN ('Paid','Pending') OR TransactionStatus IS NULL
UNION ALL
SELECT test_case,OrderItem,SAFE_CAST(Period AS INT64),'DUPLICATE_PERIOD_INVOICE_IDENTITY',
  CAST(NULL AS STRING)
FROM (
  SELECT test_case,OrderItem,Period,IFNULL(InvoiceNo,'') invoice_no,COUNT(*) row_count
  FROM _candidate GROUP BY 1,2,3,4 HAVING row_count!=1)
UNION ALL
SELECT c.test_case,c.OrderItem,SAFE_CAST(c.Period AS INT64),'PAID_REQUIRED_FIELD_BLANK',f.field_name
FROM _candidate c
CROSS JOIN UNNEST([
  STRUCT('InvoiceNo' AS field_name,c.InvoiceNo AS field_value),
  STRUCT('PaymentDate' AS field_name,c.PaymentDate AS field_value),
  STRUCT('PaymentMethod' AS field_name,c.PaymentMethod AS field_value),
  STRUCT('PaymentChannel' AS field_name,c.PaymentChannel AS field_value)
]) f
WHERE c.TransactionStatus='Paid' AND NULLIF(TRIM(f.field_value),'') IS NULL
UNION ALL
SELECT c.test_case,c.OrderItem,SAFE_CAST(c.Period AS INT64),'REQUIRED_VALUE_NULL_OR_LITERAL_NULL',
  field_name
FROM _candidate c,
UNNEST(REGEXP_EXTRACT_ALL(TO_JSON_STRING(c),r'"([^"]+)":(?:null|"NULL")')) field_name
UNION ALL
SELECT test_case,OrderItem,SAFE_CAST(Period AS INT64),'DATE_FORMAT_INVALID',date_column
FROM _candidate
UNPIVOT(date_value FOR date_column IN (OrderDate,PolicyDate,ExpectedDate,BatchRunDate))
WHERE LENGTH(IFNULL(date_value,''))!=8 OR SAFE.PARSE_DATE('%d%m%Y',date_value) IS NULL
UNION ALL
SELECT test_case,OrderItem,SAFE_CAST(Period AS INT64),'PAYMENT_DATE_FORMAT_INVALID','PaymentDate'
FROM _candidate
WHERE NULLIF(PaymentDate,'') IS NOT NULL
  AND (LENGTH(PaymentDate)!=8 OR SAFE.PARSE_DATE('%d%m%Y',PaymentDate) IS NULL);

CREATE TEMP TABLE _candidate_invalid_field AS
SELECT test_case,order_item,ARRAY_AGG(DISTINCT field_name ORDER BY field_name) invalid_fields
FROM _candidate_validation_issue
WHERE field_name IS NOT NULL
GROUP BY test_case,order_item;

CREATE TEMP TABLE _candidate_hold AS
SELECT i.test_case,i.order_item,
  STRING_AGG(DISTINCT i.rule_code,'|' ORDER BY i.rule_code) hold_reason,
  IFNULL(ANY_VALUE(f.invalid_fields),ARRAY<STRING>[]) invalid_fields
FROM _candidate_validation_issue i
LEFT JOIN _candidate_invalid_field f USING(test_case,order_item)
GROUP BY i.test_case,i.order_item;

CREATE TEMP TABLE _candidate_release AS
SELECT c.test_case,c.OrderItem,c.Period,c.TotalPeriods,c.InvoiceNo,c.TransactionStatus,c.LastName,
  c.PolicyNo,c.PaymentDate,c.PaymentMethod,c.PaymentChannel,c.OrderDate,c.PolicyDate,c.ExpectedDate,
  c.BatchRunDate
FROM _candidate c
WHERE NOT EXISTS (SELECT 1 FROM _candidate_hold h
  WHERE h.test_case=c.test_case AND h.order_item=c.OrderItem);

ASSERT (SELECT COUNT(*) FROM _candidate_hold WHERE test_case='MIXED')=7
  AS 'mixed fixture must hold all seven invalid items';
ASSERT (SELECT COUNT(*) FROM _candidate_release WHERE test_case='MIXED')=2
  AND (SELECT COUNT(DISTINCT OrderItem) FROM _candidate_release WHERE test_case='MIXED')=1
  AS 'mixed fixture must release only the complete clean item';
ASSERT (SELECT hold_reason LIKE '%REQUIRED_VALUE_NULL_OR_LITERAL_NULL%'
  FROM _candidate_hold WHERE test_case='MIXED' AND order_item='BAD-LITERAL-V1')
  AS 'literal NULL fixture must be quarantined';
ASSERT (SELECT hold_reason LIKE '%PAID_REQUIRED_FIELD_BLANK%'
  FROM _candidate_hold WHERE test_case='MIXED' AND order_item='BAD-PAID-BLANK-V1')
  AS 'Paid blank fixture must be quarantined before publication';
ASSERT (SELECT COUNT(*) FROM _candidate_hold WHERE test_case='ZERO_HELD')=0
  AND (SELECT COUNT(*) FROM _candidate_release WHERE test_case='ZERO_HELD')=1
  AS 'zero-held fixture must release its clean item';
ASSERT (SELECT COUNT(*) FROM _candidate_hold WHERE test_case='ZERO_RELEASED')=1
  AND (SELECT COUNT(*) FROM _candidate_release WHERE test_case='ZERO_RELEASED')=0
  AS 'zero-released fixture must retain its invalid item';
ASSERT (SELECT COUNT(*) FROM _candidate_validation_issue i
  WHERE EXISTS (SELECT 1 FROM _candidate_release r
    WHERE r.test_case=i.test_case AND r.OrderItem=i.order_item))=0
  AS 'a held item leaked into fixture release';

SELECT 'PASS' fixture_status,7 mixed_held_items,1 mixed_released_item,
  0 zero_held_items,0 zero_released_rows;

-- READ ONLY. Minimal regression fixture for DDL 058's whole-item required-value quarantine.
-- The fixture reproduces the two production shapes: SQL NULL LastName and SQL NULL PolicyNo.

CREATE TEMP TABLE _candidate (
  OrderItem STRING,Period STRING,LastName STRING,PolicyNo STRING
);
INSERT INTO _candidate VALUES
  ('GOOD-V1','1','Good','POL-1'),
  ('GOOD-V1','2','Good','POL-1'),
  ('BAD-LAST-V1','1',NULL,'POL-2'),
  ('BAD-LAST-V1','2','Known','POL-2'),
  ('BAD-POLICY-V1','1','Known',NULL),
  ('BAD-POLICY-V1','2','Known','POL-3');

CREATE TEMP TABLE _candidate_required_hold AS
SELECT c.OrderItem order_item,
  ARRAY_AGG(DISTINCT field_name ORDER BY field_name) invalid_fields,
  COUNT(DISTINCT SAFE_CAST(c.Period AS INT64)) invalid_period_rows
FROM _candidate c,
UNNEST(REGEXP_EXTRACT_ALL(TO_JSON_STRING(c),r'"([^"]+)":(?:null|"NULL")')) field_name
GROUP BY c.OrderItem;

CREATE TEMP TABLE _candidate_release AS
SELECT c.* FROM _candidate c
WHERE NOT EXISTS (SELECT 1 FROM _candidate_required_hold h WHERE h.order_item=c.OrderItem);

ASSERT (SELECT COUNT(*) FROM _candidate_required_hold)=2
  AS 'fixture must hold exactly the LastName and PolicyNo items';
ASSERT (SELECT ARRAY_LENGTH(invalid_fields)=1 AND invalid_fields[SAFE_OFFSET(0)]='LastName'
  FROM _candidate_required_hold WHERE order_item='BAD-LAST-V1')
  AS 'LastName fixture field attribution changed';
ASSERT (SELECT ARRAY_LENGTH(invalid_fields)=1 AND invalid_fields[SAFE_OFFSET(0)]='PolicyNo'
  FROM _candidate_required_hold WHERE order_item='BAD-POLICY-V1')
  AS 'PolicyNo fixture field attribution changed';
ASSERT (SELECT COUNT(*) FROM _candidate_release)=2
  AND (SELECT COUNT(DISTINCT OrderItem) FROM _candidate_release)=1
  AND (SELECT ANY_VALUE(OrderItem) FROM _candidate_release)='GOOD-V1'
  AS 'one invalid period must quarantine its complete OrderItem spine only';
ASSERT (SELECT COUNT(*) FROM _candidate_release c
  WHERE REGEXP_CONTAINS(TO_JSON_STRING(c),r':null|:"NULL"'))=0
  AS 'released fixture rows must contain no SQL NULL or literal NULL';

SELECT 'PASS' AS fixture_status,2 AS held_items,1 AS released_items,2 AS released_rows;

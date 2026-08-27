-- Zero-byte, non-persistent fixture for BigQuery's ARRAY nullability rule.
-- DDL 058 must leave ARRAY fields nullable because BigQuery rejects NOT NULL on ARRAY columns;
-- stored ARRAY values are nevertheless always represented as an array rather than SQL NULL.

CREATE TEMP TABLE _required_hold_schema (
  pipeline_run_id STRING NOT NULL,
  order_item STRING NOT NULL,
  invalid_fields ARRAY<STRING>,
  invalid_period_rows INT64 NOT NULL
);

INSERT INTO _required_hold_schema
VALUES ('FIXTURE-RUN', 'FIXTURE-ITEM', ['LastName', 'PolicyNo'], 2);

ASSERT (SELECT COUNT(*) FROM _required_hold_schema) = 1
  AS 'Required-hold ARRAY schema fixture must preserve one row';
ASSERT (SELECT TO_JSON_STRING(invalid_fields) FROM _required_hold_schema)
  = '["LastName","PolicyNo"]'
  AS 'Required-hold ARRAY schema fixture must preserve field-name evidence';

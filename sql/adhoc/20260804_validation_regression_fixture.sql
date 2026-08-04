-- Literal-only healthy/failing validation-regression acceptance fixture.
-- Human alert delivery must be tested separately after reviewed deployment.

CREATE TEMP TABLE fixture (
  case_name STRING,
  current_records INT64,
  prior_records INT64,
  current_orders INT64,
  prior_orders INT64,
  max_record_increase INT64,
  max_order_increase INT64,
  expected_breach BOOL
);

INSERT INTO fixture VALUES
  ('healthy_same', 22, 22, 20, 20, 10, 5, FALSE),
  ('healthy_decrease', 10, 22, 9, 20, 10, 5, FALSE),
  ('healthy_at_limit', 32, 22, 25, 20, 10, 5, FALSE),
  ('failing_record_spike', 33, 22, 20, 20, 10, 5, TRUE),
  ('failing_order_spike', 22, 22, 26, 20, 10, 5, TRUE),
  ('failing_new_rule_above_floor', 11, 0, 11, 0, 10, 5, TRUE);

ASSERT (
  SELECT COUNTIF(
    ((current_records - prior_records > max_record_increase)
      OR (current_orders - prior_orders > max_order_increase)) != expected_breach
  )
  FROM fixture
) = 0 AS 'validation regression fixture failed';

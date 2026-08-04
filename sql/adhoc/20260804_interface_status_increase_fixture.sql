-- Literal-only decision fixture for the day-over-day increase seam.
-- No production reads or writes.

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
  ('unchanged', 100, 100, 90, 90, 10, 5, FALSE),
  ('decrease_never_alerts', 50, 100, 40, 90, 10, 5, FALSE),
  ('at_record_threshold_passes', 110, 100, 90, 90, 10, 5, FALSE),
  ('record_increase_alerts', 111, 100, 90, 90, 10, 5, TRUE),
  ('order_increase_alerts', 100, 100, 96, 90, 10, 5, TRUE);

ASSERT (
  SELECT COUNTIF(
    ((current_records - prior_records > max_record_increase)
      OR (current_orders - prior_orders > max_order_increase)) != expected_breach
  )
  FROM fixture
) = 0 AS 'interface-status increase decision fixture failed';

-- RED/GREEN fixture for the Unit 2 magnitude decision seam.
-- Literal-only: no production table reads or writes.

CREATE TEMP FUNCTION magnitude_breach(
  baseline_value NUMERIC,
  current_value NUMERIC,
  max_absolute_delta NUMERIC,
  max_percentage_delta NUMERIC
) AS (
  ABS(current_value - baseline_value) > max_absolute_delta
  AND (
    baseline_value = 0
    OR SAFE_DIVIDE(ABS(current_value - baseline_value), ABS(baseline_value))
      > max_percentage_delta
  )
);

CREATE TEMP TABLE fixture AS
SELECT 'ordinary_pass' AS case_name, 100 AS baseline_value, 105 AS current_value,
  25 AS max_absolute_delta, NUMERIC '0.20' AS max_percentage_delta, FALSE AS expected
UNION ALL
SELECT 'percentage_only_does_not_block', 100, 121, 25, NUMERIC '0.20', FALSE
UNION ALL
SELECT 'absolute_and_percentage_block', 100, 126, 25, NUMERIC '0.20', TRUE
UNION ALL
SELECT 'removed_cell_blocks', 100, 0, 25, NUMERIC '0.20', TRUE
UNION ALL
SELECT 'small_new_zero_baseline_passes_floor', 0, 25, 25, NUMERIC '0.20', FALSE
UNION ALL
SELECT 'large_new_zero_baseline_blocks', 0, 26, 25, NUMERIC '0.20', TRUE;

ASSERT (
  SELECT COUNTIF(
    magnitude_breach(
      baseline_value, current_value, max_absolute_delta, max_percentage_delta
    ) != expected
  )
  FROM fixture
) = 0 AS 'Magnitude decision fixture failed';

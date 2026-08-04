-- Literal-only fixture for the shared DDL 058/059/069 complete-spine assertion.
-- No production tables are read or written.

BEGIN
  CREATE TEMP TABLE fixture AS
  SELECT 'healthy_contiguous' case_name, period, 3 total_periods
  FROM UNNEST([1,2,3]) period
  UNION ALL
  SELECT 'gap_with_same_cardinality', period, 3
  FROM UNNEST([1,2,4]) period
  UNION ALL
  SELECT 'inconsistent_total', period, total_periods
  FROM UNNEST([
    STRUCT(1 AS period,3 AS total_periods),
    STRUCT(2 AS period,4 AS total_periods),
    STRUCT(3 AS period,3 AS total_periods)
  ]);

  CREATE TEMP TABLE result AS
  SELECT case_name,
    COUNT(DISTINCT period) period_n,
    MIN(period) first_period,
    MAX(period) last_period,
    COUNT(DISTINCT total_periods) total_value_n,
    MAX(total_periods) total_n,
    COUNT(DISTINCT total_periods)!=1 OR MIN(period)!=1
      OR MAX(period)!=MAX(total_periods)
      OR COUNT(DISTINCT period)!=MAX(total_periods) is_incomplete
  FROM fixture
  GROUP BY case_name;

  ASSERT (SELECT COUNT(*) FROM result
    WHERE case_name='healthy_contiguous' AND NOT is_incomplete)=1
    AS 'healthy contiguous 1..TotalPeriods spine must pass';
  ASSERT (SELECT COUNT(*) FROM result
    WHERE case_name='gap_with_same_cardinality' AND is_incomplete)=1
    AS 'same-cardinality spine with out-of-range period must fail';
  ASSERT (SELECT COUNT(*) FROM result
    WHERE case_name='inconsistent_total' AND is_incomplete)=1
    AS 'inconsistent TotalPeriods values must fail';
END;

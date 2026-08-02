-- Non-production rehearsal: TEMP tables only. No persistent table or procedure is mutated.
CREATE TEMP TABLE period_state AS
SELECT * FROM UNNEST([
  STRUCT('2026-07' AS period_id,DATE '2026-07-01' AS period_start,
    DATE '2026-08-01' AS period_end,'OPEN' AS status,
    TIMESTAMP '2026-08-03 07:00:00+00' AS closing_at,
    CAST(NULL AS TIMESTAMP) AS closed_at,CAST(NULL AS STRING) AS closed_by,
    1 AS state_version),
  STRUCT('2026-08',DATE '2026-08-01',DATE '2026-09-01','PLANNED',CAST(NULL AS TIMESTAMP),
    CAST(NULL AS TIMESTAMP),CAST(NULL AS STRING),1)
]);
CREATE TEMP TABLE legacy_lock AS
SELECT '2026-07' period,DATE '2026-07-01' open_period_start,
  TIMESTAMP '2026-08-03 07:00:00+00' lock_datetime;

ASSERT (SELECT COUNT(*) FROM period_state WHERE status='OPEN')=1 AS 'pre exact-one OPEN';
ASSERT (SELECT COUNT(*) FROM period_state a JOIN period_state b
  ON a.period_end=b.period_start WHERE a.status='OPEN' AND b.status='PLANNED')=1
  AS 'pre adjacency';

-- Rehearse the success transition using an explicit simulated clock after close.
BEGIN TRANSACTION;
UPDATE period_state SET status='CLOSED',closed_at=TIMESTAMP '2026-08-03 07:00:01+00',
  closed_by='REHEARSAL',state_version=state_version+1 WHERE period_start=DATE '2026-07-01';
UPDATE period_state SET status='OPEN',closing_at=TIMESTAMP '2026-09-03 07:00:00+00',
  state_version=state_version+1 WHERE period_start=DATE '2026-08-01';
UPDATE legacy_lock SET lock_datetime=TIMESTAMP '2026-08-03 07:00:00+00'
  WHERE open_period_start=DATE '2026-07-01';
INSERT INTO legacy_lock VALUES('2026-08',DATE '2026-08-01',TIMESTAMP '2026-09-03 07:00:00+00');
INSERT INTO period_state VALUES('2026-09',DATE '2026-09-01',DATE '2026-10-01','PLANNED',NULL,NULL,NULL,1);
ASSERT (SELECT COUNT(*) FROM period_state WHERE status='OPEN')=1 AS 'post exact-one OPEN';
ASSERT (SELECT COUNT(*) FROM period_state WHERE period_start=DATE '2026-07-01'
  AND status='CLOSED' AND closed_by='REHEARSAL')=1 AS 'July did not close';
ASSERT (SELECT COUNT(*) FROM period_state WHERE period_start=DATE '2026-08-01'
  AND status='OPEN' AND closing_at=TIMESTAMP '2026-09-03 07:00:00+00')=1 AS 'August did not open';
ASSERT (SELECT COUNT(*) FROM legacy_lock
  WHERE lock_datetime>TIMESTAMP '2026-08-03 07:00:01+00')=1 AS 'legacy active invariant';
COMMIT TRANSACTION;

-- Date behavior: backlog clamps to the new OPEN start; in-period remains raw; future is held.
CREATE TEMP TABLE classified AS WITH cases AS (
  SELECT raw_date FROM UNNEST([DATE '2026-06-20',DATE '2026-08-02',DATE '2026-09-01']) AS raw_date
), classified AS (
  SELECT raw_date,
    CASE WHEN raw_date>=DATE '2026-09-01' THEN 'HOLD_FUTURE'
      ELSE 'READY' END outcome,
    CASE WHEN raw_date<DATE '2026-08-01' THEN DATE '2026-08-01'
      WHEN raw_date<DATE '2026-09-01' THEN raw_date END effective_date
  FROM cases
)
SELECT * FROM classified ORDER BY raw_date;
ASSERT (SELECT COUNT(*) FROM classified WHERE raw_date=DATE '2026-06-20'
  AND effective_date=DATE '2026-08-01')=1 AS 'backlog clamp failed';
ASSERT (SELECT COUNT(*) FROM classified WHERE raw_date=DATE '2026-08-02'
  AND effective_date=raw_date)=1 AS 'in-period date changed';
ASSERT (SELECT COUNT(*) FROM classified WHERE raw_date=DATE '2026-09-01'
  AND outcome='HOLD_FUTURE' AND effective_date IS NULL)=1 AS 'future hold failed';

-- Prove an error inside the transaction rolls back every preceding mutation.
CREATE TEMP TABLE rollback_probe AS SELECT 1 value;
BEGIN
  BEGIN TRANSACTION;
  UPDATE rollback_probe SET value=2 WHERE TRUE;
  ASSERT FALSE AS 'deliberate rollback rehearsal';
  COMMIT TRANSACTION;
EXCEPTION WHEN ERROR THEN
  ROLLBACK TRANSACTION;
END;
ASSERT (SELECT value FROM rollback_probe)=1 AS 'failed transition did not roll back atomically';

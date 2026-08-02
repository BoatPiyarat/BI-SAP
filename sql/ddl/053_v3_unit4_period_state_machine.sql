-- SOURCE ONLY / Class A. Explicit monthly OPEN/CLOSED state with legacy sap_period_lock compatibility.
-- Deploying definitions does not close a period. Seed and close CALLs are separate mutations.

CREATE TABLE IF NOT EXISTS `pacific-plating-282708.sap_integration_v3.sap_period_state` (
  period_id STRING NOT NULL,
  period_start DATE NOT NULL,
  period_end DATE NOT NULL,
  status STRING NOT NULL,
  closing_at TIMESTAMP,
  closed_at TIMESTAMP,
  closed_by STRING,
  state_version INT64 NOT NULL,
  created_at TIMESTAMP NOT NULL,
  updated_at TIMESTAMP NOT NULL
)
CLUSTER BY status, period_start;

CREATE OR REPLACE PROCEDURE `pacific-plating-282708.sap_integration_v3.sp_seed_period_state_from_lock`()
BEGIN
  DECLARE active_count INT64;
  DECLARE current_start DATE;
  DECLARE current_close TIMESTAMP;
  SET active_count=(SELECT COUNT(*)
    FROM `pacific-plating-282708.sap_integration_v3.sap_period_lock`
    WHERE lock_datetime>CURRENT_TIMESTAMP());
  ASSERT active_count=1 AS 'Seed requires exactly one active legacy sap_period_lock row';
  ASSERT (SELECT COUNT(*) FROM `pacific-plating-282708.sap_integration_v3.sap_period_state`)=0
    AS 'Seed is one-time only; sap_period_state is not empty';
  SET (current_start,current_close)=(SELECT AS STRUCT open_period_start,lock_datetime
    FROM `pacific-plating-282708.sap_integration_v3.sap_period_lock`
    WHERE lock_datetime>CURRENT_TIMESTAMP());
  ASSERT current_start=DATE_TRUNC(current_start,MONTH) AS 'Legacy open period is not month-aligned';
  ASSERT current_close>CURRENT_TIMESTAMP() AS 'Legacy closing time is not in the future';

  BEGIN TRANSACTION;
  INSERT INTO `pacific-plating-282708.sap_integration_v3.sap_period_state`
    (period_id,period_start,period_end,status,closing_at,closed_at,closed_by,state_version,
     created_at,updated_at)
  VALUES
    (FORMAT_DATE('%Y-%m',current_start),current_start,DATE_ADD(current_start,INTERVAL 1 MONTH),
     'OPEN',current_close,NULL,NULL,1,CURRENT_TIMESTAMP(),CURRENT_TIMESTAMP()),
    (FORMAT_DATE('%Y-%m',DATE_ADD(current_start,INTERVAL 1 MONTH)),
     DATE_ADD(current_start,INTERVAL 1 MONTH),DATE_ADD(current_start,INTERVAL 2 MONTH),
     'PLANNED',NULL,NULL,NULL,1,CURRENT_TIMESTAMP(),CURRENT_TIMESTAMP());
  ASSERT (SELECT COUNT(*) FROM `pacific-plating-282708.sap_integration_v3.sap_period_state`
    WHERE status='OPEN')=1 AS 'Seed failed exact-one OPEN invariant';
  COMMIT TRANSACTION;
END;

CREATE OR REPLACE PROCEDURE `pacific-plating-282708.sap_integration_v3.sp_close_open_period`(
  p_period_start DATE,
  p_closing_at TIMESTAMP,
  p_next_closing_at TIMESTAMP,
  p_closed_by STRING
)
BEGIN
  DECLARE next_start DATE DEFAULT DATE_ADD(p_period_start,INTERVAL 1 MONTH);
  ASSERT p_period_start=DATE_TRUNC(p_period_start,MONTH) AS 'period_start must be month-aligned';
  ASSERT NULLIF(TRIM(p_closed_by),'') IS NOT NULL AS 'closed_by is required';
  ASSERT p_closing_at<=CURRENT_TIMESTAMP() AS 'Cannot close before authoritative closing_at';
  ASSERT p_next_closing_at>p_closing_at AS 'Next closing_at must be later than current closing_at';
  ASSERT (SELECT COUNT(*) FROM `pacific-plating-282708.sap_integration_v3.sap_period_state`
    WHERE status='OPEN')=1 AS 'Requires exactly one OPEN period';
  ASSERT (SELECT COUNT(*) FROM `pacific-plating-282708.sap_integration_v3.sap_period_state`
    WHERE period_start=p_period_start AND period_end=next_start AND status='OPEN'
      AND closing_at=p_closing_at)=1 AS 'OPEN period or authoritative closing_at mismatch';
  ASSERT (SELECT COUNT(*) FROM `pacific-plating-282708.sap_integration_v3.sap_period_state`
    WHERE period_start=next_start AND period_end=DATE_ADD(next_start,INTERVAL 1 MONTH)
      AND status='PLANNED')=1 AS 'Adjacent next PLANNED period is missing';
  ASSERT (SELECT COUNT(*) FROM `pacific-plating-282708.sap_integration_v3.sap_period_lock`
    WHERE open_period_start=p_period_start)=1 AS 'Legacy current-period row mismatch';

  BEGIN TRANSACTION;
  UPDATE `pacific-plating-282708.sap_integration_v3.sap_period_state`
  SET status='CLOSED',closed_at=CURRENT_TIMESTAMP(),closed_by=p_closed_by,
      state_version=state_version+1,updated_at=CURRENT_TIMESTAMP()
  WHERE period_start=p_period_start AND status='OPEN';

  UPDATE `pacific-plating-282708.sap_integration_v3.sap_period_state`
  SET status='OPEN',closing_at=p_next_closing_at,state_version=state_version+1,
      updated_at=CURRENT_TIMESTAMP()
  WHERE period_start=next_start AND status='PLANNED';

  UPDATE `pacific-plating-282708.sap_integration_v3.sap_period_lock`
  SET lock_datetime=p_closing_at,locked_by=p_closed_by,locked_at=CURRENT_TIMESTAMP()
  WHERE open_period_start=p_period_start;

  INSERT INTO `pacific-plating-282708.sap_integration_v3.sap_period_lock`
    (period,open_period_start,lock_datetime,locked_by,locked_at)
  VALUES (FORMAT_DATE('%Y-%m',next_start),next_start,p_next_closing_at,NULL,NULL);

  INSERT INTO `pacific-plating-282708.sap_integration_v3.sap_period_state`
    (period_id,period_start,period_end,status,closing_at,closed_at,closed_by,state_version,
     created_at,updated_at)
  VALUES (FORMAT_DATE('%Y-%m',DATE_ADD(next_start,INTERVAL 1 MONTH)),
    DATE_ADD(next_start,INTERVAL 1 MONTH),DATE_ADD(next_start,INTERVAL 2 MONTH),
    'PLANNED',NULL,NULL,NULL,1,CURRENT_TIMESTAMP(),CURRENT_TIMESTAMP());

  ASSERT (SELECT COUNT(*) FROM `pacific-plating-282708.sap_integration_v3.sap_period_state`
    WHERE status='OPEN')=1 AS 'Post-transition exact-one OPEN invariant failed';
  ASSERT (SELECT COUNT(*) FROM `pacific-plating-282708.sap_integration_v3.sap_period_lock`
    WHERE lock_datetime>CURRENT_TIMESTAMP())=1 AS 'Legacy compatibility exact-one active invariant failed';
  COMMIT TRANSACTION;
END;

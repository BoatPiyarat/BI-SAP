-- 010_rcl_backfill_full_period_chunked.sql
-- Boat, 2026-07-25: corrects the first backfill attempt, which violated the real RCL interface
-- rule Boat clarified: "when you want the new period payment change from pending to paid - you
-- need to interface the full periods starting with the old paid (on SAP) together with new
-- payment period and anything unpaid is remain pending." The first attempt scoped by
-- (order_item, period) against recon_status = 'MISSING_FROM_SAP', which stripped out each
-- order's already-Paid anchor period and still-legitimately-Pending tail periods - SAP rejected
-- the malformed file before it could be pulled back (files were already gone from the bucket by
-- the time this was caught; Boat: "no need to pull back... SAP will reject it anyway, malformatted
-- file").
--
-- Fix: scope by whole OrderItem (any order with >=1 currently-missing period), then pull that
-- order's COMPLETE period range straight from the (already date-fixed, unmodified) production
-- view - Paid periods keep their real invoice, still-unpaid periods stay Pending, exactly as SAP
-- expects to see a full, self-consistent order state per submission.
--
-- Boat also asked to split the backfill into smaller files (the first attempt was one 36,917-row/
-- 20.5MB file). Chunking is done by MOD(ABS(FARM_FINGERPRINT(OrderItem)), N) - a deterministic
-- hash bucket - so every period for a given order always lands in the same chunk file. Never
-- chunk by raw row count/offset, which would risk splitting one order's periods across two files
-- and reintroducing the exact violation this script fixes.
--
-- Kept as a reusable procedure (Boat: "keep the backfill script as validation") - can be re-run
-- for a fresh run_label any time it's needed, not just today.

CREATE OR REPLACE PROCEDURE `pacific-plating-282708.sap_integration_v3.sp_backfill_rcl_newpayment_chunked`(
  run_label STRING, n_chunks_motor INT64, n_chunks_nonmotor INT64
)
BEGIN
  DECLARE i INT64 DEFAULT 0;

  EXECUTE IMMEDIATE FORMAT("""
    CREATE OR REPLACE TABLE `pacific-plating-282708.sap_integration_v3._backfill_rcl_motor_%s` AS
    WITH affected AS (
      SELECT DISTINCT order_item
      FROM `pacific-plating-282708.sap_integration_v3.recon_careos_charges`
      WHERE recon_status = 'MISSING_FROM_SAP' AND period > 1
    )
    SELECT v.*, MOD(ABS(FARM_FINGERPRINT(v.OrderItem)), %d) AS chunk_id
    FROM `pacific-plating-282708.sap_view.RCL_Motor_process_2_newpayment` v
    JOIN affected a ON a.order_item = v.OrderItem
  """, run_label, n_chunks_motor);

  WHILE i < n_chunks_motor DO
    EXECUTE IMMEDIATE FORMAT("""
      EXPORT DATA OPTIONS(
        uri='gs://interface-file/RCB_MOTOR/_tmp_backfill_motor_%s_chunk%d_*.csv',
        format='CSV', overwrite=true, header=true
      ) AS
      SELECT * EXCEPT(chunk_id)
      FROM `pacific-plating-282708.sap_integration_v3._backfill_rcl_motor_%s`
      WHERE chunk_id = %d
    """, run_label, i, run_label, i);
    SET i = i + 1;
  END WHILE;

  SET i = 0;
  EXECUTE IMMEDIATE FORMAT("""
    CREATE OR REPLACE TABLE `pacific-plating-282708.sap_integration_v3._backfill_rcl_nonmotor_%s` AS
    WITH affected AS (
      SELECT DISTINCT order_item
      FROM `pacific-plating-282708.sap_integration_v3.recon_careos_charges`
      WHERE recon_status = 'MISSING_FROM_SAP' AND period > 1
    )
    SELECT v.*, MOD(ABS(FARM_FINGERPRINT(v.OrderItem)), %d) AS chunk_id
    FROM `pacific-plating-282708.sap_view.RCL_NonMotor_process_2_newpayment` v
    JOIN affected a ON a.order_item = v.OrderItem
  """, run_label, n_chunks_nonmotor);

  WHILE i < n_chunks_nonmotor DO
    EXECUTE IMMEDIATE FORMAT("""
      EXPORT DATA OPTIONS(
        uri='gs://interface-file/RCB_NONMOTOR/_tmp_backfill_nonmotor_%s_chunk%d_*.csv',
        format='CSV', overwrite=true, header=true
      ) AS
      SELECT * EXCEPT(chunk_id)
      FROM `pacific-plating-282708.sap_integration_v3._backfill_rcl_nonmotor_%s`
      WHERE chunk_id = %d
    """, run_label, i, run_label, i);
    SET i = i + 1;
  END WHILE;
END;
